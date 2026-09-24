require_relative "../test_helper"

class Steep::Server::LSPFormatterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include FactoryHelper

  include Steep

  LSP = LanguageServer::Protocol
  LSPFormatter = Server::LSPFormatter
  ContentChange = Services::ContentChange

  def dirs
    @dirs ||= []
  end

  # @rbs (::Steep::Server::CustomMethods::Hover::content) -> String
  def format_hover(content)
    LSPFormatter.format_hover_content(content, env: factory.env, builder: factory.definition_builder)
  end

  # @rbs (::Steep::Server::CustomMethods::Completion::item) -> String?
  def format_completion(item)
    LSPFormatter.format_completion_docs(item, env: factory.env, builder: factory.definition_builder)
  end

  def range
    { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } }
  end

  def test_ruby_hover_variable
    with_factory do
      comment = format_hover({ kind: "variable", name: "x", type: "::Array[::Integer]" })
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

      comment = format_hover(
        {
          kind: "method_call",
          return_type: "::Array[::Integer]",
          special: false,
          error: false,
          method_types: ["[A] (A) -> ::Array[A]"],
          methods: ["::HoverMethodCallTest#foo"]
        }
      )
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

      comment = format_hover(
        {
          kind: "method_call",
          return_type: "void",
          special: false,
          error: false,
          method_types: ["() -> void"],
          methods: ["::HoverMethodCallUnderscoreTest#__foo__"]
        }
      )
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

      comment = format_hover(
        {
          kind: "method_call",
          return_type: "::Array[::Integer]",
          special: false,
          error: false,
          method_types: ["[A] (A) -> ::Array[A]"],
          methods: ["::HoverMethodCallTest#foo"]
        }
      )
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

      comment = format_hover(
        {
          kind: "method_call",
          return_type: "(::Integer | ::String | ::Symbol)",
          special: false,
          error: false,
          method_types: ["() -> ::Integer", "() -> ::String", "() -> ::Symbol"],
          methods: ["::HoverMethodCallTest1#foo", "::HoverMethodCallTest2#foo", "::HoverMethodCallTest3#foo"]
        }
      )
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
      # The documentation of `Array#compact` comes from the core RBS of the environment
      comment = format_hover(
        {
          kind: "method_call",
          return_type: "::Array[::Integer]",
          special: true,
          error: false,
          method_types: ["() -> ::Array[::Integer]"],
          methods: ["::Array#compact"]
        }
      )
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

      comment = format_hover(
        {
          kind: "method_call",
          return_type: nil,
          special: false,
          error: true,
          method_types: ["() -> ::Integer"],
          methods: ["::HoverMethodCallTest#foo"]
        }
      )
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

  def test_ruby_hover_method_call__unknown_method
    with_factory do
      # A method the environment does not know has no documentation
      comment = format_hover(
        {
          kind: "method_call",
          return_type: "void",
          special: false,
          error: false,
          method_types: ["() -> void"],
          methods: ["::NoSuchClass#foo"]
        }
      )
      assert_equal <<~MD, comment
        ```rbs
        void
        ```

        ----
        **Method type**:
        ```rbs
        () -> void
        ```
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

      comment = format_hover(
        {
          kind: "definition",
          method: "::HoverMethodCallTest#foo",
          method_type: "(::String | nil) -> (::Integer | ::String)",
          method_types: ["() -> ::Integer"]
        }
      )
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

      definition = factory.definition_builder.build_singleton(RBS::TypeName.parse("::HoverMethodCallTest")).methods[:foo]

      comment = format_hover(
        {
          kind: "definition",
          method: "::HoverMethodCallTest.foo",
          method_type: "((::Symbol | ::String | ::Integer | nil)) -> (::Integer | ::String | ::Symbol)",
          method_types: definition.method_types.map(&:to_s)
        }
      )
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
      comment = format_hover({ kind: "constant", name: "::ClassHover" })
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

      comment = format_hover({ kind: "constant", name: "::ClassHover" })
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

      comment = format_hover({ kind: "constant", name: "::ClassHover" })
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

      comment = format_hover({ kind: "type_name", name: "::HelloWorld" })
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

  def test_rbs_hover_class__no_doc
    with_factory({ "foo.rbs" => <<~RBS }) do
        class ClassHover
        end
      RBS

      comment = format_hover({ kind: "type_name", name: "::ClassHover" })
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

      comment = format_hover({ kind: "constant", name: "::ClassHover::VERSION" })
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

  def test_ruby_hover_constant__unknown
    with_factory do
      # A constant the environment does not know is rendered by its name
      comment = format_hover({ kind: "constant", name: "::NoSuchConstant" })
      assert_equal <<~MD, comment
        ```rbs
        NoSuchConstant
        ```
      MD
    end
  end

  def test_ruby_hover_type
    with_factory() do
      comment = format_hover({ kind: "type", type: "[::String, ::Integer]" })
      assert_equal <<~MD, comment
        ```rbs
        [::String, ::Integer]
        ```
      MD
    end
  end

  def test_ruby_hover_assertion
    with_factory() do
      comment = format_hover({ kind: "type_assertion", original_type: "nil", asserted_type: "(::String | nil)" })
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

      comment = format_hover({ kind: "type_name", name: "::foo" })
      assert_equal <<~MD, comment
        ```rbs
        type foo[T, S < ::Numeric] = [ T, S ]
        ```
      MD

      comment = format_hover({ kind: "type_name", name: "::bar" })
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

  def test_rbs_hover_interface
    with_factory({ "foo.rbs" => <<~RBS }) do
        # This is an interface!
        #
        interface _HelloWorld[T]
        end

        interface _HelloWorld2
        end
      RBS

      comment = format_hover({ kind: "type_name", name: "::_HelloWorld" })
      assert_equal <<~MD, comment
        ```rbs
        interface _HelloWorld[T]
        ```

        ----
        ### 📚 \\_HelloWorld

        This is an interface!
      MD

      comment = format_hover({ kind: "type_name", name: "::_HelloWorld2" })
      assert_equal <<~MD, comment
        ```rbs
        interface _HelloWorld2
        ```
      MD
    end
  end

  def test_ruby_completion__local_variable
    with_factory() do
      comment = format_completion({ kind: "local_variable", range: range, name: "foo", type: "(::String | ::Symbol)" })
      assert_equal <<~MD, comment
        **Local variable** `foo: (::String | ::Symbol)`
      MD
    end
  end

  def test_ruby_completion__instance_variable
    with_factory() do
      comment = format_completion({ kind: "instance_variable", range: range, name: "@foo", type: "(::String | ::Symbol)" })
      assert_equal <<~MD, comment
        **Instance variable** `@foo: (::String | ::Symbol)`
      MD
    end
  end

  def test_ruby_completion__constant___constant__no_doc
    with_factory({ "foo.rbs" => <<~RBS}) do
      Foo: String | Symbol
      RBS

      comment = format_completion({ kind: "constant", range: range, name: "Foo", full_name: "::Foo" })
      assert_equal <<~MD, comment
        ```rbs
        Foo: ::String | ::Symbol
        ```
      MD
    end
  end

  def test_ruby_completion__constant___constant__doc
    with_factory({ "foo.rbs" => <<~RBS}) do
      # Foo is something
      Foo: String | Symbol
      RBS

      comment = format_completion({ kind: "constant", range: range, name: "Foo", full_name: "::Foo" })
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

  def test_ruby_completion__constant___class__multiple_decls
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
      end

      # Foo is something
      class Foo
      end
      RBS

      comment = format_completion({ kind: "constant", range: range, name: "Foo", full_name: "::Foo" })
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

  def test_ruby_completion__method___simple__no_docs
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
        def foo: () -> void
      end
      RBS

      comment = format_completion({ kind: "method", range: range, name: "foo", method_types: ["() -> void"], methods: ["::Foo#foo"] })
      assert_equal <<~MD, comment
        **Method type**:
        ```rbs
        () -> void
        ```
      MD
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

      comment = format_completion(
        { kind: "method", range: range, name: "foo", method_types: ["() -> void", "(::String) -> void"], methods: ["::Foo#foo"] }
      )
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

      comment = format_completion(
        {
          kind: "method",
          range: range,
          name: "foo",
          method_types: ["() -> void", "() -> void", "() -> void"],
          methods: ["::Foo#foo", "::Bar#foo", "::Baz#foo"]
        }
      )
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

  def test_ruby_completion__method___generated
    with_factory() do
      comment = format_completion({ kind: "method", range: range, name: "first", method_types: ["() -> ::String?"], methods: [] })
      assert_equal <<~MD, comment
        **Method type**:
        ```rbs
        () -> ::String?
        ```
        🤖 Generated method for receiver type
      MD
    end
  end

  def test_ruby_completion__method___singleton_new
    with_factory({ "foo.rbs" => <<~RBS}) do
      class Foo
        # Foo#initialize doc
        def initialize: (String) -> void
      end
      RBS

      # `Foo.new` comes from `initialize`, which is not defined in the singleton
      comment = format_completion({ kind: "method", range: range, name: "new", method_types: ["(::String) -> ::Foo"], methods: ["::Foo.new"] })
      assert_equal <<~MD, comment
        **Method type**:
        ```rbs
        (::String) -> ::Foo
        ```
        ----
        ### 📚 Foo.new

        Foo#initialize doc

      MD
    end
  end

  def test_rbs_completion
    with_factory({ "foo.rbs" => <<~RBS }) do
        # RBSCompletionTest of T
        class RBSCompletionTest[T]
        end
      RBS

      comment = format_completion({ kind: "type_name", range: range, name: "RBSCompletionTest", full_name: "::RBSCompletionTest" })
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

  def test_completion_item__type_name
    with_factory({ "foo.rbs" => <<~RBS }) do
        %a{deprecated}
        class Deprecated
        end

        interface _Fooable
        end

        type foo = Integer
      RBS

      env = factory.env
      builder = factory.definition_builder

      LSPFormatter.completion_item({ kind: "type_name", range: range, name: "Deprecated", full_name: "::Deprecated" }, env: env, builder: builder).tap do |item|
        assert_equal "Deprecated", item.label
        assert_equal LSP::Constant::CompletionItemKind::CLASS, item.kind
        assert_equal "class Deprecated", item.label_details.description
        assert_equal [LSP::Constant::CompletionItemTag::DEPRECATED], item.tags
        assert_equal "Deprecated", item.text_edit.new_text
      end

      LSPFormatter.completion_item({ kind: "type_name", range: range, name: "_Fooable", full_name: "::_Fooable" }, env: env, builder: builder).tap do |item|
        assert_equal LSP::Constant::CompletionItemKind::INTERFACE, item.kind
        assert_empty item.tags
      end

      LSPFormatter.completion_item({ kind: "type_name", range: range, name: "foo", full_name: "::foo" }, env: env, builder: builder).tap do |item|
        assert_equal LSP::Constant::CompletionItemKind::FIELD, item.kind
        assert_equal "type foo = ::Integer", item.label_details.description
      end
    end
  end

  def test_completion_item__method
    with_factory({ "foo.rbs" => <<~RBS }) do
        class Foo
          %a{deprecated}
          def foo: () -> void

          def bar: () -> void
        end
      RBS

      env = factory.env
      builder = factory.definition_builder

      LSPFormatter.completion_item({ kind: "method", range: range, name: "foo", method_types: ["() -> void"], methods: ["::Foo#foo"] }, env: env, builder: builder).tap do |item|
        assert_equal "foo", item.label
        assert_equal LSP::Constant::CompletionItemKind::FUNCTION, item.kind
        assert_equal "Foo#foo", item.label_details.description
        assert_equal [LSP::Constant::CompletionItemTag::DEPRECATED], item.tags
        assert_equal "foo", item.insert_text
      end

      LSPFormatter.completion_item({ kind: "method", range: range, name: "bar", method_types: ["() -> void"], methods: ["::Foo#bar", "::Foo#bar"] }, env: env, builder: builder).tap do |item|
        assert_equal "Foo#bar", item.label_details.description
        assert_empty item.tags
      end

      LSPFormatter.completion_item({ kind: "method", range: range, name: "first", method_types: ["() -> ::String?"], methods: [] }, env: env, builder: builder).tap do |item|
        assert_equal "(Generated)", item.label_details.description
      end
    end
  end

  def test_completion_item__others
    with_factory do
      env = factory.env
      builder = factory.definition_builder

      LSPFormatter.completion_item({ kind: "builtin_type", range: range, name: "untyped" }, env: env, builder: builder).tap do |item|
        assert_equal "untyped", item.label
        assert_equal "(builtin type)", item.detail
        assert_equal LSP::Constant::CompletionItemKind::KEYWORD, item.kind
        assert_equal "zz__untyped", item.sort_text
        refute item.attributes.key?(:documentation)
      end

      LSPFormatter.completion_item({ kind: "text", range: range, label: "@type var x: T", text: "@type var ${1:variable}: ${2:var type}", help_text: "Type of local variable" }, env: env, builder: builder).tap do |item|
        assert_equal "@type var x: T", item.label
        assert_equal LSP::Constant::CompletionItemKind::SNIPPET, item.kind
        assert_equal LSP::Constant::InsertTextFormat::SNIPPET, item.insert_text_format
        assert_equal "Type of local variable", item.label_details.description
        assert_equal "@type var ${1:variable}: ${2:var type}", item.text_edit.new_text
      end

      LSPFormatter.completion_item({ kind: "keyword_argument", range: range, name: "size:" }, env: env, builder: builder).tap do |item|
        assert_equal "size:", item.label
        assert_equal "Keyword argument", item.label_details.description
        assert_equal "**Keyword argument**: `size:`\n", item.documentation.value
      end
    end
  end

  # @rbs () -> ::Steep::Services::TypeCheckService
  def type_check_service
    project = Project.new(steepfile_path: current_dir + "Steepfile")
    Project::DSL.parse(project, <<~RUBY)
      target :lib do
        check "lib"
        signature "sig"
      end
    RUBY

    Services::TypeCheckService.new(project: project)
  end

  def test_hover
    in_tmpdir do
      service = type_check_service
      service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<~RBS)]
            # Foo is something
            class Foo
            end
          RBS
        }
      )

      hover = LSPFormatter.hover(
        {
          target: "lib",
          range: { start: { line: 1, character: 2 }, end: { line: 1, character: 5 } },
          content: { kind: "constant", name: "::Foo" }
        },
        service: service
      )

      assert_instance_of LSP::Interface::Hover, hover
      assert_equal({ start: { line: 1, character: 2 }, end: { line: 1, character: 5 } }.to_json, hover.range.to_json)
      assert_equal <<~MD, hover.contents.value
        ```rbs
        class Foo
        ```
        ----
        ### 📚 Foo

        Foo is something

      MD
    end
  end

  def test_completion_list
    in_tmpdir do
      service = type_check_service
      service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<~RBS)]
            class Foo
              def foo: () -> void
            end
          RBS
        }
      )

      list = LSPFormatter.completion_list(
        {
          target: "lib",
          incomplete: true,
          items: [
            { kind: "method", range: range, name: "foo", method_types: ["() -> void"], methods: ["::Foo#foo"] },
            { kind: "local_variable", range: range, name: "x", type: "::Integer" }
          ]
        },
        service: service
      )

      assert_instance_of LSP::Interface::CompletionList, list
      assert list.is_incomplete
      assert_equal ["foo", "x"], list.items.map(&:label)
    end
  end

  def test_signature_help
    in_tmpdir do
      service = type_check_service
      service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<~RBS)]
            class Foo
              # Foo#foo doc <!-- hidden -->
              def foo: (String name, ?Integer size) -> void
            end
          RBS
        }
      )

      help = LSPFormatter.signature_help(
        {
          target: "lib",
          signatures: [
            { method_type: "(::String name, ?::Integer size) -> void", parameters: ["::String name", "?::Integer size"], active_parameter: 1, method: "::Foo#foo" },
            { method_type: "() -> void", parameters: [], active_parameter: nil, method: nil }
          ],
          active_signature: 0
        },
        service: service
      )

      assert_instance_of LSP::Interface::SignatureHelp, help
      assert_equal 0, help.active_signature

      help.signatures[0].tap do |signature|
        assert_equal "(::String name, ?::Integer size) -> void", signature.label
        assert_equal ["::String name", "?::Integer size"], signature.parameters.map(&:label)
        assert_equal 1, signature.active_parameter
        assert_equal "Foo#foo doc \n", signature.documentation.value
      end

      help.signatures[1].tap do |signature|
        assert_equal "() -> void", signature.label
        refute signature.attributes.key?(:documentation)
      end
    end
  end
end
