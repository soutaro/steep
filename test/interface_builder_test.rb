require_relative "test_helper"

class InterfaceBuilderTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  include Steep

  def config(**opts)
    opts = opts.merge(
      {
        self_type: parse_type("::Object"),
        class_type: nil,
        instance_type: nil,
        resolve_self: true,
        resolve_class: true,
        resolve_instance: true,
        variable_bounds: {},
      }
    )
    Interface::Builder::Config.new(**opts)
  end

  def test_interface_shape
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def hello: () -> void
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::_Foo"), public_only: true, config: config)

      assert_equal parse_type("::_Foo"), shape.type
      assert_equal [:hello], shape.methods.each_name.to_a
      assert_equal [parse_method_type("() -> void")], shape.methods[:hello].method_types
    end
  end

  def test_class_shape
    with_factory({ "a.rbs" => <<-RBS }) do
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::String"), public_only: true, config: config)

      assert_equal parse_type("::String"), shape.type
      assert_includes shape.methods.each_name.to_a, :gsub!      # Method from String
      assert_includes shape.methods.each_name.to_a, :__id__     # Method from BasicObject
      refute_includes shape.methods.each_name.to_a, :initialize # Private method String
    end
  end

  def test_interface_shape_unfold_self
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def itself: () -> self
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::_Foo"),
        public_only: true,
        config: config.update(resolve_self: true)
      )

      assert_equal parse_type("::_Foo"), shape.type
      assert_equal [parse_method_type("() -> ::_Foo")], shape.methods[:itself].method_types
    end
  end

  def test_self_shape_with_resolve
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def itself: () -> self
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("self"),
        public_only: true,
        config: config.update(
          resolve_self: true,
          self_type: parse_type("::_Foo")
        )
      )

      assert_equal parse_type("::_Foo"), shape.type
      assert_equal [parse_method_type("() -> self")], shape.methods[:itself].method_types
    end
  end

  def test_self_shape_with_resolve_application
    with_factory({ "a.rbs" => <<-RBS }) do
class Foo[A, B, C]
  def foo: () -> [A, B, C]
         | () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::Foo[self, class, instance]"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::String"),
          class_type: parse_type("singleton(::String)"),
          instance_type: parse_type("::String"),
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type("::Foo[::String, singleton(::String), ::String]"), shape.type
      assert_equal(
        [
          parse_method_type("() -> [::String, singleton(::String), ::String]"),
          parse_method_type("() -> [::Foo[::String, singleton(::String), ::String], singleton(::Foo), ::Foo[untyped, untyped, untyped]]")
        ],
        shape.methods[:foo].method_types
      )
    end
  end

  def test_self_shape_with_resolve_application_union
    with_factory({ "a.rbs" => <<-RBS }) do
class Foo[A, B, C]
  def itself: () -> [A, B, C]

  def foo: () -> [self, instance, class]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::Foo[self, class, instance]?"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::String"),
          class_type: parse_type("singleton(::String)"),
          instance_type: parse_type("::String"),
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type("::Foo[::String, singleton(::String), ::String]?"), shape.type
      assert_equal(
        [
          parse_method_type("() -> ([self, class, instance] | ::Foo[self, class, instance] | nil)"),
        ],
        shape.methods[:itself].method_types
      )
    end
  end

  def test_shape_bool
    with_factory({ "a.rbs" => <<-RBS }) do
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("bool"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::String"),
          class_type: parse_type("singleton(::String)"),
          instance_type: parse_type("::String"),
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type("bool"), shape.type
      assert_equal(
        [
          parse_method_type("() -> bool")
        ],
        shape.methods[:itself].method_types
      )
    end
  end

  def test_shape_literal
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type(":foo"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::String"),
          class_type: parse_type("singleton(::String)"),
          instance_type: parse_type("::String"),
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type(":foo"), shape.type
      assert_equal(
        [
          parse_method_type("() -> :foo")
        ],
        shape.methods[:itself].method_types
      )
      assert_equal(
        [
          parse_method_type("() -> [:foo, singleton(::Symbol), ::Symbol]")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_shape_union_self_no_self
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::Integer | ::String"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::Object"),
          class_type: nil,
          instance_type: nil,
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type("::Integer | ::String"), shape.type
      assert_equal(
        [
          parse_method_type("() -> ([::Integer | ::String, singleton(::Integer), ::Integer] | [::Integer | ::String, singleton(::String), ::String])")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_shape_union_self_with_self
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("self?"),
        public_only: true,
        config: config.update(
          self_type: parse_type("::Object"),
          class_type: nil,
          instance_type: nil,
          resolve_self: true,
          resolve_class: true,
          resolve_instance: true
        )
      )

      assert_equal parse_type("::Object?"), shape.type
      assert_equal(
        [
          parse_method_type("() -> ([self?, singleton(::Object), ::Object] | [self?, singleton(::NilClass), ::NilClass])")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_instance_shape_with_resolve
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def itself: () -> self
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("instance"),
        public_only: true,
        config: config.update(instance_type: parse_type("::Array[bool]"))
      )

      assert_equal parse_type("::Array[bool]"), shape.type
    end
  end

  def test_class_shape_with_resolve
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def itself: () -> self
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("class"),
        public_only: true,
        config: config.update(class_type: parse_type("singleton(::Array)"))
      )

      assert_equal parse_type("singleton(::Array)"), shape.type
    end
  end

  def test_alias_shape
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def itself: () -> self
end

type foo = _Foo
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::foo"), public_only: true, config: config)

      assert_equal parse_type("::foo"), shape.type
    end
  end

  def test_alias_shape_broken
    with_factory({ "a.rbs" => <<-RBS }) do
type k = k | ^() -> k
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::k"), public_only: true, config: config)

      assert_nil shape
    end
  end

  def test_union_shape_methods
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def f: (Integer) -> Integer

  def g: (String) -> Integer

  def h: () -> void
end

interface _Bar
  def f: (String) -> String

  def g: () -> void
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::_Foo | ::_Bar"), public_only: true, config: config)

      assert_equal parse_type("::_Foo | ::_Bar"), shape.type
      assert_equal [:f], shape.methods.each_name.to_a

      assert_equal [parse_method_type("(::Integer & ::String) -> (::Integer | ::String)")], shape.methods[:f].method_types
    end
  end

  def test_intersection_shape_methods
    with_factory({ "a.rbs" => <<-RBS }) do
interface _Foo
  def f: (Integer) -> Integer

  def g: (String) -> Integer
end

interface _Bar
  def f: (String) -> String
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("::_Foo & ::_Bar"), public_only: true, config: config)

      assert_equal parse_type("::_Foo & ::_Bar"), shape.type
      assert_equal [:f, :g], shape.methods.each_name.to_a

      assert_equal [parse_method_type("(::String) -> ::String")], shape.methods[:f].method_types
      assert_equal [parse_method_type("(::String) -> ::Integer")], shape.methods[:g].method_types
    end
  end

  def test_tuple_shape
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("[::Integer, top]"), public_only: true, config: config)

      assert_equal parse_type("[::Integer, top]"), shape.type

      assert_includes(shape.methods[:[]].method_types, parse_method_type("(0) -> ::Integer"))
      assert_includes(shape.methods[:[]].method_types, parse_method_type("(1) -> top"))

      assert_includes(shape.methods[:[]=].method_types, parse_method_type("(0, ::Integer) -> ::Integer"))
      assert_includes(shape.methods[:[]=].method_types, parse_method_type("(1, top) -> top"))

      assert_includes(shape.methods[:fetch].method_types, parse_method_type("(0) -> ::Integer"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("(1) -> top"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (0, T) -> (::Integer | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (1, T) -> (top | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (0) { (::Integer) -> T } -> (::Integer | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (1) { (::Integer) -> T } -> (top | T)"))

      assert_equal([parse_method_type("() -> ::Integer")], shape.methods[:first].method_types)
      assert_equal([parse_method_type("() -> top")], shape.methods[:last].method_types)

      assert_equal(
        [
          parse_method_type("() -> [[::Integer, top], singleton(::Array), ::Array[untyped]]")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_record_shape
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("{ id: ::Integer, name: ::String }"), public_only: true, config: config)

      assert_equal parse_type("{ id: ::Integer, name: ::String }"), shape.type

      assert_includes(shape.methods[:[]].method_types, parse_method_type("(:id) -> ::Integer"))
      assert_includes(shape.methods[:[]].method_types, parse_method_type("(:name) -> ::String"))

      assert_includes(shape.methods[:[]=].method_types, parse_method_type("(:id, ::Integer) -> ::Integer"))
      assert_includes(shape.methods[:[]=].method_types, parse_method_type("(:name, ::String) -> ::String"))

      assert_includes(shape.methods[:fetch].method_types, parse_method_type("(:id) -> ::Integer"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("(:name) -> ::String"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (:id, T) -> (::Integer | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (:name, T) -> (::String | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (:id) { (:id | :name) -> T } -> (::Integer | T)"))
      assert_includes(shape.methods[:fetch].method_types, parse_method_type("[T] (:name) { (:id | :name) -> T } -> (::String | T)"))

      assert_equal(
        [
          parse_method_type("() -> [{ id: ::Integer, name: ::String }, singleton(::Hash), ::Hash[untyped, untyped]]")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_proc_shape
    with_factory({ "a.rbs" => <<-RBS }) do
class BasicObject
  def special_types: () -> [self, class, instance]
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(parse_type("^(::String) { (::Integer) -> void } -> ::String"), public_only: true, config: config)

      assert_equal parse_type("^(::String) { (::Integer) -> void } -> ::String"), shape.type

      assert_equal(
        [parse_method_type("(::String) { (::Integer) -> void } -> ::String")],
        shape.methods[:[]].method_types
      )
      assert_equal(
        [parse_method_type("(::String) { (::Integer) -> void } -> ::String")],
        shape.methods[:call].method_types
      )

      assert_equal(
        [
          parse_method_type("() -> [^(::String) { (::Integer) -> void } -> ::String, singleton(::Proc), ::Proc]")
        ],
        shape.methods[:special_types].method_types
      )
    end
  end

  def test_union_try
    with_factory({ "a.rbs" => <<-RBS }, nostdlib: true) do
class BasicObject
end

class Object < BasicObject
  def try: [T] () { (self) -> T } -> T
         | [T] () { () -> T } -> T
end

class Module
end

class Class < Module
  def new: () -> instance
end

class Integer
end

class String
end

class Symbol
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::Integer | ::String"),
        public_only: true,
        config: config.update(resolve_self: parse_type("::Integer | ::String"))
      )

      assert_equal(
        [
          parse_method_type("[T] () { ((::Integer | ::String)) -> T } -> T"),
          parse_method_type("[T] () { () -> T } -> T")
        ],
        shape.methods[:try].method_types
      )
    end
  end

  def test_union_itself
    with_factory({ "a.rbs" => <<-RBS }, nostdlib: true) do
class BasicObject
end

class Object < BasicObject
  def itself: () -> self
end

class Module
end

class Class < Module
  def new: () -> instance
end

class Integer
end

class String
end

class Symbol
end
      RBS
      builder = Interface::Builder.new(factory)

      shape = builder.shape(
        parse_type("::Object"),
        public_only: true,
        config: config.update(resolve_self: parse_type("::Object"))
      )

      shape = builder.shape(
        parse_type("::Integer | ::String"),
        public_only: true,
        config: config.update(resolve_self: parse_type("::Integer | ::String"))
      )

      assert_equal(
        [
          parse_method_type("() -> (::Integer | ::String)")
        ],
        shape.methods[:itself].method_types
      )
    end
  end
end
