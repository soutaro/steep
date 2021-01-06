require "test_helper"

class AnnotationParsingTest < Minitest::Test
  include TestHelper
  include ASTAssertion
  include FactoryHelper

  AnnotationParser = Steep::AnnotationParser
  Annotation = Steep::AST::Annotation
  Types = Steep::AST::Types

  def parse_type(src, factory:)
    factory.type(RBS::Parser.parse_type(src))
  end

  def parse_annotation(source, factory:)
    AnnotationParser.new(factory: factory).parse(source, location: nil)
  end

  def test_skip_annotation
    with_factory do |factory|
      annot = parse_annotation("This is not annotation", factory: factory)
      assert_nil annot
    end
  end

  def test_var_type_annotation
    with_factory do |factory|
      annot = parse_annotation("@type var foo: Bar", factory: factory)
      assert_instance_of Annotation::VarType, annot
      assert_equal :foo, annot.name
      assert_equal Types::Name.new_instance(name: :Bar), annot.type
    end
  end

  def test_method_annotation
    with_factory do |factory|
      annot = parse_annotation("@type method foo: (Bar) -> Baz", factory: factory)

      assert_instance_of Annotation::MethodType, annot
      assert_equal :foo, annot.name
      assert_equal factory.method_type(RBS::Parser.parse_method_type("(Bar) -> Baz"), self_type: Steep::AST::Types::Self.new, method_decls: Set[]),
                   annot.type
    end
  end

  def test_return_type_annotation
    with_factory do |factory|
      annot = parse_annotation("@type return: Integer", factory: factory)

      assert_instance_of Annotation::ReturnType, annot
      assert_equal parse_type("Integer", factory: factory), annot.type
    end
  end

  def test_block_type_annotation
    with_factory do |factory|
      annot = parse_annotation("@type block: String", factory: factory)

      assert_instance_of Annotation::BlockType, annot
      assert_equal parse_type("String", factory: factory), annot.type
    end
  end

  def test_self_type
    with_factory do |factory|
      annot = parse_annotation("@type self: String", factory: factory)
      assert_instance_of Annotation::SelfType, annot
      assert_equal parse_type("String", factory: factory), annot.type
    end
  end

  def test_const_type
    with_factory do |factory|
      annot = parse_annotation("@type const Foo::Bar::Baz: String", factory: factory)
      assert_instance_of Annotation::ConstType, annot
      assert_equal TypeName("Foo::Bar::Baz"), annot.name
      assert_equal parse_type("String", factory: factory), annot.type
    end
  end

  def test_const_type2
    with_factory do |factory|
      annot = parse_annotation("@type const Foo: String", factory: factory)
      assert_instance_of Annotation::ConstType, annot
      assert_equal TypeName("Foo"), annot.name
      assert_equal parse_type("String", factory: factory), annot.type
    end
  end

  def test_const_type3
    with_factory do |factory|
      annot = parse_annotation("@type const ::Foo: String", factory: factory)
      assert_instance_of Annotation::ConstType, annot
      assert_equal TypeName("::Foo"), annot.name
      assert_equal parse_type("String", factory: factory), annot.type
    end
  end

  def test_instance_type
    with_factory do |factory|
      annot = parse_annotation("@type instance: String", factory: factory)
      assert_instance_of Annotation::InstanceType, annot
      assert_equal Steep::AST::Types::Name.new_instance(name: :String), annot.type
    end
  end

  def test_module_type
    with_factory do |factory|
      annot = parse_annotation("@type module: singleton(String)", factory: factory)
      assert_instance_of Annotation::ModuleType, annot
      assert_equal parse_type("singleton(String)", factory: factory), annot.type
    end
  end

  def test_implements
    with_factory do |factory|
      annot = parse_annotation("@implements String", factory: factory)
      assert_instance_of Annotation::Implements, annot
      assert_equal TypeName("String"), annot.name.name
      assert_empty annot.name.args
    end
  end

  def test_implement2
    with_factory do |factory|
      annot = parse_annotation("@implements Array[A]", factory: factory)
      assert_instance_of Annotation::Implements, annot
      assert_equal TypeName('Array'), annot.name.name
      assert_equal [:A], annot.name.args
    end
  end

  def test_ivar_type
    with_factory do |factory|
      annot = parse_annotation("@type ivar @x: Integer", factory: factory)
      assert_instance_of Annotation::IvarType, annot
      assert_equal :"@x", annot.name
      assert_equal parse_type("Integer", factory: factory), annot.type
    end
  end

  def test_dynamic
    with_factory do |factory|
      parse_annotation("@dynamic foo, self.bar, self?.baz, self.current=", factory: factory).tap do |annot|
        assert_instance_of Annotation::Dynamic, annot

        assert_equal Annotation::Dynamic::Name.new(name: :foo, kind: :instance), annot.names[0]
        assert_equal Annotation::Dynamic::Name.new(name: :bar, kind: :module), annot.names[1]
        assert_equal Annotation::Dynamic::Name.new(name: :baz, kind: :module_instance), annot.names[2]
        assert_equal Annotation::Dynamic::Name.new(name: :current=, kind: :module), annot.names[3]
      end

      parse_annotation("@dynamic foo", factory: factory).tap do |annot|
        assert_instance_of Annotation::Dynamic, annot
      end
    end
  end

  def test_break
    with_factory do |factory|
      annot = parse_annotation("@type break: Integer", factory: factory)
      assert_instance_of Annotation::BreakType, annot
      assert_equal parse_type("Integer", factory: factory), annot.type
    end
  end

  def test_annotation_syntax_error
    with_factory do |factory|
      exn = assert_raises AnnotationParser::SyntaxError do
        parse_annotation("@type break: Array<Integer.class>", factory: factory)
      end

      assert_equal "@type break: Array<Integer.class>", exn.source
      assert_instance_of RBS::Parser::SyntaxError, exn.cause
    end
  end
end
