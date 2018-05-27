require "test_helper"

class AnnotationCollectionTest < Minitest::Test
  include TestHelper

  Annotation = Steep::AST::Annotation
  Types = Steep::AST::Types

  def annotations
    @annotations ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(name: :x, type: Types::Name.new_instance(name: :X)),
      Annotation::VarType.new(name: :y, type: Types::Name.new_instance(name: :Y)),
      Annotation::ReturnType.new(type: Types::Name.new_instance(name: :Z)),
      Annotation::BlockType.new(type: Types::Name.new_instance(name: :A)),
      Annotation::Dynamic.new(names: [
        Annotation::Dynamic::Name.new(name: :path, kind: :instance)
      ])
    ])
  end

  def annotations_
    @annotations_ ||= Annotation::Collection.new(annotations: [
      Annotation::VarType.new(name: :x, type: Types::Name.new_instance(name: :X2))
    ])
  end

  def test_lookup_var_type
    assert_equal Types::Name.new_instance(name: :X), annotations.lookup_var_type(:x)
    assert_equal Types::Name.new_instance(name: :Y), annotations.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)
  end

  def test_return_type
    assert_equal Types::Name.new_instance(name: :Z), annotations.return_type
  end

  def test_block_type
    assert_equal Types::Name.new_instance(name: :A), annotations.block_type
  end

  def test_annotations_merge
    as = annotations + annotations_

    assert_equal Types::Name.new_instance(name: :X2), as.lookup_var_type(:x)
    assert_equal Types::Name.new_instance(name: :Y), as.lookup_var_type(:y)
    assert_nil annotations.lookup_var_type(:z)

    assert_equal Types::Name.new_instance(name: :Z), as.return_type
    assert_nil as.block_type
  end

  def test_dynamics
    annotations.dynamics[:path].yield_self do |annot|
      assert_instance_of Annotation::Dynamic::Name, annot
      assert annot.instance_method?
      refute annot.module_method?
    end
  end
end
