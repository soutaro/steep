require_relative "test_helper"

# Unit tests for the return-forwarding source walk (felixefelip/steep#62): a
# method returning `K.new(..., self)` forwards K's `self`-bound readers to the
# call's own receiver.
class ReturnForwardingAnalyzerTest < Minitest::Test
  ReturnForwardingAnalyzer = Steep::TypeInference::ReturnForwardingAnalyzer

  # Minimal ConstructorBindingRegistry stand-in.
  class Bindings
    def initialize(map) = @map = map
    def bindings_for(name) = @map[name.to_s.sub(/\A::/, "")]
  end

  def analyze(source, bindings)
    parser = Steep::Source.new_parser
    buffer = ::Parser::Source::Buffer.new("<test>")
    buffer.source = source
    ReturnForwardingAnalyzer.analyze(parser.parse(buffer), constructor_bindings: bindings)
  end

  def test_forwards_reader_bound_to_self_argument
    result = analyze(<<~RUBY, Bindings.new("Proxy" => { owner: 1 }))
      class Post
        def assignments
          Proxy.new(Assignment, self)
        end
      end
    RUBY

    assert_equal({ "Post#assignments" => Set[:owner] }, result)
  end

  def test_no_forward_when_argument_is_not_self
    result = analyze(<<~RUBY, Bindings.new("Proxy" => { owner: 1 }))
      class Post
        def assignments(other)
          Proxy.new(Assignment, other)
        end
      end
    RUBY

    assert_empty result
  end

  def test_no_forward_without_constructor_binding
    result = analyze(<<~RUBY, Bindings.new({}))
      class Post
        def assignments
          Proxy.new(Assignment, self)
        end
      end
    RUBY

    assert_empty result
  end
end
