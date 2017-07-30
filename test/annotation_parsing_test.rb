require "test_helper"

class AnnotationParsingTest < Minitest::Test
  Parser = Steep::Parser

  def test_skip_annotation
    annot = Parser.parse_annotation_opt("This is not annotation")
    assert_nil annot
  end

  def test_var_type_annotation
    annot = Parser.parse_annotation_opt("@type var foo: Bar")
    assert_equal :foo, annot.var
    assert_equal Steep::Types::Name.interface(name: :Bar), annot.type
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
    assert_equal Steep::Types::Name.interface(name: :Integer), annot.type
  end

  def test_block_type_annotation
    annot = Parser.parse_annotation_opt("@type block: String")
    assert_equal Steep::Types::Name.interface(name: :String), annot.type
  end
end
