$LOAD_PATH.unshift File.expand_path('../../vendor/ruby-signature/lib', __FILE__)
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'steep'

require "minitest/reporters"
MiniTest::Reporters.use!
require 'minitest/autorun'
require "pp"
require "open3"
require "tmpdir"
require 'minitest/hooks/test'

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
  def assert_any(collection, &block)
    assert collection.any?(&block)
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

  def dig(node, *indexes)
    if indexes.size == 1
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
  def tap: { (instance) -> any } -> instance
  def gets: -> String?
  def to_s: -> String
  def nil?: -> bool
  def !: -> bool
  def itself: -> self
end

class Class
end

class Module
  def block_given?: -> any
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
  def initialize: () -> any
                | (Integer, A) -> any
                | (Integer) -> any
  def `[]`: (Integer) -> A
  def `[]=`: (Integer, A) -> A
  def `<<`: (A) -> self
  def each: { (A) -> any } -> self
  def zip: [B] (Array[B]) -> Array[A | B]
  def each_with_object: [B] (B) { (A, B) -> any } -> B
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
  def `[]`: any
  def call: any
  def `===`: any
  def yield: any
  def arity: -> Integer
end
  EOS

  def checker
    @checker or raise "#checker should be used within from #with_checker"
  end

  def with_checker(*files, &block)
    paths = {}

    files.each.with_index do |content, index|
      if content.is_a?(Hash)
        paths.merge!(content)
      else
        paths["#{index}.rbi"] = content
      end
    end

    paths["builtin.rbi"] = BUILTIN
    with_factory(paths, nostdlib: true) do |factory|
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

      env = Ruby::Signature::Environment.new()

      env_loader = Ruby::Signature::EnvironmentLoader.new(env: env)
      if nostdlib
        env_loader.stdlib_root = nil
      end
      env_loader.add path: root
      env_loader.load

      definition_builder = Ruby::Signature::DefinitionBuilder.new(env: env)

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
    type = Ruby::Signature::Parser.parse_type(string, variables: variables)
    factory.type(type)
  end

  def parse_ruby(string, factory: self.factory)
    Steep::Source.parse(string, path: Pathname("test.rb"), factory: factory)
  end

  def parse_method_type(string, factory: self.factory, variables: [])
    type = Ruby::Signature::Parser.parse_method_type(string, variables: variables)
    factory.method_type type
  end
end
