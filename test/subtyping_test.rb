require_relative "test_helper"

class SubtypingTest < Minitest::Test
  include TestHelper
  include Steep

  BUILTIN = <<-EOB
class BasicObject
end

class Object < BasicObject
  def class: () -> class
  def tap: { (self) -> any } -> self
  def yield_self: <'a> { (self) -> 'a } -> 'a
end

class Class
  def new: (*any) -> any 
  def allocate: -> any
end

class Module
  def attr_reader: (Symbol) -> nil
end

class String
  def to_str: -> String
  def self.try_convert: (any) -> String
end

class Integer
  def to_int: -> Integer
  def self.sqrt: (Integer) -> Integer
end

class Array<'a>
  def []: (Integer) -> 'a
  def []=: (Integer, 'a) -> 'a
end

class Hash<'a, 'b>
  def []: ('a) -> 'b
  def []=: ('a, 'b) -> 'b
  def keys: -> Array<'a>
  def values: -> Array<'b>
end

class Symbol
end

module Kernel
  def Integer: (any) -> Integer
end
  EOB

  def new_checker(signature)
    env = AST::Signature::Env.new

    parse_signature(BUILTIN).each do |sig|
      env.add sig
    end

    parse_signature(signature).each do |sig|
      env.add sig
    end

    builder = Interface::Builder.new(signatures: env)
    Subtyping::Check.new(builder: builder)
  end

  def test_interface
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B
  def foo: -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(sub_type: parse_type("::A"), super_type: parse_type("::B")),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface2
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
  def bar: -> any
end

class B
  def foo: -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
    assert_equal :bar, result.error.name
    assert_equal [
                   [AST::Types::Name.new_instance(name: "::B"),
                    AST::Types::Name.new_instance(name: "::A")]
                 ], result.trace.array
  end

  def test_interface3
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B
  def foo: -> String
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
    assert_equal :to_str, result.error.name
  end

  def test_interface4
    checker = new_checker(<<-EOS)
class A
  def foo: () -> Integer
end

class B
  def foo: (?Integer, ?foo: Symbol) -> any
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface5
    checker = new_checker(<<-EOS)
class A
  def foo: <'a> () -> 'a
end

class B
  def foo: () -> Integer
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::PolyMethodSubtyping, result.error

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface51
    checker = new_checker(<<-EOS)
class A
  def foo: <'a> ('a) -> Integer
end

class B
  def foo: (String) -> Integer
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::PolyMethodSubtyping, result.error

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface52
    checker = new_checker(<<-EOS)
class A
  def foo: <'a> ('a) -> Object
end

class B
  def foo: (String) -> Integer
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::PolyMethodSubtyping, result.error


    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_interface6
    checker = new_checker(<<-EOS)
class A
  def foo: <'a, 'b> ('a) -> 'b
end

class B
  def foo: <'x, 'y> ('x) -> 'y
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_interface7
    checker = new_checker(<<-EOS)
class A
  def foo: (Integer) -> Integer
         | (any) -> any
end

class B
  def foo: (String) -> String
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_interface8
    checker = new_checker(<<-EOS)
class A
  def foo: () { -> Object } -> String
end

class B
  def foo: () { -> String } -> Object
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_interface9
    checker = new_checker(<<-EOS)
class A
  def foo: () { (String) -> any } -> String
end

class B
  def foo: () { (Object) -> any } -> Object
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A"),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::MethodMissingError, result.error
  end

  def test_literal0
    checker = new_checker("")

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("123"),
        super_type: parse_type("::Integer"),
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("::Integer"),
        super_type: parse_type("123"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type('"Foo"'),
        super_type: parse_type("::Integer"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
  end

  def test_void
    checker = new_checker("")

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Void.new,
        super_type: AST::Types::Void.new
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Void.new,
        super_type: AST::Types::Name.new_instance(name: "::A"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_instance_of Subtyping::Result::Failure::UnknownPairError, result.error
  end

  def test_union
    checker = new_checker(<<-EOS)
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::String"),
        super_type: AST::Types::Union.build(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                    AST::Types::Name.new_instance(name: "::String")]),
      ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Union.build(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                  AST::Types::Name.new_instance(name: "::Integer")]),
        super_type: AST::Types::Name.new_instance(name: "::String")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_equal 1, result.trace.size

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Integer"),
        super_type: AST::Types::Union.build(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                    AST::Types::Name.new_instance(name: "::BasicObject")]),
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Integer"),
        super_type: AST::Types::Union.build(types: [AST::Types::Name.new_instance(name: "::Object"),
                                                    AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_intersection
    checker = new_checker(<<-EOS)
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::String"),
        super_type: AST::Types::Intersection.build(types: [
          AST::Types::Name.new_instance(name: "::Object"),
          AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )

    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Intersection.build(types: [
          AST::Types::Name.new_instance(name: "::Object"),
          AST::Types::Name.new_instance(name: "::Integer")
        ]),
        super_type: AST::Types::Name.new_instance(name: "::String")
      ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
    assert_equal 1, result.trace.size

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::Object"),
        super_type: AST::Types::Intersection.build(types: [
          AST::Types::Name.new_instance(name: "::Integer"),
          AST::Types::Name.new_instance(name: "::String")]),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
  end

  def test_caching
    checker = new_checker("")

    checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: :"::Object"),
        super_type: AST::Types::Var.new(name: :foo)
      ),
      constraints: Subtyping::Constraints.empty
    )

    # Not cached because the relation has free variables
    assert_empty checker.cache

    checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: :"::Integer"),
        super_type: AST::Types::Name.new_instance(name: :"::Object")
      ),
      constraints: Subtyping::Constraints.empty
    )

    # Cached because the relation does not have free variables
    assert_operator checker.cache,
                    :key?,
                    Subtyping::Relation.new(
                      sub_type: AST::Types::Name.new_instance(name: :"::Integer"),
                      super_type: AST::Types::Name.new_instance(name: :"::Object")
                    )
  end

  def test_resolve_instance
    checker = new_checker("")

    type = parse_type("::String")
    interface = checker.resolve(type)

    assert_equal [:class, :tap, :yield_self, :to_str], interface.methods.keys
    assert_equal ["() -> ::String.class"], interface.methods[:class].types.map(&:to_s)
    assert_equal ["() { (::String) -> any } -> ::String"], interface.methods[:tap].types.map(&:to_s)
    assert_equal ["<'a> () { (::String) -> 'a } -> 'a"], interface.methods[:yield_self].types.map(&:to_s)
    assert_equal ["() -> ::String"], interface.methods[:to_str].types.map(&:to_s)
  end

  def test_resolve_instance2
    checker = new_checker("")

    type = parse_type("::Array<::Integer>")
    interface = checker.resolve(type)

    assert_equal [:class, :tap, :yield_self, :[], :[]=], interface.methods.keys
    assert_equal ["() -> ::Array.class"], interface.methods[:class].types.map(&:to_s)
    assert_equal ["() { (::Array<::Integer>) -> any } -> ::Array<::Integer>"], interface.methods[:tap].types.map(&:to_s)
    assert_equal ["<'a> () { (::Array<::Integer>) -> 'a } -> 'a"], interface.methods[:yield_self].types.map(&:to_s)
    assert_equal ["(::Integer) -> ::Integer"], interface.methods[:[]].types.map(&:to_s)
    assert_equal ["(::Integer, ::Integer) -> ::Integer"], interface.methods[:[]=].types.map(&:to_s)
  end

  def test_resolve_instance3
    checker = new_checker("")

    type = parse_type("::Kernel")
    interface = checker.resolve(type)

    assert_equal [:Integer], interface.methods.keys
    assert_equal ["(any) -> ::Integer"], interface.methods[:Integer].types.map(&:to_s)
  end

  def test_resolve_instance_private
    checker = new_checker(<<-EOF)
class Foo
  def foo: () -> void
  def (private) bar: () -> void
end
    EOF

    type = parse_type("::Foo")

    checker.resolve(type).tap do |interface|
      assert_operator interface.methods, :key?, :foo
      refute_operator interface.methods, :key?, :bar
    end

    checker.resolve(type, with_private: true).tap do |interface|
      assert_operator interface.methods, :key?, :foo
      assert_operator interface.methods, :key?, :bar
    end
  end

  def test_resolve_class
    checker = new_checker("")

    type = parse_type("::Array.class")
    interface = checker.resolve(type)

    assert_equal [:class, :tap, :yield_self, :allocate], interface.methods.keys
    assert_equal ["() -> ::Class.class"], interface.methods[:class].types.map(&:to_s)
    assert_equal ["() { (::Array.class) -> any } -> ::Array.class"], interface.methods[:tap].types.map(&:to_s)
    assert_equal ["<'a> () { (::Array.class) -> 'a } -> 'a"], interface.methods[:yield_self].types.map(&:to_s)
    assert_equal ["() -> any"], interface.methods[:allocate].types.map(&:to_s)
  end

  def test_resolve_class2
    checker = new_checker("class A end")

    type = parse_type("::A.class constructor")
    interface = checker.resolve(type)

    interface.methods[:new].yield_self do |method|
      assert_equal ["() -> ::A"], method.types.map(&:to_s)
    end
  end

  def test_resolve_class3
    checker = new_checker(<<-EOF)
class Set<'a>
  def initialize: (Array<'a>) -> any
end
    EOF

    type = parse_type("::Set.class constructor")
    interface = checker.resolve(type)

    interface.methods[:new].yield_self do |method|
      assert_equal ["<'a> (::Array<'a>) -> ::Set<'a>"], method.types.map(&:to_s)
    end
  end

  def test_resolve_class4
    checker = new_checker(<<-EOF)
class Set<'a>
  def initialize: (Array<'a>) -> any
end
    EOF

    type = parse_type("::Set.class constructor")
    interface = checker.resolve(type)

    interface.methods[:new].yield_self do |method|
      assert_equal ["<'a> (::Array<'a>) -> ::Set<'a>"], method.types.map(&:to_s)
    end
  end

  def test_resolve_class_private
    checker = new_checker(<<-EOF)
class Foo
  def self.foo: () -> void
  def (private) self.bar: () -> void
end
    EOF

    type = parse_type("::Foo.class")

    checker.resolve(type).tap do |interface|
      assert_operator interface.methods, :key?, :foo
      refute_operator interface.methods, :key?, :bar
    end

    checker.resolve(type, with_private: true).tap do |interface|
      assert_operator interface.methods, :key?, :foo
      assert_operator interface.methods, :key?, :bar
    end
  end

  def test_resolve_module
    checker = new_checker("")

    type = parse_type("::Kernel.module")
    interface = checker.resolve(type)

    assert_equal [:class, :tap, :yield_self, :attr_reader], interface.methods.keys
    assert_equal ["() -> ::Module.class"], interface.methods[:class].types.map(&:to_s)
    assert_equal ["() { (::Kernel.module) -> any } -> ::Kernel.module"], interface.methods[:tap].types.map(&:to_s)
    assert_equal ["<'a> () { (::Kernel.module) -> 'a } -> 'a"], interface.methods[:yield_self].types.map(&:to_s)
    assert_equal ["(::Symbol) -> nil"], interface.methods[:attr_reader].types.map(&:to_s)
  end

  def test_resolve_interface
    checker = new_checker(<<EOF)
interface _A<'a>
  def each: { ('a) -> any } -> self
end
EOF

    type = parse_type("_A<::Integer>")
    interface = checker.resolve(type)

    assert_equal [:each], interface.methods.keys
    assert_equal ["() { (::Integer) -> any } -> _A<::Integer>"], interface.methods[:each].types.map(&:to_s)
  end

  def test_resolve_union
    checker = new_checker("")

    type = parse_type("::String | ::Integer")
    interface = checker.resolve(type)

    assert_equal [:tap, :yield_self], interface.methods.keys
    assert_equal [type], interface.methods[:tap].types.map {|ty| ty.return_type }
    assert_equal [[type]], interface.methods[:yield_self].types.map {|ty| ty.block.type.params.required }
  end

  def test_resolve2
    checker = new_checker("")

    interface = checker.resolve(
      AST::Types::Intersection.build(types: [
        AST::Types::Name.new_instance(name: "::String"),
        AST::Types::Name.new_instance(name: "::Integer")
      ])
    )

    assert_equal [:class, :tap, :yield_self, :to_str, :to_int].sort, interface.methods.keys.sort
    refute_empty interface.methods[:class].types
    assert_equal [AST::Types::Name.new_instance(name: "::String")], interface.methods[:to_str].types.map(&:return_type)
    assert_equal [AST::Types::Name.new_instance(name: "::Integer")], interface.methods[:to_int].types.map(&:return_type)
  end

  def test_resolve4
    checker = new_checker("")

    interface = checker.resolve(parse_type("::Array<::Integer> | ::Array<::String>"))

    assert_equal [:tap, :yield_self, :[]], interface.methods.keys
    assert_equal ["() { ((::Array<::Integer> | ::Array<::String>)) -> any } -> (::Array<::Integer> | ::Array<::String>)"],
                 interface.methods[:tap].types.map(&:to_s)
    assert_equal ["<'a> () { ((::Array<::Integer> | ::Array<::String>)) -> 'a } -> 'a"],
                 interface.methods[:yield_self].types.map(&:to_s)
    assert_equal ["(::Integer) -> (::Integer | ::String)"],
                 interface.methods[:[]].types.map(&:to_s)
  end

  def test_resolve_void
    checker = new_checker("")

    interface = checker.resolve(AST::Types::Void.new)

    assert_instance_of Interface::Instantiated, interface
    assert_empty interface.methods
    assert_empty interface.ivars
  end

  def test_constraints1
    checker = new_checker(<<-EOS)
class A
  def foo: -> Integer
end

class B<'a>
  def foo: -> 'a
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(sub_type: parse_type("::A"), super_type: parse_type("::B<'x>")),
      constraints: Subtyping::Constraints.new(unknowns: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :unknown?, :x
    assert_instance_of AST::Types::Top, result.constraints.upper_bound(:x)
    assert_equal parse_type("::Integer"), result.constraints.lower_bound(:x)
  end

  def test_constraints2
    checker = new_checker(<<-EOS)
class A<'a>
  def get: -> 'a
  def set: ('a) -> self
end

class B
  def get: -> String
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)]),
        super_type: AST::Types::Name.new_instance(name: "::B")
      ),
      constraints: Subtyping::Constraints.new(unknowns: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :unknown?, :x
    assert_equal AST::Types::Name.new_instance(name: :"::String"), result.constraints.upper_bound(:x)
    assert_equal AST::Types::Name.new_instance(name: :"::String"), result.constraints.lower_bound(:x)

    variance = Subtyping::VariableVariance.new(covariants: Set.new([:x]), contravariants: Set.new([:x]))
    s = result.constraints.solution(checker, variance: variance, variables: Set.new([:x]))
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end

  def test_constraints3
    checker = new_checker(<<-EOS)
class A<'a>
  def set: ('a) -> self
end

class B
  def get: -> String
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::B"),
        super_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)])
      ),
      constraints: Subtyping::Constraints.new(unknowns: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :unknown?, :x
    assert_equal AST::Types::Name.new_instance(name: :"::String"), result.constraints.upper_bound(:x)
    assert_instance_of AST::Types::Bot, result.constraints.lower_bound(:x)

    variance = Subtyping::VariableVariance.new(contravariants: Set.new([:x]), covariants: Set.new)
    s = result.constraints.solution(checker, variance: variance, variables: Set.new([:x]))
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end

  def test_constraints4
    checker = new_checker(<<-EOS)
class A<'a>
  def set: ('a) -> self
end

class B
  def set: (String) -> self
end
    EOS

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: AST::Types::Name.new_instance(name: "::A", args: [AST::Types::Var.new(name: :x)]),
        super_type: AST::Types::Name.new_instance(name: "::B"),
      ),
      constraints: Subtyping::Constraints.new(unknowns: [:x])
    )

    assert_instance_of Subtyping::Result::Success, result
    assert_operator result.constraints, :unknown?, :x
    assert_equal AST::Types::Name.new_instance(name: :"::String"), result.constraints.lower_bound(:x)
    assert_instance_of AST::Types::Top, result.constraints.upper_bound(:x)

    variance = Subtyping::VariableVariance.new(contravariants: Set.new([:x]),
                                               covariants: Set.new([:x]))
    s = result.constraints.solution(checker, variance: variance, variables: Set.new([:x]))
    assert_equal AST::Types::Name.new_instance(name: :"::String"), AST::Types::Var.new(name: :x).subst(s)
  end

  def test_tuple
    checker = new_checker("")

    interface = checker.resolve(parse_type("[1, String]"))
    assert_equal [:class, :tap, :yield_self, :[], :[]=], interface.methods.keys

    assert_equal ["(0) -> 1", "(1) -> String", "(::Integer) -> (1 | String)"], interface.methods[:[]].types.map(&:to_s)
    assert_equal ["(0, 1) -> 1", "(1, String) -> String", "(::Integer, (1 | String)) -> (1 | String)"], interface.methods[:[]=].types.map(&:to_s)
  end

  def test_tuple_subtyping
    checker = new_checker("")

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("[123]"),
        super_type: parse_type("::Array<123>"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("[123, String]"),
        super_type: parse_type("::Array<123 | String>"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("[123]"),
        super_type: parse_type("::Array<::Integer | ::String>"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("[123, 456]"),
        super_type: parse_type("[123]"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check(
      Subtyping::Relation.new(
        sub_type: parse_type("[123]"),
        super_type: parse_type("[::Integer]"),
        ),
      constraints: Subtyping::Constraints.empty
    )
    assert_instance_of Subtyping::Result::Failure, result
  end

  def test_expand_alias
    checker = new_checker(<<-EOF)
type foo = String | Integer
type bar<'a> = 'a | Array<'a> | foo
    EOF

    assert_equal parse_type("::String | ::Integer"), checker.expand_alias(parse_type("foo"))
    assert_equal parse_type("::Integer | ::Array<::Integer> | ::String"), checker.expand_alias(parse_type("bar<::Integer>"))
    assert_raises { checker.expand_alias(parse_type("hello")) }
  end

  def test_expand_alias2
    checker = new_checker(<<-EOF)
type Foo::foo = String | ::String | Integer
class Foo::String
end
    EOF

    assert_equal parse_type("::Foo::String | ::String | ::Integer"), checker.expand_alias(parse_type("Foo::foo"))
  end

  def test_alias
    checker = new_checker(<<-EOF)
type foo = String | Integer
    EOF

    result = checker.check0(
      Subtyping::Relation.new(
        sub_type: parse_type("::String"),
        super_type: parse_type("foo")
      ),
      constraints: Subtyping::Constraints.empty,
      assumption: Set.new,
      trace: Subtyping::Trace.new
    )
    assert_instance_of Subtyping::Result::Success, result

    result = checker.check0(
      Subtyping::Relation.new(
        sub_type: parse_type("foo"),
        super_type: parse_type("::String")
      ),
      constraints: Subtyping::Constraints.empty,
      assumption: Set.new,
      trace: Subtyping::Trace.new
    )
    assert_instance_of Subtyping::Result::Failure, result
  end

  def test_resolve_hash
    checker = new_checker("")

    type = parse_type("{ foo: ::Integer, bar: ::String }")
    interface = checker.resolve(type)

    interface.methods[:[]].yield_self do |method|
      assert_equal ["(:foo) -> ::Integer",
                    "(:bar) -> ::String",
                    "((:bar | :foo)) -> (::Integer | ::String)"],
                   method.types.map(&:to_s)
    end

    interface.methods[:[]=].yield_self do |method|
      assert_equal ["(:foo, ::Integer) -> ::Integer",
                    "(:bar, ::String) -> ::String",
                    "((:bar | :foo), (::Integer | ::String)) -> (::Integer | ::String)"],
                   method.types.map(&:to_s)
    end

    interface.methods[:keys].yield_self do |method|
      assert_equal ["() -> ::Array<(:bar | :foo)>"], method.types.map(&:to_s)
    end

    interface.methods[:values].yield_self do |method|
      assert_equal ["() -> ::Array<(::Integer | ::String)>"], method.types.map(&:to_s)
    end

    interface.methods[:tap].yield_self do |method|
      assert_equal ["() { ({ :foo => ::Integer, :bar => ::String }) -> any } -> { :foo => ::Integer, :bar => ::String }"],
                   method.types.map(&:to_s)
    end
  end

  def test_hash
    checker = new_checker("")

    result = checker.check0(
      Subtyping::Relation.new(
        sub_type: parse_type("{ foo: Integer }"),
        super_type: parse_type("{ foo: Integer }")
      ),
      constraints: Subtyping::Constraints.empty,
      assumption: Set.new,
      trace: Subtyping::Trace.new
    )
    assert_instance_of Subtyping::Result::Success, result
  end

  def test_hash2
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(unknowns: [:a])
    result = checker.check0(
      Subtyping::Relation.new(
        sub_type: parse_type("{ foo: Integer }"),
        super_type: parse_type("{ foo: 'a }")
      ),
      constraints: constraints,
      assumption: Set.new,
      trace: Subtyping::Trace.new
    )
    assert_instance_of Subtyping::Result::Success, result

    assert_equal({ a: parse_type("Integer") },
                 constraints.solution(checker,
                                      variance: Subtyping::VariableVariance.new(covariants: Set.new, contravariants: Set.new),
                                      variables: [:a]).dictionary)
  end

  def test_hash3
    checker = new_checker("")

    constraints = Subtyping::Constraints.new(unknowns: [:a])
    result = checker.check0(
      Subtyping::Relation.new(
        sub_type: parse_type("{ foo: Integer, bar: String }"),
        super_type: parse_type("{ foo: 'a }")
      ),
      constraints: constraints,
      assumption: Set.new,
      trace: Subtyping::Trace.new
    )
    assert_instance_of Subtyping::Result::Success, result

    assert_equal({ a: parse_type("Integer") },
                 constraints.solution(checker,
                                      variance: Subtyping::VariableVariance.new(covariants: Set.new, contravariants: Set.new),
                                      variables: [:a]).dictionary)
  end
end
