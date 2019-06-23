$LOAD_PATH.unshift File.expand_path('../../vendor/ruby-signature/lib', __FILE__)
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'steep'

require "minitest/reporters"
MiniTest::Reporters.use!
require 'minitest/autorun'
require "pp"
require "open3"
require "tmpdir"

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

  def parse_signature(signature)
    Steep::Parser.parse_signature(signature)
  end

  def parse_method_type(string)
    Steep::Parser.parse_method(string)
  end

  def parse_type(string)
    Steep::Parser.parse_type(string)
  end

  def parse_single_method(string, super_method: nil, attributes: [])
    type = Steep::Parser.parse_method(string)
    Steep::Interface::Method.new(types: [type], super_method: super_method, attributes: attributes)
  end

  def parse_ruby(string)
    Steep::Source.parse(string, path: Pathname("test.rb"))
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

  def assert_required_param(params, index:, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::Required, params
      yield params.type, params if block_given?
    else
      assert_required_param params.next_params, index: index - 1, &block
    end
  end

  def assert_optional_param(params, index:, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::Optional, params
      yield params.type, params if block_given?
    else
      assert_optional_param params.next_params, index: index - 1, &block
    end
  end

  def assert_rest_param(params, index:, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::Rest, params
      yield params.type, params if block_given?
    else
      assert_rest_param params.next_params, index: index - 1, &block
    end
  end

  def assert_required_keyword(params, index:, name: nil, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::RequiredKeyword, params
      assert_equal name, params.name if name
      yield params.type, params if block_given?
    else
      assert_required_keyword params.next_params, index: index - 1, name: name, &block
    end
  end

  def assert_optional_keyword(params, index:, name: nil, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::OptionalKeyword, params
      assert_equal name, params.name if name
      yield params.type, params if block_given?
    else
      assert_optional_keyword params.next_params, index: index - 1, name: name, &block
    end
  end

  def assert_rest_keyword(params, index:, &block)
    if index == 0
      assert_instance_of Steep::AST::MethodType::Params::RestKeyword, params
      yield params.type, params if block_given?
    else
      assert_rest_keyword params.next_params, index: index - 1, &block
    end
  end

  def assert_params_length(params, size, acc: 0)
    case params
    when Steep::AST::MethodType::Params::RestKeyword
      assert_equal size, acc+1
    when nil
      assert_equal size, acc
    else
      assert_params_length params.next_params, size, acc: acc+1
    end
  end

  def assert_type_params(params, variables: nil)
    assert_instance_of Steep::AST::TypeParams, params
    assert_equal variables, params.variables if variables
  end

  def assert_union_type(type)
    assert_instance_of Steep::AST::Types::Union, type
    yield type.types if block_given?
  end

  def assert_instance_type(type)
    assert_instance_of Steep::AST::Types::Instance, type
  end

  def assert_class_signature(sig, name: nil, params: nil)
    assert_instance_of Steep::AST::Signature::Class, sig
    assert_equal name, sig.name if name
    assert_equal params, sig.params.variables if params
    yield members: sig.members if block_given?
  end

  def assert_super_class(super_class, name: nil)
    assert_instance_of Steep::AST::Signature::SuperClass, super_class
    assert_equal name, super_class.name if name
    yield super_class.args, super_class if block_given?
  end

  def assert_module_signature(sig, name: nil, params: nil)
    assert_instance_of Steep::AST::Signature::Module, sig
    assert_equal name, sig.name if name
    assert_equal params, sig.params.variables if params
    yield sig if block_given?
  end

  def assert_interface_signature(sig, name: nil, params: nil)
    assert_instance_of Steep::AST::Signature::Interface, sig
    if name
      name = Steep::Names::Interface.new(name: name, namespace: Steep::AST::Namespace.empty) if name.is_a?(Symbol)
      assert_equal name, sig.name
    end
    assert_equal params, sig.params&.variables if params
    yield name: sig.name, params: sig.params, methods: sig.methods if block_given?
  end

  def assert_interface_method(method, name: nil)
    assert_instance_of Steep::AST::Signature::Interface::Method, method
    assert_equal name, method.name if name
    yield(*method.types) if block_given?
  end

  def assert_include_member(member, name: nil, args: nil)
    assert_instance_of Steep::AST::Signature::Members::Include, member
    assert_equal name, member.name if name
    assert_equal args, member.args if args
  end

  def assert_extend_member(member, name: nil, args: nil)
    assert_instance_of Steep::AST::Signature::Members::Extend, member
    assert_equal name, member.name if name
    assert_equal args, member.args if args
  end

  def assert_method_member(member, name: nil, kind: nil, attributes: nil)
    assert_instance_of Steep::AST::Signature::Members::Method, member
    assert_equal name, member.name if name
    assert_equal kind, member.kind if kind
    assert_equal attributes, member.attributes if attributes
    yield name: member.name, kind: member.kind, types: member.types, attributes: attributes if block_given?
  end

  def assert_extension_signature(sig, module_name: nil, name: nil)
    assert_instance_of Steep::AST::Signature::Extension, sig
    assert_equal module_name, sig.module_name if module_name
    assert_equal name, sig.name if name
    yield module_name: sig.module_name, name: sig.name, params: sig.params if block_given?
  end

  def assert_method_type_annotation(annot, name: nil)
    assert_instance_of Steep::AST::Annotation::MethodType, annot
    assert_equal name, annot.name if name
    yield name: annot.name, type: annot.type if block_given?
  end
end

module SubtypingHelper
  BUILTIN = <<-EOS
class BasicObject
end

class Object < BasicObject
  def class: -> module
  def tap: { (instance) -> any } -> instance
  def gets: -> String?
  def to_s: -> String
  def nil?: -> bool
  def !: -> bool
end

class Class
end

class Module
  def block_given?: -> any
end

class String
  def to_str: -> String
  def +: (String) -> String
  def size: -> Integer
  def -@: -> String
end

class Numeric
  def +: (Numeric) -> Numeric
  def to_int: -> Integer
end

class Integer < Numeric
end

class Symbol
  def id2name: -> String
end

class Range<'a>
  def begin: -> 'a
  def end: -> 'a
end

class Regexp
end

class Array<'a>
  def initialize: () -> any
                | (Integer, 'a) -> any
                | (Integer) -> any
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
  def <<: ('a) -> self
  def each: { ('a) -> any } -> self
  def zip: <'b> (Array<'b>) -> Array<'a | 'b>
  def each_with_object: <'b> ('b) { ('a, 'b) -> any } -> 'b
  def map: <'x> { ('a) -> 'x } -> Array<'x>
end

class Hash<'a, 'b>
  def []: ('a) -> 'b
  def []=: ('a, 'b) -> 'b
  def each: { (['a, 'b]) -> void } -> self
end

class NilClass
end

class Proc
  def []: (*any) -> any
  def call: (*any) -> any
  def ===: (*any) -> any
  def yield: (*any) -> any
  def arity: -> Integer
end
  EOS

  DEFAULT_SIGS = <<-EOS
interface _A
  def +: (_A) -> _A
end

interface _B
end

interface _C
  def f: () -> _A
  def g: (_A, ?_B) -> _B
  def h: (a: _A, ?b: _B) -> _C
end

interface _D
  def foo: () -> any
end

interface _X
  def f: () { (_A) -> _D } -> _C 
end

interface _Kernel
  def foo: (_A) -> _B
         | (_C) -> _D
end

interface _PolyMethod
  def snd: <'a>(any, 'a) -> 'a
  def try: <'a> { (any) -> 'a } -> 'a
end

module Foo<'a>
end
  EOS

  def new_subtyping_checker(sigs = DEFAULT_SIGS)
    signatures = Steep::AST::Signature::Env.new.tap do |env|
      parse_signature(BUILTIN).each do |sig|
        env.add sig
      end

      parse_signature(sigs).each do |sig|
        env.add sig
      end
    end

    builder = Steep::Interface::Builder.new(signatures: signatures)
    Steep::Subtyping::Check.new(builder: builder)
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
