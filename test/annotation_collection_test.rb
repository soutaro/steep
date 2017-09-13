require "test_helper"

class AnnotationCollectionTest < Minitest::Test
  include TestHelper

  Annotation = Steep::Annotation
  Types = Steep::Types

  def annotations
    @annotations ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(var: :x, type: Types::Name.new(name: :X, params: [])),
      Annotation::VarType.new(var: :y, type: Types::Name.new(name: :Y, params: [])),
      Annotation::ReturnType.new(type: Types::Name.new(name: :Z, params: [])),
      Annotation::BlockType.new(type: Types::Name.new(name: :A, params: [])),
      Annotation::Dynamic.new(name: :path)
    ])
  end

  def annotations_
    @annotations_ ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(var: :x, type: Types::Name.new(name: :X2, params: []))
    ])
  end

  def test_lookup_var_type
    assert_equal Types::Name.new(name: :X, params: []), annotations.lookup_var_type(:x)
    assert_equal Types::Name.new(name: :Y, params: []), annotations.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)
  end

  def test_return_type
    assert_equal Types::Name.new(name: :Z, params: []), annotations.return_type
  end

  def test_block_type
    assert_equal Types::Name.new(name: :A, params: []), annotations.block_type
  end

  def test_annotations_merge
    as = annotations + annotations_

    assert_equal Types::Name.new(name: :X2, params: []), as.lookup_var_type(:x)
    assert_equal Types::Name.new(name: :Y, params: []), as.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)

    assert_equal Types::Name.new(name: :Z, params: []), as.return_type
    assert_nil as.block_type
  end

  def test_dynamics
    assert_equal Set.new([:path]), annotations.dynamics
  end
end
