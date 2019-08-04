require "test_helper"

class AnnotationCollectionTest < Minitest::Test
  include Minitest::Hooks
  include TestHelper
  include FactoryHelper

  Names = Steep::Names
  Annotation = Steep::AST::Annotation
  Types = Steep::AST::Types
  AST = Steep::AST

  def new_collection(current_module:, factory:)
    Annotation::Collection.new(
      annotations: [
        Annotation::VarType.new(name: :x, type: parse_type("Object")),
        Annotation::IvarType.new(name: :@y, type: parse_type("Object")),
        Annotation::ConstType.new(name: Names::Module.parse("Object"), type: parse_type("singleton(Object)")),
        Annotation::MethodType.new(name: :foo, type: parse_method_type("() -> Object")),
        Annotation::BlockType.new(type: parse_type("Object")),
        Annotation::ReturnType.new(type: parse_type("Object")),
        Annotation::SelfType.new(type: parse_type("String")),
        Annotation::InstanceType.new(type: parse_type("String")),
        Annotation::ModuleType.new(type: parse_type("String")),
        Annotation::BreakType.new(type: parse_type("::Object")),
        Annotation::Implements.new(name: Annotation::Implements::Module.new(name: Names::Module.parse("Object"), args: [])),
        Annotation::Dynamic.new(names: [
          Annotation::Dynamic::Name.new(name: :foo, kind: :instance),
          Annotation::Dynamic::Name.new(name: :bar, kind: :module),
          Annotation::Dynamic::Name.new(name: :baz, kind: :module_instance),
        ])
      ],
      factory: factory,
      current_module: current_module)
  end

  RBIS = {
    "foo.rbi" => <<EOF
class Person
end

class Person::Object
end
EOF
  }

  def test_types
    with_factory RBIS do |factory|
      annotations = new_collection(current_module: AST::Namespace.parse("::Person"), factory: factory)

      assert_equal parse_type("::Person::Object"), annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)

      assert_equal parse_type("::Person::Object"), annotations.var_type(ivar: :@y)
      assert_nil annotations.var_type(ivar: :@x)

      assert_equal parse_type("singleton(::Person::Object)"), annotations.var_type(const: Names::Module.parse("Object"))
      assert_nil annotations.var_type(const: Names::Module.parse("::Object"))

      assert_equal "() -> ::Person::Object", annotations.method_type(:foo).to_s

      assert_equal parse_type("::Person::Object"), annotations.block_type
      assert_equal parse_type("::Person::Object"), annotations.return_type
      assert_equal parse_type("::String"), annotations.self_type
      assert_equal parse_type("::String"), annotations.instance_type
      assert_equal parse_type("::String"), annotations.module_type
      assert_equal parse_type("::Object"), annotations.break_type
    end
  end

  def test_dynamics
    with_factory do |factory|
      annotations = new_collection(current_module: AST::Namespace.parse("::Person"), factory: factory)

      assert_equal [:foo, :baz], annotations.instance_dynamics
      assert_equal [:bar, :baz], annotations.module_dynamics
    end
  end

  def test_merge_block_annotations
    with_factory RBIS do |factory|
      namespace = AST::Namespace.parse("::Person")
      current_annotations = new_collection(current_module: namespace, factory: factory)

      block_annotations = Annotation::Collection.new(
        annotations: [
          Annotation::VarType.new(name: :x, type: parse_type("Integer")),
          Annotation::BreakType.new(type: parse_type("String"))
        ],
        factory: factory,
        current_module: namespace
      )

      new_annotations = current_annotations.merge_block_annotations(block_annotations)

      assert_equal parse_type("::Integer"), new_annotations.var_type(lvar: :x)
      assert_equal parse_type("::Person::Object"), new_annotations.var_type(ivar: :@y)

      assert_equal parse_type("::String"), new_annotations.break_type
      assert_nil new_annotations.block_type
    end
  end
end
