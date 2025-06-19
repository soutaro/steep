require_relative "../test_helper"

class Steep::Server::LSPFormatterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include FactoryHelper

  include Steep
  MethodDecl = TypeInference::MethodCall::MethodDecl

  def type_check(content)
    source = Source.parse(content, path: Pathname("a.rb"), factory: factory)
    builder = Interface::Builder.new(factory, implicitly_returns_nil: true)
    subtyping = Subtyping::Check.new(builder: builder)
    resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
    Services::TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver, cursor: nil)
  end

  def test_ruby_hover_variable
    with_factory do
      content = Services::HoverProvider::VariableContent.new(
        node: nil,
        name: :x,
        type: parse_type("::Array[::Integer]"),
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        **Local variable** `x: ::Array[::Integer]`
      MD
    end
  end

  def test_ruby_hover_method_call__simple_receiver
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest
          # This is comment for `HoverMethodCallTest#foo`.
          def foo: [A] (A) -> Array[A]
                 | () -> void
        end
      RBS

      typing = type_check(<<~RUBY)
        HoverMethodCallTest.new.foo(1)
      RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        ::Array[::Integer]
        ```

        ----
        **Method type**:
        ```rbs
        [A] (A) -> ::Array[A]
        ```
        ----
        ### 📚 HoverMethodCallTest#foo

        This is comment for `HoverMethodCallTest#foo`.

      MD
    end
  end

  def test_ruby_hover_method_call__underscore
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallUnderscoreTest
          # This is comment for `HoverMethodCallTest#__foo__`.
          def __foo__: () -> void
        end
      RBS

      typing = type_check(<<~RUBY)
        HoverMethodCallUnderscoreTest.new.__foo__()
      RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        void
        ```

        ----
        **Method type**:
        ```rbs
        () -> void
        ```
        ----
        ### 📚 HoverMethodCallUnderscoreTest#\\_\\_foo\\_\\_

        This is comment for `HoverMethodCallTest#__foo__`.

      MD
    end
  end

  def test_ruby_hover_method_call__simple_receiver__no_doc
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest
          def foo: [A] (A) -> Array[A]
                 | () -> void
        end
      RBS

      typing = type_check(<<~RUBY)
        HoverMethodCallTest.new.foo(1)
      RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        ::Array[::Integer]
        ```

        ----
        **Method type**:
        ```rbs
        [A] (A) -> ::Array[A]
        ```
      MD
    end
  end

  def test_ruby_hover_method_call__complex_receiver
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest1
          # This is comment for `HoverMethodCallTest1#foo`.
          def foo: () -> Integer
        end

        class HoverMethodCallTest2
          # This is comment for `HoverMethodCallTest2#foo`.
          def foo: () -> String
        end

        class HoverMethodCallTest3
          def foo: () -> Symbol
        end
      RBS

      typing = type_check(<<~RUBY)
        # @type var x: HoverMethodCallTest1 | HoverMethodCallTest2 | HoverMethodCallTest3
        x = (_ = nil)
        x.foo()
      RUBY

      call = typing.call_of(node: typing.source.node.children[1])

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        (::Integer | ::String | ::Symbol)
        ```

        ----
        **Method type**:
        ```rbs
          () -> ::Integer
        | () -> ::String
        | () -> ::Symbol
        ```
        **Possible methods**: `HoverMethodCallTest1#foo`, `HoverMethodCallTest2#foo`, `HoverMethodCallTest3#foo`

        ----
        ### 📚 HoverMethodCallTest1#foo

        This is comment for `HoverMethodCallTest1#foo`.

        ### 📚 HoverMethodCallTest2#foo

        This is comment for `HoverMethodCallTest2#foo`.


        ----
        🔍 One more definition without docs
      MD
    end
  end

  def test_ruby_hover_method_call__special
    with_factory do
      typing = type_check(<<~RUBY)
        [1, nil].compact
      RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        ::Array[::Integer]
        ```

        ----
        **💡 Custom typing rule applies**

        ----
        **Method type**:
        ```rbs
        () -> ::Array[::Integer]
        ```
        ----
        ### 📚 Array#compact

        Returns a new array containing only the non-`nil` elements from `self`;
        element order is preserved:

            a = [nil, 0, nil, false, nil, '', nil, [], nil, {}]
            a.compact # => [0, false, \"\", [], {}]

        Related: Array#compact!; see also [Methods for
        Deleting](rdoc-ref:Array@Methods+for+Deleting).

      MD
    end
  end


  def test_ruby_hover_method_call__error
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest
          # This is comment for `HoverMethodCallTest#foo`.
          def foo: () -> Integer
        end
      RBS

      typing = type_check(<<~RUBY)
        HoverMethodCallTest.new.foo(3)
      RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD.chomp, comment
        **🚨 No compatible method type found**

        ----
        **Method type**:
        ```rbs
        () -> ::Integer
        ```
        ----
        ### 📚 HoverMethodCallTest#foo

        This is comment for `HoverMethodCallTest#foo`.


      MD
    end
  end

  def test_ruby_hover_method_def
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest
          # This is comment for `HoverMethodCallTest#foo`.
          def foo: () -> Integer
        end
      RBS

      content = Services::HoverProvider::DefinitionContent.new(
        node: nil,
        method_name: MethodName("::HoverMethodCallTest#foo"),
        method_type: parse_method_type("(::String | nil) -> (::Integer | ::String)"),
        definition: factory.definition_builder.build_instance(RBS::TypeName.parse("::HoverMethodCallTest")).methods[:foo],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        def foo: () -> ::Integer
        ```

        ----
        ### 📚 HoverMethodCallTest#foo

        This is comment for `HoverMethodCallTest#foo`.

      MD
    end
  end

  def test_ruby_hover_method_def__overloads
    with_factory({ "foo.rbs" => <<~RBS }) do
        class HoverMethodCallTest
          # This is comment for `HoverMethodCallTest#foo`.
          def self.foo: () -> Integer
                      | (Integer) -> String

          # This is another comment for `HoverMethodCallTest#foo`.
          def self.foo: (String) -> String
                      | ...

          def self.foo: (Symbol) -> Symbol
                      | ...
        end
      RBS

      content = Services::HoverProvider::DefinitionContent.new(
        node: nil,
        method_name: MethodName("::HoverMethodCallTest.foo"),
        method_type: parse_method_type("(::Symbol | ::String | ::Integer | nil) -> (::Integer | ::String | ::Symbol)"),
        definition: factory.definition_builder.build_singleton(RBS::TypeName.parse("::HoverMethodCallTest")).methods[:foo],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        def self.foo: (::Symbol) -> ::Symbol
                    | (::String) -> ::String
                    | () -> ::Integer
                    | (::Integer) -> ::String
        ```

        ----
        **Internal method type**
        ```rbs
        ((::Symbol | ::String | ::Integer | nil)) -> (::Integer | ::String | ::Symbol)
        ```

        ----
        ### 📚 HoverMethodCallTest.foo

        This is another comment for `HoverMethodCallTest#foo`.

        ### 📚 HoverMethodCallTest.foo

        This is comment for `HoverMethodCallTest#foo`.

      MD
    end
  end

  def test_ruby_hover_constant_class__single_definition
    with_factory({ "foo.rbs" => <<RBS }) do
# ClassHover is a class to do something with String.
#
class ClassHover[A < String] < BasicObject
end
RBS
      content = Services::HoverProvider::ConstantContent.new(
        full_name: RBS::TypeName.parse("::ClassHover"),
        type: parse_type("singleton(::ClassHover)"),
        decl: factory.env.class_decls[RBS::TypeName.parse("::ClassHover")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        class ClassHover[A < ::String] < ::BasicObject
        ```
        ----
        ### 📚 ClassHover

        ClassHover is a class to do something with String.

      MD
    end
  end

  def test_ruby_hover_constant_class__single_definition_no_doc
    with_factory({ "foo.rbs" => <<~RBS }) do
        class ClassHover[A < String] < BasicObject
        end
      RBS
      content = Services::HoverProvider::ConstantContent.new(
        full_name: RBS::TypeName.parse("::ClassHover"),
        type: parse_type("singleton(::ClassHover)"),
        decl: factory.env.class_decls[RBS::TypeName.parse("::ClassHover")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        class ClassHover[A < ::String] < ::BasicObject
        ```
      MD
    end
  end


  def test_ruby_hover_constant_class__multiple_definitions
    with_factory({ "foo.rbs" => <<~RBS }) do
        # ClassHover is a class to do something with String.
        #
        class ClassHover
        end

        # ClassHover is another doc.
        class ClassHover
        end

        class ClassHover
        end
      RBS

      content = Services::HoverProvider::ConstantContent.new(
        full_name: RBS::TypeName.parse("::ClassHover"),
        type: parse_type("singleton(::ClassHover)"),
        decl: factory.env.class_decls[RBS::TypeName.parse("::ClassHover")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        class ClassHover
        ```
        ----
        ### 📚 ClassHover

        ClassHover is a class to do something with String.

        ### 📚 ClassHover

        ClassHover is another doc.

      MD
    end
  end

  def test_rbs_hover_class__single
    with_factory({ "foo.rbs" => <<~RBS }) do
        # This is a class!
        #
        class HelloWorld[T] < Numeric
        end
      RBS

      Services::HoverProvider::ClassTypeContent.new(
        decl: factory.env.class_decls[RBS::TypeName.parse("::HelloWorld")].primary_decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<~MD, comment
          ```rbs
          class HelloWorld[T] < ::Numeric
          ```
          ----
          ### 📚 HelloWorld

          This is a class!

        MD
      end
    end
  end

  def test_rbs_hover_class__no_doc
    with_factory({ "foo.rbs" => <<~RBS }) do
        class ClassHover
        end
      RBS

      content = Services::HoverProvider::ClassTypeContent.new(
        decl: factory.env.class_decls[RBS::TypeName.parse("::ClassHover")].primary_decl,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        class ClassHover
        ```
      MD
    end
  end


  def test_ruby_hover_constant_const
    with_factory({ "foo.rbs" => <<~RBS }) do
        # The version of ClassHover
        #
        ClassHover::VERSION: String

        class ClassHover
        end
      RBS

      content = Services::HoverProvider::ConstantContent.new(
        full_name: RBS::TypeName.parse("::ClassHover::VERSION"),
        type: parse_type("::String"),
        decl: factory.env.constant_decls[RBS::TypeName.parse("::ClassHover::VERSION")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        ClassHover::VERSION: ::String
        ```
        ----
        ### 📚 ClassHover::VERSION

        The version of ClassHover

      MD
    end
  end

  def test_ruby_hover_type
    with_factory() do
      content = Services::HoverProvider::TypeContent.new(
        node: nil,
        type: parse_type("[::String, ::Integer]"),
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        [::String, ::Integer]
        ```
      MD
    end
  end

  def test_ruby_hover_assertion
    with_factory() do
      content = Services::HoverProvider::TypeAssertionContent.new(
        node: nil,
        original_type: parse_type("nil"),
        asserted_type: parse_type("::String?"),
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<~MD, comment
        ```rbs
        (::String | nil)
        ```

        ↑ Converted from `nil`
      MD
    end
  end

  def test_rbs_hover_type_alias
    with_factory({ "foo.rbs" => <<~RBS }) do
        type foo[T, S < Numeric] = [T, S]

        # Hello World
        type bar = 123
      RBS

      Services::HoverProvider::TypeAliasContent.new(
        decl: factory.env.type_alias_decls[RBS::TypeName.parse("::foo")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<~MD, comment
          ```rbs
          type foo[T, S < ::Numeric] = [ T, S ]
          ```
        MD
      end

      Services::HoverProvider::TypeAliasContent.new(
        decl: factory.env.type_alias_decls[RBS::TypeName.parse("::bar")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<~MD, comment
          ```rbs
          type bar = 123
          ```

          ----
          ### 📚 bar

          Hello World
        MD
      end
    end
  end

  def test_rbs_hover_interface
    with_factory({ "foo.rbs" => <<~RBS }) do
        # This is an interface!
        #
        interface _HelloWorld[T]
        end

        interface _HelloWorld2
        end
      RBS

      Services::HoverProvider::InterfaceTypeContent.new(
        decl: factory.env.interface_decls[RBS::TypeName.parse("::_HelloWorld")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<~MD, comment
        ```rbs
        interface _HelloWorld[T]
        ```

        ----
        ### 📚 \\_HelloWorld

        This is an interface!
        MD
      end

      Services::HoverProvider::InterfaceTypeContent.new(
        decl: factory.env.interface_decls[RBS::TypeName.parse("::_HelloWorld2")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<~MD, comment
        ```rbs
        interface _HelloWorld2
        ```
        MD
      end
    end
  end

  def test_ruby_completion__local_variable
    with_factory() do
      Services::CompletionProvider::LocalVariableItem.new(
        identifier: :foo,
        range: nil,
        type: parse_type("::String | ::Symbol")
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          **Local variable** `foo: (::String | ::Symbol)`
        MD
      end
    end
  end

  def test_ruby_completion__instance_variable
    with_factory() do
      Services::CompletionProvider::InstanceVariableItem.new(
        identifier: :@foo,
        range: nil,
        type: parse_type("::String | ::Symbol")
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          **Instance variable** `@foo: (::String | ::Symbol)`
        MD
      end
    end
  end

  def test_ruby_completion__constant___constant__no_doc
    with_factory({ "foo.rbs" => <<~RBS}) do
      Foo: String | Symbol
      RBS

      Services::CompletionProvider::ConstantItem.new(
        env: factory.env,
        identifier: :Foo,
        range: nil,
        type: parse_type("::String | ::Symbol"),
        full_name: RBS::TypeName.parse("::Foo")
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
        ```rbs
        Foo: ::String | ::Symbol
        ```
        MD
      end
    end
  end

  def test_ruby_completion__constant___constant__doc
    with_factory({ "foo.rbs" => <<~RBS}) do
      # Foo is something
      Foo: String | Symbol
      RBS

      Services::CompletionProvider::ConstantItem.new(
        env: factory.env,
        identifier: :Foo,
        range: nil,
        type: parse_type("::String | ::Symbol"),
        full_name: RBS::TypeName.parse("::Foo")
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
        ```rbs
        Foo: ::String | ::Symbol
        ```
        ----
        ### 📚 Foo

        Foo is something

        MD
      end
    end
  end

  def test_ruby_completion__constant___class__multiple_decls
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
      end

      # Foo is something
      class Foo
      end
      RBS

      Services::CompletionProvider::ConstantItem.new(
        env: factory.env,
        identifier: :Foo,
        range: nil,
        type: parse_type("singleton(::Foo)"),
        full_name: RBS::TypeName.parse("::Foo")
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          ```rbs
          class Foo
          ```
          ----
          ### 📚 Foo

          Foo is something


          ----
          🔍 One more definition without docs
        MD
      end
    end
  end

  def test_ruby_completion__method___simple__no_docs
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
        def foo: () -> void
      end
      RBS

      definition = factory.definition_builder.build_instance(RBS::TypeName.parse("::Foo"))
      method = definition.methods[:foo]

      Services::CompletionProvider::SimpleMethodNameItem.new(
        identifier: :foo,
        range: nil,
        receiver_type: parse_type("::Foo"),
        method_name: MethodName("::Foo#foo"),
        method_types: method.method_types,
        method_member: method.members[0]
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          **Method type**:
          ```rbs
          () -> void
          ```
        MD
      end
    end
  end

  def test_ruby_completion__method___simple__with_docs
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
        # Foo#foo doc
        def foo: () -> void
               | (String) -> void
      end
      RBS

      definition = factory.definition_builder.build_instance(RBS::TypeName.parse("::Foo"))
      method = definition.methods[:foo]

      Services::CompletionProvider::SimpleMethodNameItem.new(
        identifier: :foo,
        range: nil,
        receiver_type: parse_type("::Foo"),
        method_name: MethodName("::Foo#foo"),
        method_types: method.method_types,
        method_member: method.members[0]
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          **Method type**:
          ```rbs
            () -> void
          | (::String) -> void
          ```
          ----
          ### 📚 Foo#foo

          Foo#foo doc

        MD
      end
    end
  end

  def test_ruby_completion__method___complex
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
        # Foo#foo doc
        def foo: () -> void
      end

      class Bar
        # Bar#foo doc
        def foo: () -> void
      end

      class Baz
        def foo: () -> void
      end
      RBS

      method_decls = []

      factory.definition_builder.build_instance(RBS::TypeName.parse("::Foo")).methods[:foo].defs.each do |defn|
        method_decls << MethodDecl.new(
          method_name: MethodName("::Foo#foo"),
          method_def: defn
        )
      end

      factory.definition_builder.build_instance(RBS::TypeName.parse("::Bar")).methods[:foo].defs.each do |defn|
        method_decls << MethodDecl.new(
          method_name: MethodName("::Bar#foo"),
          method_def: defn
        )
      end

      factory.definition_builder.build_instance(RBS::TypeName.parse("::Baz")).methods[:foo].defs.each do |defn|
        method_decls << MethodDecl.new(
          method_name: MethodName("::Baz#foo"),
          method_def: defn
        )
      end

      Services::CompletionProvider::ComplexMethodNameItem.new(
        identifier: :foo,
        range: nil,
        receiver_type: parse_type("::Foo | ::Bar | ::Baz"),
        method_types: [RBS::Parser.parse_method_type("() -> void"), RBS::Parser.parse_method_type("() -> void"), RBS::Parser.parse_method_type("() -> void")],
        method_decls: method_decls
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
          **Method type**:
          ```rbs
            () -> void
          | () -> void
          | () -> void
          ```
          **Possible methods**: `Foo#foo`, `Bar#foo`, `Baz#foo`

          ----
          ### 📚 Foo#foo

          Foo#foo doc

          ### 📚 Bar#foo

          Bar#foo doc


          ----
          🔍 One more definition without docs
        MD
      end
    end
  end

  def test_ruby_completion__method___generated
    with_factory() do
      Services::CompletionProvider::GeneratedMethodNameItem.new(
        identifier: :first,
        range: nil,
        receiver_type: parse_type("[::String]"),
        method_types: [RBS::Parser.parse_method_type("() -> ::String?")],
      ).tap do |item|
        comment = Server::LSPFormatter.format_completion_docs(item)
        assert_equal <<~MD, comment
        **Method type**:
        ```rbs
        () -> ::String?
        ```
        🤖 Generated method for receiver type
        MD
      end
    end
  end

  def test_rbs_completion
    with_factory({ "foo.rbs" => <<~RBS }) do
        # RBSCompletionTest of T
        class RBSCompletionTest[T]
        end
      RBS

      decl = factory.env.class_decls[RBS::TypeName.parse("::RBSCompletionTest")].primary_decl

      comment = Server::LSPFormatter.format_rbs_completion_docs(RBS::TypeName.parse("::RBSCompletionTest"), decl, [decl.comment])

      assert_equal <<~MD, comment
        ```rbs
        class RBSCompletionTest[T]
        ```

        ----
        ### 📚 RBSCompletionTest

        RBSCompletionTest of T

      MD
    end
  end
end
