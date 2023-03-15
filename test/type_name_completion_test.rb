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

      completion = Services::TypeNameCompletion.new(env: factory.env, context: nil)

      # Returns all accessible type names from the context
      assert_equal [TypeName("::Foo")], completion.find_type_names(nil)

      # Returns all type names that contains the identifier case-insensitively
      assert_equal [TypeName("::Foo::Bar"), TypeName("::Foo::Bar::baz"), TypeName("::Foo::Bar::_Quax")], completion.find_type_names(Services::TypeNameCompletion::Prefix::RawIdentPrefix.new("ba"))

      # Returns all type names that shares the prefix and contains the identifier case-insensitively
      assert_equal [TypeName("::Foo::Bar::baz")], completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacedIdentPrefix.new(RBS::Namespace.parse("::Foo::Bar::"), "ba"))

      # Returns all type names that shares the prefix
      assert_equal [TypeName("::Foo::Bar::baz"), TypeName("::Foo::Bar::_Quax")], completion.find_type_names(Services::TypeNameCompletion::Prefix::NamespacePrefix.new(RBS::Namespace.parse("::Foo::Bar::")))
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

      completion = Services::TypeNameCompletion.new(env: factory.env, context: [nil, TypeName("::Foo")])

      assert_equal TypeName("baz"), completion.relative_name_in_context(TypeName("::Foo::baz"))
      assert_equal TypeName("Bar::baz"), completion.relative_name_in_context(TypeName("::Foo::Bar::baz"))

      assert_equal TypeName("_Quax"), completion.relative_name_in_context(TypeName("::Foo::_Quax"))
    end
  end
end
