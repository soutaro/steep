require_relative "../test_helper"

# @rbs use Steep::*

class CompletionProvider__RubyTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep
  CompletionProvider = Services::CompletionProvider #: singleton(Steep::Services::CompletionProvider)

  def test_on_lower_identifier
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
req

lvar1 = 1
lvar2 = "2"
lva
lvar1
      EOR

        provider.run(line: 1, column: 3).tap do |items|
          assert_equal [:require], items.map(&:identifier)
        end

        provider.run(line: 5, column: 3).tap do |items|
          assert_equal [:lvar1, :lvar2], items.map(&:identifier)
        end

        provider.run(line: 6, column: 5).tap do |items|
          assert_equal [:lvar1], items.map(&:identifier)
        end
      end
    end
  end

  def test_on_upper_identifier
    with_checker <<EOF do
class Object
  def Array: (untyped) -> Array[untyped]
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
Arr
      EOR

        provider.run(line: 1, column: 3).tap do |items|
          assert_equal 2, items.size

          items.find {|item| item.is_a?(CompletionProvider::ConstantItem) }.tap do |item|
            assert_equal :Array, item.identifier
          end

          items.find {|item| item.is_a?(CompletionProvider::SimpleMethodNameItem) }.tap do |item|
            assert_equal :Array, item.identifier
            assert_equal MethodName("::Object#Array"), item.method_name
          end
        end
      end
    end
  end

  def test_on_method_identifier
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
self.cl
      EOR

        provider.run(line: 1, column: 7).tap do |items|
          assert_equal [:class], items.map(&:identifier)
        end

        provider.run(line: 1, column: 5).tap do |items|
          assert_equal [:class, :is_a?, :itself, :nil?, :tap, :to_s], items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_method_identifier_colon2
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
self::cl
      EOR

        provider.run(line: 1, column: 8).tap do |items|
          assert_equal [:class], items.map(&:identifier)
        end

        provider.run(line: 1, column: 6).tap do |items|
          assert_equal [:class, :is_a?, :itself, :nil?, :tap, :to_s], items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_ivar_identifier
    with_checker <<EOF do
class Hello
  @foo1: String
  @foo2: Integer

  def world: () -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
class Hello
  def world
    @foo
    @foo2
  end
end
      EOR

        provider.run(line: 3, column: 8).tap do |items|
          assert_equal [:@foo1, :@foo2], items.map(&:identifier)
        end

        provider.run(line: 4, column: 9).tap do |items|
          assert_equal [:@foo2], items.map(&:identifier)
        end
      end
    end
  end

  def test_dot_trigger
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
" ".
      EOR

        provider.run(line: 1, column: 4).tap do |items|
          assert_equal [
            :class,
            :is_a?,
            :itself,
            :nil?,
            :size,
            :tap,
            :to_s,
            :to_str
          ],
          items.map(&:identifier).sort
        end
      end
    end
  end

  def test_qcall_trigger
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
n = [1].first
n&.to
      EOR

        provider.run(line: 2, column: 3).tap do |items|
          assert_equal [
            :class,
            :is_a?,
            :itself,
            :nil?,
            :tap,
            :to_int,
            :to_s,
            :zero?
          ],
          items.map(&:identifier).sort
        end

        provider.run(line: 2, column: 5).tap do |items|
          assert_equal [:to_int, :to_s], items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_atmark
    with_checker <<EOF do
class Hello
  @foo1: String
  @foo2: Integer

  def world: () -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
class Hello
  def world
    @
  end
end
      EOR

        provider.run(line: 3, column: 5).tap do |items|
          assert_equal [:@foo1, :@foo2], items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_trigger
    with_checker <<EOF do
class Hello
  @foo1: String
  @foo2: Integer

  def world: () -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
class Hello
  def world

  end

end
      EOR

        provider.run(line: 3, column: 0).tap do |items|
          items.grep(CompletionProvider::InstanceVariableItem).tap do |items|
            assert_equal [:@foo1, :@foo2], items.map(&:identifier)
          end
          items.grep(CompletionProvider::LocalVariableItem).tap do |items|
            assert_empty items
          end
          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_equal [:class, :gets, :is_a?, :itself, :nil?, :puts, :require, :tap, :to_s, :world],
                         items.map(&:identifier).sort
          end
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:Array, :BasicObject, :Class, :FalseClass, :Float, :Hash, :Hello, :Integer, :Module, :NilClass, :Numeric, :Object, :Proc, :Range, :Regexp, :String, :Symbol, :TrueClass],
                         items.map(&:identifier).sort
          end
        end

        provider.run(line: 5, column: 0).tap do |items|
          items.grep(CompletionProvider::InstanceVariableItem).tap do |items|
            assert_empty items
          end
          items.grep(CompletionProvider::LocalVariableItem).tap do |items|
            assert_empty items
          end
          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_equal [:attr_reader, :block_given?, :class, :gets, :is_a?, :itself, :new, :nil?, :puts, :require, :tap, :to_s],
                         items.map(&:identifier).sort
          end
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:Array, :BasicObject, :Class, :FalseClass, :Float, :Hash, :Hello, :Integer, :Module, :NilClass, :Numeric, :Object, :Proc, :Range, :Regexp, :String, :Symbol, :TrueClass],
                         items.map(&:identifier).sort
          end
        end
      end
    end
  end

  def test_on_interface
    with_checker <<EOF do
interface _ToStr
  def to_str: () -> String
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
# @type var x: _ToStr
x = _ = nil

x.
      EOR

        provider.run(line: 4, column: 2).tap do |items|
          assert_equal [:to_str],
                       items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_module_public
    with_checker <<EOF do
interface _Named
  def name: () -> String
end

module TestModule : _Named
  def foo: () -> String

  def bar: () -> Integer
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
module TestModule
  def foo
    self.
  end
end
      EOR

        provider.run(line: 3, column: 9).tap do |items|
          assert_equal [:bar, :class, :foo, :is_a?, :itself, :name, :nil?, :tap, :to_s],
                       items.map(&:identifier).sort
        end
      end
    end
  end

  def test_on_paren
    with_checker <<EOF do
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
require()
      EOR

        provider.run(line: 1, column: 8)
      end
    end
  end

  def test_on_const
    with_checker <<EOF do
class Hello
  class World
  end
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
Hello::W
      EOR

        provider.run(line: 1, column: 8).tap do |items|
          assert_equal [:World], items.map(&:identifier)
        end
      end
    end
  end

  def test_on_colon2_parent
    with_checker <<EOF do
class Hello
  class World
  end
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
Hello::
      EOR

        provider.run(line: 1, column: 7).tap do |items|
          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_equal [:attr_reader, :block_given?, :class, :is_a?, :itself, :new, :nil?, :tap, :to_s],
                         items.map(&:identifier).sort
          end
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:World],
                         items.map(&:identifier).sort
          end
        end
      end
    end
  end

  def test_on_colon2_root
    with_checker <<EOF do
class Hello
  class World
  end
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
::
      EOR

        provider.run(line: 1, column: 2).tap do |items|
          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_empty items
          end
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:Array, :BasicObject, :Class, :FalseClass, :Float, :Hash, :Hello, :Integer, :Module, :NilClass, :Numeric, :Object, :Proc, :Range, :Regexp, :String, :Symbol, :TrueClass],
                         items.map(&:identifier).sort
          end
        end
      end
    end
  end

  def test_on_colon2_call
    with_checker <<EOF do
class Hello
  class World
  end
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
Hello::
bar()
      EOR

        # provider.run(line: 1, column: 7).tap do |items|
        #   assert_equal [:World], items.map(&:identifier)
        # end

        provider.run(line: 1, column: 7).tap do |items|
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:World],
                         items.map(&:identifier).sort
          end

          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_equal [:attr_reader, :block_given?, :class, :is_a?, :itself, :new, :nil?, :tap, :to_s],
                         items.map(&:identifier).sort
          end
        end
      end
    end
  end

  def test_on_colon2_call_masgn
    with_checker <<EOF do
class Hello
  class World
  end
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
Hello::
a, b = []
      EOR

        provider.run(line: 1, column: 7).tap do |items|
          items.grep(CompletionProvider::ConstantItem).tap do |items|
            assert_equal [:World], items.map(&:identifier).sort
          end
        end
      end
    end
  end

  def test_simple_method_name_item_two_defs
    with_checker <<~RBS do
        class TestClass
          def foo: () -> String

          def foo: (String) -> void
                 | ...
        end
      RBS
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
          TestClass.new.f
        RUBY

        provider.run(line: 1, column: 15).tap do |items|
          items.grep(CompletionProvider::SimpleMethodNameItem).tap do |items|
            assert_equal [:foo, :foo], items.map(&:identifier).sort

            assert_any!(items) do |item|
              assert_equal <<~RBS.chomp, item.method_member.location.source
                  def foo: () -> String
                RBS
            end

            assert_any!(items) do |item|
              assert_equal <<~RBS.chomp, item.method_member.location.source
                  def foo: (String) -> void
                           | ...
                RBS
            end
          end
        end
      end
    end
  end

  def test_generated_method_name_item
    with_checker <<~RBS do
      RBS
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
          a = [] #: [Integer, String]
          a.fir
        RUBY

        provider.run(line: 2, column: 5).tap do |items|
          items.grep(CompletionProvider::GeneratedMethodNameItem).tap do |items|
            assert_equal [:first], items.map(&:identifier).sort

            assert_equal ["() -> ::Integer"], items[0].method_types.map(&:to_s)

          end
        end
      end
    end
  end

  def test_complex_method_name_item
    with_checker <<~RBS do
        class Integer
          def to_s: () -> String
        end

        class String
          def to_s: () -> String
        end
      RBS
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
          a = [] #: Integer | String
          a.to_s
        RUBY

        provider.run(line: 2, column: 6).tap do |items|
          items.grep(CompletionProvider::ComplexMethodNameItem).tap do |items|
            assert_equal [:to_s], items.map(&:identifier).sort

            assert_equal ["() -> ::String"], items[0].method_types.map(&:to_s)
            assert_equal [MethodName("::Integer#to_s"), MethodName("::String#to_s")], items[0].method_names
          end
        end
      end
    end
  end

  def test_on_comment
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        x = [] # Hoge hoge
      RUBY

        provider.run(line: 1, column: 10).tap do |items|
          assert_empty items
        end
      end
    end
  end

  def test_on_steep_inline_comment
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        # @type var x: Ar
        x = []
      RUBY

        provider.run(line: 1, column: 17).tap do |items|
          assert_equal [RBS::TypeName.parse("Array")], items.map(&:relative_type_name)
        end
      end
    end
  end

  def test_on_steep_type_assertion
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        x = [] #: Ar
      RUBY

        provider.run(line: 1, column: 12).tap do |items|
          assert_equal [RBS::TypeName.parse("Array")], items.map(&:relative_type_name)
        end
      end
    end
  end

  def test_on_steep_type_application
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<~RUBY, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        [1, 2].inject([]) do |x, y| #$ Ar
        end
      RUBY

        provider.run(line: 1, column: 33).tap do |items|
          assert_equal [RBS::TypeName.parse("Array")], items.map(&:relative_type_name)
        end
      end
    end
  end

  def test_first_keyword_argument
    with_checker <<EOF do
class TestClass
  def foo: (arg1: Integer, arg2: Integer, ?arg3: Integer, ?arg4: Integer) -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
TestClass.new.foo(a)
      EOR

        provider.run(line: 1, column: 19).tap do |items|
          assert_equal ["arg1:", "arg2:", "arg3:", "arg4:"], items.map(&:identifier)
        end
      end
    end
  end

  def test_following_keyword_argument
    with_checker <<EOF do
class TestClass
  def foo: (arg1: Integer, arg2: Integer, ?arg3: Integer, ?arg4: Integer) -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
TestClass.new.foo(arg1: 1, a)
      EOR

        provider.run(line: 1, column: 28).tap do |items|
          assert_equal ["arg2:", "arg3:", "arg4:"], items.map(&:identifier)
        end
      end
    end
  end

  def test_keyword_argument_block
    with_checker <<EOF do
class TestClass
  def foo: (arg1: Integer, arg2: Integer, ?arg3: Integer, ?arg4: Integer) { () -> void } -> void
end
EOF
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
TestClass.new.foo(arg1: 1, a) do
end
#                         ^
      EOR

        provider.run(line: 1, column: 28).tap do |items|
          assert_equal ["arg2:", "arg3:", "arg4:"], items.map(&:identifier)
        end
      end
    end
  end

  def test_comment__ignore
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
# s
      EOR

        provider.run(line: 1, column: 3).tap do |items|
          assert_equal ["steep:ignore:start", "steep:ignore:end", "steep:ignore ${1:optional diagnostics}"], items.map(&:text)
        end
      end
    end
  end

  def test_comment__type
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
# @
      EOR

        provider.run(line: 1, column: 3).tap do |items|
          assert_equal(
            ["@type var ${1:variable}: ${2:var type}", "@type self: ${1:self type}", "@type block: ${1:block type}", "@type break: ${1:break type}"],
            items.map(&:text)
          )
        end
      end
    end
  end

  def test_self_receiver_call_type
    with_checker do
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
puts i
      EOR

        provider.run(line: 1, column: 6) # Assert nothing raised
      end
    end
  end

  def test_constant__deprecated
    with_checker(<<~RBS) do
        %a{deprecated} class Foo
        end

        %a{deprecated} class Bar = Foo

        %a{deprecated} BAZ: String
      RBS
      CompletionProvider::Ruby.new(source_text: <<-EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        Foo
        Bar
        BAZ
      EOR


        items = provider.run(line: 1, column: 3)
        items.find {|item| item.is_a?(CompletionProvider::ConstantItem) && item.full_name.to_s == "::Foo" }.tap do |item|
          assert_predicate item, :deprecated?
        end

        items = provider.run(line: 2, column: 3)
        items.find {|item| item.is_a?(CompletionProvider::ConstantItem) && item.full_name.to_s == "::Foo" }.tap do |item|
          assert_predicate item, :deprecated?
        end

        items = provider.run(line: 3, column: 3)
        items.find {|item| item.is_a?(CompletionProvider::ConstantItem) && item.full_name.to_s == "::Foo" }.tap do |item|
          assert_predicate item, :deprecated?
        end
      end
    end
  end

  def test_method__deprecated
    with_checker(<<~RBS) do
        class Foo
          def m1: () -> void

          %a{deprecated} def m2: () -> void

          %a{deprecated} alias m3 m1
        end
      RBS
      CompletionProvider::Ruby.new(source_text: <<~EOR, path: Pathname("foo.rb"), subtyping: checker).tap do |provider|
        Foo.new.m
      EOR

        items = provider.run(line: 1, column: 9)

        items.find {|item| item.identifier == :m1 }.tap do |item|
          refute_operator item, :deprecated
        end
        items.find {|item| item.identifier == :m2 }.tap do |item|
          assert_operator item, :deprecated
        end
        items.find {|item| item.identifier == :m3 }.tap do |item|
          assert_operator item, :deprecated
        end
      end
    end
  end
end
