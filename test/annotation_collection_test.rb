require "test_helper"

class AnnotationCollectionTest < Minitest::Test
  include TestHelper

  Annotation = Steep::Annotation
  Types = Steep::Types

  def annotations
    @annotations ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(var: :x, type: Types::Name.new(name: :X, params: [])),
      Annotation::VarType.new(var: :y, type: Types::Name.new(name: :Y, params: []))
    ])
  end

  def annotations_
    @annotations_ ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(var: :x, type: Types::Name.new(name: :X2, params: [])),
    ])
  end

  def test_lookup_var_type
    assert_equal Types::Name.new(name: :X, params: []), annotations.lookup_var_type(:x)
    assert_equal Types::Name.new(name: :Y, params: []), annotations.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)
  end

  def test_annotations_merge
    as = annotations + annotations_

    assert_equal Types::Name.new(name: :X2, params: []), as.lookup_var_type(:x)
    assert_equal Types::Name.new(name: :Y, params: []), as.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)
  end
end
