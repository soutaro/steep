require "test_helper"

class AnnotationParsingTest < Minitest::Test
  Parser = Steep::Parser

  def test_skip_annotation
    annot = Parser.parse_annotation_opt("This is not annotation")
    assert_nil annot
  end

  def test_var_type_annotation
    annot = Parser.parse_annotation_opt("@type foo: Bar")
    assert_equal :foo, annot.var
    assert_equal Steep::Types::Name.new(name: :Bar, params: []), annot.type
  end

  def test_method_annotation
    annot = Parser.parse_annotation_opt("@type foo: Bar -> Baz")
    assert_equal :foo, annot.method
    assert_equal Parser.parse_method("Bar -> Baz"), annot.type
  end

  def test_method_annotation_app
    annot = Parser.parse_annotation_opt("@type foo: <'a> Bar -> Baz")
    assert_equal :foo, annot.method
    assert_equal Parser.parse_method("<'a> Bar -> Baz"), annot.type
  end
end
