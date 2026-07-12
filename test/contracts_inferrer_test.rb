require_relative "test_helper"

class ContractsInferrerTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Contracts = Steep::Contracts

  RBS_FIXTURE = <<~RBS
    class Foo
      attr_reader name: String?
      attr_reader inner: Bar
      def helper: () -> Integer
      def chain_helper: () -> Integer
      def safe_helper: () -> Integer
      def explicit_self_helper: () -> Integer
    end

    class Bar
      attr_reader value: String?
    end
  RBS

  def infer_for(ruby)
    contracts = nil
    with_checker(RBS_FIXTURE) do |checker|
      source = parse_ruby(ruby)
      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        contracts = Contracts::Inferrer.infer(source, typing, return_aliases: {})
      end
    end
    contracts
  end

  def test_infers_not_nil_for_self_method_in_class_body
    contracts = infer_for(<<~RUBY)
      class Foo
        def helper
          name.size
        end
      end
    RUBY

    assert_equal 1, contracts.size
    c = contracts.first
    assert_equal "Foo", c.type_name
    assert_equal :helper, c.method_name
    refute c.singleton

    req = c.requires.first
    assert_instance_of Contracts::Predicate::NotNil, req
    assert_instance_of Contracts::Expr::Send, req.expr
    assert_instance_of Contracts::Expr::SelfRef, req.expr.receiver
    assert_equal :name, req.expr.method
    assert_empty req.expr.chain
  end

  def test_infers_chain_obligation
    contracts = infer_for(<<~RUBY)
      class Foo
        def chain_helper
          inner.value.size
        end
      end
    RUBY

    assert_equal 1, contracts.size
    req = contracts.first.requires.first
    assert_equal :inner, req.expr.method
    assert_equal [:value], req.expr.chain
  end

  def test_handles_explicit_self_receiver
    contracts = infer_for(<<~RUBY)
      class Foo
        def explicit_self_helper
          self.name.size
        end
      end
    RUBY

    assert_equal 1, contracts.size
    assert_equal :name, contracts.first.requires.first.expr.method
  end

  def test_emits_nothing_when_body_is_already_safe
    contracts = infer_for(<<~RUBY)
      class Foo
        def safe_helper
          1 + 2
        end
      end
    RUBY

    assert_empty contracts
  end

  def test_ignores_non_self_receivers
    contracts = infer_for(<<~RUBY)
      class Foo
        def helper
          arg = name
          arg.size
        end
      end
    RUBY

    assert_empty contracts,
                 "expected no contract when the failing receiver is a local, got: #{contracts.map(&:type_name)}"
  end

  def test_emits_fully_qualified_name_for_nested_class
    rbs = <<~RBS
      module Outer
        class Inner
          attr_reader name: String?
          def helper: () -> Integer
        end
      end
    RBS

    contracts = nil
    with_checker(rbs) do |checker|
      source = parse_ruby(<<~RUBY)
        module Outer
          class Inner
            def helper
              name.size
            end
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        contracts = Contracts::Inferrer.infer(source, typing, return_aliases: {})
      end
    end

    assert_equal 1, contracts.size
    assert_equal "Outer::Inner", contracts.first.type_name,
                 "expected fully-qualified type name, got: #{contracts.first.type_name}"
  end

  def test_handles_deeply_nested_modules_and_classes
    rbs = <<~RBS
      module A
        module B
          class C
            attr_reader name: String?
            def helper: () -> Integer
          end
        end
      end
    RBS

    contracts = nil
    with_checker(rbs) do |checker|
      source = parse_ruby(<<~RUBY)
        module A
          module B
            class C
              def helper
                name.size
              end
            end
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        contracts = Contracts::Inferrer.infer(source, typing, return_aliases: {})
      end
    end

    assert_equal 1, contracts.size
    assert_equal "A::B::C", contracts.first.type_name
  end

  def test_handles_class_inside_class
    rbs = <<~RBS
      class Outer
        class Inner
          attr_reader name: String?
          def helper: () -> Integer
        end
      end
    RBS

    contracts = nil
    with_checker(rbs) do |checker|
      source = parse_ruby(<<~RUBY)
        class Outer
          class Inner
            def helper
              name.size
            end
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        contracts = Contracts::Inferrer.infer(source, typing, return_aliases: {})
      end
    end

    assert_equal 1, contracts.size
    assert_equal "Outer::Inner", contracts.first.type_name
  end

  def test_dedupes_same_obligation_across_uses
    contracts = infer_for(<<~RUBY)
      class Foo
        def helper
          name.size
          name.upcase
        end
      end
    RUBY

    assert_equal 1, contracts.size
    assert_equal 1, contracts.first.requires.size
  end
end
