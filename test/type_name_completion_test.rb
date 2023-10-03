require_relative "test_helper"

class TypeNameCompletionTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  include Steep

  def buffer(string)
    RBS::Buffer.new(name: "a.rb", content: string)
  end

  def test_prefix_parse
    Services::TypeNameCompletion::Prefix.parse(buffer("() -> "), line: 1, column: 5).tap do |prefix|
      assert_nil prefix
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> St"), line: 1, column: 8).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::RawIdentPrefix, prefix
      assert_equal "St", prefix.ident
      assert_predicate prefix, :const_name?
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> booli"), line: 1, column: 11).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::RawIdentPrefix, prefix
      assert_equal "booli", prefix.ident
      refute_predicate prefix, :const_name?
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> ::RBS::"), line: 1, column: 13).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::NamespacePrefix, prefix
      assert_equal RBS::Namespace.parse("::RBS::"), prefix.namespace
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> ::"), line: 1, column: 8).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::NamespacePrefix, prefix
      assert_equal RBS::Namespace.parse("::"), prefix.namespace
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> ::RBS::Na"), line: 1, column: 15).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix, prefix
      assert_equal RBS::Namespace.parse("::RBS::"), prefix.namespace
      assert_equal "Na", prefix.ident
      assert_predicate prefix, :const_name?
    end

    Services::TypeNameCompletion::Prefix.parse(buffer("() -> ::RBS"), line: 1, column: 11).tap do |prefix|
      assert_instance_of Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix, prefix
      assert_equal RBS::Namespace.parse("::"), prefix.namespace
      assert_equal "RBS", prefix.ident
      assert_predicate prefix, :const_name?
    end
  end

  def test_find_type_names
    with_factory({ "a.rbs" => <<~RBS }, nostdlib: true) do |factory|
        class Foo
          module Bar
            type baz = Integer

            interface _Quax
            end
          end
        end
      RBS

      completion = Services::TypeNameCompletion.new(env: factory.env, context: nil, dirs: [])

      # Returns all accessible type names from the context
      assert_equal [TypeName("::Foo")], completion.find_type_names(nil)

      # Returns all type names that contains the identifier case-insensitively
      assert_equal [TypeName("::Foo::Bar"), TypeName("::Foo::Bar::baz"), TypeName("::Foo::Bar::_Quax")], completion.find_type_names(Services::TypeNameCompletion::Prefix::RawIdentPrefix.new("ba"))

      # Returns all type names that shares the prefix and contains the identifier case-insensitively
      assert_equal [TypeName("::Foo::Bar::baz")], completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("::Foo::Bar::"), "ba"))

      assert_equal [TypeName("::Foo")], completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("::"), "Fo"))

      # Returns all type names that shares the prefix
      assert_equal [TypeName("::Foo::Bar::baz"), TypeName("::Foo::Bar::_Quax")], completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacePrefix.new(RBS::Namespace.parse("::Foo::Bar::")))
    end
  end

  def test_each_type_name_used
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use NoSuchClass, Object as ExistingClass
      RBS

      buf = factory.env.buffers.find {|buf| File.basename(buf.name) == "a.rbs" } or raise
      dirs, _ = factory.env.signatures[buf]

      completion = Services::TypeNameCompletion.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      refute completion.each_type_name.include?(TypeName("NoSuchClass"))
      assert completion.each_type_name.include?(TypeName("ExistingClass"))
    end
  end

  def test_each_type_name_alias
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        module Foo
          module Bar = ::Bar
        end

        module Bar
          module Baz = Integer
        end
      RBS

      buf = factory.env.buffers.find {|buf| File.basename(buf.name) == "a.rbs" } or raise
      dirs, _ = factory.env.signatures[buf]

      completion = Services::TypeNameCompletion.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      assert completion.each_type_name.include?(TypeName("::Foo"))
      assert completion.each_type_name.include?(TypeName("::Foo::Bar"))
      assert completion.each_type_name.include?(TypeName("::Foo::Bar::Baz"))
      assert completion.each_type_name.include?(TypeName("::Bar"))
      assert completion.each_type_name.include?(TypeName("::Bar::Baz"))
    end
  end

  def test_each_type_name_alias_use
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use Foo as FOO, Baz as BAZ

        module Foo
          module Bar = BAZ
        end

        module Baz
          type t = Integer
        end
      RBS

      buf = factory.env.buffers.find {|buf| File.basename(buf.name) == "a.rbs" } or raise
      dirs, _ = factory.env.signatures[buf]

      completion = Services::TypeNameCompletion.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      type_names = completion.each_type_name.to_set

      assert type_names.include?(TypeName("FOO"))
      assert type_names.include?(TypeName("FOO::Bar"))
      assert type_names.include?(TypeName("FOO::Bar::t"))
    end
  end


  def test_relative_name_in_context
    with_factory({ "a.rbs" => <<~RBS}) do |factory|
        class Foo
          interface _Quax
          end

          type baz = String

          module Bar
            type baz = Integer
          end
        end
      RBS

      completion = Services::TypeNameCompletion.new(env: factory.env, context: [nil, TypeName("::Foo")], dirs: [])

      assert_equal [TypeName("::Foo::baz"), TypeName("baz")], completion.resolve_name_in_context(TypeName("::Foo::baz"))
      assert_equal [TypeName("::Foo::Bar::baz"), TypeName("Bar::baz")], completion.resolve_name_in_context(TypeName("::Foo::Bar::baz"))

      assert_equal [TypeName("::Foo::_Quax"), TypeName("_Quax")], completion.resolve_name_in_context(TypeName("::Foo::_Quax"))
    end
  end

  def test_use_type_names
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use Object as Foo, Integer as String
      RBS

      buf = factory.env.buffers.find {|buf| Pathname(buf.name).basename == Pathname("a.rbs") }
      dirs = factory.env.signatures[buf][0]

      completion = Services::TypeNameCompletion.new(env: factory.env, context: nil, dirs: dirs)

      assert_operator completion.each_type_name, :include?, TypeName("Foo")
      assert_operator completion.each_type_name, :include?, TypeName("String")
      assert_operator completion.each_type_name, :include?, TypeName("::String")

      assert_operator completion.find_type_names(nil), :include?, TypeName("Foo")
      assert_operator completion.find_type_names(nil), :include?, TypeName("String")
      assert_operator completion.find_type_names(nil), :include?, TypeName("::String")

      assert_operator completion.find_type_names(Services::TypeNameCompletion::Prefix::RawIdentPrefix.new("Foo")), :include?, TypeName("Foo")

      assert_equal [TypeName("::Object"), TypeName("Foo")], completion.resolve_name_in_context(TypeName("Foo"))
      assert_equal [TypeName("::Integer"), TypeName("String")], completion.resolve_name_in_context(TypeName("String"))
      assert_equal [TypeName("::String"), TypeName("::String")], completion.resolve_name_in_context(TypeName("::String"))
    end
  end

  def test_find_type_names_module_alias
    with_factory({ "a.rbs" => <<~RBS }, nostdlib: true) do |factory|
        class Foo
          module Bar
            type id = Integer
          end
        end

        class Baz = Foo::Bar
      RBS

      completion = Services::TypeNameCompletion.new(env: factory.env, context: nil, dirs: [])

      assert_equal(
        [TypeName("::Baz::id")],
        completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacePrefix.new(RBS::Namespace.parse("Baz::")))
      )

      assert_equal(
        [TypeName("::Baz::id")],
        completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("Baz::"), "i"))
      )
    end
  end
end
