require "test_helper"

class TypeConstructionTest < Minitest::Test
  include TestHelper
  include TypeErrorAssertions
  include FactoryHelper
  include SubtypingHelper

  Typing = Steep::Typing
  Namespace = Steep::AST::Namespace
  ConstantEnv = Steep::TypeInference::ConstantEnv
  TypeEnv = Steep::TypeInference::TypeEnv
  TypeConstruction = Steep::TypeConstruction
  Annotation = Steep::AST::Annotation
  Names = Steep::Names

  DEFAULT_SIGS = <<-EOS
interface _A
  def `+`: (_A) -> _A
end

interface _B
end

interface _C
  def f: () -> _A
  def g: (_A, ?_B) -> _B
  def h: (a: _A, ?b: _B) -> _C
end

interface _D
  def foo: () -> any
end

interface _X
  def f: () { (_A) -> _D } -> _C 
end

interface _Kernel
  def foo: (_A) -> _B
         | (_C) -> _D
end

interface _PolyMethod
  def snd: [A] (any, A) -> A
  def try: [A] { (any) -> A } -> A
end

module Foo[A]
end
  EOS

  def with_checker(*files, no_default: false, &block)
    unless no_default
      files << DEFAULT_SIGS
    end

    super(*files, &block)
  end

  def with_standard_construction(checker, source)
    typing = Typing.new
    annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
    const_env = ConstantEnv.new(factory: factory, context: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.factory.env)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        self_type: parse_type("::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    yield construction, typing
  end

  def test_lvar_with_annotation
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
x = (_ = nil)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_A"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_lvar_with_annotation_type_check
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _B
# @type var z: _A
x = (_ = nil)
z = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_A"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_A"),
                                       rhs_type: parse_type("::_B") do |error|
          assert_equal :lvasgn, error.node.type
          assert_equal :z, error.node.children[0].name
        end
      end
    end
  end

  def test_lvar_without_annotation
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
x = 1
z = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize source.node

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_lvar_without_annotation_inference
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
x = (_ = nil)
z = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_A"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.f
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_A"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call_with_argument
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _A
x = (_ = nil)
y = (_ = nil)
x.g(y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call_incompatible_argument_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = (_ = nil)
y = (_ = nil)
x.g(y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_argument_type_mismatch typing.errors[0],
                                      expected: parse_type("::_A"),
                                      actual: parse_type("::_B")
      end
    end
  end

  def test_method_call_no_error_if_any
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
x = (_ = nil)
x.no_such_method
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("any"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call_no_method_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.no_such_method
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("any"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_no_method_error typing.errors.first, method: :no_such_method, type: parse_type("::_C")
      end
    end
  end

  def test_method_call_missing_argument
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = (_ = nil)
x = (_ = nil)
a.g()
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Steep::Errors::IncompatibleArguments, error
          assert_equal parse_method_type("(::_A, ?::_B) -> ::_B"), error.method_type
        end
      end
    end
  end

  def test_method_call_extra_args
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = (_ = nil)
x = (_ = nil)
a.g(_ = nil, _ = nil, _ = nil)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Steep::Errors::IncompatibleArguments, error
          assert_equal parse_method_type("(::_A, ?::_B) -> ::_B"), error.method_type
        end
      end
    end
  end

  def test_keyword_call
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var a: _A
# @type var b: _B
x = (_ = nil)
a = (_ = nil)
b = (_ = nil)
x.h(a: a, b: b)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_keyword_missing
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.h()
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size

        typing.errors.first.tap do |error|
          assert_instance_of Steep::Errors::IncompatibleArguments, error
          assert_equal parse_method_type("(a: ::_A, ?b: ::_B) -> ::_C"), error.method_type
        end
      end
    end
  end

  def test_extra_keyword_given
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.h(a: (_ = nil), b: (_ = nil), c: (_ = nil))
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Steep::Errors::UnexpectedKeyword, error
          assert_equal Set.new([:c]), error.unexpected_keywords
        end
      end
    end
  end

  def test_keyword_typecheck
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = (_ = nil)
y = (_ = nil)
x.h(a: y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_A"),
                                       rhs_type: parse_type("::_B")
      end
    end
  end

  def test_def_no_params
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo
  # @type var x: _A
  x = (_ = nil)
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        def_body = source.node.children[2]
        assert_equal parse_type("::_A"), typing.type_of(node: def_body)
      end
    end
  end

  def test_def_param
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x)
  # @type var x: _A
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        def_body = source.node.children[2]
        assert_equal parse_type("::_A"), typing.type_of(node: def_body)
        assert_equal parse_type("::_A"), typing.type_of(node: def_body.children[1])
      end
    end
  end

  def test_def_param_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_C"),
                                       rhs_type: parse_type("::_A") do |error|
          assert_equal :optarg, error.node.type
          assert_equal :y, error.node.children[0].name
        end

        x = dig(source.node, 2, 0)
        y = dig(source.node, 2, 1)

        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_C"), typing.type_of(node: y)
      end
    end
  end

  def test_def_kw_param_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_C"),
                                       rhs_type: parse_type("::_A") do |error|
          assert_equal :kwoptarg, error.node.type
          assert_equal :y, error.node.children[0].name
        end

        x = dig(source.node, 2, 0)
        y = dig(source.node, 2, 1)

        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_C"), typing.type_of(node: y)
      end
    end
  end

  def test_block
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: _X
a = (_ = nil)

b = a.f do |x|
  # @type var x: _A
  # @type var y: _B
  y = (_ = nil)
  x
  y
end

a
b
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        a = dig(source.node, 2)
        b = dig(source.node, 3)
        x = dig(source.node, 1, 1, 2, 1)
        y = dig(source.node, 1, 1, 2, 2)

        assert_equal parse_type("::_X"), typing.type_of(node: a)
        assert_equal parse_type("::_C"), typing.type_of(node: b)
        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_B"), typing.type_of(node: y)
      end
    end
  end

  def test_block_shadow
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: _X
a = (_ = nil)

a.f do |a|
  # @type var a: _A
  b = a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        block_body = dig(source.node, 1, 2)

        assert_equal parse_type("::_X"), typing.type_of(node: lvar_in(source.node, :a))
        assert_equal parse_type("::_A"), typing.type_of(node: lvar_in(block_body, :a))
        assert_equal parse_type("::_A"), typing.type_of(node: lvar_in(block_body, :b))
      end
    end
  end

  def test_block_param_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  # @type var d: _D
  a
  d = (_ = nil)
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_X"), typing.type_of(node: lvar_in(source.node, :x))
        assert_equal parse_type("::_A"), typing.type_of(node: lvar_in(source.node, :a))
        assert_equal parse_type("::_D"), typing.type_of(node: lvar_in(source.node, :d))
        assert_empty typing.errors
      end
    end
  end

  def test_block_value_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_block_type_mismatch typing.errors[0],
                                   expected: "^(::_A) -> ::_D",
                                   actual: "^(::_A) -> ::_A"

        assert_equal parse_type("::_X"), typing.type_of(node: lvar_in(source.node, :x))
        assert_equal parse_type("::_A"), typing.type_of(node: lvar_in(source.node, :a))
      end
    end
  end

  def test_block_break_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  break a
  # @type var d: _D
  d = (_ = nil)
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_X"), typing.type_of(node: lvar_in(source.node, :x))
        assert_equal parse_type("::_A"), typing.type_of(node: lvar_in(source.node, :a))

        assert_equal 1, typing.errors.size
        assert_break_type_mismatch typing.errors[0], expected: parse_type("::_C"), actual: parse_type("::_A")
      end
    end
  end

  def test_return_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo()
  # @type return: _A
  # @type var a: _A
  a = (_ = nil)
  return a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_return_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo()
  # @type return: _X
  # @type var a: _A
  a = (_ = nil)
  return a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ReturnTypeMismatch) && error.expected == parse_type("::_X") && error.actual == parse_type("::_A")
        end
      end
    end
  end

  def test_constant_annotation
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type const Hello: Integer
# @type var hello: Integer
hello = Hello
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_constant_annotation2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type const Hello::World: Integer
Hello::World = ""
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)
      end
    end
  end

  def test_constant_signature
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: String
x = String
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_constant_signature2
    with_checker <<-EOS do |checker|
X: Module
    EOS
      source = parse_ruby(<<-EOF)
X = 3
# @type var x: String
x = X
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Steep::Errors::IncompatibleAssignment) }
      end
    end
  end

  def test_overloaded_method
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var k: _Kernel
# @type var a: _A
# @type var c: _C
k = (_ = nil)
a = (_ = nil)
c = (_ = nil)

# @type var b: _B
b = k.foo(a)

# @type var d: _D
d = k.foo(c)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_ivar_types
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo
  # @type ivar @x: _A
  # @type var y: _D
  
  y = (_ = nil)
  
  @x = y
  y = @x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :ivasgn &&
            error.node.children[0] == :"@x"
        end
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :lvasgn &&
            error.node.children[1].type == :ivar &&
            error.node.children[1].children[0] == :"@x"
        end
      end
    end
  end

  def test_poly_method_arg
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = (_ = nil)

# @type var string: String
string = poly.snd(1, "a")
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_poly_method_block
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = (_ = nil)

# @type var string: String
string = poly.try { "string" }
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_union_type
    with_checker do |checker|
      source = parse_ruby("1")

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("_A | _C"),
                     construction.union_type(parse_type("_A"), parse_type("_C"))

        assert_equal parse_type("_A"),
                     construction.union_type(parse_type("_A"), parse_type("_A"))
      end
    end
  end

  def test_module_self
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
module Foo
  # @implements Foo[A]
  
  block_given?
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_class_constructor_with_signature
    with_checker <<-EOS do |checker|
class Person end
    EOS
      source = parse_ruby("class Person; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_class = construction.for_class(source.node)

        assert_equal(
          Annotation::Implements::Module.new(
            name: Names::Module.parse("::Person"),
            args: []
          ),
          for_class.module_context.implement_name
        )
        assert_equal parse_type("::Person"), for_class.module_context.instance_type
        assert_equal parse_type("singleton(::Person)"), for_class.module_context.module_type
      end
    end
  end

  def test_class_constructor_without_signature
    with_checker <<-EOF do |checker|
class Address
end
    EOF
      source = parse_ruby("class Person; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_class = construction.for_class(source.node)

        assert_nil for_class.module_context.implement_name
        assert_nil for_class.module_context.instance_type
        assert_nil for_class.module_context.module_type
      end
    end
  end

  def test_class_constructor_nested
    with_checker <<-EOF do |checker|
class Steep::Names::Module end
    EOF
      source = parse_ruby("module Steep; class Names::Module; end; end")

      typing = Typing.new
      annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
      const_env = ConstantEnv.new(factory: factory, context: nil)
      type_env = TypeEnv.build(annotations: annotations,
                               subtyping: checker,
                               const_env: const_env,
                               signatures: checker.factory.env)

      module_context = TypeConstruction::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        current_namespace: Namespace.parse("::Steep"),
        const_env: const_env,
        class_name: nil
      )

      module_name_class_node = source.node.children[1]

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          type_env: type_env,
                                          self_type: nil,
                                          block_context: nil,
                                          method_context: nil,
                                          typing: typing,
                                          module_context: module_context,
                                          break_context: nil)

      for_module = construction.for_class(module_name_class_node)

      assert_equal(
        Annotation::Implements::Module.new(
          name: Names::Module.parse("::Steep::Names::Module"),
          args: []
        ),
        for_module.module_context.implement_name)
    end
  end

  def test_module_constructor_with_signature
    with_checker <<-EOF do |checker|
module Steep end
    EOF

      source = parse_ruby("module Steep; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_module = construction.for_module(source.node)

        assert_equal(
          Annotation::Implements::Module.new(
            name: Names::Module.parse("::Steep"),
            args: []
          ),
          for_module.module_context.implement_name
        )
        assert_equal parse_type("::Steep & ::Object"), for_module.module_context.instance_type
        assert_equal parse_type("::Module & singleton(::Steep)"), for_module.module_context.module_type
      end
    end
  end

  def test_module_constructor_without_signature
    with_checker <<-EOF do |checker|
module Rails end
    EOF

      source = parse_ruby("module Steep; end")

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        for_module = construction.for_module(source.node)

        assert_nil for_module.module_context.implement_name
        assert_nil for_module.module_context.instance_type
        assert_equal parse_type("::Module"), for_module.module_context.module_type
      end
    end
  end

  def test_module_constructor_nested
    with_checker <<-EOS do |checker|
module Steep::Printable end
    EOS
      source = parse_ruby("class Steep; module Printable; end; end")

      typing = Typing.new
      annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
      const_env = ConstantEnv.new(factory: factory, context: nil)
      type_env = TypeEnv.build(annotations: annotations,
                               subtyping: checker,
                               const_env: const_env,
                               signatures: checker.factory.env)

      module_context = TypeConstruction::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        current_namespace: Namespace.parse("::Steep"),
        const_env: const_env,
        class_name: nil
      )

      module_node = source.node.children.last

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          type_env: type_env,
                                          self_type: nil,
                                          block_context: nil,
                                          method_context: nil,
                                          typing: typing,
                                          module_context: module_context,
                                          break_context: nil)

      for_module = construction.for_module(module_node)

      assert_equal(
        Annotation::Implements::Module.new(
          name: Names::Module.parse("::Steep::Printable"),
          args: []
        ),
        for_module.module_context.implement_name)
    end
  end

  def test_new_method_constructor
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby("class A; def foo(x); end; end")

      with_standard_construction(checker, source) do |construction, typing|
        type_name = checker.factory.type_name_1(parse_type("::A").name)
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]
        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal instance_definition.methods[:foo], method_context.method
        assert_equal parse_method_type("(::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::Integer"), method_context.return_type
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal [:x], for_method.type_env.lvar_types.keys
        assert_equal parse_type("::String"),
                     for_method.type_env.lvar_types[:x]
      end
    end
  end

  def test_new_method_constructor_overloaded
    with_checker <<-EOS do |checker|
class A
  def foo: (String) -> Integer
         | (Object) -> Integer
end
EOS

      source = parse_ruby("class A; def foo(x); end; end")

      with_standard_construction(checker, source) do |construction, typing|
        type_name = checker.factory.type_name_1(parse_type("::A").name)
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]
        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("(::Object | ::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::Integer"), method_context.return_type
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal parse_type("::Object | ::String"), for_method.type_env.lvar_types[:x]

        assert_empty typing.errors
      end
    end
  end

  def test_new_method_constructor_method_annotation
    with_checker <<-EOS do |checker|
class A
  def foo: () -> Integer
         | [A] () { () -> A } -> A
end
    EOS
      source = parse_ruby(<<-EOF)
class A
  # @type method foo: () ?{ () -> any } -> any
  def foo()
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        type_name = checker.factory.type_name_1(parse_type("::A").name)
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]

        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("() ?{ () -> any } -> any"), method_context.method_type
        assert_equal parse_type("any"), method_context.return_type
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_empty for_method.type_env.lvar_types

        assert_empty typing.errors
      end
    end
  end

  def test_new_method_constructor_with_return_type
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  def foo(x)
    # @type return: String
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type_name = checker.factory.type_name_1(parse_type("::A").name)
        instance_definition = checker.factory.definition_builder.build_instance(type_name)
        def_node = source.node.children[2]

        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("(::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::String"), method_context.return_type
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal [:x], for_method.type_env.lvar_types.keys
        assert_equal parse_type("::String"), for_method.type_env.lvar_types[:x]

        assert_equal 1, typing.errors.size
        assert_instance_of Steep::Errors::MethodReturnTypeAnnotationMismatch, typing.errors.first
      end
    end
  end

  def test_new_method_with_incompatible_annotation
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  # @type method foo: (String) -> String
  def foo(x)
    nil
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        def_node = source.node.children[2]
        type_name = checker.factory.type_name_1(parse_type("::A").name)
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        skip "Skip testing if method type annotation is compatible with interface"

        assert_equal 1, typing.errors.size
        assert_instance_of Steep::Errors::IncompatibleMethodTypeAnnotation, typing.errors.first
      end
    end
  end

  def test_relative_type_name
    with_checker <<-EOF do |checker|
class A::String
  def aaaaa: -> any
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  def foo
    # @type var x: String
    x = ""
  end

  # @type method bar: -> String
  def bar
    ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
        typing.errors.find {|e| e.is_a?(Steep::Errors::IncompatibleAssignment) }.yield_self do |error|
          assert_equal parse_type("::String"), error.rhs_type
          assert_equal parse_type("::A::String"), error.lhs_type
        end

        assert_any typing.errors do |error| error.is_a?(Steep::Errors::MethodBodyTypeMismatch) end
        typing.errors.find {|e| e.is_a?(Steep::Errors::MethodBodyTypeMismatch) }.yield_self do |error|
          assert_equal parse_type("::String"), error.actual
          assert_equal parse_type("::A::String"), error.expected
        end
      end
    end
  end

  def test_namespace_module
    with_checker <<-EOS do |checker|
class A
  def foobar: -> any
end

class A::String
  def aaaaa: -> any
end
    EOS

      source = parse_ruby(<<-RUBY)
class A < Object
  class String
  end

  class XYZ
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_instance_of Steep::Errors::MethodDefinitionMissing, typing.errors[0]
      end
    end
  end

  def test_namespace_module_nested
    with_checker <<-EOF do |checker|
class A
end

class A::String
  def foo: -> any
end
    EOF

      source = parse_ruby(<<-RUBY)
class A::String < Object
  def foo
    # @type var x: String
    x = ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_namespace_module_nested2
    with_checker <<-EOF do |checker|
class A
end

class A::String
  def foo: -> any
end
    EOF

      source = parse_ruby(<<-RUBY)
class ::A::String < Object
  def foo
    # @type var x: String
    x = ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_masgn
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
a, @b = 1, 2
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :lvasgn
        end
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :ivasgn
        end
      end
    end
  end

  def test_masgn_array
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
x = [1, 2]
a, @b = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :lvasgn
        end
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.node.type == :ivasgn
        end
      end
    end
  end

  def test_masgn_union
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Array[Integer] | Array[String]
x = (_ = nil)
a, b = x
      RUBY


      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        union = parse_type("::Integer | ::String")
        assert_equal union, construction.type_env.lvar_types[:a]
        assert_equal union, construction.type_env.lvar_types[:b]
      end
    end
  end

  def test_union_send_error
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer | String
x = (_ = nil)
y = x + ""
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch)
        end
      end
    end
  end

  def test_intersection_send
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer & String
x = (_ = nil)
y = x + ""
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_union_send
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer | String
x = (_ = nil)
y = x.itself
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_masgn_array_error
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
a, @b = 3
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::FallbackAny)
        end
      end
    end
  end

  def test_op_asgn
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
a = ""
a += ""
a += 3
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch)
        end
      end
    end
  end


  def test_while0
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
while true
  break
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_while2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
tap do
  while true
    break 30
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::UnexpectedJumpValue)
        end
      end
    end
  end

  def test_while3
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
while true
  tap do
    break self
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_while_post
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
begin
  a = 3
end while true
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_range
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: Range[Integer]
a = 1..2
a = 2..."a"
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_regexp
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Regexp
a = /./
a = /#{a + 3}/
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod)
        end
      end
    end
  end

  def test_nth_ref
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Integer
a = $1
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_or_and_asgn
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
a = 3
a &&= a
a ||= a + "foo"
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch)
        end
      end
    end
  end

  def test_next
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
while true
  next
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_next1
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
while true
  next 3
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::UnexpectedJumpValue)
        end
      end
    end
  end

  def test_next2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
tap do |a|
  next
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_method_arg_assign
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
def f(x)
  x = "forever" if x == nil
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
      end
    end
  end

  def test_restargs
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
def f(*x)
  # @type var y: String
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error| error.is_a?(Steep::Errors::FallbackAny) end
        assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
      end
    end
  end

  def test_restargs2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type method f: (*String) -> any
def f(*x)
  # @type var y: String
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
      end
    end
  end

  def test_gvar
    with_checker "$HOGE: Integer" do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_gvar1
    with_checker "$HOGE: Integer" do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = ""

# @type var x: Array[String]
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Steep::Errors::IncompatibleAssignment) }
      end
    end
  end

  def test_gvar2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Steep::Errors::FallbackAny) }
      end
    end
  end

  def test_ivar
    with_checker <<-EOF do |checker|
class A
  def foo: -> String
  @foo: String
end
    EOF
      source = parse_ruby(<<-'EOF')
class A
  def foo
    @foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_ivar2
    with_checker <<-EOF do |checker|
class A
  @foo: String
end
    EOF
      source = parse_ruby(<<-'EOF')
class A
  x = @foo
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error| error.is_a?(Steep::Errors::FallbackAny) end
      end
    end
  end

  def test_splat
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
a = [1]

# @type var b: Array[String]
b = [*a]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_splat_range
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var b: Array[String]
b = [*1...3]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_splat_object
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Array[Symbol] | Integer
a = (_ = nil)
b = [*a, *["foo"]]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::Array[::Integer|::Symbol|::String]"), construction.type_env.lvar_types[:b]
      end
    end
  end

  def test_splat_arg
    with_checker <<-EOF do |checker|
class A
  def initialize: () -> any
  def gen: (*Integer) -> String
end
    EOF
      source = parse_ruby(<<-'EOF')
a = A.new
a.gen(*["1"])
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch)
        end

        assert_equal parse_type("::A"), construction.type_env.lvar_types[:a]
      end
    end
  end

  def test_splat_arg2
    with_checker <<-EOF do |checker|
class A
  def initialize: () -> any
  def gen: (*Integer) -> String
end
      EOF
      source = parse_ruby(<<-'EOF')
a = A.new
b = [1]
a.gen(*b)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_void
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (self) -> void
end
    EOF
      source = parse_ruby(<<-'EOF')
class Hoge
  def foo(a)
    # @type var x: Integer
    x = a.foo(self)
    a.foo(self).class
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) && error.rhs_type.is_a?(Steep::AST::Types::Void)
        end
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod) && error.type.is_a?(Steep::AST::Types::Void)
        end
      end
    end
  end

  def test_void2
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () { () -> void } -> any
end
    EOF
      source = parse_ruby(<<-'EOF')
class Hoge
  def foo()
    # @type var x: String
    x = yield
    x = yield.class

    self.foo { 30 }
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) && error.rhs_type.is_a?(Steep::AST::Types::Void)
        end
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod) && error.type.is_a?(Steep::AST::Types::Void)
        end
      end
    end
  end

  def test_zip
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array[Integer|String]
b = a.zip(["foo"])
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_each_with_object
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array[Integer]
b = a.each_with_object([]) do |x, y|
  # @type var y: ::Array[String]
  y << ""
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_instance_of Steep::Errors::IncompatibleAssignment, typing.errors[0]
      end
    end
  end

  def test_if_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
if 3
  x = 1
  y = (x + 1).to_int
else
  x = "foo"
  y = (x.to_str).size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer"), construction.type_env.lvar_types[:x]
        assert_equal parse_type("::Integer"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_if_annotation
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = (_ = nil)

if 3
  # @type var x: String
  x + ""
else
  # @type var x: Integer
  x + 1
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        if_node = dig(source.node, 1)

        true_construction = construction.for_branch(if_node.children[1])
        assert_equal parse_type("::String"), true_construction.type_env.lvar_types[:x]

        false_construction = construction.for_branch(if_node.children[2])
        assert_equal parse_type("::Integer"), false_construction.type_env.lvar_types[:x]

        construction.synthesize(source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_if_annotation_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String]
x = (_ = nil)

if 3
  # @type var x: String
  x + ""
else
  # @type var x: Integer
  x + 1
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        if_node = dig(source.node, 1)

        true_construction = construction.for_branch(if_node.children[1])
        assert_equal parse_type("::String"), true_construction.type_env.lvar_types[:x]

        false_construction = construction.for_branch(if_node.children[2])
        assert_equal parse_type("::Integer"), false_construction.type_env.lvar_types[:x]

        typing.errors.find {|error| error.node == if_node.children[1] }.yield_self do |error|
          assert_instance_of Steep::Errors::IncompatibleAnnotation, error
          assert_equal :x, error.var_name
        end

        typing.errors.find {|error| error.node == if_node.children[2] }.yield_self do |error|
          assert_instance_of Steep::Errors::IncompatibleAnnotation, error
          assert_equal :x, error.var_name
        end
      end
    end
  end

  def test_when_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
case
when 30
  x = 1
  y = (x + 1).to_int
else
  x = "foo"
  y = (x.to_str).size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer"), construction.type_env.lvar_types[:x]
        assert_equal parse_type("::Integer"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_while_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = (_ = nil)

while 3
  # @type var x: Integer
  x + 3 
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_rescue_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type const E: any
# @type const F: any

begin
  1 + 2
rescue E
  x = 3
  x + 1
rescue F
  # @type var x: String
  x = "foo"
  x + ""
rescue
  x = :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer | ::Symbol"), construction.type_env.lvar_types[:x]
      end
    end
  end

  def test_rescue_bidning_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type const E: singleton(String)
# @type const F: singleton(Integer)

begin
  1 + 2
rescue E => exn
  exn + ""
rescue F => exn
  exn + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer"), construction.type_env.lvar_types[:exn]
      end
    end
  end

  def test_type_case_case_when
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer | Symbol
x = (_ = nil)

case x
when String
  y = (x + "").size
when Integer
  y = x + 1
else
  y = x.id2name.size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_type_case_array
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String] | Array[Integer] | Range[Symbol]
x = (_ = nil)

case x
when Array
  y = x[0]
  z = :foo
else
  z = x.begin
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer | nil"), construction.type_env.lvar_types[:y]
        assert_equal parse_type("::Symbol"), construction.type_env.lvar_types[:z]
      end
    end
  end

  def test_type_case_array2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String] | Array[Integer]
x = (_ = nil)

case x
when Array
  y = x[0]
else
  z = x
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::ElseOnExhaustiveCase, error
        end
      end
    end
  end

  def test_initialize_typing
    with_checker <<-EOF do |checker|
class ABC
  def initialize: (String) -> any
end
    EOF
      source = parse_ruby(<<EOF)
class ABC
  def initialize(foo)
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_cast_via_underscore
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String
x = (_ = 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_parametrized_class_constant
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = Array.new
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::Array[any]"), construction.type_env.lvar_types[:a]
      end
    end
  end

  def test_splat_from_any
    with_checker do |checker|
      source = parse_ruby(<<EOF)
(_ = []).[]=(*(_ = nil))
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_polymorphic
    with_checker <<-EOF do |checker|
class Optional
  def map: [A, B] (A) { (A) -> B } -> B
  def map2: [A, B] (A) { (A) -> B } -> B
end
    EOF
      source = parse_ruby(<<EOF)
class Optional
  def map(x)
    yield x
  end

  def map2(x)
    x.foo
    yield x
  end
end

# @type var x: Optional
x = (_ = nil)
(x.map("foo") {|x| x.size }) + 3
(x.map("foo") {|x| (_ = x) }) + 3
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod)
        end
      end
    end
  end

  def test_parameterized_class
    with_checker <<-EOF do |checker|
class Container[A]
  @value: A
  def initialize: () -> any
  def value: -> A
  def `value=`: (A) -> A
end
    EOF
      source = parse_ruby(<<EOF)
class Container
  def initialize()
  end

  def value
    @value
  end

  def value=(v)
    @value = v
  end
end

# @type var container: Container[Integer]
container = Container.new
container.value = 3
container.value + 4
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_parameterized_module
    with_checker <<-EOF do |checker|
module Value[A]
  @value: A
  def value: -> A
end
    EOF
      source = parse_ruby(<<EOF)
module Value
  def value
    @value
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_initialize
    with_checker <<-EOF do |checker|
class HelloWorld
end
    EOF
      source = parse_ruby(<<EOF)
hello = HelloWorld.new
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_initialize2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var hello: Integer
hello = Array.new(3, "")[0]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.lhs_type == parse_type("::Integer") &&
            error.rhs_type == parse_type("::String")
        end
      end
    end
  end

  def test_initialize_unbound_type_var_fallback_to_any
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer    
x = Array.new(3)[0]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_truthy_variables
    with_checker do
      assert_equal Set.new([:x]), TypeConstruction.truthy_variables(parse_ruby("x = 1").node)
      assert_equal Set.new([:x, :y]), TypeConstruction.truthy_variables(parse_ruby("x = y = 1").node)
      assert_equal Set.new([:x]), TypeConstruction.truthy_variables(parse_ruby("(x = 1) && f()").node)
    end
  end

  def test_if_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = nil

if x
  x + 1
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_and_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = nil
# @type var y1: Integer
y1 = 3

z = (x && y1 = y = x + 1)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Numeric?"), construction.type_env.lvar_types[:y]
        assert_equal parse_type("::Integer?"), construction.type_env.lvar_types[:z]
      end
    end
  end

  def test_csend_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String?
x = nil

z = x&.size()
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Integer?"), construction.type_env.lvar_types[:z]
      end
    end
  end

  def test_while
    with_checker do |checker|
      source = parse_ruby(<<EOF)
while line = gets
  # @type var x: String
  x = line
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::String?"), construction.type_env.lvar_types[:line]
      end
    end
  end

  def test_case_non_exhaustive
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

y = case x
when String
  3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Integer?"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_case_exhaustive
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

y = case x
when String
  3
when Integer
  4
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Integer"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_case_exhaustive_else
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer

y = case (x = "")
when String
  3
else
  4
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Integer"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_def_with_splat_kwargs
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type method f: (**String) -> any
def f(**args)
  args[:foo] + "hoge"
end

def g(**xs)
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::FallbackAny, error
        end
      end
    end
  end

  def test_splat_kw_args
    with_checker <<-EOF do |checker|
class KWArgTest
  def foo: (Integer, **String) -> void
end
    EOF
      source = parse_ruby(<<EOF)
test = KWArgTest.new

params = { a: 123 }
test.foo(123, **params)
test.foo(123, **123)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment) &&
            error.rhs_type == parse_type("::Integer") &&
            error.lhs_type == parse_type("::Hash[::Symbol, any]")
        end
      end
    end
  end

  def test_splat_kw_args_2
    with_checker <<-EOS do |checker|
class KWArgTest
  def foo: (Integer, **String) -> void
end
    EOS
      source = parse_ruby(<<EOF)
test = KWArgTest.new

params = { a: 123 }
test.foo(123, params)
test.foo(123, 123)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch) &&
            error.actual == parse_type("::Hash[::Symbol, ::Integer]") &&
            error.expected == parse_type("::Hash[::Symbol, ::String]")
        end

        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch) &&
            error.actual == parse_type("::Integer") &&
            error.expected == parse_type("::Hash[::Symbol, ::String]")
        end
      end
    end
  end

  def test_block_arg
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type method f: () { (any) -> any } -> any
def f(&block)
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_and_or
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = true && false
b = false || true
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("bool"), construction.type_env.lvar_types[:a]
        assert_equal parse_type("bool"), construction.type_env.lvar_types[:b]
      end
    end
  end

  def test_empty_body_method
    with_checker <<-EOF do |checker|
class EmptyBodyMethod
  def foo: () -> String
end
    EOF
      source = parse_ruby(<<EOF)
class EmptyBodyMethod
  def foo
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
      end
    end
  end

  def test_nil_reject
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = "x"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::IncompatibleAssignment, error
        end
      end
    end
  end

  def test_nil_method
    with_checker do |checker|
      source = parse_ruby(<<EOF)
nil.class
nil.no_such_method
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::NoMethod, error
          assert_equal :no_such_method, error.method
        end
      end
    end
  end

  def test_optional_method
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = 3
x.to_s
x.no_such_method
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::NoMethod, error
          assert_equal :no_such_method, error.method
        end
      end
    end
  end

  def test_literal
    with_checker <<-EOS do |checker|
class ClassWithLiteralArg
  def foo: (123) -> "foo"
         | (Integer) -> :bar
end
    EOS
      source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
a = ClassWithLiteralArg.new.foo(x)
b = ClassWithLiteralArg.new.foo(123)
c = ClassWithLiteralArg.new.foo(1234)
EOF


      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type('"foo"'), construction.type_env.lvar_types[:a]
        assert_equal parse_type('"foo"'), construction.type_env.lvar_types[:b]
        assert_equal parse_type(':bar'), construction.type_env.lvar_types[:c]
      end
    end
  end

  def test_literal2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
x + 123

# @type var y: "foo"
y = "foo"
y + "bar"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_tuple
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = (_=[])

a = x[0]
b = x[1]
c = x[2]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type('::Integer'), construction.type_env.lvar_types[:a]
        assert_equal parse_type('::String'), construction.type_env.lvar_types[:b]
        assert_equal parse_type('::Integer | ::String'), construction.type_env.lvar_types[:c]

        assert_empty typing.errors
      end
    end
  end

  def test_tuple1
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: ([Integer, String]) -> [Integer, String]
end
    EOF
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = [1, "foo"]
x = ["foo", 1]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
      end
    end
  end

  def test_tuple2
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: ([Integer, String]) -> [String, Integer]
end
    EOF
      source = parse_ruby(<<EOF)
x = TupleMethod.new.foo([1, "foo"])
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type('[::String, ::Integer]'), construction.type_env.lvar_types[:x]
      end
    end
  end

  def test_tuple3
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: () -> [String, Integer, bool]
end
    EOF
      source = parse_ruby(<<EOF)
x, y, z = TupleMethod.new.foo()
a, b = TupleMethod.new.foo()
_, _, _, c = TupleMethod.new.foo()
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type('::String'), construction.type_env.lvar_types[:x]
        assert_equal parse_type('::Integer'), construction.type_env.lvar_types[:y]
        assert_equal parse_type('bool'), construction.type_env.lvar_types[:z]

        assert_equal parse_type('::String'), construction.type_env.lvar_types[:a]
        assert_equal parse_type('::Integer'), construction.type_env.lvar_types[:b]

        assert_equal parse_type("nil"), construction.type_env.lvar_types[:c]
      end
    end
  end

  def test_tuple4
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = [1, "foo"]
x.each do |a|
  a.no_such_method
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::NoMethod, error
          assert_equal parse_type("(::Integer | ::String)"), error.type
        end
      end
    end
  end

  def test_tuple5_subtyping
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer | String, String]
x = [1, "foo"]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_hash_tuple
    with_checker do |checker|
      source = parse_ruby(<<EOF)
hash = { "foo" => 1 }

hash.each do |x|
  a = x[0] + ""
  b = x[1] + 3
end

hash.each do |a, b|
  a + ""
  b + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_super
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () -> Integer
end

class TestSuperChild < TestSuper
  def foo: () -> Integer
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def foo
    super + 3
    super() + 1
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_super_no_decl
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () -> Integer
end

class TestSuperChild < TestSuper
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def foo
    super + 3
    super() + 1
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_empty_array_is_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
[]
{}
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_all typing.errors do |error|
          error.is_a?(Steep::Errors::FallbackAny)
        end
      end
    end
  end

  def test_alias_hint
    with_checker <<-EOF do |checker|
type a = :foo | :bar
    EOF
      source = parse_ruby(<<EOF)
# @type var a: a
a = :foo
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_or
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String?
x = nil

a = x || "foo"
b = "foo" || x
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::String"), construction.type_env.lvar_types[:a]
        assert_equal parse_type("::String?"), construction.type_env.lvar_types[:b]
      end
    end
  end

  def test_hash_optional
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Hash[Symbol, String?]
x = { foo: "bar" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_array_optional
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[Symbol?]
x = [:foo, :bar]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_passing_empty_block
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = 1

x.tap {|x| }
x.to_s {|x| }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::UnexpectedBlockGiven)
        end
      end
    end
  end

  def test_type_block
    with_checker do |checker|
      source = parse_ruby(<<EOF)
foo.bar {|x, y| x }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        block_params_node = source.node.children[1]
        block_body_node = source.node.children[2]
        block_annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
        block_params = Steep::TypeInference::BlockParams.from_node(block_params_node, annotations: block_annotations)

        type = construction.type_block(block_param_hint: nil,
                                       block_type_hint: nil,
                                       node_type_hint: nil,
                                       block_params: block_params,
                                       block_body: block_body_node,
                                       block_annotations: block_annotations,
                                       topdown_hint: true)
        assert_equal "^(any, any) -> any", type.to_s
      end
    end
  end

  def test_type_block_annotation
    with_checker do |checker|
      source = parse_ruby(<<EOF)
foo.bar do |x, y|
  # @type var x: String
  # @type var y: Integer
  # @type block: :bar
  :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        block_params_node = source.node.children[1]
        block_body_node = source.node.children[2]
        block_annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
        block_params = Steep::TypeInference::BlockParams.from_node(block_params_node, annotations: block_annotations)

        type = construction.type_block(block_param_hint: nil,
                                       block_type_hint: nil,
                                       node_type_hint: nil,
                                       block_params: block_params,
                                       block_body: block_body_node,
                                       block_annotations: block_annotations,
                                       topdown_hint: true)
        assert_equal parse_type("^(::String, ::Integer) -> :bar"), type

        refute_empty typing.errors
      end
    end
  end

  def test_type_block_hint
    with_checker do |checker|
      source = parse_ruby(<<EOF)
foo.bar do |x, y|
  :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        hint = parse_method_type("() { (::String, ::Integer) -> :bar } -> void")

        block_params_node = source.node.children[1]
        block_body_node = source.node.children[2]
        block_annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
        block_params = Steep::TypeInference::BlockParams.from_node(block_params_node, annotations: block_annotations)

        type = construction.type_block(block_param_hint: hint.block.type.params,
                                       block_type_hint: hint.block.type.return_type,
                                       node_type_hint: nil,
                                       block_params: block_params,
                                       block_body: block_body_node,
                                       block_annotations: block_annotations,
                                       topdown_hint: true)
        assert_equal "^(::String, ::Integer) -> ::Symbol", type.to_s
      end
    end
  end

  def test_type_block_hint2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
foo.bar do |x, y, z|
  z.bazbazbaz
  :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        hint = parse_method_type("() { (::String, ::Integer) -> :bar } -> void")

        block_params_node = source.node.children[1]
        block_body_node = source.node.children[2]
        block_annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
        block_params = Steep::TypeInference::BlockParams.from_node(block_params_node, annotations: block_annotations)

        type = construction.type_block(block_param_hint: hint.block.type.params,
                                       block_type_hint: hint.block.type.return_type,
                                       node_type_hint: nil,
                                       block_params: block_params,
                                       block_body: block_body_node,
                                       block_annotations: block_annotations,
                                       topdown_hint: true)
        assert_equal parse_type("^(::String, ::Integer) -> ::Symbol"), type

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod) &&
            error.method == :bazbazbaz &&
            error.type == parse_type("nil")
        end
      end
    end
  end

  def test_type_block_arg
    with_checker <<-EOF do |checker|
class MethodWithBlockArg
  def foo: [X] { (Integer) -> X } -> Array[X]
end
    EOF
      source = parse_ruby(<<EOF)
class MethodWithBlockArg
  def foo(&block)
    [1,2,3].map(&block)
  end
end

a = MethodWithBlockArg.new.foo {|x| x.to_s }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::Array[::String]"), construction.type_env.lvar_types[:a]
      end
    end
  end

  def test_type_proc_objects
    with_checker <<-EOF do |checker|
class MethodWithBlockArg
  def foo: [X] { (Integer) -> X } -> Array[X]
end
    EOF
      source = parse_ruby(<<EOF)
class MethodWithBlockArg
  def foo(&block)
    block.arity
    block.call("")
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::ArgumentTypeMismatch, error
        end
      end
    end
  end

  def test_lambda1
    with_checker do |checker|
      source = parse_ruby(<<EOF)
l = -> (x, y) do
  # @type var x: Integer
  x + y
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal "^(::Integer, any) -> ::Numeric", construction.type_env.lvar_types[:l].to_s
      end
    end
  end

  def test_lambda2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var l: String
l = -> (x, y) do
  x + y
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Steep::Errors::IncompatibleAssignment, error
        end
      end
    end
  end

  def test_empty_begin
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = begin; end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("nil"), construction.type_env.lvar_types[:a]
      end
    end
  end

  def test_begin_type
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var a: :foo
a = begin
  :bar
  x = :baz
  y = :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type(":foo"), construction.type_env.lvar_types[:a]
        assert_equal parse_type("::Symbol"), construction.type_env.lvar_types[:x]
        assert_equal parse_type(":foo"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_hash_type
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3, name: "foo" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_hash_type2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3, name: :symbol }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_hash_type3
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3 }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::IncompatibleAssignment)
        end
      end
    end
  end

  def test_hash_type4
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { count: Object }
x = { count: "3" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_hash_type5
    with_checker <<-EOF do |checker|
module WithHashArg
  def self.f: [A] ({ foo: A }) -> A
end
    EOF
      source = parse_ruby(<<EOF)
WithHashArg.f(foo: 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_polymorphic_method
    with_checker <<-EOF do |checker|
interface _Ref[X]
  def get: -> X
end

class Factory[X]
  def initialize: (_Ref[X]) -> any
end

class WithPolyMethod
  def foo: [X] (_Ref[X]) -> Factory[X]
end
    EOF
      source = parse_ruby(<<-EOF)
class WithPolyMethod
  def foo(x)
    Factory.new(x)
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_array_arg
    with_checker <<-EOF do |checker|
class WithArray
  def foo: (?path: Array[Symbol]) -> void
end
    EOF
      source = parse_ruby(<<-EOF)
WithArray.new.foo(path: [])
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_private_method1
    with_checker <<-EOF do |checker|
class WithPrivate
  private
  def foo: () -> void
end
    EOF
      source = parse_ruby(<<-EOF)
WithPrivate.new.foo
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod)
        end
      end
    end
  end

  def test_private_method2
    with_checker <<-EOF do |checker|
class WithPrivate
  private
  def foo: () -> void
end
    EOF
      source = parse_ruby(<<-EOF)
class WithPrivate
  def foo; end

  def bar
    foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_private_method3
    with_checker <<-EOS do |checker|
class WithPrivate
  private
  def foo: () -> void
end
    EOS
      source = parse_ruby(<<-EOF)
class WithPrivate
  def foo; end

  def bar
    self.foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::NoMethod)
        end
      end
    end
  end

  def test_inherit_class
    with_checker <<-EOF do |checker|
class SuperClass
  def foo: () -> Integer
end
    EOF
      source = parse_ruby(<<-EOF)
class ChildClass < SuperClass
  def bar
    foo + ""
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Steep::Errors::ArgumentTypeMismatch)
        end
      end
    end
  end

  def test_or_nil_unwrap
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: Array[Integer]?
x = nil
y = x || []
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::Array[::Integer]"), construction.type_env.lvar_types[:y]
      end
    end
  end

  def test_skip_alias
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
alias foo bar
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("any"), typing.type_of(node: source.node)
      end
    end
  end
end
