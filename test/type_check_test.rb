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
  # @rbs inline_code: Hash[String, String]
  # @rbs expectations: String?
  # @rbs postconditions: Steep::Postconditions::Store
  # @rbs callbacks: Steep::Callbacks::Store
  # @rbs &block: ? (Hash[String, Steep::Typing]) -> void
  # @rbs return: void
  def run_type_check_test(signatures: {}, code: {}, inline_code: {}, expectations: nil, postconditions: Steep::Postconditions::Store.empty, callbacks: Steep::Callbacks::Store.empty, &block)
    typings = {}

    with_factory(signatures, inline_code, nostdlib: false) do |factory|
      builder = Interface::Builder.new(factory, implicitly_returns_nil: true)
      subtyping = Subtyping::Check.new(builder: builder)

      code.merge(inline_code).each do |path, content|
        source = Source.parse(content, path: Pathname(path), factory: factory)
        with_standard_construction(subtyping, source, postconditions: postconditions, callbacks: callbacks) do |construction, typing|
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
                character: 4
              end:
                line: 4
                character: 47
            severity: ERROR
            message: 'Assertion cannot hold: no relationship between inferred type (`^(::Integer)
              -> ::Integer`) and asserted type (`^(::Integer) -> ::String`)'
            code: Ruby::FalseAssertion
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

  def test_ivar_pure_call_narrowing
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarNarrowContainer
            attr_reader value: Integer?
          end

          class IvarNarrowHost
            attr_reader container: IvarNarrowContainer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarNarrowHost.new.instance_eval do
            if @container.value
              @container.value + 1
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

  def test_ivar_pure_call_narrowing__invalidated_by_reassignment
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarReassignContainer
            attr_reader value: Integer?
          end

          class IvarReassignHost
            attr_accessor container: IvarReassignContainer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarReassignHost.new.instance_eval do
            if @container.value
              @container = IvarReassignContainer.new
              @container.value + 1
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
                character: 21
              end:
                line: 4
                character: 22
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_ivar_pure_call_narrowing__non_pure_method_not_narrowed
    # Negative control: a method annotated `%a{impure}` opts out of the
    # optimistic-pure default (felixefelip/steep#12), so the pure_call
    # cache stays empty and the second `@provider.maybe_value` doesn't
    # carry the narrowing from the conditional.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarNonPureProvider
            %a{impure}
            def maybe_value: () -> Integer?
          end

          class IvarNonPureHost
            attr_reader provider: IvarNonPureProvider
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarNonPureHost.new.instance_eval do
            if @provider.maybe_value
              @provider.maybe_value + 1
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
                line: 3
                character: 26
              end:
                line: 3
                character: 27
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_ivar_union_assignment_narrows_to_validated_branch
    # Phase 1 of felixefelip/steep#16: in a Rails-like controller, the
    # backing ivar is declared as a union of "validated" and "raw" forms
    # of the model. Calling `Model.find` (whose RBS in the
    # `rbs_rails`/`rbs_collection` fork returns `Model & Validated`)
    # selects the validated branch, so a subsequent call to a method
    # declared only on the validated marker type-checks without manual
    # `is_a?` narrowing.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarUnionCompany
            def self.find: (Integer) -> (IvarUnionCompany & IvarUnionCompany::Validated)
            def self.new: () -> IvarUnionCompany
          end

          module IvarUnionCompany::Validated
            def name_required: () -> String
          end

          class IvarUnionController
            @company: (IvarUnionCompany & IvarUnionCompany::Validated) | IvarUnionCompany
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarUnionController.new.instance_eval do
            @company = IvarUnionCompany.find(1)
            @company.name_required
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

  def test_ivar_union_assignment_narrows_does_not_apply_to_non_validated_branch
    # Negative control: assigning the raw form (`Model.new`) selects the
    # non-validated branch, so the validated-only method must error.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarUnionCompanyB
            def self.find: (Integer) -> (IvarUnionCompanyB & IvarUnionCompanyB::Validated)
            def self.new: () -> IvarUnionCompanyB
          end

          module IvarUnionCompanyB::Validated
            def name_required: () -> String
          end

          class IvarUnionControllerB
            @company: (IvarUnionCompanyB & IvarUnionCompanyB::Validated) | IvarUnionCompanyB
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarUnionControllerB.new.instance_eval do
            @company = IvarUnionCompanyB.new
            @company.name_required
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
                character: 11
              end:
                line: 3
                character: 24
            severity: ERROR
            message: Type `::IvarUnionCompanyB` does not have method `name_required`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_ivar_union_reassignment_resets_narrow_to_new_branch
    # After narrowing the ivar to the validated branch via `find`, a
    # reassignment with the non-validated form (`new`) must reset the
    # env's view of the ivar so the validated-only method now errors.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarUnionCompanyC
            def self.find: (Integer) -> (IvarUnionCompanyC & IvarUnionCompanyC::Validated)
            def self.new: () -> IvarUnionCompanyC
          end

          module IvarUnionCompanyC::Validated
            def name_required: () -> String
          end

          class IvarUnionControllerC
            @company: (IvarUnionCompanyC & IvarUnionCompanyC::Validated) | IvarUnionCompanyC
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarUnionControllerC.new.instance_eval do
            @company = IvarUnionCompanyC.find(1)
            @company.name_required

            @company = IvarUnionCompanyC.new
            @company.name_required
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
                character: 11
              end:
                line: 6
                character: 24
            severity: ERROR
            message: Type `::IvarUnionCompanyC` does not have method `name_required`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_ivar_attr_accessor_narrows_to_validated_branch
    # Phase 2 of felixefelip/steep#16: in a PORO that exposes the
    # backing ivar via `attr_accessor`, writing through the setter with
    # a value typed as the validated marker narrows the env's view of
    # the ivar, so reading back through the getter (also via attr) sees
    # the validated branch — no manual `is_a?` required.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarAttrCompany
            def self.find: (Integer) -> (IvarAttrCompany & IvarAttrCompany::Validated)
            def self.new: () -> IvarAttrCompany
          end

          module IvarAttrCompany::Validated
            def name_required: () -> String
          end

          class IvarAttrForm
            attr_accessor company: (IvarAttrCompany & IvarAttrCompany::Validated) | IvarAttrCompany
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarAttrForm.new.instance_eval do
            self.company = IvarAttrCompany.find(1)
            self.company.name_required
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

  def test_ivar_attr_accessor_narrow_does_not_apply_to_raw_branch
    # Negative control: assigning the raw (non-validated) form via the
    # setter narrows the ivar to that branch; reading the getter then
    # returns a type without the validated marker, so the validated-only
    # method must error.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarAttrCompanyB
            def self.find: (Integer) -> (IvarAttrCompanyB & IvarAttrCompanyB::Validated)
            def self.new: () -> IvarAttrCompanyB
          end

          module IvarAttrCompanyB::Validated
            def name_required: () -> String
          end

          class IvarAttrFormB
            attr_accessor company: (IvarAttrCompanyB & IvarAttrCompanyB::Validated) | IvarAttrCompanyB
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarAttrFormB.new.instance_eval do
            self.company = IvarAttrCompanyB.new
            self.company.name_required
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
                character: 15
              end:
                line: 3
                character: 28
            severity: ERROR
            message: Type `::IvarAttrCompanyB` does not have method `name_required`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_ivar_attr_reader_consumes_direct_ivar_narrow
    # The read side of the rule works even when the narrowing comes
    # from a direct `@x = …` assignment (Phase 1) rather than from the
    # setter. The attr_reader call returns the env's current ivar type,
    # not the declared method return type.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class IvarAttrCompanyC
            def self.find: (Integer) -> (IvarAttrCompanyC & IvarAttrCompanyC::Validated)
          end

          module IvarAttrCompanyC::Validated
            def name_required: () -> String
          end

          class IvarAttrReadOnlyForm
            attr_reader company: (IvarAttrCompanyC & IvarAttrCompanyC::Validated) | IvarAttrCompanyC
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          IvarAttrReadOnlyForm.new.instance_eval do
            @company = IvarAttrCompanyC.find(1)
            self.company.name_required
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

  def test_type_narrowing__union_send2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            attr_reader foo: String?

            def foo!: () -> void
          end

          class Bar
            attr_reader foo: nil
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          foo = rand > 0.1 ? Foo.new : Bar.new
          if x = foo.foo
            foo.foo!
            x + ""
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

  def test_deprecated_method
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            %a{steep:deprecated} def foo: () -> void

            %a{deprecated:Don't use bar} def bar: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.foo()

          Foo.new.bar()
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 8
              end:
                line: 1
                character: 11
            severity: ERROR
            message: The method is deprecated
            code: Ruby::DeprecatedReference
          - range:
              start:
                line: 3
                character: 8
              end:
                line: 3
                character: 11
            severity: ERROR
            message: 'The method is deprecated: Don''t use bar'
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_method_alias
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: () -> void

            %a{steep:deprecated} alias bar foo
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.bar()
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 8
              end:
                line: 1
                character: 11
            severity: ERROR
            message: The method is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_method_overload
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: () -> void
                   | %a{deprecated} (Integer) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.foo()
          Foo.new.foo(1)
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
                character: 11
            severity: ERROR
            message: The method is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_class_module
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          %a{deprecated} class Foo
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo
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
                character: 3
            severity: ERROR
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_class_module_alias
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          %a{deprecated} class Foo
          end

          class Bar = Foo

          %a{deprecated} class Baz = Foo
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Bar
          Baz
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
                character: 3
            severity: ERROR
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_constant
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          %a{deprecated} FOO: Integer
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          FOO = 123
          FOO
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
                character: 3
            severity: ERROR
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 3
            severity: ERROR
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_deprecated_global
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          %a{deprecated} $FOO: Integer
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          $FOO = 123
          $FOO
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
                character: 4
            severity: ERROR
            message: The global variable is deprecated
            code: Ruby::DeprecatedReference
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 4
            severity: ERROR
            message: The global variable is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_class_module_decl__deprecated
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          %a{deprecated} class Foo end
          %a{deprecated} module Bar end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
          end
          module Bar
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
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
          - range:
              start:
                line: 3
                character: 7
              end:
                line: 3
                character: 10
            severity: ERROR
            message: The constant is deprecated
            code: Ruby::DeprecatedReference
      YAML
    )
  end

  def test_argument_forwarding__dynamic
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: (?) -> void

            def bar: (Integer) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo(...)
              bar(...)
            end

            def bar(x)
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

  def test_argument_forwarding__undeclared
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
            def foo(...)
              1.to_s(...)
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
                character: 9
            severity: ERROR
            message: Method `::Foo#foo` is not declared in RBS
            code: Ruby::UndeclaredMethodDefinition
      YAML
    )
  end

  def test_type_check_untyped_calls_with_blocks
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          Foo
            .foo {}
            .foo {}
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
                character: 3
            severity: ERROR
            message: 'Cannot find the declaration of constant: `Foo`'
            code: Ruby::UnknownConstant
      YAML
    )
  end

  def test_generics_optional_arg #: void
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Test
            def foo: [T] (?T) { () -> T } -> T
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Test.new.foo(1) { 1 }.fooo
          Test.new.foo() { 1 }.fooo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 22
              end:
                line: 1
                character: 26
            severity: ERROR
            message: Type `::Integer` does not have method `fooo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 2
                character: 21
              end:
                line: 2
                character: 25
            severity: ERROR
            message: Type `::Integer` does not have method `fooo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_self_type__block_hint
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Test
            def self.foo: () { () [self: self] -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Test
            # @dynamic self.foo

            foo { no_such_method }
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
                character: 8
              end:
                line: 4
                character: 22
            severity: ERROR
            message: Type `singleton(::Test)` does not have method `no_such_method`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_self_type__block_annotation
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Test
            def self.foo: () { () [self: self] -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Test
            # @dynamic self.foo

            foo do
              # @type self: singleton(Test)
              no_such_method
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
                character: 4
              end:
                line: 6
                character: 18
            severity: ERROR
            message: Type `singleton(::Test)` does not have method `no_such_method`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_self_type__lambda_hint
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Test
            def self.foo: (^() [self: self] -> void) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Test
            # @dynamic self.foo

            foo(-> { no_such_method })
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
                character: 11
              end:
                line: 4
                character: 25
            severity: ERROR
            message: Type `singleton(::Test)` does not have method `no_such_method`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_block_type_comment__call
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          [1,2,3].map do |x|
            # @type block: String
            123
          end.ffffffffff
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
                line: 4
                character: 3
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::BlockBodyTypeMismatch
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 14
            severity: ERROR
            message: Type `::Array[::String]` does not have method `ffffffffff`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_block_type_comment__untyped
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          (_ = 123).foo do
            # @type block: String
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
                character: 14
              end:
                line: 4
                character: 3
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

  def test_block_type_comment__lambda
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = -> do
            # @type block: String
            123
          end
          x.ffffffffff
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
                line: 4
                character: 3
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::BlockBodyTypeMismatch
          - range:
              start:
                line: 5
                character: 2
              end:
                line: 5
                character: 12
            severity: ERROR
            message: Type `^() -> ::String` does not have method `ffffffffff`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_splat_block
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: () { ([Integer, String]) -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.foo do |x, *|
            x + 1
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

  def test_unnamed_splat_method_definition
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def bar: (Integer, *String) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def bar(x, *)
              x + 1
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

  def test_unnamed_kwsplat_method_definition
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def bar: (x: Integer, **String) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def bar(x:, **)
              x + 1
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

  def test_inline__module_include
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          module M[T]
            def foo: () -> T
          end
        RBS
      },
      inline_code: {
        "a.rb" => <<~RUBY
          class Foo
            include M #[String]
          end

          Foo.new.foo.bar
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 5
                character: 12
              end:
                line: 5
                character: 15
            severity: ERROR
            message: Type `::String` does not have method `bar`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_inline__attributes
    run_type_check_test(
      signatures: {},
      inline_code: {
        "a.rb" => <<~RUBY
          class Foo
            attr_reader :foo

            attr_writer :bar #: Integer

            # @rbs skip
            attr_accessor :baz
          end

          foo = Foo.new
          foo.foo.bar
          foo.bar = ""
          foo.baz
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 12
                character: 10
              end:
                line: 12
                character: 12
            severity: ERROR
            message: |-
              Cannot pass a value of type `::String` as an argument of type `::Integer`
                ::String <: ::Integer
                  ::Object <: ::Integer
                    ::BasicObject <: ::Integer
            code: Ruby::ArgumentTypeMismatch
          - range:
              start:
                line: 13
                character: 4
              end:
                line: 13
                character: 7
            severity: ERROR
            message: Type `::Foo` does not have method `baz`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_inline__inheritance
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Parent
            def foo: () -> String
          end

          class GenericParent[T]
            def bar: () -> T
          end
        RBS
      },
      inline_code: {
        "a.rb" => <<~RUBY
          class Child < Parent
            def call_foo
              foo
            end
          end

          class GenericChild < GenericParent #[Integer]
            def call_bar
              bar + 1
            end
          end

          class StringChild < GenericParent #[String]
            def call_bar
              bar + "!"
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

  def test_inline__instance_variables
    run_type_check_test(
      signatures: {
      },
      inline_code: {
        "a.rb" => <<~RUBY
          class Foo
            # @rbs @name: String

            def initialize
              @name = "Soutaro"
            end

            def to_s
              "{ name => #{@name.inspect} }"
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

  def test_inline_constant_declaration_basic
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class MyClass
            CONSTANT = "hello" #: String
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

  def test_inline_constant_declaration_type_mismatch
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class MyClass
            NUMBER = 42 #: String
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
                character: 11
              end:
                line: 2
                character: 23
            severity: ERROR
            message: 'Assertion cannot hold: no relationship between inferred type (`::Integer`)
              and asserted type (`::String`)'
            code: Ruby::FalseAssertion
      YAML
    )
  end

  def test_inline_constant_declaration_with_complex_type
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class MyClass
            CONFIG = { name: "test", count: 42 } #: Hash[Symbol, String | Integer]
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

  def test_inline_constant_declaration_nested_class
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class Outer
            class Inner
              VALUE = ["a", "b", "c"] #: Array[String]
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

  def test_inline_constant_declaration_module
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          module MyModule
            DEFAULT_SIZE = 100 #: Integer
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

  def test_inline_constant_declaration_with_nil
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class MyClass
            OPTIONAL = nil #: String?
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

  def test_inline_constant_declaration_generic_type
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class Container
            ITEMS = [{ "count" => 1 }, { "total" => 100 }] #: Array[Hash[String, Integer]]
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

  def test_inline_constant_declaration_inheritance
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class Parent
            BASE_VALUE = "parent" #: String
          end

          class Child < Parent
            CHILD_VALUE = 42 #: Integer
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

  def test_inline_constant_declaration_top_level
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          # Version of the library
          VERSION = "1.2.3".freeze #: String

          ITEMS = [1, "hello"] #: [Integer, String]
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_inline_constant_declaration_type_inference
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class Config
            MAX_SIZE = 100           # Should infer as Integer
            PI = 3.14159            # Should infer as Float
            DEBUG = false           # Should infer as bool
            APP_NAME = "MyApp"      # Should infer as String
            DEFAULT_MODE = :strict  # Should infer as :strict
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

  def test_inline_class_alias_basic
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class OriginalClass
            def foo
              "hello"
            end
          end

          MyClass = OriginalClass #: class-alias

          # Should be able to use MyClass as OriginalClass
          obj = MyClass.new
          obj.foo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_inline_module_alias_basic
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          module OriginalModule
            def bar
              42
            end
          end

          MyModule = OriginalModule #: module-alias

          class MyClass
            include MyModule

            def test
              bar
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

  def test_inline_class_alias_with_explicit_type
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          class SomeClass
            def method1
              "test"
            end
          end

          # Using a variable that references the class
          klass = SomeClass
          AliasedClass = klass #: class-alias SomeClass

          # Should work with the explicit type annotation
          instance = AliasedClass.new
          instance.method1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_inline_module_alias_with_explicit_type
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          module SomeModule
            def helper
              true
            end
          end

          # Using a variable that references the module
          mod = SomeModule
          AliasedModule = mod #: module-alias SomeModule

          class TestClass
            include AliasedModule

            def use_helper
              helper
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

  def test_inline_class_alias_nested
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          module Namespace
            class InnerClass
              def inner_method
                "inner"
              end
            end

            MyInnerClass = InnerClass #: class-alias
          end

          # Should work with nested alias
          obj = Namespace::MyInnerClass.new
          obj.inner_method
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_inline_class_alias_type_name
    run_type_check_test(
      inline_code: {
        "a.rb" => <<~RUBY
          MyString = String #: class-alias
          MyKernel = Kernel #: module-alias

          string = nil #: MyString?
          kernel = nil #: MyKernel?
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_erb_convention_imports_ivars_from_self_type
    ENV["STEEP_ERB_CONVENTION"] = "1"
    run_type_check_test(
      signatures: {
        "erb_class.rbs" => <<~RBS
          class ERBPostsShow
            @post: String
            @count: Integer
          end
        RBS
      },
      code: {
        "app/views/posts/show.html.erb" => <<~ERB
          <%= @post %>
          <%= @count %>
        ERB
      },
      expectations: <<~YAML
        ---
        - file: app/views/posts/show.html.erb
          diagnostics: []
      YAML
    )
  ensure
    ENV.delete("STEEP_ERB_CONVENTION")
  end

  def test_type_instance_annotation_imports_ivars_from_annotated_type
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            @name: String
          end

          module Concern
            def do_thing: () -> String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          module Concern
            # @type instance: Foo
            def do_thing
              @name
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

  def test_type_instance_annotation_imports_ivars_from_intersection_type
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class ApplicationController
            @request_id: String
          end

          module FilterConfiguration
            @filter_name: Symbol

            def configure_filter: (untyped name) -> untyped
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          module FilterConfiguration
            # @type instance: FilterConfiguration & ApplicationController
            def configure_filter(name)
              @filter_name
              @request_id
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

  def test_type_instance_annotation_imports_inherited_ivars
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Base
            @base_var: Integer
          end

          class Child < Base
            @child_var: String
          end

          module Mixin
            def check: () -> untyped
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          module Mixin
            # @type instance: Child
            def check
              @child_var
              @base_var
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

  # ---------------------------------------------------------------------------
  # Conditional postconditions (felixefelip/steep#10)
  #
  # Sidecar declarations refine the receiver in the truthy/falsy branches of a
  # boolean call. Hits Pattern A (predicate) and Pattern B (update/save/valid?).
  # ---------------------------------------------------------------------------

  def postconditions_store(entries)
    Steep::Postconditions::Store.from_hash(
      { "postconditions" => entries },
      source: "test"
    )
  end

  def test_postconditions__predicate_refines_receiver
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCOrderImport
            attr_reader logistics_operator: PCLogisticsOperator?
            def shipment?: () -> bool

            class ValidatedAsShipment
              attr_reader logistics_operator: PCLogisticsOperator
            end
          end

          class PCLogisticsOperator
            attr_reader name: String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          order_import = PCOrderImport.new
          if order_import.shipment?
            order_import.logistics_operator.name
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCOrderImport",
          "method" => "shipment?",
          "when_true" => { "self" => "PCOrderImport & PCOrderImport::ValidatedAsShipment" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__predicate_refines_ivar_receiver
    # Mirror of the lvar test: the receiver of the predicate is an
    # instance variable. Before the `:ivar` case was added to
    # `LogicTypeInterpreter#refine_node_type`, the env's
    # `instance_variable_types[@order_import]` stayed at the declared
    # type inside the truthy branch, so `@order_import.logistics_operator`
    # remained `PCLogisticsOperator?` and the `.name` call errored.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIvarOrderImport
            attr_reader logistics_operator: PCIvarLogisticsOperator?
            def shipment?: () -> bool

            class ValidatedAsShipment
              attr_reader logistics_operator: PCIvarLogisticsOperator
            end
          end

          class PCIvarLogisticsOperator
            attr_reader name: String
          end

          class PCIvarHost
            @order_import: PCIvarOrderImport
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          PCIvarHost.new.instance_eval do
            if @order_import.shipment?
              @order_import.logistics_operator.name
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIvarOrderImport",
          "method" => "shipment?",
          "when_true" => { "self" => "PCIvarOrderImport & PCIvarOrderImport::ValidatedAsShipment" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__update_refines_ivar_receiver
    # Real-world Rails pattern: `if @company.save then @company.name`
    # — `save` declared with a `when_true` postcondition that narrows the
    # receiver to a `Validated` marker promoting `name` from `String?`
    # to `String`. Inside the `if`, `@company.name.upcase` must type-check
    # because the ivar is narrowed.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIvarUser
            attr_reader name: String?
            def save: () -> bool

            class Validated
              attr_reader name: String
            end
          end

          class PCIvarSaveHost
            @user: PCIvarUser
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          PCIvarSaveHost.new.instance_eval do
            if @user.save
              @user.name.upcase
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIvarUser",
          "method" => "save",
          "when_true" => { "self" => "PCIvarUser & PCIvarUser::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__update_refines_receiver
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCUser
            attr_reader name: String?
            def update: (untyped) -> bool

            class Validated
              attr_reader name: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          user = PCUser.new
          if user.update({})
            user.name.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCUser",
          "method" => "update",
          "when_true" => { "self" => "PCUser & PCUser::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__composition_via_and
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCMixUser
            attr_reader email: String?
            attr_reader phone: String?
            def email_required?: () -> bool
            def phone_required?: () -> bool

            class ValidatedAsEmail
              attr_reader email: String
            end

            class ValidatedAsPhone
              attr_reader phone: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          user = PCMixUser.new
          if user.email_required? && user.phone_required?
            user.email.length
            user.phone.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCMixUser",
          "method" => "email_required?",
          "when_true" => { "self" => "PCMixUser & PCMixUser::ValidatedAsEmail" }
        },
        {
          "class" => "PCMixUser",
          "method" => "phone_required?",
          "when_true" => { "self" => "PCMixUser & PCMixUser::ValidatedAsPhone" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__falsy_branch_not_refined_without_when_false
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCFalsyHost
            attr_reader value: String?
            def ready?: () -> bool

            class Validated
              attr_reader value: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          host = PCFalsyHost.new
          unless host.ready?
            host.value.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCFalsyHost",
          "method" => "ready?",
          "when_true" => { "self" => "PCFalsyHost & PCFalsyHost::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 13
              end:
                line: 3
                character: 19
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_postconditions__return_unless_pattern
    # `return X unless cond` narrows the continuation to cond's truthy env.
    # Mirrors `app/models/company.rb#store_code` from order_factory: column
    # readers live on an AR mixin (`GeneratedAttributeMethods`), the
    # predicate is on the class, and the marker module overrides only the
    # column reader.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          module PCRetCompany::GeneratedAttributeMethods
            def code: () -> ::String?
          end

          class PCRetCompany
            include PCRetCompany::GeneratedAttributeMethods
            def store?: () -> bool

            class Validated
            end

            class ValidatedAsStore
              def code: () -> ::String
            end

            def self.first!: () -> (PCRetCompany & PCRetCompany::Validated)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # @type self: PCRetCompany
          company = PCRetCompany.first!
          return "N/A" unless company.store?

          company.code.length
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCRetCompany",
          "method" => "store?",
          "when_true" => { "self" => "PCRetCompany & PCRetCompany::ValidatedAsStore" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # ---------------------------------------------------------------------------
  # via_receiver — Phase 2 (felixefelip/steep#14)
  #
  # Refines the *receiver of the receiver* of a predicate call. Covers
  # delegation patterns: POROs (`def x; y.x; end`) and `has_one through:`.
  # ---------------------------------------------------------------------------

  def test_postconditions__via_receiver_poro_delegation
    # account.profile.display_ready? narrows account.profile (via `self`)
    # AND narrows account itself (via via_receiver), so the delegated
    # accessor `account.nickname` resolves through Account's marker class.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCProfile
            attr_reader nickname: String?
            def display_ready?: () -> bool

            class DisplayReady
              attr_reader nickname: String
            end
          end

          class PCAccount
            attr_reader profile: PCProfile
            def nickname: () -> String?

            class WithDisplayReadyProfile
              def nickname: () -> String
            end

            def self.first: () -> PCAccount
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          account = PCAccount.first
          if account.profile.display_ready?
            account.nickname.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCProfile",
          "method" => "display_ready?",
          "when_true" => {
            "self" => "PCProfile & PCProfile::DisplayReady",
            "via_receiver" => [
              { "through" => "PCAccount#profile",
                "as" => "PCAccount & PCAccount::WithDisplayReadyProfile" }
            ]
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__via_receiver_does_not_match_other_method
    # The via_receiver only fires when the through method matches.
    # Calling .display_ready? on a *different* parent chain (.other.profile.display_ready?)
    # must not narrow the irrelevant host.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCProfile2
            def display_ready?: () -> bool
          end

          class PCOtherHost
            attr_reader profile: PCProfile2
            def nickname: () -> String?
            def self.first: () -> PCOtherHost
          end

          class PCHost
            attr_reader profile: PCProfile2
            def nickname: () -> String?

            class Refined
              def nickname: () -> String
            end

            def self.first: () -> PCHost
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          host = PCOtherHost.first
          if host.profile.display_ready?
            host.nickname.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCProfile2",
          "method" => "display_ready?",
          "when_true" => {
            "via_receiver" => [
              { "through" => "PCHost#profile",
                "as" => "PCHost & PCHost::Refined" }
            ]
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 16
              end:
                line: 3
                character: 22
            severity: ERROR
            message: Type `(::String | nil)` does not have method `upcase`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_postconditions__via_receiver_when_false_branch
    # via_receiver under `when_false` narrows the host in the falsy branch.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCInner
            def fail?: () -> bool
          end

          class PCOuter
            attr_reader inner: PCInner
            def message: () -> String?

            class WhenNotFail
              def message: () -> String
            end

            def self.first: () -> PCOuter
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          outer = PCOuter.first
          unless outer.inner.fail?
            outer.message.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCInner",
          "method" => "fail?",
          "when_false" => {
            "via_receiver" => [
              { "through" => "PCOuter#inner",
                "as" => "PCOuter & PCOuter::WhenNotFail" }
            ]
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__phase1_send_receiver_narrowing
    # Sanity check: Phase 1's `self:` refinement should already narrow a
    # pure-send receiver (account.profile). This isolates whether the
    # bug in compose_with_self is in Phase 2 or pre-existing.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSendProfile
            attr_reader nickname: String?
            def display_ready?: () -> bool

            class Ready
              attr_reader nickname: String
            end
          end

          class PCSendAccount
            attr_reader profile: PCSendProfile
            def self.first: () -> PCSendAccount
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          account = PCSendAccount.first
          if account.profile.display_ready?
            account.profile.nickname.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSendProfile",
          "method" => "display_ready?",
          "when_true" => { "self" => "PCSendProfile & PCSendProfile::Ready" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__via_receiver_composes_with_self
    # Both `self:` and `via_receiver` apply at once: account.profile
    # (the inner receiver) gets the Profile marker AND account gets the
    # Account marker. Accessor on both should narrow.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCComProfile
            attr_reader nickname: String?
            def display_ready?: () -> bool

            class Ready
              attr_reader nickname: String
            end
          end

          class PCComAccount
            attr_reader profile: PCComProfile
            def nickname: () -> String?

            class WithReady
              def nickname: () -> String
            end

            def self.first: () -> PCComAccount
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          account = PCComAccount.first
          if account.profile.display_ready?
            account.profile.nickname.upcase
            account.nickname.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCComProfile",
          "method" => "display_ready?",
          "when_true" => {
            "self" => "PCComProfile & PCComProfile::Ready",
            "via_receiver" => [
              { "through" => "PCComAccount#profile",
                "as" => "PCComAccount & PCComAccount::WithReady" }
            ]
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # ---------------------------------------------------------------------------
  # Ivar postconditions (felixefelip/steep#23)
  #
  # `when_true.ivars` refines the caller's `instance_variable_types`
  # after a self-receiver call. Models Rails `set_company` / form-object
  # `load!(id)` patterns where the method body assigns an ivar to a
  # narrower type than the ivar's declaration.
  # ---------------------------------------------------------------------------

  def test_postconditions__ivars_refined_after_self_call
    # Explicit `set_company` call narrows `@company` from the declared
    # union to the validated branch.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIvarPostCompany
            def self.find: (Integer) -> (PCIvarPostCompany & PCIvarPostCompany::Validated)
          end

          module PCIvarPostCompany::Validated
            def name_required: () -> String
          end

          class PCIvarPostController
            @company: (PCIvarPostCompany & PCIvarPostCompany::Validated) | PCIvarPostCompany

            def set_company: () -> (PCIvarPostCompany & PCIvarPostCompany::Validated)
            def edit: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCIvarPostController
            # @dynamic set_company, edit

            def edit
              set_company
              @company.name_required
            end

            def set_company
              @company = PCIvarPostCompany.find(1)
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIvarPostController",
          "method" => "set_company",
          "unconditional" => {
            "ivars" => { "@company" => "PCIvarPostCompany & PCIvarPostCompany::Validated" }
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__ivars_not_applied_for_non_self_receiver
    # Same shape, but the call is `other.set_company` rather than
    # `set_company`. Refining our `@company` from someone else's call
    # is unsound, so the rule must skip and the validated-only method
    # errors.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIvarPostCompanyB
            def self.find: (Integer) -> (PCIvarPostCompanyB & PCIvarPostCompanyB::Validated)
          end

          module PCIvarPostCompanyB::Validated
            def name_required: () -> String
          end

          class PCIvarPostControllerB
            @company: (PCIvarPostCompanyB & PCIvarPostCompanyB::Validated) | PCIvarPostCompanyB

            def set_company: () -> (PCIvarPostCompanyB & PCIvarPostCompanyB::Validated)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # @type var other: PCIvarPostControllerB
          other = (_ = nil)
          PCIvarPostControllerB.new.instance_eval do
            other.set_company
            @company.name_required
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIvarPostControllerB",
          "method" => "set_company",
          "unconditional" => {
            "ivars" => { "@company" => "PCIvarPostCompanyB & PCIvarPostCompanyB::Validated" }
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 5
                character: 11
              end:
                line: 5
                character: 24
            severity: ERROR
            message: Type `((::PCIvarPostCompanyB & ::PCIvarPostCompanyB::Validated) | ::PCIvarPostCompanyB)`
              does not have method `name_required`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_postconditions__ivars_unconditional_fires_before_conditional_use
    # When a method that narrows an ivar via `unconditional.ivars` is
    # called as the guard of an `if`, the narrowing applies *before*
    # the conditional split — the ivar is already refined in both
    # branches. Validates that `unconditional:` doesn't depend on
    # entering through `apply_postconditions` (which only fires in
    # conditional contexts).
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIvarPostCompanyC
            def self.find: (Integer) -> (PCIvarPostCompanyC & PCIvarPostCompanyC::Validated)
          end

          module PCIvarPostCompanyC::Validated
            def name_required: () -> String
          end

          class PCIvarPostControllerC
            @company: (PCIvarPostCompanyC & PCIvarPostCompanyC::Validated) | PCIvarPostCompanyC

            def setup_then_decide: () -> void
            private def setup: () -> (PCIvarPostCompanyC & PCIvarPostCompanyC::Validated)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCIvarPostControllerC
            # @dynamic setup_then_decide

            def setup_then_decide
              setup
              @company.name_required
            end

            def setup
              @company = PCIvarPostCompanyC.find(1)
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIvarPostControllerC",
          "method" => "setup",
          "unconditional" => {
            "ivars" => { "@company" => "PCIvarPostCompanyC & PCIvarPostCompanyC::Validated" }
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__predicate_from_included_module_matches_by_receiver_type
    # Predicate `verified?` is defined in module `PCVerifiable`, which
    # `PCDocument` includes. The sidecar is keyed on `PCDocument` (the
    # receiver's concrete type), not on the module. Lookup must walk the
    # receiver type to find the entry. Hits the same shape as Rails AR
    # column predicates that live in `Model::GeneratedAttributeMethods`.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          module PCVerifiable
            def verified?: () -> bool
          end

          class PCDocument
            include PCVerifiable
            attr_reader content: String?

            class Verified
              attr_reader content: String
            end

            def self.first!: () -> PCDocument
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          doc = PCDocument.first!
          if doc.verified?
            doc.content.upcase
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCDocument",
          "method" => "verified?",
          "when_true" => { "self" => "PCDocument & PCDocument::Verified" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__via_receiver_matches_intersected_inner_type
    # The inner receiver may already be narrowed (e.g. another marker
    # applied earlier). The `through:` check walks intersections.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCIntInner
            def ready?: () -> bool
          end

          class PCIntHost
            attr_reader inner: PCIntInner
            def value: () -> String?

            class Marker
            end

            class Refined
              def value: () -> String
            end

            def self.first: () -> (PCIntHost & PCIntHost::Marker)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          host = PCIntHost.first
          if host.inner.ready?
            host.value.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCIntInner",
          "method" => "ready?",
          "when_true" => {
            "via_receiver" => [
              { "through" => "PCIntHost#inner",
                "as" => "PCIntHost & PCIntHost::Refined" }
            ]
          }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__dropout_on_attribute_write
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCDropOrderImport
            attr_accessor logistics_operator: PCDropLogisticsOperator?
            def shipment?: () -> bool

            class ValidatedAsShipment
              attr_reader logistics_operator: PCDropLogisticsOperator
            end
          end

          class PCDropLogisticsOperator
            attr_reader name: String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          order_import = PCDropOrderImport.new
          if order_import.shipment?
            order_import.logistics_operator = nil
            order_import.logistics_operator.name
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCDropOrderImport",
          "method" => "shipment?",
          "when_true" => { "self" => "PCDropOrderImport & PCDropOrderImport::ValidatedAsShipment" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 34
              end:
                line: 4
                character: 38
            severity: ERROR
            message: Type `(::PCDropLogisticsOperator | nil)` does not have method `name`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_postconditions__negative_control_no_entry_no_refinement
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCNoEntry
            attr_reader value: String?
            def ready?: () -> bool
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          host = PCNoEntry.new
          if host.ready?
            host.value.length
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
                character: 13
              end:
                line: 3
                character: 19
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  # ---------------------------------------------------------------------------
  # Edge cases — felixefelip/steep#14 issue comment
  #
  # Each test below corresponds to a numbered scenario in the issue thread.
  # Scenarios that depend on undecided semantics (#9 safe-nav) or that fall
  # outside Phase 1/2 scope (#10 arg-dependent, #11 recursive marker) are not
  # covered here. Some tests document *current* behavior of edge cases that
  # may not yet be supported (generics with free vars, union receivers,
  # missing marker classes) — when the behavior changes, the assertion shifts.
  # ---------------------------------------------------------------------------

  # #1 — Predicate inherited from a superclass.
  # Sidecar is keyed on `Base#authenticated?`. The call site uses an `Admin`
  # receiver, which inherits `authenticated?`. Lookup must fall back through
  # `call.method_decls.type_name` (Base) to find the entry.
  def test_postconditions__edge_01_inherited_predicate
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeBase
            attr_reader token: String?
            def authenticated?: () -> bool

            class Authenticated
              attr_reader token: String
            end
          end

          class PCEdgeAdmin < PCEdgeBase
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          admin = PCEdgeAdmin.new
          if admin.authenticated?
            admin.token.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeBase",
          "method" => "authenticated?",
          "when_true" => { "self" => "PCEdgeBase & PCEdgeBase::Authenticated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #3 — Marker references a generic parameter. The sidecar declares
  # `Container[T] & Container::WithValue[T]`. The free type variable `T` in
  # the parsed RBS is not substituted by the factory; `build_instance` raises
  # `Unknown name for build_instance: ::T` from RBS's definition builder.
  # This is a real bug — generic markers are not supported and crash the type
  # check. Skipped until fixed; remove the skip when the factory grows a
  # substitution step for the receiver's generic args.
  def test_postconditions__edge_03_generic_marker
    skip "TODO: generic free var T in postcondition marker crashes RBS::DefinitionBuilder#build_instance"
  end

  # #4 — Union receiver. `pet : (Cat | Dog)` calls `.hungry?`, sidecars on
  # both Cat and Dog. Steep dispatches the call separately for each union
  # member, so narrowing applies independently to each side and both
  # accessors resolve through their respective markers. This passes — locks
  # in the (surprisingly good) current behavior.
  def test_postconditions__edge_04_union_receiver
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeCat
            attr_reader meal_at: String?
            def hungry?: () -> bool

            class Hungry
              attr_reader meal_at: String
            end
          end

          class PCEdgeDog
            attr_reader meal_at: String?
            def hungry?: () -> bool

            class Hungry
              attr_reader meal_at: String
            end
          end

          class PCEdgePetFactory
            def self.pet: () -> (PCEdgeCat | PCEdgeDog)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          pet = PCEdgePetFactory.pet
          if pet.hungry?
            pet.meal_at.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeCat",
          "method" => "hungry?",
          "when_true" => { "self" => "PCEdgeCat & PCEdgeCat::Hungry" }
        },
        {
          "class" => "PCEdgeDog",
          "method" => "hungry?",
          "when_true" => { "self" => "PCEdgeDog & PCEdgeDog::Hungry" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #6 — Nested control flow. Two predicates on the same receiver compose
  # into `Door & Locked & Open` inside the inner branch.
  def test_postconditions__edge_06_nested_control_flow
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeDoor
            attr_reader key: String?
            attr_reader log: String?
            def locked?: () -> bool
            def open?: () -> bool

            class Locked
              attr_reader key: String
            end

            class Open
              attr_reader log: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          door = PCEdgeDoor.new
          if door.locked?
            if door.open?
              door.key.length
              door.log.length
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeDoor",
          "method" => "locked?",
          "when_true" => { "self" => "PCEdgeDoor & PCEdgeDoor::Locked" }
        },
        {
          "class" => "PCEdgeDoor",
          "method" => "open?",
          "when_true" => { "self" => "PCEdgeDoor & PCEdgeDoor::Open" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #7 — Rebinding the local variable inside the truthy branch drops the
  # narrowing. After `user = PCEdgeUser.new`, the previous refinement no
  # longer applies, so `user.name` is back to `String?`.
  def test_postconditions__edge_07_rebind_invalidates
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeUser
            attr_reader name: String?
            def valid?: () -> bool

            class Validated
              attr_reader name: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          user = PCEdgeUser.new
          if user.valid?
            user = PCEdgeUser.new
            user.name.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeUser",
          "method" => "valid?",
          "when_true" => { "self" => "PCEdgeUser & PCEdgeUser::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 12
              end:
                line: 4
                character: 18
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  # #8 — `case` with predicate-based when clauses. Each branch narrows the
  # receiver independently to that branch's marker.
  def test_postconditions__edge_08_case_when_predicates
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeOrder
            attr_reader draft_log: String?
            attr_reader published_log: String?
            def draft?: () -> bool
            def published?: () -> bool

            class DraftOrder
              attr_reader draft_log: String
            end

            class PublishedOrder
              attr_reader published_log: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          order = PCEdgeOrder.new
          case
          when order.draft?     then order.draft_log.length
          when order.published? then order.published_log.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeOrder",
          "method" => "draft?",
          "when_true" => { "self" => "PCEdgeOrder & PCEdgeOrder::DraftOrder" }
        },
        {
          "class" => "PCEdgeOrder",
          "method" => "published?",
          "when_true" => { "self" => "PCEdgeOrder & PCEdgeOrder::PublishedOrder" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #12 — Sidecar marker references a class that does not exist in RBS.
  # `Postconditions::Branch#rbs_type` parses the marker string optimistically
  # and `factory.type` builds an `AST::Types::Name::Instance` pointing at the
  # non-existent class. Later, when the type checker tries to resolve methods
  # on the intersection, `RBS::DefinitionBuilder#build_instance` raises
  # `Unknown name for build_instance: ::Host::DoesNotExist`. Same root cause
  # as edge_03 — the failure surfaces as `Ruby::UnexpectedError`, not as a
  # graceful "marker missing" diagnostic.
  #
  # Skipped until there is a fail-safe: either validate marker names at
  # sidecar load (preferred — same fix as `rbs_definition_resolver`), or
  # rescue the build error and degrade to no narrowing for this entry.
  def test_postconditions__edge_12_missing_marker_class
    skip "TODO: postcondition marker referencing a missing RBS class crashes RBS::DefinitionBuilder#build_instance; add fail-safe at sidecar load"
  end

  # #13 — `return unless` chain where the second guard contradicts the first
  # narrowing. Both branches narrow the receiver to different markers; the
  # code after both guards is unreachable in practice. Documents the
  # composed-narrowing behavior past two guards (no false diagnostics on the
  # third statement just because the intersection becomes unsatisfiable).
  def test_postconditions__edge_13_contradiction_guards
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeContradiction
            attr_reader status: String?
            def draft?: () -> bool
            def published?: () -> bool

            class DraftOrder
              attr_reader status: String
            end

            class PublishedOrder
              attr_reader status: String
            end

            def self.new!: () -> PCEdgeContradiction
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          order = PCEdgeContradiction.new!
          return unless order.draft?
          return unless order.published?
          order.status.length
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeContradiction",
          "method" => "draft?",
          "when_true" => { "self" => "PCEdgeContradiction & PCEdgeContradiction::DraftOrder" }
        },
        {
          "class" => "PCEdgeContradiction",
          "method" => "published?",
          "when_true" => { "self" => "PCEdgeContradiction & PCEdgeContradiction::PublishedOrder" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #14 — Bang vs question mark. Conventionally `loaded!` is impure (mutates
  # state) and `loaded?` is pure. The user's intent was that postconditions
  # should *only* fire on pure calls, so `loaded!` would not narrow.
  # Current behavior: `pure?` for an RBS-declared method is determined by
  # the call site (no Ruby def body to inspect), and the `!` suffix is not
  # treated as an impurity marker. Both calls narrow.
  #
  # This test locks in current behavior. If/when bang methods are classified
  # impure-by-convention for postcondition lookup, flip the expectation:
  # the `cache_a.data.size` line should then raise a NoMethod on (Hash | nil).
  def test_postconditions__edge_14_bang_predicate_currently_narrows
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeCache
            attr_reader data: Hash[String, untyped]?
            def loaded!: () -> Hash[String, untyped]
            def loaded?: () -> bool

            class Loaded
              attr_reader data: Hash[String, untyped]
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          cache_a = PCEdgeCache.new
          if cache_a.loaded!
            cache_a.data.size
          end

          cache_b = PCEdgeCache.new
          if cache_b.loaded?
            cache_b.data.size
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeCache",
          "method" => "loaded!",
          "when_true" => { "self" => "PCEdgeCache & PCEdgeCache::Loaded" }
        },
        {
          "class" => "PCEdgeCache",
          "method" => "loaded?",
          "when_true" => { "self" => "PCEdgeCache & PCEdgeCache::Loaded" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # #15 — Narrowing inside a block. `item.valid?` narrows `item` within the
  # truthy branch of the if, but does not leak past the if (still inside the
  # `each` block) nor across iterations.
  def test_postconditions__edge_15_loop_block
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeItem
            attr_reader payload: String?
            def valid?: () -> bool

            class Validated
              attr_reader payload: String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          items = [PCEdgeItem.new] #: Array[PCEdgeItem]
          items.each do |item|
            if item.valid?
              item.payload.length
            end
            item.payload.length
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeItem",
          "method" => "valid?",
          "when_true" => { "self" => "PCEdgeItem & PCEdgeItem::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 15
              end:
                line: 6
                character: 21
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  # #16 — Marker ordering in an intersection. When two predicates narrow
  # overlapping accessors with different return types, `intersection_shape`
  # follows last-wins: the last marker in the intersection determines which
  # method definition wins for an overlapping name. This locks the current
  # behavior so reordering the markers in the sidecar can't regress silently.
  def test_postconditions__edge_16_marker_last_wins
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEdgeFoo
            def code: () -> String?
            def m1?: () -> bool
            def m2?: () -> bool

            class Marker1
              def code: () -> String
            end

            class Marker2
              def code: () -> Integer
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          foo = PCEdgeFoo.new
          if foo.m1? && foo.m2?
            x = foo.code #: Integer
            x + 1
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCEdgeFoo",
          "method" => "m1?",
          "when_true" => { "self" => "PCEdgeFoo & PCEdgeFoo::Marker1" }
        },
        {
          "class" => "PCEdgeFoo",
          "method" => "m2?",
          "when_true" => { "self" => "PCEdgeFoo & PCEdgeFoo::Marker2" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  # ---------------------------------------------------------------------------
  # felixefelip/steep#25: postcondition narrowing of `self`
  #
  # Before the fix, `refine_node_type` had no `:self` case, so a postcondition
  # whose receiver is `self` (implicit `if save` or explicit `if self.save`
  # inside a method body) fell through to `[env, env]` and never narrowed.
  # The fix routes those refinements to `TypeEnv#refined_self_type`, which
  # overlays `Context::ModuleContext#self_type` for the narrowed branch.
  # ---------------------------------------------------------------------------

  def test_postconditions__self_refines_implicit_self_call
    # `if save` is dispatched with `receiver = nil` (implicit self).
    # Inside the truthy branch, `name.camelize` is also implicit-self;
    # both reads should see `self` as `PCSelfModel & PCSelfModel::Validated`
    # so `name` returns `String` (non-nil) and `.camelize` resolves.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSelfModel
            def name: () -> String?
            def save: () -> bool
            def teste2: () -> String?

            class Validated
              def name: () -> String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCSelfModel
            # @dynamic name, save
            def teste2
              if save
                name
              end
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSelfModel",
          "method" => "save",
          "when_true" => { "self" => "PCSelfModel & PCSelfModel::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__self_refines_explicit_self_call
    # Same shape but the receiver is `:self` (an AST node) instead of
    # nil. The `:self` case in `refine_node_type` should still write to
    # `env.refined_self_type` and the inner read of `name` (implicit
    # self) should pick that up.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSelfExplicit
            def name: () -> String?
            def save: () -> bool
            def teste2: () -> String?

            class Validated
              def name: () -> String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCSelfExplicit
            # @dynamic name, save
            def teste2
              if self.save
                name
              end
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSelfExplicit",
          "method" => "save",
          "when_true" => { "self" => "PCSelfExplicit & PCSelfExplicit::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__self_does_not_leak_to_falsy_branch
    # In the `else` branch — where `save` returned a falsy value and
    # no `when_false` postcondition was declared — `self` must remain
    # at its declared (widest) shape. Reading `name` from there is
    # still `String?`, so the truthy-branch `String`-only `.length`
    # call inside the else MUST flag an error.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSelfLeak
            def name: () -> String?
            def save: () -> bool
            def teste2: () -> Integer?

            class Validated
              def name: () -> String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCSelfLeak
            # @dynamic name, save
            def teste2
              if save
                nil
              else
                name.length
              end
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSelfLeak",
          "method" => "save",
          "when_true" => { "self" => "PCSelfLeak & PCSelfLeak::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 7
                character: 11
              end:
                line: 7
                character: 17
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_postconditions__refined_self_composes_with_and
    # Both predicates refine self. Inside the truthy branch of
    # `save && valid?`, self must be `Model & Validated & Active` so
    # both `name` (from Validated) and `tag` (from Active) resolve to
    # non-nil readers. This verifies that `refined_self_type` composes
    # via intersection across `&&`.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSelfAnd
            def name: () -> String?
            def tag: () -> String?
            def save: () -> bool
            def valid?: () -> bool
            def teste2: () -> String?

            class Validated
              def name: () -> String
            end

            class Active
              def tag: () -> String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCSelfAnd
            # @dynamic name, tag, save, valid?
            def teste2
              if save && valid?
                name
                tag
              end
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSelfAnd",
          "method" => "save",
          "when_true" => { "self" => "PCSelfAnd & PCSelfAnd::Validated" }
        },
        {
          "class" => "PCSelfAnd",
          "method" => "valid?",
          "when_true" => { "self" => "PCSelfAnd & PCSelfAnd::Active" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_postconditions__refined_self_cleared_on_method_entry
    # A refinement applied in `method_a` (inside its `if save` branch)
    # must NOT survive into `method_b`'s body. The env is rebuilt on
    # method entry, so `refined_self_type` starts as `nil` again and
    # `name.length` in `method_b` flags a NoMethod against `String?`.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCSelfReset
            def name: () -> String?
            def save: () -> bool
            def method_a: () -> String?
            def method_b: () -> Integer

            class Validated
              def name: () -> String
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCSelfReset
            # @dynamic name, save
            def method_a
              if save
                name
              end
            end

            def method_b
              name.length
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCSelfReset",
          "method" => "save",
          "when_true" => { "self" => "PCSelfReset & PCSelfReset::Validated" }
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 10
                character: 9
              end:
                line: 10
                character: 15
            severity: ERROR
            message: Type `(::String | nil)` does not have method `length`
            code: Ruby::NoMethod
      YAML
    )
  end

  # ---------------------------------------------------------------------------
  # felixefelip/steep#27: generic callback sidecar.
  #
  # When `.steep_callbacks.yml` declares that handler H runs before
  # method M of class C, Steep applies H's `unconditional` postcondition
  # to M's initial env. This lets `before_action :set_post`-style hooks
  # (translated by the generator into the sidecar) refine ivars at the
  # entry of every action they cover, without H being called explicitly
  # in M's body.
  # ---------------------------------------------------------------------------

  def callbacks_store(entries)
    Steep::Callbacks::Store.from_hash(
      { "callbacks" => entries },
      source: "test"
    )
  end

  def test_callbacks__refines_ivar_at_method_entry
    # `set_post` writes `@post: PCBaCompany & Validated`. The callback
    # declares it runs before `show`. Inside `show`'s body, `@post.title`
    # must typecheck because the env starts with the refinement already
    # applied. Without the callback hook, `@post` stays at the declared
    # nilable union and `@post.title` flags NoMethod.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCBaCompany
            def self.find: (Integer) -> (PCBaCompany & PCBaCompany::Validated)
          end

          module PCBaCompany::Validated
            def title: () -> String
          end

          class PCBaController
            @company: (PCBaCompany & PCBaCompany::Validated) | PCBaCompany | nil

            def show: () -> String
            def set_company: () -> (PCBaCompany & PCBaCompany::Validated)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCBaController
            # @dynamic show, set_company
            def show
              @company.title
            end

            def set_company
              @company = PCBaCompany.find(1)
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCBaController",
          "method" => "set_company",
          "unconditional" => {
            "ivars" => { "@company" => "PCBaCompany & PCBaCompany::Validated" }
          }
        }
      ]),
      callbacks: callbacks_store([
        {
          "class" => "PCBaController",
          "apply_postcondition_of" => "set_company",
          "runs_before" => ["show"]
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_callbacks__methods_not_in_runs_before_stay_at_declared_type
    # `set_company runs_before [show]` — but `index` is NOT covered. In
    # `index`, `@company` must remain at the declared nilable union, so
    # `@company.title` reports NoMethod on `nil`.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCNotCoveredCompany
            def self.find: (Integer) -> (PCNotCoveredCompany & PCNotCoveredCompany::Validated)
          end

          module PCNotCoveredCompany::Validated
            def title: () -> String
          end

          class PCNotCoveredController
            @company: (PCNotCoveredCompany & PCNotCoveredCompany::Validated) | PCNotCoveredCompany | nil

            def show: () -> String
            def index: () -> String?
            def set_company: () -> (PCNotCoveredCompany & PCNotCoveredCompany::Validated)
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCNotCoveredController
            # @dynamic show, index, set_company
            def index
              @company.title
            end

            def show
              @company.title
            end

            def set_company
              @company = PCNotCoveredCompany.find(1)
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCNotCoveredController",
          "method" => "set_company",
          "unconditional" => {
            "ivars" => { "@company" => "PCNotCoveredCompany & PCNotCoveredCompany::Validated" }
          }
        }
      ]),
      callbacks: callbacks_store([
        {
          "class" => "PCNotCoveredController",
          "apply_postcondition_of" => "set_company",
          "runs_before" => ["show"]
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 13
              end:
                line: 4
                character: 18
            severity: ERROR
            message: Type `((::PCNotCoveredCompany & ::PCNotCoveredCompany::Validated) | ::PCNotCoveredCompany
              | nil)` does not have method `title`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_callbacks__handler_without_unconditional_postcondition_is_ignored
    # Callback references `set_company`, but `set_company` has only a
    # `when_true` postcondition (or none at all). The callback hook
    # silently no-ops — body sees `@company` at the declared widest
    # type, errors out as if no callback was declared.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCNoUncondCompany
            def self.find: (Integer) -> PCNoUncondCompany
            def specific_method: () -> Integer
          end

          class PCNoUncondController
            @company: PCNoUncondCompany | nil

            def show: () -> Integer
            def set_company: () -> PCNoUncondCompany
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCNoUncondController
            # @dynamic show, set_company
            def show
              @company.specific_method
            end

            def set_company
              @company = PCNoUncondCompany.find(1)
            end
          end
        RUBY
      },
      # No postconditions store entry → callback hook finds nothing to apply.
      callbacks: callbacks_store([
        {
          "class" => "PCNoUncondController",
          "apply_postcondition_of" => "set_company",
          "runs_before" => ["show"]
        }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 13
              end:
                line: 4
                character: 28
            severity: ERROR
            message: Type `(::PCNoUncondCompany | nil)` does not have method `specific_method`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_callbacks__multiple_handlers_compose_via_last_wins
    # Two callbacks for `show`: `set_company` and `set_extra`. Each
    # writes a distinct ivar. Both refinements must compose so the body
    # sees BOTH ivars narrowed at entry.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCMultiCompany
            def self.find: (Integer) -> (PCMultiCompany & PCMultiCompany::Validated)
          end

          module PCMultiCompany::Validated
            def title: () -> String
          end

          class PCMultiExtra
            def label: () -> String
          end

          class PCMultiController
            @company: (PCMultiCompany & PCMultiCompany::Validated) | PCMultiCompany | nil
            @extra: PCMultiExtra | nil

            def show: () -> Integer
            def set_company: () -> (PCMultiCompany & PCMultiCompany::Validated)
            def set_extra: () -> PCMultiExtra
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCMultiController
            # @dynamic show, set_company, set_extra
            def show
              @company.title.length + @extra.label.length
            end

            def set_company
              @company = PCMultiCompany.find(1)
            end

            def set_extra
              @extra = PCMultiExtra.new
            end
          end
        RUBY
      },
      postconditions: postconditions_store([
        {
          "class" => "PCMultiController",
          "method" => "set_company",
          "unconditional" => {
            "ivars" => { "@company" => "PCMultiCompany & PCMultiCompany::Validated" }
          }
        },
        {
          "class" => "PCMultiController",
          "method" => "set_extra",
          "unconditional" => {
            "ivars" => { "@extra" => "PCMultiExtra" }
          }
        }
      ]),
      callbacks: callbacks_store([
        { "class" => "PCMultiController", "apply_postcondition_of" => "set_company", "runs_before" => ["show"] },
        { "class" => "PCMultiController", "apply_postcondition_of" => "set_extra",   "runs_before" => ["show"] }
      ]),
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_callbacks__empty_store_no_op
    # Regression guard: passing the default empty store must NOT change
    # behavior. Body sees the declared nilable ivar and errors as
    # before.
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class PCEmptyCompany
            def specific_method: () -> Integer
          end

          class PCEmptyController
            @company: PCEmptyCompany | nil

            def show: () -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class PCEmptyController
            # @dynamic show
            def show
              @company.specific_method
            end
          end
        RUBY
      },
      # No callbacks passed → default empty store.
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 13
              end:
                line: 4
                character: 28
            severity: ERROR
            message: Type `(::PCEmptyCompany | nil)` does not have method `specific_method`
            code: Ruby::NoMethod
      YAML
    )
  end
end
