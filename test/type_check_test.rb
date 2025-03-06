require_relative "test_helper"

# (Almost) end-to-end type checking test
#
# Specify the type definition, Ruby code, and expected diagnostics.
# Running test here allows using debuggers.
#
# You can use `Add type_check_test case` VSCode snippet to add new test case.
#
class TypeCheckTest < Minitest::Test
  include TestHelper
  include TypeErrorAssertions
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  include Steep

  # @rbs signatures: Hash[String, String]
  # @rbs code: Hash[String, String]
  # @rbs expectations: String?
  # @rbs &block: ? (Hash[String, Steep::Typing]) -> void
  # @rbs return: void
  def run_type_check_test(signatures: {}, code: {}, expectations: nil, &block)
    typings = {}

    with_factory(signatures, nostdlib: false) do |factory|
      builder = Interface::Builder.new(factory, implicitly_returns_nil: true)
      subtyping = Subtyping::Check.new(builder: builder)

      code.each do |path, content|
        source = Source.parse(content, path: Pathname(path), factory: factory)
        with_standard_construction(subtyping, source) do |construction, typing|
          if source.node
            construction.synthesize(source.node)
          end

          typings[path] = typing
        end
      end
    end

    yield typings if block_given?

    formatter = Diagnostic::LSPFormatter.new()

    diagnostics = typings.transform_values do |typing|
      typing.errors.map do |error|
        Expectations::Diagnostic.from_lsp(formatter.format(error))
      end
    end

    if expectations
      exps = Expectations.empty
      diagnostics.each do |path, ds|
        exps.diagnostics[path] = ds
      end
      exps.to_yaml

      assert_equal expectations, exps.to_yaml
    end
  end

  def test_setter_type
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class SetterReturnType
            def foo=: (String) -> String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class SetterReturnType
            def foo=(value)
              if _ = value
                return
              else
                123
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 6
              end:
                line: 2
                character: 10
            severity: ERROR
            message: |-
              Setter method `foo=` cannot have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::SetterBodyTypeMismatch
          - range:
              start:
                line: 4
                character: 6
              end:
                line: 4
                character: 12
            severity: ERROR
            message: |-
              The setter method `foo=` cannot return a value of type `nil` because declared as type `::String`
                nil <: ::String
            code: Ruby::SetterReturnTypeMismatch
      YAML
    )
  end

  def test_lambda_method
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          # @type var f: ^(Integer) -> Integer
          f = lambda {|x| x + 1 }

          g = lambda {|x| x + 1 } #: ^(Integer) -> String
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 11
              end:
                line: 4
                character: 23
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::BlockBodyTypeMismatch
      YAML
    )
  end

  def test_back_ref
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # @type var x: String
          x = $&
          x = $'
          x = $+
          x = $,
          x = $'
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 5
                character: 0
              end:
                line: 5
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 6
                character: 0
              end:
                line: 6
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
      YAML
    )
  end

  def test_type_variable_in_Set_new
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # @type var array: _Each[Integer]
          array = [1,2,3]

          a = Set.new([1, 2, 3])
          a.each do |x|
            x.fooo
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 8
            severity: ERROR
            message: Type `::Integer` does not have method `fooo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_if_unreachable
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123 #: Integer

          if x.is_a?(String)
            foo()
          end

          if x.is_a?(Integer)
          else
            bar()
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 2
              end:
                line: 4
                character: 5
            severity: ERROR
            message: Type `::Object` does not have method `foo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 9
                character: 2
              end:
                line: 9
                character: 5
            severity: ERROR
            message: Type `::Object` does not have method `bar`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_if_unreachable__if_then
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Then branch is unreachable
          if nil then
            123
          else
            123
          end

          if nil
            123
          else
            123
          end

          if nil
            123
          end

          123 if nil
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 7
              end:
                line: 2
                character: 11
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 14
                character: 0
              end:
                line: 14
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 18
                character: 4
              end:
                line: 18
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_if_unreachable__if_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Else branch is unreachable
          if 123 then
            123
          else
            123
          end

          if 123
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 10
                character: 0
              end:
                line: 10
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_if_unreachable__unless_then
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Then branch is unreachable
          unless true then
            123
          else
            123
          end

          unless true
            123
          else
            123
          end

          unless true
            123
          end

          123 unless true
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 12
              end:
                line: 2
                character: 16
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 14
                character: 0
              end:
                line: 14
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 18
                character: 4
              end:
                line: 18
                character: 10
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end


  def test_if_unreachable__unless_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Else branch is unreachable
          unless false then
            123
          else
            123
          end

          unless false
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 10
                character: 0
              end:
                line: 10
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_if_unreachable__if_void
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def void: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # Both branches are unreachable
          if Foo.new.void
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end
  def test_if_unreachable__if_bot
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def bot: () -> bot
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # Both branches are unreachable
          if Foo.new.bot
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_case_unreachable_1
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123

          case x
          when String
            x.is_a_string
          when Integer
            x + 1
          when Array
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `untyped` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 5
                character: 4
              end:
                line: 5
                character: 15
            severity: ERROR
            message: Type `::String` does not have method `is_a_string`
            code: Ruby::NoMethod
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `nil` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_case_unreachable_2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123
          case
          when x.is_a?(String)
            x.is_a_string
          when x.is_a?(Integer)
            x+1
          when x.is_a?(Array)
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `untyped` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 15
            severity: ERROR
            message: Type `::String` does not have method `is_a_string`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_unreachable_3
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case x = 123
          when Integer
            x+1
          else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `nil` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_flow_sensitive__csend
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Integer?

          if x&.nonzero?
            x.no_method_in_then
          else
            x.no_method_in_else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 21
            severity: ERROR
            message: Type `::Integer` does not have method `no_method_in_then`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 21
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `no_method_in_else`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__csend2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Integer?

          if x&.is_a?(String)
            x.no_method_in_then
          else
            x.no_method_in_else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 21
            severity: ERROR
            message: Type `::String` does not have method `no_method_in_then`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 21
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `no_method_in_else`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.instance_eval do
            if self.name
              self.name + "!"
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_flow_sensitive__self2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () [self: self] -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            if self.name
              Hello.new.foo do
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 16
              end:
                line: 4
                character: 17
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self3
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            # @type self: Hello
            if self.name
              Hello.new.foo do
                # @type self: Hello
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 16
              end:
                line: 6
                character: 17
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self4
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            # @type self: Hello
            if self.name
              Hello.new.foo do
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_and_shortcut__truthy
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].find { true }
          1 and return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_and_shortcut__false
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].find { true }
          return and true unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_or_shortcut__nil
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].find { true }
          nil or return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_or_shortcut__false
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].find { true }
          x or return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_assertion__generic_type_error
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            class Bar
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            a = [] #: Array[Bar]
            a.map {|x| x } #$ Bar
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_case__local_variable_narrowing
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          type foo = Integer | String | nil
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          foo = 3 #: foo

          case foo
          when Integer
            1
          when String, nil
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    ) do |typings|
      typing = typings["a.rb"] or raise

      node, * = typing.source.find_nodes(line: 3, column: 6)
      node or raise

      assert_equal "::foo", typing.type_of(node: node).to_s
    end
  end

  def test_branch_unreachable__logic_type
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 1
          y = x.is_a?(String)

          if y
            z = 1
          else
            z = 2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_case__returns_nil_untyped_union
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = _ = 1
          y = _ = 2
          z = _ = 3

          a =
            case x
            when :foo
              y
            when :bar
              z
            end

          a.is_untyped
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 13
                character: 2
              end:
                line: 13
                character: 12
            severity: ERROR
            message: Type `nil` does not have method `is_untyped`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_when__no_subject__reachability
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when false
            :a
          when nil
            :b
          when "".is_a?(NilClass)
            :c
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 6
                character: 0
              end:
                line: 6
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_case_when__no_subject__reachability_no_continue
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when true
            :a
          when 1
            :b
          else
            :c
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__untyped_value
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          foo = true #: untyped

          case foo
          when nil
            1
          when true
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__narrow_pure_call
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class CaseWhenNarrowPure
            attr_reader foo: Integer | String | Array[String]
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          test = CaseWhenNarrowPure.new

          case test.foo
          when Integer
            test.foo + 1
          when String
            test.foo + ""
          else
            test.foo.each
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__bool_value
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          foo = true #: bool

          case foo
          when false
            1
          when true
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_inference__nested_block
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = 123.yield_self do
            "abc".yield_self do
              :hogehoge
            end
          end

          a.is_symbol
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 7
                character: 2
              end:
                line: 7
                character: 11
            severity: ERROR
            message: Type `::Symbol` does not have method `is_symbol`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_type_inference__nested_block_free_variable
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo[T]
            def foo: () -> T
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # Type error is reported because `::Symbol`` cannot be `T`
          class Foo
            def foo
              "".yield_self do
                :symbol
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 18
              end:
                line: 6
                character: 7
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Symbol` because declared as type `T`
                ::Symbol <: T
            code: Ruby::BlockBodyTypeMismatch
        YAML
    )
  end

  def test_type_narrowing__local_variable_safe_navigation_operator
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            type context = [context, String | false] | nil
            def foo: (context) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(context)
              context&.[](0)
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_narrowing__union_send
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Object
            def present?: () -> bool
          end

          class NilClass
            def present?: () -> false
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          a = [1].first
          a + 1 if a.present?
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end


  def test_argument_error__unexpected_unexpected_positional_argument
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.foo(hello_world: true)
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 12
              end:
                line: 1
                character: 23
            severity: ERROR
            message: Unexpected keyword argument
            code: Ruby::UnexpectedKeywordArgument
      YAML
    )
  end

  def test_type_assertion__type_error
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          nil #: Int
          [1].map {} #$ Int
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 7
              end:
                line: 1
                character: 10
            severity: ERROR
            message: Cannot find type `::Int`
            code: Ruby::RBSError
          - range:
              start:
                line: 2
                character: 14
              end:
                line: 2
                character: 17
            severity: ERROR
            message: Cannot find type `::Int`
            code: Ruby::RBSError
      YAML
    )
  end

  def test_nilq_unreachable
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          if 1.nil?
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 0
              end:
                line: 1
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_type_case__type_variable
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def foo: [A] (A) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(x)
              case x
              when Hash
                123
              when String
                123
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_lambda__hint_is_untyped
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = _ = ->(x) { x + 1 }
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_safe_navigation_operator__or_hint
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def foo: (Integer?) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(a)
              a&.then {|x| x.infinite? } || -1
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_check__elsif
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Symbol?

          if x.is_a?(Integer)
            1
          elsif x.is_a?(String)
            2
          elsif x.is_a?(NilClass)
            3
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 5
                character: 0
              end:
                line: 5
                character: 5
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_untyped_nilp
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = _ = nil

          if a.nil?
            1
          else
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_paren_conditional
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          a = [1].first
          b = [2].first

          if (a && b)
            a + b
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_self_constant
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class ConstantTest
            NAME: String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class ConstantTest
            self::NAME
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_class_narrowing
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          module Foo
            def self.foo: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          klass = Class.new()

          if klass < Foo
            klass.foo()
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_calls_with_index_writer_methods
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class WithIndexWriter
            def []=: (String, String) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          obj = WithIndexWriter.new
          obj.[]=("hoge", "huga").foo
          obj&.[]=("hoge", "huga").foo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 24
              end:
                line: 2
                character: 27
            severity: ERROR
            message: Type `::Integer` does not have method `foo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 3
                character: 25
              end:
                line: 3
                character: 28
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `foo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_underscore_opt_param
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: (?String, *untyped, **untyped) -> void

            def bar: () { (?String, *untyped, **untyped) -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo(_ = "", *_, **_)
              bar {|_ = "", *_, **_| }
            end

            def bar
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_rescue_assignment
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          begin
            x = 123
          rescue
            raise
          end

          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_defined?
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          defined? foo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_string_match
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          "" =~ ""
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 0
              end:
                line: 1
                character: 8
            severity: ERROR
            message: |-
              Cannot find compatible overloading of method `=~` of type `::String`
              Method types:
                def =~: (::Regexp) -> (::Integer | nil)
                      | [T] (::String::_MatchAgainst[::String, T]) -> T
            code: Ruby::UnresolvedOverloading
      YAML
    )
  end

  def test_big_literal_union_type
    names = 100.times.map {|i| "'#{i}'"}

    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          type names = #{names.join(" | ")}
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = (_ = nil) #: names
          x + ""
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_nilp_flow_sensitive_typing_error__or
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Event
            attr_reader pubkey: String?
            attr_reader id: String?
            attr_reader sig: String?

            def foo: (String, String, String) -> bool
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          event = Event.new()

          return if event.pubkey.nil? || event.id.nil? || event.sig.nil?

          event.pubkey.strip
          event.id.size
          event.sig.encoding
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_nilp_flow_sensitive_typing_error__and
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Event
            attr_reader pubkey: String?
            attr_reader id: String?
            attr_reader sig: String?

            def foo: (String, String, String) -> bool
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          event = Event.new()

          return unless !event.pubkey.nil? && !event.id.nil? && !event.sig.nil?

          event.pubkey.strip
          event.id.size
          event.sig.encoding
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_method_call__untyped
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def f: (?) -> void

            def g: () { (?) -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          hello = Hello.new()

          hello.f(1, 2, 3)
          hello.f() { }
          hello.f(&-> { 1 })

          hello.g {|x,y| x + y }
          hello.g(&-> (x, y) { x + y })
          hello.g(&-> (x) { x.foo })
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_method_call__untyped_block_body
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def f: (?) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          hello = Hello.new()

          hello.f() do |x|
            # @type var x: String
            x.foo
            1.bar
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 5
                character: 4
              end:
                line: 5
                character: 7
            severity: ERROR
            message: Type `::String` does not have method `foo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 7
            severity: ERROR
            message: Type `::Integer` does not have method `bar`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_method_def__untyped
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def f: (?) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def f(x, y, z)
              x + y + z
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_method_yield__untyped
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def f: () { (?) -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def f(&block)
              yield 1, 2, 3
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_args_annotation
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def foo: (String) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(x) #: Integer
              3
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_data_struct_annotation
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello < Data
            attr_reader name(): String

            def self.new: (String name) -> instance
                        | (name: String) -> instance
          end

          class World < Struct[untyped]
            attr_accessor size(): Integer

            def self.new: (Integer size) -> instance
                        | (size: Integer) -> instance
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello = Data.define(
            :name #: String
          )

          World = Struct.new(
            :size #: Integer
          )
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_any_upperbound
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: [X < String?] (X) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo(x)
              if x
                x.encoding
              end

              x.encoding
            end
          end

          foo = Foo.new
          foo.foo("123") #$ String
          foo.foo("foo") #$ String?
          foo.foo(nil)
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 7
                character: 6
              end:
                line: 7
                character: 14
            severity: ERROR
            message: Type `(::String | nil)` does not have method `encoding`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_generics_upperbound_default
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo[X = Integer]
            def foo: (X) -> X
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo(x)
              x
            end
          end

          x = Foo.new
          x.foo(1) + 1

          y = Foo.new #: Foo[String]
          y.foo("foo") + ""

          z = Foo.new #: Foo
          z.foo(1) + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_record__optional_key__assignment
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          # @type var record: { id: Integer, ?name: String }

          record = { id: 123, name: "Hello" }
          record = { id: 123 }

          record = { id: 123, name: 123 }
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 0
              end:
                line: 6
                character: 31
            severity: ERROR
            message: |-
              Cannot assign a value of type `{ :id => ::Integer, ?:name => ::Integer }` to a variable of type `{ :id => ::Integer, ?:name => ::String }`
                { :id => ::Integer, ?:name => ::Integer } <: { :id => ::Integer, ?:name => ::String }
                  ::Integer <: ::String
                    ::Numeric <: ::String
                      ::Object <: ::String
                        ::BasicObject <: ::String
            code: Ruby::IncompatibleAssignment
      YAML
    )
  end

  def test_record__optional_key__get
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          # @type var record: { id: Integer, ?name: String }

          record = _ = nil

          record[:id] + 1
          record[:name] + ""

          record.fetch(:id) + 1
          record.fetch(:name) + ""
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 14
              end:
                line: 6
                character: 15
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_generics__tuple
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo[X < Object?]
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          a = Foo.new #$ [Integer]
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_yield_self_union
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = (_ = nil) #: String | Integer
          x.yield_self do
            ""
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_class_type
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def initialize: (Integer) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new(1).class.fooo
          Foo.class.barr
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 17
              end:
                line: 1
                character: 21
            severity: ERROR
            message: Type `singleton(::Foo)` does not have method `fooo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 2
                character: 10
              end:
                line: 2
                character: 14
            severity: ERROR
            message: Type `::Class` does not have method `barr`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_record_type__keys
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          a = { 1 => "one", "two" => 2, true => [] } #: { 1 => String, "two" => Integer, true => Array[String] }

          a[1] + ""
          a["two"] + 1
          a[true].pop
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_implicitly_returns_nil
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            %a{implicitly-returns-nil} def foo: () -> Integer

            def bar: (Integer) -> String
                   | %a{implicitly-returns-nil} () -> String

            alias baz foo
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          foo = Foo.new
          foo.foo + 1

          foo.bar(1) + ""

          foo.bar() + ""

          foo.baz + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 8
              end:
                line: 2
                character: 9
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 10
              end:
                line: 6
                character: 11
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_untyped_hash
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          { foo: 1} #: Hash[untyped, untyped] | String
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_empty_collection
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          a = []
          b = {}

          x = [] #: Array[String]
          y = {} #: Hash[String, untyped]

          t = [] #: untyped
          s = {} #: untyped
        RUBY
      },
      expectations: <<~YAML
      ---
      - file: a.rb
        diagnostics:
        - range:
            start:
              line: 1
              character: 4
            end:
              line: 1
              character: 6
          severity: ERROR
          message: Empty array doesn't have type annotation
          code: Ruby::UnannotatedEmptyCollection
        - range:
            start:
              line: 2
              character: 4
            end:
              line: 2
              character: 6
          severity: ERROR
          message: Empty hash doesn't have type annotation
          code: Ruby::UnannotatedEmptyCollection
      YAML
    )
  end

  def test_masgn_splat
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          array = %w(a b c)
          a, b = *//.match('hoge')

          a.ffffff
          b.ffffff
        RUBY
      },
      expectations: <<~YAML
      ---
      - file: a.rb
        diagnostics:
        - range:
            start:
              line: 4
              character: 2
            end:
              line: 4
              character: 8
          severity: ERROR
          message: Type `(::String | nil)` does not have method `ffffff`
          code: Ruby::NoMethod
        - range:
            start:
              line: 5
              character: 2
            end:
              line: 5
              character: 8
          severity: ERROR
          message: Type `(::String | nil)` does not have method `ffffff`
          code: Ruby::NoMethod
      YAML
    )
  end

  def test_class_module_mismatch
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
          end

          module Bar
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          module Foo
          end

          class Bar
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 7
              end:
                line: 1
                character: 10
            severity: ERROR
            message: \"::Foo is declared as a class in RBS\"
            code: Ruby::ClassModuleMismatch
          - range:
              start:
                line: 4
                character: 6
              end:
                line: 4
                character: 9
            severity: ERROR
            message: \"::Bar is declared as a module in RBS\"
            code: Ruby::ClassModuleMismatch
      YAML
    )
  end

  def test_unknown_record_key
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          var = { name: "soutaro", email: "soutaro@example.com" } #: { name: String }
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 25
              end:
                line: 1
                character: 30
            severity: ERROR
            message: Unknown key `:email` is given to a record type
            code: Ruby::UnknownRecordKey
      YAML
    )
  end

  def test_undeclared_method
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo = nil

            def self.foo = nil
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 6
              end:
                line: 2
                character: 9
            severity: ERROR
            message: Method `::Foo#foo` is not declared in RBS
            code: Ruby::UndeclaredMethodDefinition
          - range:
              start:
                line: 4
                character: 11
              end:
                line: 4
                character: 14
            severity: ERROR
            message: Method `::Foo.foo` is not declared in RBS
            code: Ruby::UndeclaredMethodDefinition
      YAML
    )
  end

  def test_undeclared_method2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo = nil
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 6
              end:
                line: 1
                character: 9
            severity: ERROR
            message: 'Cannot find the declaration of class: `Foo`'
            code: Ruby::UnknownConstant
          - range:
              start:
                line: 2
                character: 6
              end:
                line: 2
                character: 9
            severity: ERROR
            message: Method `foo` is defined in undeclared module
            code: Ruby::MethodDefinitionInUndeclaredModule
      YAML
    )
  end

  def test_when__assertion
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          a = case [1,2,3].sample
          when Integer
            ["foo", 1] #: [String, Integer]
          end

          a.foo()  # To confirm the type of `a`
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 2
              end:
                line: 6
                character: 5
            severity: ERROR
            message: Type `([::String, ::Integer] | nil)` does not have method `foo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_when__type_annotation
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          a = [1, ""].sample

          case
          when 1.even?
            # @type var a: String
            a + ""
          when 2.even?
            # @type var a: Integer
            a + 1
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_tuple_type_assertion
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          [1, ""] #: [1, "", bool]
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 0
              end:
                line: 1
                character: 24
            severity: ERROR
            message: 'Assertion cannot hold: no relationship between inferred type (`[1, \"\"]`)
              and asserted type (`[1, \"\", bool]`)'
            code: Ruby::FalseAssertion
      YAML
    )
  end

  def test_case_when__no_subject__assignment_in_when__raise_in_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when 1
            v = 1
          when 2
            v = 10
          else
            raise
          end

          v + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_self_type_union_assertion
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def bar: (bool) -> self?
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def bar(var)
              return nil if var
              self
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__no_subject__assignment_in_when__no_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when 1
            v = 1
          when 2
            v = 10
          else
          end

          v + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 9
                character: 2
              end:
                line: 9
                character: 3
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_when__with_subject__assignment_in_when__raise_in_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case rand(3)
          when 1
            v = 1
          when 2
            v = 10
          else
            raise
          end

          v + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__with_subject__assignment_in_when__empty_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case rand(3)
          when 1
            v = 1
          when 2
            v = 10
          else
          end

          v + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 9
                character: 2
              end:
                line: 9
                character: 3
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_when__with_subject__assignment_in_when__no_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case rand(3)
          when 1
            v = 1
          when 2
            v = 10
          end

          v + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 8
                character: 2
              end:
                line: 8
                character: 3
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end
end
