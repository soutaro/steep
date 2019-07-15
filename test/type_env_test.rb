require_relative "test_helper"

class TypeEnvTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  ConstantEnv = TypeInference::ConstantEnv
  TypeEnv = TypeInference::TypeEnv

  def test_ivar_without_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      # If no annotation is given to ivar, assign yields the block with nil and returns `any`
      yield_self do
        ivar_type = type_env.assign(ivar: :"@x",
                                    type: AST::Types::Name.new_instance(name: "::String")) {|error| assert_nil error}
        assert_instance_of AST::Types::Any, ivar_type
      end

      # If no annotation is given to ivar, get yields the block and returns `any`
      yield_self do
        ivar_type = type_env.get(ivar: :"@x") {|error| assert_nil error}
        assert_instance_of AST::Types::Any, ivar_type
      end
    end
  end

  def test_ivar_with_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      type_env.set(ivar: :"@x", type: AST::Types::Name.new_instance(name: "::Numeric"))

      # If annotation is given, get returns the type
      yield_self do
        ivar_type = type_env.get(ivar: :"@x")
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), ivar_type
      end

      # If annotation is given and assigned type is compatible with that, assign returns annotated type, no yield
      yield_self do
        ivar_type = type_env.assign(ivar: :"@x",
                                    type: AST::Types::Name.new_instance(name: "::Integer")) do |_|
          raise
        end
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), ivar_type
      end

      # If annotation is given and assigned type is incompatible with that, assign returns annotated type and yield an failure result
      yield_self do
        ivar_type = type_env.assign(ivar: :"@x",
                                    type: AST::Types::Name.new_instance(name: "::String")) do |error|
          assert_instance_of Subtyping::Result::Failure, error
        end
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), ivar_type
      end
    end
  end

  def test_gvar_without_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      # If no annotation is given to ivar, assign yields the block with nil and returns `any`
      yield_self do
        type = type_env.assign(gvar: :"$x",
                               type: AST::Types::Name.new_instance(name: "::String")) {|error| assert_nil error}
        assert_instance_of AST::Types::Any, type
      end

      # If no annotation is given to ivar, get yields the block and returns `any`
      yield_self do
        type = type_env.get(gvar: :"$x") {|error| assert_nil error}
        assert_instance_of AST::Types::Any, type
      end
    end
  end

  def test_gvar_with_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      type_env.set(gvar: :"$x", type: AST::Types::Name.new_instance(name: "::Numeric"))

      # If annotation is given, get returns the type
      yield_self do
        type = type_env.get(gvar: :"$x")
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), type
      end

      # If annotation is given and assigned type is compatible with that, assign returns annotated type, no yield
      yield_self do
        type = type_env.assign(gvar: :"$x",
                               type: AST::Types::Name.new_instance(name: "::Integer")) do |_|
          raise
        end
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), type
      end

      # If annotation is given and assigned type is incompatible with that, assign returns annotated type and yield an failure result
      yield_self do
        type = type_env.assign(gvar: :"$x",
                               type: AST::Types::Name.new_instance(name: "::String")) do |error|
          assert_instance_of Subtyping::Result::Failure, error
        end
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), type
      end
    end
  end

  def test_const_without_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      # When constant type is known from const env

      yield_self do
        type = type_env.get(const: Names::Module.parse("Regexp"))
        assert_equal AST::Types::Name.new_class(name: "::Regexp", constructor: nil), type
      end

      yield_self do
        type = type_env.assign(const: Names::Module.parse("Regexp"),
                               type: AST::Types::Name.new_instance(name: "::String")) do |error|
          assert_instance_of Subtyping::Result::Failure, error
        end
        assert_equal AST::Types::Name.new_class(name: "::Regexp", constructor: nil), type
      end

      yield_self do
        type = type_env.assign(const: Names::Module.parse("Regexp"),
                               type: AST::Types::Any.new) do |_|
          raise
        end
        assert_equal AST::Types::Name.new_class(name: "::Regexp", constructor: nil), type
      end

      # When constant type is unknown

      yield_self do
        type = type_env.get(const: Names::Module.parse("HOGE")) do
        end
        assert_instance_of AST::Types::Any, type
      end

      yield_self do
        type = type_env.assign(const: Names::Module.parse("HOGE"),
                               type: AST::Types::Name.new_instance(name: "::String")) do |error|
          assert_nil error
        end
        assert_instance_of AST::Types::Any, type
      end
    end
  end

  def test_const_with_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      type_env.set(const: Names::Module.parse("Regexp"), type: AST::Types::Name.new_instance(name: "::String"))

      yield_self do
        type = type_env.get(const: Names::Module.parse("Regexp"))
        assert_equal AST::Types::Name.new_instance(name: "::String"), type
      end

      yield_self do
        type = type_env.assign(const: Names::Module.parse("Regexp"),
                               type: AST::Types::Name.new_instance(name: "::Integer")) do |error|
          assert_instance_of Subtyping::Result::Failure, error
        end
        assert_equal AST::Types::Name.new_instance(name: "::String"), type
      end

      yield_self do
        type = type_env.assign(const: Names::Module.parse("Regexp"),
                               type: AST::Types::Name.new_instance(name: "::String")) do |_|
          raise
        end
        assert_equal AST::Types::Name.new_instance(name: "::String"), type
      end
    end
  end

  def test_lvar_get_without_assign
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)


      type = type_env.get(lvar: :x) {AST::Types::Name.new_instance(name: "::String")}
      # Returns a type which obtained from given block
      assert_equal AST::Types::Name.new_instance(name: "::String"), type

      # And update environment
      assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.lvar_types[:x]
    end
  end

  def test_lvar_without_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)


      yield_self do
        type = type_env.assign(lvar: :x,
                               type: AST::Types::Name.new_instance(name: "::String")) {|_| raise}
        assert_equal AST::Types::Name.new_instance(name: "::String"), type
      end

      yield_self do
        type = type_env.assign(lvar: :x,
                               type: AST::Types::Name.new_instance(name: "::Numeric")) do |error|
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type
      end
    end
  end

  def test_lvar_with_annotation
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      type_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      type_env.set(lvar: :x, type: AST::Types::Name.new_instance(name: "::Numeric"))

      yield_self do
        type = type_env.assign(lvar: :x,
                               type: AST::Types::Name.new_instance(name: "::Integer")) {|_| raise}
        assert_equal AST::Types::Name.new_instance(name: "::Numeric"), type
      end
    end
  end

  def test_with_annotation_lvar
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      original_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      union_type = AST::Types::Union.build(types: [
        AST::Types::Name.new_instance(name: "::Integer"),
        AST::Types::Name.new_instance(name: "::String")
      ])

      original_env.set(lvar: :x, type: union_type)

      yield_self do
        type_env = original_env.with_annotations(lvar_types: {
          x: AST::Types::Name.new_instance(name: "::String")
        }) do |_, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(lvar: :x) {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(lvar_types: {
          x: AST::Types::Name.new_instance(name: "::Regexp")
        }) do |name, relation, error|
          assert_equal name, :x
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::Regexp"), type_env.get(lvar: :x) {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(lvar_types: {
          y: AST::Types::Name.new_instance(name: "::String")
        }) do |_, _, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(lvar: :y) {raise}
      end
    end
  end

  def test_with_annotation_ivar
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      original_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      union_type = AST::Types::Union.build(types: [
        AST::Types::Name.new_instance(name: "::Integer"),
        AST::Types::Name.new_instance(name: "::String")
      ])

      original_env.set(ivar: :"@x", type: union_type)

      yield_self do
        type_env = original_env.with_annotations(ivar_types: {
          "@x": AST::Types::Name.new_instance(name: "::String")
        }) do |_, _, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(ivar: :"@x") {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(ivar_types: {
          "@x": AST::Types::Name.new_instance(name: "::Regexp")
        }) do |name, relation, error|
          assert_equal name, :"@x"
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::Regexp"), type_env.get(ivar: :"@x") {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(ivar_types: {
          "@y": AST::Types::Name.new_instance(name: "::String")
        }) do |_, _, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(ivar: :"@y") {raise}
      end
    end
  end

  def test_with_annotation_gvar
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      original_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      union_type = AST::Types::Union.build(types: [
        AST::Types::Name.new_instance(name: "::Integer"),
        AST::Types::Name.new_instance(name: "::String")
      ])

      original_env.set(gvar: :"$x", type: union_type)

      yield_self do
        type_env = original_env.with_annotations(gvar_types: {
          "$x": AST::Types::Name.new_instance(name: "::String")
        }) do |_, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(gvar: :"$x") {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(gvar_types: {
          "$x": AST::Types::Name.new_instance(name: "::Regexp")
        }) do |name, relation, error|
          assert_equal name, :"$x"
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::Regexp"), type_env.get(gvar: :"$x") {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(gvar_types: {
          "$y": AST::Types::Name.new_instance(name: "::String")
        }) do |_, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(gvar: :"$y") {raise}
      end
    end
  end

  def test_with_annotation_const
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      original_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      union_type = AST::Types::Union.build(types: [
        AST::Types::Name.new_instance(name: "::Integer"),
        AST::Types::Name.new_instance(name: "::String")
      ])

      original_env.set(const: Names::Module.parse("FOO"), type: union_type)

      yield_self do
        type_env = original_env.with_annotations(const_types: {
          Names::Module.parse("FOO") => AST::Types::Name.new_instance(name: "::String")
        }) do |_, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"),
                     type_env.get(const: Names::Module.parse("FOO")) {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(const_types: {
          Names::Module.parse("FOO") => AST::Types::Name.new_instance(name: "::Regexp")
        }) do |name, relation, error|
          assert_equal name, Names::Module.parse("FOO")
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::Regexp"),
                     type_env.get(const: Names::Module.parse("FOO")) {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(const_types: {
          Names::Module.parse("String") => AST::Types::Name.new_instance(name: "::Regexp")
        }) do |name, relation, error|
          assert_equal name, Names::Module.parse("String")
          assert_instance_of Subtyping::Result::Failure, error
        end

        assert_equal AST::Types::Name.new_instance(name: "::Regexp"),
                     type_env.get(const: Names::Module.parse("String")) {raise}
      end

      yield_self do
        type_env = original_env.with_annotations(const_types: {
          Names::Module.parse("BAR") => AST::Types::Name.new_instance(name: "::String")
        }) do |_, _, _|
          raise
        end

        assert_equal AST::Types::Name.new_instance(name: "::String"), type_env.get(const: Names::Module.parse("BAR")) {raise}
      end
    end
  end

  def test_join
    with_checker do |checker|
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)
      original_env = TypeEnv.new(subtyping: checker, const_env: const_env)

      original_env.set(lvar: :z, type: AST::Types::Any.new)

      envs = [
        original_env.with_annotations(lvar_types: {
          x: AST::Types::Name.new_instance(name: "::String"),
          y: AST::Types::Name.new_instance(name: "::Integer")
        }),
        original_env.with_annotations(lvar_types: {
          x: AST::Types::Name.new_instance(name: "::Integer"),
          z: AST::Types::Name.new_instance(name: "::Regexp")
        })
      ]

      original_env.join!(envs)

      assert_equal AST::Types::Union.build(types: [
        AST::Types::Name.new_instance(name: "::String"),
        AST::Types::Name.new_instance(name: "::Integer"),
      ]), original_env.get(lvar: :x)

      assert_equal AST::Types::Union.build(types: [AST::Types::Name.new_instance(name: "::Integer"),
                                                   AST::Types::Nil.new]),
                   original_env.get(lvar: :y)
      assert_instance_of AST::Types::Any, original_env.get(lvar: :z)
    end
  end

  def test_build
    with_checker <<-EOS do |checker|
class X end
class Y end
$foo: String
    EOS
      const_env = ConstantEnv.new(factory: checker.factory, context: nil)

      annotations = AST::Annotation::Collection.new(annotations: [
        AST::Annotation::VarType.new(name: :x, type: AST::Types::Name.new_instance(name: :X)),
        AST::Annotation::IvarType.new(name: :"@y", type: AST::Types::Name.new_instance(name: :Y)),
        AST::Annotation::ConstType.new(name: Names::Module.parse("Foo"), type: AST::Types::Name.new_instance(name: "::Integer")),
        AST::Annotation::ReturnType.new(type: AST::Types::Name.new_instance(name: :Z)),
        AST::Annotation::BlockType.new(type: AST::Types::Name.new_instance(name: :A)),
        AST::Annotation::Dynamic.new(names: [
          AST::Annotation::Dynamic::Name.new(name: :path, kind: :instance)
        ])
      ], factory: checker.factory, current_module: AST::Namespace.root)

      env = TypeInference::TypeEnv.build(annotations: annotations,
                                         signatures: factory.env,
                                         subtyping: checker,
                                         const_env: const_env)

      assert_equal AST::Types::Name.new_instance(name: "::X"), env.get(lvar: :x)
      assert_equal AST::Types::Name.new_instance(name: "::Y"), env.get(ivar: :"@y")
      assert_equal AST::Types::Name.new_instance(name: "::Integer"), env.get(const: Names::Module.parse("Foo"))
      assert_equal AST::Types::Name.new_instance(name: "::String"), env.get(gvar: :"$foo")
    end
  end
end
