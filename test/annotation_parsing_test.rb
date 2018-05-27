require "test_helper"

class AnnotationParsingTest < Minitest::Test
  Parser = Steep::Parser
  include TestHelper
  include ASTAssertion
  ModuleName = Steep::ModuleName
  
  def parse_annotation(source)
    Parser.parse_annotation_opt(source, buffer: Steep::AST::Buffer.new(name: nil, content: source))
  end

  def test_skip_annotation
    annot = parse_annotation("This is not annotation")
    assert_nil annot
  end

  def test_var_type_annotation
    annot = parse_annotation("@type var foo: Bar")
    assert_instance_of Steep::AST::Annotation::VarType, annot
    assert_equal :foo, annot.name
    assert_equal Steep::AST::Types::Name.new_instance(name: :Bar), annot.type
  end

  def test_method_annotation
    annot = parse_annotation("@type method foo: Bar -> Baz")

    assert_method_type_annotation annot, name: :foo do |type:, **|
      assert_nil type.type_params

      assert_params_length type.params, 1
      assert_required_param type.params, index: 0 do |ty|
        assert_equal Steep::AST::Types::Name.new_instance(name: :Bar), ty
      end

      assert_equal Steep::AST::Types::Name.new_instance(name: :Baz), type.return_type

      assert_nil type.block
    end
  end

  def test_return_type_annotation
    annot = parse_annotation("@type return: Integer")
    assert_instance_of Steep::AST::Annotation::ReturnType, annot
    assert_equal Steep::AST::Types::Name.new_instance(name: :Integer), annot.type
  end

  def test_block_type_annotation
    annot = parse_annotation("@type block: String")
    assert_instance_of Steep::AST::Annotation::BlockType, annot
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_self_type
    annot = parse_annotation("@type self: String")
    assert_instance_of Steep::AST::Annotation::SelfType, annot
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_const_type
    annot = parse_annotation("@type const Foo::Bar::Baz: String")
    assert_instance_of Steep::AST::Annotation::ConstType, annot
    assert_equal ModuleName.parse("Foo::Bar::Baz"), annot.name
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_const_type2
    annot = parse_annotation("@type const Foo: String")
    assert_instance_of Steep::AST::Annotation::ConstType, annot
    assert_equal ModuleName.parse("Foo"), annot.name
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_const_type3
    annot = parse_annotation("@type const ::Foo: String")
    assert_instance_of Steep::AST::Annotation::ConstType, annot
    assert_equal ModuleName.parse("::Foo"), annot.name
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_instance_type
    annot = parse_annotation("@type instance: String")
    assert_instance_of Steep::AST::Annotation::InstanceType, annot
    assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
  end

  def test_module_type
    annot = parse_annotation("@type module: String.class")
    assert_instance_of Steep::AST::Annotation::ModuleType, annot
    assert_equal Steep::AST::Types::Name.new_class(name: :String, constructor: nil), annot.type
  end

  def test_implements
    annot = parse_annotation("@implements String")
    assert_instance_of Steep::AST::Annotation::Implements, annot
    assert_equal ModuleName.parse(:String), annot.name.name
    assert_empty annot.name.args
  end

  def test_implement2
    annot = parse_annotation("@implements Array<'a>")
    assert_instance_of Steep::AST::Annotation::Implements, annot
    assert_equal ModuleName.parse(:Array), annot.name.name
    assert_equal [:a], annot.name.args
  end

  def test_ivar_type
    annot = parse_annotation("@type ivar @x: Integer")
    assert_instance_of Steep::AST::Annotation::IvarType, annot
    assert_equal :"@x", annot.name
    assert_equal Steep::AST::Types::Name.new_instance(name: :Integer), annot.type
  end

  def test_dynamic
    parse_annotation("@dynamic foo, self.bar, self?.baz").yield_self do |annot|
      assert_instance_of Steep::AST::Annotation::Dynamic, annot

      assert_equal Steep::AST::Annotation::Dynamic::Name.new(name: :foo, kind: :instance), annot.names[0]
      assert_equal Steep::AST::Annotation::Dynamic::Name.new(name: :bar, kind: :module), annot.names[1]
      assert_equal Steep::AST::Annotation::Dynamic::Name.new(name: :baz, kind: :module_instance), annot.names[2]
    end
  end

  def test_break
    annot = parse_annotation("@type break: Integer")
    assert_instance_of Steep::AST::Annotation::BreakType, annot
    assert_equal Steep::AST::Types::Name.new_instance(name: :Integer), annot.type
  end
end
