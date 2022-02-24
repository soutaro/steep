require_relative "test_helper"

class LocalVariableTypeEnvTest < Minitest::Test
  include Steep

  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  ConstantEnv = TypeInference::ConstantEnv
  LocalVariableTypeEnv = TypeInference::LocalVariableTypeEnv

  Entry = LocalVariableTypeEnv::Entry

  def test_assign_no_decl
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
x = 1
y = 2
EOF

      node = dig(source.node, 0)

      type_env.assign(:x, node: node, type: parse_type("Integer")).tap do |env|
        assert_equal({}, env.declared_types)
        assert_equal({
                       x: Entry.new(type: parse_type("Integer"), nodes: [node])
                     }, env.assigned_types)
        assert_equal parse_type("Integer"), env[:x]
      end
    end
  end

  def test_assign_with_decl_no_error
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::Integer | ::String")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: Integer
x = 1
y = 2
EOF

      node = dig(source.node, 0)

      type_env.assign(:x, node: node, type: parse_type("::Integer")).tap do |env|
        assert_equal parse_type("::Integer | ::String"), env[:x]
      end
    end
  end

  def test_assign_with_decl_type_error
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::Integer | ::String")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: Integer
x = 1
y = 2
EOF

      node = dig(source.node, 0)

      type_env.assign(:x, node: node, type: parse_type("::Symbol")) do |declared_type, assigned_type, result|
        assert_predicate result, :failure?
        assert_equal declared_type, parse_type("::Integer | ::String")
        assert_equal assigned_type, parse_type("::Symbol")
      end.tap do |env|
        assert_equal parse_type("::Integer | ::String"), env[:x]
      end
    end
  end

  def test_annotate
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::Integer | ::String")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = 1

if foo()
  # @type var x: Integer
  x + 1
end
EOF

      annotations = source.annotations(block: dig(source.node, 1, 1),
                                       factory: checker.factory,
                                       current_module: RBS::Namespace.root)

      type_env.annotate(annotations).tap do |env|
        assert_equal parse_type("::Integer"), env[:x]
      end
    end
  end

  def test_annotate_with_error
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::Integer | ::String")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = 1

if foo()
  # @type var x: ::Symbol
  x + 1
end
EOF

      annotations = source.annotations(block: dig(source.node, 1, 1),
                                       factory: checker.factory,
                                       current_module: RBS::Namespace.root)

      type_env.annotate(annotations) do |name, outer_type, inner_type, result|
        assert_equal :x, name
        assert_equal parse_type("::Symbol"), inner_type
        assert_equal parse_type("::Integer | ::String"), outer_type
        assert_predicate result, :failure?
      end
    end
  end

  def test_annotate_block
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = 1

[].each do |x|
  # @type var x: Array[String]
end
EOF

      top_annots = source.annotations(block: dig(source.node),
                                      factory: checker.factory,
                                      current_module: RBS::Namespace.root)
      top_level_env = type_env.annotate(top_annots)

      assert_equal parse_type("::Integer | ::String"), top_level_env[:x]

      block_annots = source.annotations(block: dig(source.node, 1),
                                        factory: checker.factory,
                                        current_module: RBS::Namespace.root)
      block_env = top_level_env.except(Set[:x]).annotate(block_annots)

      assert_equal parse_type("::Array[::String]"), block_env[:x]
    end
  end

  def test_for_loop_no_decl
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
x = 1

[1,2,3].each do |y|
  x = ""
end
EOF

      type_env.assign(:x, node: dig(source.node, 0), type: parse_type("::Integer")).pin_assignments.tap do |new_env|
        assert_equal parse_type("::Integer"), new_env[:x]

        assert_equal parse_type("::Integer"), new_env.declared_types[:x].type
        assert_nil new_env.assigned_types[:x]

        new_env.assign(:x, node: dig(source.node, 1, 2), type: parse_type("::String")) do |declared_type, assigned_type, result|
          assert_equal parse_type("::Integer"), declared_type
          assert_equal parse_type("::String"), assigned_type
          assert_predicate result, :failure?
        end
      end
    end
  end

  def test_for_loop_with_decl
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::String | ::Integer")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = 1

[1,2,3].each do |y|
  x = ""
end
EOF

      type_env.assign(:x, node: dig(source.node, 0), type: parse_type("::Integer")).pin_assignments.tap do |new_env|
        assert_equal parse_type("::Integer | ::String"), new_env[:x]

        assert_equal parse_type("::Integer | ::String"), new_env.declared_types[:x].type
        assert_nil new_env.assigned_types[:x]

        new_env.assign(:x, node: dig(source.node, 1, 2), type: parse_type("::String"))
      end
    end
  end

  def test_for_loop_assign_and_decl_error
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
x = 1

[1,2,3].each do |y|
  # @type var x: String | Integer
  x = ""
end
EOF

      annots = source.annotations(block: dig(source.node, 1),
                                  factory: checker.factory,
                                  current_module: RBS::Namespace.root)

      type_env.assign(:x, node: dig(source.node, 0), type: parse_type("::Integer"))
        .pin_assignments
        .except(Set[:y]).tap do |loop_env|
        loop_env.annotate(annots) do |var, out_type, in_type, result|
          assert_equal :x, var
          assert_equal parse_type("::Integer"), out_type
          assert_equal parse_type("::Integer | ::String"), in_type
          assert_predicate result, :failure?
        end
      end
    end
  end

  def test_for_loop_assign_and_decl_error2
    with_checker do
      type_env = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      source = parse_ruby(<<EOF)
x = 1

[1,2,3].each do |y|
  # @type var x: String | Integer
  x = ""
end
EOF

      type_env.assign(:x, node: dig(source.node, 0), type: parse_type("::Integer | ::String | nil"))
        .pin_assignments
        .tap do |loop_env|
        loop_annots = source.annotations(block: dig(source.node, 1),
                                         factory: checker.factory,
                                         current_module: RBS::Namespace.root)
        # Annotate with more precise type is okay.
        loop_env.annotate(loop_annots)
      end
    end
  end

  def test_entry_optional
    with_checker do
      e = Entry.new(type: parse_type("::Integer"))
      assert_equal Entry.new(type: parse_type("::Integer?")), e.optional
    end
  end

  def test_entry_plus
    with_checker do
      e1 = Entry.new(type: parse_type("::Integer"))
      e2 = Entry.new(type: parse_type("::String"))

      assert_equal Entry.new(type: parse_type("::Integer | ::String")), e1 + e2
    end
  end

  def test_join_assignment
    with_checker do
      #                  # env1
      #
      # if foo
      #   x = "foo"      # env2
      #   y = :foo
      # else
      #   x = 3          # env3
      #   z = [1]
      # end
      #
      #                  # env1.merge(env2, env3)

      env1 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      env2 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: { x: Entry.new(type: parse_type("::String")),
                          y: Entry.new(type: parse_type("::Symbol")) },
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      env3 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: { x: Entry.new(type: parse_type("::Integer")),
                          z: Entry.new(type: parse_type("::Array[::Integer]")) },
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      join = env1.join(env2, env3)

      assert_equal parse_type("::Integer | ::String"), join[:x]
      assert_equal parse_type("::Symbol?"), join[:y]
      assert_equal parse_type("::Array[::Integer]?"), join[:z]
    end
  end

  def test_join_with_decl
    with_checker do
      # # @type var x: String | Integer | Symbol
      # x = ...
      #
      # if foo
      #   # @type var x: String  # env2
      #   # @type var y: String
      #   x = "foo"
      #   y = ""
      # else
      #   # @type var x: Integer # env3
      #   x = 3
      # end
      #
      #                         # env1.merge(env2, env3)

      env1 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::String | ::Integer | ::Symbol")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      env2 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::String")),
                          y: Entry.new(type: parse_type("::String")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      env3 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::Integer")) },
        assigned_types: {},
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      join = env1.join(env2, env3)

      assert_equal parse_type("::Integer | ::String | ::Symbol"), join[:x]
      assert_equal parse_type("::String?"), join[:y]
    end
  end

  def test_join_loop_assignment
    with_checker do
      # x = ""
      #
      # while foo
      #   y = 12345             # env2
      # end
      #
      #                         # env1.merge(env1, env2)

      env1 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: {},
        assigned_types: { x: Entry.new(type: parse_type("::String")) },
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      env2 = LocalVariableTypeEnv.new(
        subtyping: checker,
        declared_types: { x: Entry.new(type: parse_type("::String")) },
        assigned_types: { y: Entry.new(type: parse_type("::Integer")) },
        self_type: parse_type("::Object"),
        instance_type: parse_type("::Object"),
        class_type: parse_type("singleton(::Object)")
      )

      join = env1.join(env1, env2)

      assert_equal parse_type("::String"), join[:x]
      assert_equal parse_type("::Integer?"), join[:y]
    end
  end
end
