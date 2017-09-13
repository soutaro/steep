require "test_helper"

class AnnotationParsingTest < Minitest::Test
  Parser = Steep::Parser
  include TestHelper

  def test_skip_annotation
    annot = Parser.parse_annotation_opt("This is not annotation")
    assert_nil annot
  end

  def test_var_type_annotation
    annot = Parser.parse_annotation_opt("@type var foo: Bar")
    assert_equal :foo, annot.var
    assert_equal Steep::Types::Name.instance(name: :Bar), annot.type
  end

  def test_method_annotation
    annot = Parser.parse_annotation_opt("@type method foo: Bar -> Baz")
    assert_equal :foo, annot.method
    assert_equal Parser.parse_method("Bar -> Baz"), annot.type
  end

  def test_method_annotation_app
    annot = Parser.parse_annotation_opt("@type method foo: <'a> Bar -> Baz")
    assert_equal :foo, annot.method
    assert_equal Parser.parse_method("<'a> Bar -> Baz"), annot.type
  end

  def test_return_type_annotation
    annot = Parser.parse_annotation_opt("@type return: Integer")
    assert_equal Steep::Types::Name.instance(name: :Integer), annot.type
  end

  def test_block_type_annotation
    annot = Parser.parse_annotation_opt("@type block: String")
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_self_type
    annot = Parser.parse_annotation_opt("@type self: String")
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_const_type
    annot = Parser.parse_annotation_opt("@type const Foo::Bar::Baz: String")
    assert_equal :"Foo::Bar::Baz", annot.name
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_const_type2
    annot = Parser.parse_annotation_opt("@type const Foo: String")
    assert_equal :"Foo", annot.name
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_const_type3
    annot = Parser.parse_annotation_opt("@type const ::Foo: String")
    assert_equal :"::Foo", annot.name
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_instance_type
    annot = Parser.parse_annotation_opt("@type instance: String")
    assert_instance_of Steep::Annotation::InstanceType, annot
    assert_equal Steep::Types::Name.instance(name: :String), annot.type
  end

  def test_module_type
    annot = Parser.parse_annotation_opt("@type module: String.class")
    assert_instance_of Steep::Annotation::ModuleType, annot
    assert_equal Steep::Types::Name.module(name: :String), annot.type
  end

  def test_implements
    annot = Parser.parse_annotation_opt("@implements String")
    assert_instance_of Steep::Annotation::Implements, annot
    assert_equal :String, annot.module_name
  end

  def test_ivar_type
    annot = Parser.parse_annotation_opt("@type ivar @x: Integer")
    assert_equal Steep::Annotation::IvarType.new(name: :"@x",
                                                 type: Steep::Types::Name.instance(name: :Integer)),
                 annot
  end

  def test_dynamic
    annot = Parser.parse_annotation_opt("@dynamic foo")
    assert_equal Steep::Annotation::Dynamic.new(name: :foo), annot
  end
end
