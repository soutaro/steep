require_relative "test_helper"

# Unit tests for the source-walking part of the constructor reader→parameter
# binding pipeline (felixefelip/steep#60). The analyzer only recognizes shapes;
# the `.new`-site translation happens in `TypeConstruction` and is covered by
# integration tests.
class ConstructorBindingAnalyzerTest < Minitest::Test
  ConstructorBindingAnalyzer = Steep::TypeInference::ConstructorBindingAnalyzer

  def parse(source)
    parser = Steep::Source.new_parser
    buffer = ::Parser::Source::Buffer.new("<test>")
    buffer.source = source
    parser.parse(buffer)
  end

  def analyze(source)
    ConstructorBindingAnalyzer.analyze(parse(source))
  end

  def test_maps_reader_to_its_constructor_parameter_index
    result = analyze(<<~RUBY)
      class Proxy
        def initialize(klass, owner)
          @owner = owner
        end

        def owner
          @owner
        end
      end
    RUBY

    assert_equal({ "Proxy" => { owner: 1 } }, result)
  end

  def test_handles_endless_reader_and_nested_class_names
    result = analyze(<<~RUBY)
      module Post_Assignment
        class ActiveRecord_Associations_CollectionProxy
          def initialize(klass, owner)
            @owner = owner
          end

          def owner = @owner
        end
      end
    RUBY

    assert_equal(
      { "Post_Assignment::ActiveRecord_Associations_CollectionProxy" => { owner: 1 } },
      result
    )
  end

  def test_maps_multiple_readers
    result = analyze(<<~RUBY)
      class Pair
        def initialize(left, right)
          @left = left
          @right = right
        end

        def left = @left
        def right = @right
      end
    RUBY

    assert_equal({ "Pair" => { left: 0, right: 1 } }, result)
  end

  def test_ignores_reader_whose_ivar_is_not_a_constructor_parameter
    # `@name` is not assigned from a parameter, so `name` has no binding.
    result = analyze(<<~RUBY)
      class Thing
        def initialize(owner)
          @owner = owner
          @name = "x"
        end

        def owner = @owner
        def name = @name
      end
    RUBY

    assert_equal({ "Thing" => { owner: 0 } }, result)
  end

  def test_ignores_computed_reader
    # A reader whose body is not exactly `@ivar` is not a stable projection of
    # the constructor argument, so it must not be mapped.
    result = analyze(<<~RUBY)
      class Thing
        def initialize(owner)
          @owner = owner
        end

        def owner
          @owner || raise
        end
      end
    RUBY

    assert_empty result
  end

  def test_ignores_class_without_matching_binding
    result = analyze(<<~RUBY)
      class Plain
        def hello = "hi"
      end
    RUBY

    assert_empty result
  end
end
