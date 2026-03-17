require_relative "../test_helper"

class CompletinoProvider__TypeNameTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  include Steep

  def buffer(string)
    RBS::Buffer.new(name: Pathname("a.rb"), content: string)
  end

  def test_prefix_parse
    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> "), line: 1, column: 5).tap do |prefix|
      assert_nil prefix
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> St"), line: 1, column: 8).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix, prefix
      assert_equal "St", prefix.ident
      assert_predicate prefix, :const_name?
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> booli"), line: 1, column: 11).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix, prefix
      assert_equal "booli", prefix.ident
      refute_predicate prefix, :const_name?
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> ::RBS::"), line: 1, column: 13).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::NamespacePrefix, prefix
      assert_equal RBS::Namespace.parse("::RBS::"), prefix.namespace
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> ::"), line: 1, column: 8).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::NamespacePrefix, prefix
      assert_equal RBS::Namespace.parse("::"), prefix.namespace
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> ::RBS::Na"), line: 1, column: 15).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::NamespacedIdentPrefix, prefix
      assert_equal RBS::Namespace.parse("::RBS::"), prefix.namespace
      assert_equal "Na", prefix.ident
      assert_predicate prefix, :const_name?
    end

    Services::CompletionProvider::TypeName::Prefix.parse(buffer("() -> ::RBS"), line: 1, column: 11).tap do |prefix|
      assert_instance_of Services::CompletionProvider::TypeName::Prefix::NamespacedIdentPrefix, prefix
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

      completion = Services::CompletionProvider::TypeName.new(env: factory.env, context: nil, dirs: [])

      # Returns all accessible type names from the context
      assert_equal [RBS::TypeName.parse("::Foo")], completion.find_type_names(nil)

      # Returns all type names that contains the identifier case-insensitively
      assert_equal [RBS::TypeName.parse("::Foo::Bar"), RBS::TypeName.parse("::Foo::Bar::baz"), RBS::TypeName.parse("::Foo::Bar::_Quax")], completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix.new("ba"))

      # Returns all type names that shares the prefix and contains the identifier case-insensitively
      assert_equal [RBS::TypeName.parse("::Foo::Bar::baz")], completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("::Foo::Bar::"), "ba"))

      assert_equal [RBS::TypeName.parse("::Foo")], completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("::"), "Fo"))

      # Returns all type names that shares the prefix
      assert_equal [RBS::TypeName.parse("::Foo::Bar::baz"), RBS::TypeName.parse("::Foo::Bar::_Quax")], completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacePrefix.new(RBS::Namespace.parse("::Foo::Bar::")))
    end
  end

  def test_each_type_name_used
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use NoSuchClass, Object as ExistingClass
      RBS

      source = factory.env.each_rbs_source.find {|src| src.buffer.name.basename == Pathname("a.rbs") } or raise
      dirs = source.directives

      completion = Services::CompletionProvider::TypeName.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      refute completion.each_type_name.include?(RBS::TypeName.parse("NoSuchClass"))
      assert completion.each_type_name.include?(RBS::TypeName.parse("ExistingClass"))
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

      source = factory.env.each_rbs_source.find {|src| src.buffer.name.basename == Pathname("a.rbs") } or raise
      dirs = source.directives

      completion = Services::CompletionProvider::TypeName.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      assert completion.each_type_name.include?(RBS::TypeName.parse("::Foo"))
      assert completion.each_type_name.include?(RBS::TypeName.parse("::Foo::Bar"))
      assert completion.each_type_name.include?(RBS::TypeName.parse("::Foo::Bar::Baz"))
      assert completion.each_type_name.include?(RBS::TypeName.parse("::Bar"))
      assert completion.each_type_name.include?(RBS::TypeName.parse("::Bar::Baz"))
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

      source = factory.env.each_rbs_source.find {|src| src.buffer.name.basename == Pathname("a.rbs") } or raise
      dirs = source.directives

      completion = Services::CompletionProvider::TypeName.new(
        env: factory.env,
        context: nil,
        dirs: dirs
      )

      type_names = completion.each_type_name.to_set

      assert type_names.include?(RBS::TypeName.parse("FOO"))
      assert type_names.include?(RBS::TypeName.parse("FOO::Bar"))
      assert type_names.include?(RBS::TypeName.parse("FOO::Bar::t"))
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

      completion = Services::CompletionProvider::TypeName.new(env: factory.env, context: [nil, RBS::TypeName.parse("::Foo")], dirs: [])

      assert_equal [RBS::TypeName.parse("::Foo::baz"), RBS::TypeName.parse("baz")], completion.resolve_name_in_context(RBS::TypeName.parse("::Foo::baz"))
      assert_equal [RBS::TypeName.parse("::Foo::Bar::baz"), RBS::TypeName.parse("Bar::baz")], completion.resolve_name_in_context(RBS::TypeName.parse("::Foo::Bar::baz"))

      assert_equal [RBS::TypeName.parse("::Foo::_Quax"), RBS::TypeName.parse("_Quax")], completion.resolve_name_in_context(RBS::TypeName.parse("::Foo::_Quax"))
    end
  end

  def test_use_type_names
    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use Object as Foo, Integer as String, LongName as Long

        module LongName
          type hello = Integer
        end
      RBS

      source = factory.env.each_rbs_source.find {|src| src.buffer.name.basename == Pathname("a.rbs") } or raise
      dirs = source.directives

      completion = Services::CompletionProvider::TypeName.new(env: factory.env, context: nil, dirs: dirs)

      assert_operator completion.each_type_name, :include?, RBS::TypeName.parse("Foo")
      assert_operator completion.each_type_name, :include?, RBS::TypeName.parse("String")
      assert_operator completion.each_type_name, :include?, RBS::TypeName.parse("::String")

      assert_operator completion.find_type_names(nil), :include?, RBS::TypeName.parse("Foo")
      assert_operator completion.find_type_names(nil), :include?, RBS::TypeName.parse("String")
      assert_operator completion.find_type_names(nil), :include?, RBS::TypeName.parse("::String")

      assert_operator completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix.new("Foo")), :include?, RBS::TypeName.parse("Foo")
      assert_operator(
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacePrefix.new(RBS::Namespace.parse("Long::"), 6)),
        :include?,
        RBS::TypeName.parse("Long::hello")
      )

      assert_equal [RBS::TypeName.parse("::Object"), RBS::TypeName.parse("Foo")], completion.resolve_name_in_context(RBS::TypeName.parse("Foo"))
      assert_equal [RBS::TypeName.parse("::Integer"), RBS::TypeName.parse("String")], completion.resolve_name_in_context(RBS::TypeName.parse("String"))
      assert_equal [RBS::TypeName.parse("::String"), RBS::TypeName.parse("::String")], completion.resolve_name_in_context(RBS::TypeName.parse("::String"))
      assert_equal [RBS::TypeName.parse("::LongName::hello"), RBS::TypeName.parse("Long::hello")], completion.resolve_name_in_context(RBS::TypeName.parse("Long::hello"))
    end
  end

  def test_find_type_names_module_alias
    skip "Type name resolution for module/class aliases is changed in RBS 3.10/4.0"
    
    with_factory({ "a.rbs" => <<~RBS }, nostdlib: true) do |factory|
        class Foo
          module Bar
            type id = Integer
          end
        end

        class Baz = Foo::Bar
      RBS

      completion = Services::CompletionProvider::TypeName.new(env: factory.env, context: nil, dirs: [])

      assert_equal(
        [RBS::TypeName.parse("::Baz::id")],
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacePrefix.new(RBS::Namespace.parse("Baz::")))
      )

      assert_equal(
        [RBS::TypeName.parse("::Baz::id")],
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("Baz::"), "i"))
      )
    end
  end

  def test_use_type_names_nested
    skip "Type name resolution for module/class aliases is changed in RBS 3.10/4.0"

    with_factory({ "a.rbs" => <<~RBS }) do |factory|
        use Foo::Bar

        module Foo
          module Bar
            module Baz
            end
          end
        end

        module Bar = Foo::Bar
      RBS

      source = factory.env.each_rbs_source.find {|src| src.buffer.name.basename == Pathname("a.rbs") } or raise
      dirs = source.directives

      completion = Services::CompletionProvider::TypeName.new(env: factory.env, context: [[nil, RBS::TypeName.parse("::Foo")], RBS::TypeName.parse("::Foo::Bar")], dirs: dirs)

      assert_operator(
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix.new("Baz")),
        :include?,
        RBS::TypeName.parse("Bar::Baz")
      )
      assert_operator(
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix.new("Baz")),
        :include?,
        RBS::TypeName.parse("::Bar::Baz")
      )
      assert_operator(
        completion.find_type_names(Services::CompletionProvider::TypeName::Prefix::RawIdentPrefix.new("Baz")),
        :include?,
        RBS::TypeName.parse("::Foo::Bar::Baz")
      )

      assert_equal(
        [RBS::TypeName.parse("::Foo::Bar::Baz"), RBS::TypeName.parse("Baz")],
        completion.resolve_name_in_context(RBS::TypeName.parse("::Foo::Bar::Baz"))
      )
      assert_equal(
        [RBS::TypeName.parse("::Foo::Bar::Baz"), RBS::TypeName.parse("::Bar::Baz")],
        completion.resolve_name_in_context(RBS::TypeName.parse("::Bar::Baz"))
      )
      assert_equal(
        [RBS::TypeName.parse("::Foo::Bar::Baz"), RBS::TypeName.parse("Bar::Baz")],
        completion.resolve_name_in_context(RBS::TypeName.parse("Bar::Baz"))
      )
    end
  end
end
