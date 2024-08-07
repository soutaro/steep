$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

Encoding.default_external = Encoding::UTF_8

require "bundler/setup"
require 'steep'

require 'minitest/autorun'
require "pp"
require "open3"
require "tmpdir"
require 'minitest/hooks/test'
require 'minitest/slow_test'
require 'rbconfig'

unless Minitest.seed
  Minitest.seed = Time.now.to_i
end

require_relative "lsp_double"

Minitest::SlowTest.long_test_time = 5

Rainbow.enabled = false

module Steep::AST::Types::Name
  def self.new_singleton(name:, location: nil)
    name = TypeName(name.to_s) unless name.is_a?(RBS::TypeName)
    Steep::AST::Types::Name::Singleton.new(name: name, location: location)
  end

  def self.new_instance(location: nil, name:, args: [])
    name = TypeName(name.to_s) unless name.is_a?(RBS::TypeName)
    Steep::AST::Types::Name::Instance.new(location: location, name: name, args: args)
  end
end

module TestHelper
  class <<self
    attr_accessor :timeout
  end

  def file_scheme
    if Gem.win_platform?
      "file:///"
    else
      "file://"
    end
  end

  def assert_any(collection, &block)
    assert collection.any?(&block)
  end

  def assert_any!(collection, size: nil, &block)
    errors = []
    count = 0

    assert_equal size, collection.count if size

    collection.each do |c|
      begin
        block[c]
        count += 1
      rescue Minitest::Assertion => error
        errors << error
      end
    end

    if count == 0
      raise Minitest::Assertion.new(
        "Assertion should hold one of the collection members: [#{collection.map(&:inspect).join(', ')}]\n" +
          "  error: #{errors.last.message}"
      )
    end
  end

  def assert_all(collection, &block)
    assert collection.all?(&block)
  end

  def assert_all!(collection, size: nil)
    assert_equal size, collection.count if size

    collection.each do |c|
      yield c
    end
  end

  def refute_any(collection, &block)
    refute collection.any?(&block)
  end

  def assert_none!(collection, size: nil)
    assert_equal size, collection.count if size

    result = collection.all? do |c|
      begin
        yield(c)
        false
      rescue Minitest::Assertion
        true
      end
    end

    unless result
      raise Minitest::Assertion.new(
        "Assertion shouldn't hold any of the collection members: [#{collection.map(&:inspect).join(', ')}]"
      )
    end
  end

  def assert_size(size, collection)
    assert_equal size, collection.size
  end

  def finally(timeout: TestHelper.timeout)
    started_at = Time.now
    while Time.now < started_at + timeout
      yield
      sleep 0.2
    end
  end

  def finally_holds(timeout: TestHelper.timeout)
    finally(timeout: timeout) do
      begin
        yield
        return
      rescue Minitest::Assertion
        # ignore
      end
    end

    yield
  end

  def assert_finally(timeout: TestHelper.timeout, &block)
    finally(timeout: timeout) do
      yield.tap do |result|
        return result if result
      end
    end

    assert yield
  end

  def dig(node, *indexes)
    children = node.is_a?(Array) ? node :  node.children

    case indexes.size
    when 0
      node
    when 1
      children[indexes.first]
    else
      dig(children[indexes.first], *indexes.drop(1))
    end
  end

  def lvar_in(node, name)
    if (node.type == :lvar || node.type == :lvasgn) && node.children[0].name == name
      return node
    else
      node.children.each do |child|
        if child.is_a?(AST::Node)
          lvar = lvar_in(child, name)
          return lvar if lvar
        end
      end
      nil
    end
  end

  def flush_queue(queue)
    queue << self

    copy = []

    while true
      ret = queue.pop

      break if ret.nil?
      break if ret.equal?(self)

      copy << ret
    end

    copy
  end

  # Assert `#to_s` of a method type `type` is compatible with `string`.
  #
  # The `string` can contain notation for *fresh* type variables, like `X(a)`.
  #
  # ```
  # assert_method_type("[X(a)] (X(a)) -> X(a)", ...) => compatible with [X(0)] (X(0)) -> X0
  # ```
  def assert_method_type(string, type)
    regexp = Regexp.escape(string)

    ("a".."z").each do |name|
      pat = /\\\(#{name}\\\)/

      regexp = regexp.sub(pat) do |s|
        c = "(?<#{name}>\\d+)"
        "\\(#{c}\\)"
      end

      regexp = regexp.gsub(pat) do |s|
        c = "\\k<#{name}>"
        "\\(#{c}\\)"
      end
    end

    assert_match(/\A#{regexp}\Z/, type.to_s)
  end
end

module TypeErrorAssertions
  Diagnostic = Steep::Diagnostic

  def assert_incompatible_assignment(error, node: nil, lhs_type: nil, rhs_type:)
    assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error

    assert_equal node, error.node if node
    assert_equal lhs_type, error.lhs_type if lhs_type
    assert_equal rhs_type, error.rhs_type if rhs_type

    yield error if block_given?
  end

  def assert_no_method_error(error, node: nil, method: nil, type: nil)
    assert_instance_of Diagnostic::Ruby::NoMethod, error

    node and assert_equal node, error.node
    method and assert_equal method, error.method
    type and assert_equal type, error.type

    block_given? and yield error
  end

  def assert_argument_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error

    assert_equal expected, error.expected if expected
    assert_equal actual, error.actual if actual

    yield error.expected, error.actual if block_given?
  end

  def assert_break_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Diagnostic::Ruby::BreakTypeMismatch, error

    assert_equal expected, error.expected if expected
    assert_equal actual, error.actual if actual

    yield expected, actual if block_given?
  end
end

module ASTAssertion
  def assert_type_var(type, name: nil)
    assert_instance_of Steep::AST::Types::Var, type
    assert_equal name, type.name if name
  end

  def assert_any_type(type)
    assert_instance_of Steep::AST::Types::Any, type
  end

  def assert_location(located, name: nil, start_line: nil, start_column: nil, end_line: nil, end_column: nil)
    loc = located.location
    assert_equal name, loc.name if name
    assert_equal start_line, loc.start_line if start_line
    assert_equal start_column, loc.start_column if start_column
    assert_equal end_line, loc.end_line if end_line
    assert_equal end_column, loc.end_column if end_column
  end

  def assert_instance_name_type(type, name: nil)
    assert_instance_of Steep::AST::Types::Name::Instance, type
    assert_equal name, type.name if name
    yield type.args if block_given?
  end

  def assert_union_type(type)
    assert_instance_of Steep::AST::Types::Union, type
    yield type.types if block_given?
  end

  def assert_instance_type(type)
    assert_instance_of Steep::AST::Types::Instance, type
  end
end

module SubtypingHelper
  BUILTIN = <<-EOS
class BasicObject
  def initialize: () -> void
  def !: -> bool
end

class Object < BasicObject
  def class: -> class
  def tap: { (instance) -> untyped } -> instance
  def to_s: -> String
  def nil?: -> bool
  def itself: -> self
  def is_a?: (Module) -> bool
  def ===: (untyped) -> bool

private
  def require: (String) -> void
  def puts: (*String) -> void
  def gets: -> String?
end

class Class < Module
  def new: (*untyped, **untyped) ?{ (*untyped, **untyped) -> void } -> void
end

class Module
  def block_given?: -> untyped
  def attr_reader: (*Symbol) -> void
  def ===: (untyped) -> bool
end

class String
  def to_str: -> String
  def `+`: (String) -> String
  def size: -> Integer
  def `-@`: -> String
end

class Numeric
  def `+`: (Numeric) -> Numeric
  def to_int: -> Integer

  def zero?: () -> bool
end

class Integer < Numeric
  def +: (Integer) -> Integer
       | (Numeric) -> Numeric
end

class Float < Numeric
  def +: (Float) -> Float
       | (Integer) -> Float
       | (Numeric) -> Numeric
end

class Symbol
  def id2name: -> String
end

class Range[A]
  def begin: -> A
  def end: -> A
end

class Regexp
end

class Array[unchecked out A]
  def initialize: () -> untyped
                | (Integer, A) -> untyped
                | (Integer) -> untyped
  def `[]`: (Integer) -> A
  def `[]=`: (Integer, A) -> A
  def `<<`: (A) -> self
  def each: { (A) -> untyped } -> self
  def zip: [B] (Array[B]) -> Array[A | B]
  def each_with_object: [B] (B) { (A, B) -> untyped } -> B
  def map: [X] { (A) -> X } -> Array[X]

  def fetch: (Integer) -> A

  def first: () -> A?
  def last: () -> A?
end

class Hash[unchecked out A, unchecked out B]
  def `[]`: (A) -> B
  def `[]=`: (A, B) -> B
  def each: { ([A, B]) -> void } -> self
  def fetch: (A) -> B
end

class NilClass
end

class Proc
  def `[]`: (*untyped) -> untyped
  def call: (*untyped) -> untyped
  def `===`: (*untyped) -> untyped
  def yield: (*untyped) -> untyped
  def arity: -> Integer
end

class TrueClass
end
class FalseClass
end
  EOS

  def checker
    @checker or raise "#checker should be used within from #with_checker"
  end

  def with_checker(*files, with_stdlib: false, &block)
    paths = {}

    files.each.with_index do |content, index|
      if content.is_a?(Hash)
        paths.merge!(content)
      else
        paths["#{index}.rbs"] = content
      end
    end

    unless with_stdlib
      paths["builtin.rbs"] = BUILTIN
    end

    with_factory(paths, nostdlib: !with_stdlib) do |factory|
      builder = Steep::Interface::Builder.new(factory)
      @checker = Steep::Subtyping::Check.new(builder: builder)
      yield @checker
    ensure
      @checker = nil
    end
  end
end

module ShellHelper
  def chdir(path)
    if path.relative?
      path = current_dir + path
    end
    dirs.push(path)
    yield
  ensure
    dirs.pop
  end

  def current_dir
    dirs.last
  end

  def push_env(env)
    envs.push env
    yield
  ensure
    envs.pop
  end

  def env_vars
    envs.each.with_object({}) do |update_env, env_vars|
      env_vars.merge!(update_env)
    end
  end

  def sh(*command, **opts)
    Open3.capture2(env_vars, *command, chdir: current_dir.to_s, **opts)
  end

  def sh3(*command)
    Open3.capture3(env_vars, *command, chdir: current_dir.to_s)
  end

  def sh2e(*command)
    Open3.capture2e(env_vars, *command, chdir: current_dir.to_s)
  end

  def sh!(*command, **opts)
    stdout, status = sh(*command, **opts)
    unless status.success?
      raise "Failed to execute: #{command.join(" ")}, #{status.inspect}, stdout=#{stdout.inspect}"
    end

    stdout
  end

  def in_tmpdir(&block)
    Dir.mktmpdir do |dir|
      chdir(Pathname(dir).realpath, &block)
    end
  end
end

module FactoryHelper
  def with_factory(paths = {}, nostdlib: false)
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      paths.each do |path, content|
        absolute_path = root + path
        absolute_path.parent.mkpath
        absolute_path.write(content)
      end

      core_root = nostdlib ? nil : RBS::EnvironmentLoader::DEFAULT_CORE_ROOT
      env_loader = RBS::EnvironmentLoader.new(core_root: core_root)
      env_loader.add path: root

      env = RBS::Environment.new()
      env_loader.load(env: env)
      env = env.resolve_type_names

      definition_builder = RBS::DefinitionBuilder.new(env: env)

      @factory = Steep::AST::Types::Factory.new(builder: definition_builder)

      yield factory
    ensure
      @factory = nil
    end
  end

  def factory
    @factory or raise "#factory should be called from inside with_factory"
  end

  def parse_type(string, factory: self.factory, variables: [])
    type = RBS::Parser.parse_type(string, variables: variables)
    factory.type(type)
  end

  def parse_ruby(string, factory: self.factory)
    Steep::Source.parse(string, path: Pathname("test.rb"), factory: factory)
  end

  def parse_method_type(string, factory: self.factory, variables: [])
    type = RBS::Parser.parse_method_type(string, variables: variables)
    factory.method_type(type)
  end
end

module LSPTestHelper
  LSP = LanguageServer::Protocol

  def reader_pipe
    @reader_pipe ||= IO.pipe
  end

  def writer_pipe
    @writer_pipe ||= IO.pipe
  end

  def worker_reader
    @worker_reader ||= LSP::Transport::Io::Reader.new(reader_pipe[0])
  end

  def worker_writer
    @worker_writer ||= LSP::Transport::Io::Writer.new(writer_pipe[1])
  end

  def master_writer
    @master_writer ||= LSP::Transport::Io::Writer.new(reader_pipe[1])
  end

  def master_reader
    @master_reader ||= LSP::Transport::Io::Reader.new(writer_pipe[0])
  end

  def with_master_read_queue()
    read_queue = Queue.new

    read_thread = Thread.new do
      master_reader.read do |response|
        read_queue << response
      end
    end

    yield read_queue

    writer_pipe[1].close()

    read_thread.join
  end
end

module TypeConstructionHelper
  Namespace = RBS::Namespace

  Typing = Steep::Typing
  ConstantEnv = Steep::TypeInference::ConstantEnv
  TypeEnv = Steep::TypeInference::TypeEnv
  TypeConstruction = Steep::TypeConstruction
  Annotation = Steep::AST::Annotation
  Context = Steep::TypeInference::Context
  AST = Steep::AST
  TypeInference = Steep::TypeInference

  def with_standard_construction(checker, source, cursor: nil)
    self_type = parse_type("::Object")

    annotations = source.annotations(block: source.node, factory: checker.factory, context: nil)
    resolver = RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder)
    const_env = ConstantEnv.new(factory: factory, context: nil, resolver: resolver)

    rbs_env = checker.factory.env
    type_env = Steep::TypeInference::TypeEnvBuilder.new(
      Steep::TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(checker.factory),
      Steep::TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableAnnotations.new(annotations),
      Steep::TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annotations),
      Steep::TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annotations)
    ).build(TypeEnv.new(const_env))

    context = Context.new(
      block_context: nil,
      method_context: nil,
      module_context: Context::ModuleContext.new(
        instance_type: AST::Builtin::Object.instance_type,
        module_type: AST::Builtin::Object.module_type,
        implement_name: nil,
        nesting: nil,
        class_name: AST::Builtin::Object.module_name,
        instance_definition: checker.factory.definition_builder.build_instance(AST::Builtin::Object.module_name),
        module_definition: checker.factory.definition_builder.build_singleton(AST::Builtin::Object.module_name)
      ),
      break_context: nil,
      self_type: self_type,
      type_env: type_env,
      call_context: TypeInference::MethodCall::TopLevelContext.new(),
      variable_context: Context::TypeVariableContext.empty
    )
    loc =
      if cursor
        source.buffer.loc_to_pos(cursor)
      end

    typing = Typing.new(source: source, root_context: context, cursor: loc)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        context: context,
                                        typing: typing)

    yield construction, typing
  end

  def assert_no_error(typing)
    assert_instance_of Typing, typing
    assert_predicate typing.errors.map {|e| e.header_line }, :empty?
  end

  def assert_typing_error(typing, size: nil)
    assert_instance_of Typing, typing

    messages = typing.errors.map {|e| e.header_line }

    if size
      assert_equal size, messages.size, "errors=#{messages.inspect}"
      yield(typing.errors) if block_given?
    else
      refute_empty messages
    end
  end
end

TestHelper.timeout = ENV["CI"] ? 50 : 25

RUBY_PATH = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"])
