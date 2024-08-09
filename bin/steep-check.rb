#!/usr/bin/env ruby

require 'pathname'

$LOAD_PATH << Pathname(__dir__) + "../lib"

require 'steep'
require "fileutils"
require "optparse"

puts <<MESSAGE
This is a single-threaded and one-process type checker for profiling.
It runs really slow because it's not parallelized, but it's easier to profiling and analyzing the result.

$ bundle exec bin/steep-check --target=app
$ bundle exec bin/steep-check --target=app files...

MESSAGE

steep_file_path = Pathname("Steepfile")
target_name = nil #: Symbol?
profile_mode = :none #: Symbol?

OptionParser.new do |opts|
  opts.on("--steepfile=FILE") do |file|
    steep_file_path = Pathname(file)
  end
  opts.on("--target=TARGET") do |target|
    target_name = target.to_sym
  end
  opts.on("--profile=MODE", "vernier, memory, stackprof, none, majo, memory2, dumpall") do |mode|
    profile_mode = mode.to_sym
  end
end.parse!(ARGV)

command_line_args = ARGV.dup

class Command
  include Steep

  attr_reader :project, :target

  def initialize(steep_file_path:, target_name:)
    @project = Project.new(steepfile_path: steep_file_path).tap do |project|
      Project::DSL.parse(project, steep_file_path.read, filename: steep_file_path.to_s)
    end

    if target_name
      @target = project.targets.find { _1.name == target_name}
    else
      @target = project.targets[0]
    end

    unless target
      raise "!! Cannot find a target with #{target_name}: targets=[#{project.targets.map(&:name).join(", ")}]"
    end
  end

  def load_signatures()
    file_loader = Steep::Services::FileLoader.new(base_dir: project.base_dir)

    signature_files = {}
    file_loader.each_path_in_patterns(target.signature_pattern) do |path|
      signature_files[path] = path.read
    end

    target.options.load_collection_lock

    signature_service = Steep::Project::Target.construct_env_loader(options: target.options, project: project).yield_self do |loader|
      Steep::Services::SignatureService.load_from(loader)
    end

    env = signature_service.latest_env

    new_decls = Set[]

    signature_files.each do |path, content|
      buffer = RBS::Buffer.new(name: path.to_s, content: content)
      buffer, dirs, decls = RBS::Parser.parse_signature(buffer)
      env.add_signature(buffer: buffer, directives: dirs, decls: decls)
      new_decls.merge(decls)
    end

    env.resolve_type_names(only: new_decls)
  end

  def type_check_files(command_line_args, env)
    file_loader = Steep::Services::FileLoader.new(base_dir: project.base_dir)

    source_files = {}
    file_loader.each_path_in_patterns(target.source_pattern, command_line_args) do |path|
      source_files[path] = path.read
    end

    definition_builder = RBS::DefinitionBuilder.new(env: env)
    factory = AST::Types::Factory.new(builder: definition_builder)
    builder = Interface::Builder.new(factory)
    subtyping = Subtyping::Check.new(builder: builder)

    typings = {}

    source_files.each do |path, content|
      source = Source.parse(content, path: path, factory: factory)

      self_type = AST::Builtin::Object.instance_type

      annotations = source.annotations(block: source.node, factory: factory, context: nil)
      resolver = RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder)
      const_env = TypeInference::ConstantEnv.new(factory: factory, context: nil, resolver: resolver)

      type_env = TypeInference::TypeEnvBuilder.new(
        TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(factory),
        TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableAnnotations.new(annotations),
        TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annotations),
        TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annotations)
      ).build(TypeInference::TypeEnv.new(const_env))

      context = TypeInference::Context.new(
        block_context: nil,
        method_context: nil,
        module_context: TypeInference::Context::ModuleContext.new(
          instance_type: AST::Builtin::Object.instance_type,
          module_type: AST::Builtin::Object.module_type,
          implement_name: nil,
          nesting: nil,
          class_name: AST::Builtin::Object.module_name,
          instance_definition: factory.definition_builder.build_instance(AST::Builtin::Object.module_name),
          module_definition: factory.definition_builder.build_singleton(AST::Builtin::Object.module_name)
        ),
        break_context: nil,
        self_type: self_type,
        type_env: type_env,
        call_context: TypeInference::MethodCall::TopLevelContext.new(),
        variable_context: TypeInference::Context::TypeVariableContext.empty
      )

      typing = Typing.new(source: source, root_context: context, cursor: nil)
      construction = TypeConstruction.new(checker: subtyping, source: source, annotations: annotations, context: context, typing: typing)

      construction.synthesize(source.node)
      typings[path] = typing
    end

    typings
  end
end

command = Command.new(steep_file_path: Pathname.pwd + steep_file_path, target_name: target_name)

puts ">> Loading RBS files..."
env = command.load_signatures()

puts ">> Type checking files with #{profile_mode}..."

typings = nil

GC.start(immediate_sweep: true, immediate_mark: true, full_mark: true)
# GC.config[:rgengc_allow_major_gc] = false

case profile_mode
when :vernier
  require "vernier"
  out = Pathname.pwd + "tmp/typecheck-#{Process.pid}.vernier.json"
  puts ">> Profiling with vernier: #{out}"
  Vernier.profile(out: out.to_s) do
    typings = command.type_check_files(command_line_args, env)
  end

when :memory
  require 'memory_profiler'
  out = Pathname.pwd + "tmp/typecheck-#{Process.pid}.memory.txt"
  puts ">> Profiling with memory_profiler: #{out}"
  classes = nil
  report = MemoryProfiler.report(trace: classes) do
    typings = command.type_check_files(command_line_args, env)
  end
  report.pretty_print(to_file: out, detailed_report: true, scale_bytes: true, retained_strings: false, allocated_strings: false)

when :memory2
  require_relative 'mem_prof'
  out = Pathname.pwd + "tmp/typecheck-#{Process.pid}.memory2.csv"
  puts ">> Profiling with mem_prof: #{out}"
  generation = nil
  out.open("w") do |io|
    MemProf.trace(io: io) do
      generation = GC.count
      typings = command.type_check_files(command_line_args, env)
    end
  end

  require_relative 'mem_graph'
  graph = MemGraph.new(generation)
  ObjectSpace.each_object do |obj|
    if ObjectSpace.allocation_generation(obj) == generation
      graph.traverse(obj)
    end
  end
  (Pathname.pwd + "objects-#{Process.pid}.dot").write(graph.dot)

when :stackprof
  require "stackprof"
  out = Pathname.pwd + "tmp/typecheck-#{Process.pid}.stackprof"
  puts ">> Profiling with stackprof: #{out}"
  StackProf.run(out: out, raw: true, interval: 1000) do
    typings = command.type_check_files(command_line_args, env)
  end

when :majo
  require "majo"
  out = Pathname.pwd + "tmp/typecheck-#{Process.pid}.majo.csv"
  puts ">> Profiling with majo: #{out}"

  result = Majo.run do
    typings = command.type_check_files(command_line_args, env)
  end

  out.open("w") do  |io|
    result.report(out: io, formatter: :csv)
  end

when :dumpall
  require "objspace"
  out = Pathname.pwd + "tmp/dumpall-#{Process.pid}.json"
  puts ">> Profiling with dumpall: #{out}"
  ObjectSpace.trace_object_allocations_start
  typings = command.type_check_files(command_line_args, env)
  out.open('w+') do |io|
    ObjectSpace.dump_all(output: io)
  end

when :none

  pp rbs_method_types: ObjectSpace.each_object(RBS::MethodType).count
  GC.start(immediate_sweep: true, immediate_mark: true, full_mark: true)

  pp defs: ObjectSpace.each_object(RBS::AST::Members::MethodDefinition).count
  pp aliases: ObjectSpace.each_object(RBS::AST::Members::Alias).count
  pp attr_reader: ObjectSpace.each_object(RBS::AST::Members::AttrReader).count
  pp attr_writer: ObjectSpace.each_object(RBS::AST::Members::AttrWriter).count
  pp attr_accessor: ObjectSpace.each_object(RBS::AST::Members::AttrAccessor).count

  Steep.measure("type check", level: :fatal) do
    GC.disable
    typings = command.type_check_files(command_line_args, env)

    pp steep_method_types: ObjectSpace.each_object(Steep::Interface::MethodType).count, rbs_method_types: ObjectSpace.each_object(RBS::MethodType).count
    pp any: ObjectSpace.each_object(Steep::AST::Types::Any).count, void: ObjectSpace.each_object(Steep::AST::Types::Void).count, self: ObjectSpace.each_object(Steep::AST::Types::Self).count
  end
end

typings.size
