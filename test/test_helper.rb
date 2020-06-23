$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require "bundler/setup"
require 'steep'

require "minitest/reporters"
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new]
require 'minitest/autorun'
require "pp"
require "open3"
require "tmpdir"
require 'minitest/hooks/test'
require "lsp_double"

Rainbow.enabled = false

module Steep::AST::Types::Name
  def self.new_module(location: nil, name:, args: [])
    name = Steep::Names::Module.parse(name.to_s) unless name.is_a?(Steep::Names::Module)
    Steep::AST::Types::Name::Module.new(name: name, location: location)
  end

  def self.new_class(location: nil, name:, constructor:, args: [])
    name = Steep::Names::Module.parse(name.to_s) unless name.is_a?(Steep::Names::Module)
    Steep::AST::Types::Name::Class.new(location: location,
                                       name: name,
                                       constructor: constructor)
  end

  def self.new_instance(location: nil, name:, args: [])
    name = Steep::Names::Module.parse(name.to_s) unless name.is_a?(Steep::Names::Module)
    Steep::AST::Types::Name::Instance.new(location: location, name: name, args: args)
  end
end

module TestHelper
  class <<self
    attr_accessor :timeout
  end

  def assert_any(collection, &block)
    assert collection.any?(&block)
  end

  def assert_any!(collection, &block)
    errors = []
    count = 0

    collection.each do |c|
      begin
        block[c]
        count += 1
      rescue Minitest::Assertion => error
        errors << error
      end
    end

    if count == 0
      raise Minitest::Assertion.new("Assertion should hold one of the collection members: #{collection.to_a.join(', ')}")
    end
  end

  def assert_all(collection, &block)
    assert collection.all?(&block)
  end

  def refute_any(collection, &block)
    refute collection.any?(&block)
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
    case indexes.size
    when 0
      node
    when 1
      node.children[indexes.first]
    else
      dig(node.children[indexes.first], *indexes.drop(1))
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
end

module TypeErrorAssertions
  def assert_incompatible_assignment(error, node: nil, lhs_type: nil, rhs_type:)
    assert_instance_of Steep::Errors::IncompatibleAssignment, error

    assert_equal node, error.node if node
    assert_equal lhs_type, error.lhs_type if lhs_type
    assert_equal rhs_type, error.rhs_type if rhs_type

    yield error if block_given?
  end

  def assert_no_method_error(error, node: nil, method: nil, type: nil)
    assert_instance_of Steep::Errors::NoMethod, error

    node and assert_equal node, error.node
    method and assert_equal method, error.method
    type and assert_equal type, error.type

    block_given? and yield error
  end

  def assert_argument_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Steep::Errors::ArgumentTypeMismatch, error

    assert_equal expected, error.expected if expected
    assert_equal actual, error.actual if actual

    yield error.expected, error.actual if block_given?
  end

  def assert_block_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Steep::Errors::BlockTypeMismatch, error

    assert_equal expected, error.expected.to_s if expected
    assert_equal actual, error.actual.to_s if actual

    yield expected, actual if block_given?
  end

  def assert_break_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Steep::Errors::BreakTypeMismatch, error

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
end

class Object < BasicObject
  def class: -> class
  def tap: { (instance) -> untyped } -> instance
  def to_s: -> String
  def nil?: -> bool
  def !: -> bool
  def itself: -> self

private
  def require: (String) -> void
  def puts: (*String) -> void
  def gets: -> String?
end

class Class < Module
end

class Module
  def block_given?: -> untyped
  def attr_reader: (*Symbol) -> void
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
end

class Integer < Numeric
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

class Array[A]
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
end

class Hash[A, B]
  def `[]`: (A) -> B
  def `[]=`: (A, B) -> B
  def each: { ([A, B]) -> void } -> self
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
      @checker = Steep::Subtyping::Check.new(factory: factory)
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

  def sh(*command)
    Open3.capture3(env_vars, *command, chdir: current_dir.to_s)
  end

  def sh!(*command)
    stdout, stderr, status = sh(*command)
    unless status.success?
      raise "Failed to execute: #{command.join(" ")}, #{status.inspect}, stdout=#{stdout.inspect}, stderr=#{stderr.inspect}"
    end

    [stdout, stderr]
  end

  def in_tmpdir(&block)
    Dir.mktmpdir do |dir|
      chdir(Pathname(dir), &block)
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

      env_loader = RBS::EnvironmentLoader.new()
      if nostdlib
        env_loader.no_builtin!
      end
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

  def parse_method_type(string, factory: self.factory, variables: [], self_type: Steep::AST::Types::Self.new)
    type = RBS::Parser.parse_method_type(string, variables: variables)
    factory.method_type type, self_type: self_type
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
end


TestHelper.timeout = ENV["CI"] ? 50 : 10
