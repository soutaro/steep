require_relative "set_theoretic_helper"

class SetTheoreticClassIndexTest < Minitest::Test
  include SetTheoreticHelper

  include Steep

  def names(set)
    set.map(&:to_s).sort
  end

  def test_descendants
    with_sigs do
      assert_equal ["::Baz", "::Qux"], names(class_index.descendants(type_name("::Foo")))
      assert_equal [], names(class_index.descendants(type_name("::Baz")))
      assert_equal ["::Float", "::Integer"], names(class_index.descendants(type_name("::Numeric")))
      assert_includes names(class_index.descendants(type_name("::Object"))), "::Qux"
      refute_includes names(class_index.descendants(type_name("::Object"))), "::BasicObject"
    end
  end

  def test_includers
    with_sigs do
      assert_equal ["::Bar", "::Both", "::Oc", "::Outer"], names(class_index.includers(type_name("::Taggable")))
      assert_equal ["::Float", "::Integer", "::Numeric", "::String"], names(class_index.includers(type_name("::Comparable")))
      assert_equal ["::Array", "::Hash", "::Range"], names(class_index.includers(type_name("::Enumerable")))
      assert_equal [], names(class_index.includers(type_name("::Lonely")))
      assert_includes names(class_index.includers(type_name("::Kernel"))), "::Foo"
    end
  end

  def test_extenders
    with_sigs do
      assert_equal ["::Extending"], names(class_index.extenders(type_name("::Taggable")))
      assert_equal [], names(class_index.extenders(type_name("::Sortable")))
    end
  end

  def test_instance_classes
    with_sigs do
      assert_equal ["::Baz", "::Foo", "::Qux"], names(class_index.instance_classes(type_name("::Foo")))
      assert_equal ["::Bar", "::Both", "::Oc"], names(class_index.instance_classes(type_name("::Taggable")))
      assert_equal [], names(class_index.instance_classes(type_name("::_Quacks")))
    end
  end

  def test_common_instance
    with_sigs do
      assert class_index.common_instance?(type_name("::Foo"), type_name("::Sortable"))
      assert class_index.common_instance?(type_name("::Taggable"), type_name("::Sortable"))
      refute class_index.common_instance?(type_name("::Foo"), type_name("::Taggable"))
      refute class_index.common_instance?(type_name("::Taggable"), type_name("::Lonely"))
    end
  end

  def test_singleton_extends
    with_sigs do
      assert class_index.singleton_extends?(type_name("::Extending"), type_name("::Taggable"))
      refute class_index.singleton_extends?(type_name("::Foo"), type_name("::Taggable"))
    end
  end
end
