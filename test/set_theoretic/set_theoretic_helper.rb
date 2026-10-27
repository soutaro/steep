require_relative "../test_helper"

module SetTheoreticHelper
  include TestHelper
  include FactoryHelper

  # A class hierarchy with the shapes the emptiness check decides on, without the whole core library
  SIGS = <<~RBS
    class BasicObject
    end

    module Kernel : BasicObject
    end

    class Object < BasicObject
      include Kernel
    end

    class Module
    end

    class Class < Module
    end

    module Comparable
    end

    module Enumerable[unchecked out Elem]
    end

    class Numeric
      include Comparable
    end

    class Integer < Numeric
    end

    class Float < Numeric
    end

    class String
      include Comparable
    end

    class Symbol
    end

    class NilClass
    end

    class TrueClass
    end

    class FalseClass
    end

    class Array[unchecked out Elem]
      include Enumerable[Elem]
    end

    class Hash[unchecked out K, unchecked out V]
      include Enumerable[[K, V]]
    end

    class Range[out Elem]
      include Enumerable[Elem]
    end

    class Proc
    end

    class Box[out T]
    end

    class Sink[in T]
    end

    class Cell[T]
    end

    # No class under `Foo` includes `Taggable`
    module Taggable
    end

    # `Qux < Foo` includes `Sortable`
    module Sortable
    end

    # Nothing includes `Lonely`
    module Lonely
    end

    # `Outer` includes `Taggable`, and `Oc` includes `Outer`
    module Outer
      include Taggable
    end

    class Foo
    end

    class Bar
      include Taggable
    end

    class Baz < Foo
    end

    class Qux < Foo
      include Sortable
    end

    class Both
      include Taggable
      include Sortable
    end

    class Oc
      include Outer
    end

    class Extending
      extend Taggable
    end

    interface _Quacks
      def quack: () -> void
    end

    type int_or_str = Integer | String

    type tree = Integer | Array[tree]

    type alias_a = Array[alias_b]

    type alias_b = Array[alias_a]

    # `!T` is written `::NEG[T]` for the RBS parser, and turned into the negation type by `parse_type`
    class NEG[T]
    end
  RBS

  def with_sigs(&block)
    with_factory({ "sigs.rbs" => SIGS }, nostdlib: true, &block)
  end

  NEG = RBS::TypeName.parse("::NEG")

  # Parses a type, with the negation `!T` of a simple type `T` allowed anywhere
  def parse_type(string, factory: self.factory, variables: [])
    while (index = string.rindex("!"))
      rest = string[index + 1..] or raise
      simple = simple_type_prefix(rest) or raise "No simple type after `!` in #{string.inspect}"
      string = "#{string[0...index]}::NEG[#{simple}]#{rest[simple.size..]}"
    end

    denegate(super(string, factory: factory, variables: variables))
  end

  # The simple type at the beginning of the string: a name with its type arguments, a literal, or a parenthesized type
  def simple_type_prefix(string)
    case string
    when /\A\(/
      string[0..matching_close(string, "(", ")")]
    when /\A(::)?[A-Za-z_][A-Za-z0-9_:]*/
      name = $&
      if string[name.size] == "[" || (string[name.size] == "(" && name == "singleton")
        open = string[name.size] or raise
        close = open == "[" ? "]" : ")"
        string[0..name.size + matching_close(string[name.size..] || raise, open, close)]
      else
        name
      end
    when /\A(-?\d+|"[^"]*"|:[A-Za-z_]+)/
      $&
    end
  end

  def matching_close(string, open, close)
    depth = 0
    string.each_char.with_index do |char, index|
      depth += 1 if char == open
      depth -= 1 if char == close
      return index if depth == 0
    end
    raise "Unbalanced #{open}#{close} in #{string.inspect}"
  end

  def denegate(type)
    case type
    when Steep::AST::Types::Name::Instance
      if type.name == NEG
        Steep::AST::Types::Negation.build(type: denegate(type.args.fetch(0)))
      else
        type.map_type {|ty| denegate(ty) }
      end
    when Steep::AST::Types::Union
      Steep::AST::Types::Union.build(types: type.types.map {|ty| denegate(ty) })
    when Steep::AST::Types::Intersection
      Steep::AST::Types::Intersection.build(types: type.types.map {|ty| denegate(ty) })
    else
      type.map_type {|ty| denegate(ty) }
    end
  end

  def emptiness
    @emptiness ||= Steep::SetTheoretic::Emptiness.new(factory: factory)
  end

  def class_index
    emptiness.class_index
  end

  def type_name(string)
    RBS::TypeName.parse(string)
  end

  def assert_empty_verdict(verdict, message = nil)
    assert verdict.empty?, message || "Expected `empty` but got `#{verdict}`"
  end

  def assert_empty_in_rbs_verdict(verdict, message = nil)
    assert verdict.empty_in_rbs?, message || "Expected `empty_in_rbs` but got `#{verdict}`"
  end

  def assert_inhabited_verdict(verdict, message = nil)
    assert verdict.inhabited?, message || "Expected `inhabited` but got `#{verdict}`"
  end

  # The verdict of a type for reachability, with the RBS type variables bound by `bounds`
  def inhabitation(string, bounds: {})
    emptiness.check(parse_type(string, variables: bounds.keys), mode: :inhabitation, bounds: bounds)
  end

  # The verdict of `sub & !sup` for subtyping
  def subtyping(sub, sup, bounds: {})
    emptiness.subtype?(parse_type(sub, variables: bounds.keys), parse_type(sup, variables: bounds.keys), bounds: bounds)
  end

  def negation(type)
    Steep::AST::Types::Negation.build(type: type)
  end
end
