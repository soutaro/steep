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

  def run_type_check_test(signatures: {}, code: {}, expectations: nil)
    typings = {}

    with_factory(signatures, nostdlib: false) do |factory|
      builder = Interface::Builder.new(factory)
      subtyping = Subtyping::Check.new(builder: builder)

      code.each do |path, content|
        source = Source.parse(content, path: path, factory: factory)
        with_standard_construction(subtyping, source) do |construction, typing|
          construction.synthesize(source.node)

          typings[path] = typing
        end
      end
    end

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

    yield typings if block_given?
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
              if value
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
end
