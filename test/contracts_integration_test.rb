require_relative "test_helper"

class ContractsIntegrationTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Contracts = Steep::Contracts
  Diagnostic = Steep::Diagnostic

  CONTRACT_RBS = <<~RBS
    class Foo
      attr_reader name: String?
      def use_name: () -> Integer
      def caller_bad: () -> Integer
      def caller_good: () -> Integer?
    end
  RBS

  def use_name_contract
    Contracts::Store.from_hash(
      {
        "version" => 1,
        "methods" => {
          "Foo#use_name" => {
            "requires" => [
              { "kind" => "not_nil",
                "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
            ]
          }
        }
      },
      source: "<test>"
    )
  end

  def unenforced_name_contract
    Contracts::Store.from_hash(
      {
        "version" => 1,
        "methods" => {
          "Foo#use_name" => {
            "enforced" => false,
            "requires" => [
              { "kind" => "not_nil",
                "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
            ]
          }
        }
      },
      source: "<test>"
    )
  end

  def test_unenforced_contract_does_not_narrow_body
    with_checker(CONTRACT_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::Foo
        def use_name
          name.size
        end
      RUBY

      with_standard_construction(checker, source, contracts: unenforced_name_contract) do |construction, typing|
        construction.synthesize(source.node)

        no_method_errors = typing.errors.grep(Diagnostic::Ruby::NoMethod)
        refute_empty no_method_errors,
                     "an unenforced contract must NOT narrow the body, so `name.size` on String? still errors"
      end
    end
  end

  def test_contract_narrows_pure_receiver_inside_body
    with_checker(CONTRACT_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::Foo
        def use_name
          name.size
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_name_contract) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors.map(&:header_line),
                     "expected no errors when contract narrows `name` to String, got: #{typing.errors.map(&:header_line)}"
      end
    end
  end

  def test_caller_without_nil_check_emits_precondition_diagnostic
    with_checker(CONTRACT_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::Foo
        def caller_bad
          use_name
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_name_contract) do |construction, typing|
        construction.synthesize(source.node)

        precondition_errors = typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied)
        assert_equal 1, precondition_errors.size,
                     "expected exactly one PreconditionUnsatisfied diagnostic, got: #{typing.errors.map(&:header_line)}"
        assert_equal :use_name, precondition_errors.first.method_name
      end
    end
  end

  def test_caller_with_nil_check_does_not_emit_diagnostic
    with_checker(CONTRACT_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::Foo
        def caller_good
          if name
            use_name
          end
        end
      RUBY

      with_standard_construction(checker, source, contracts: use_name_contract) do |construction, typing|
        construction.synthesize(source.node)

        precondition_errors = typing.errors.grep(Diagnostic::Ruby::PreconditionUnsatisfied)
        assert_empty precondition_errors,
                     "expected no PreconditionUnsatisfied diagnostic when caller checks self.name first"
      end
    end
  end

  def test_no_contract_means_no_change_in_behavior
    with_checker(CONTRACT_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type self: ::Foo
        def use_name
          name.size
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        no_method_errors = typing.errors.grep(Diagnostic::Ruby::NoMethod)
        refute_empty no_method_errors,
                     "without a contract, `name.size` on String? should still report a NoMethod error"
      end
    end
  end
end
