require_relative "test_helper"

# Unit tests for the return-alias source walk (felixefelip/steep#62): a method
# returning a local whose attributes were assigned self paths exposes those as
# aliases on its result.
class ReturnAliasAnalyzerTest < Minitest::Test
  ReturnAliasAnalyzer = Steep::TypeInference::ReturnAliasAnalyzer

  def analyze(source)
    parser = Steep::Source.new_parser
    buffer = ::Parser::Source::Buffer.new("<test>")
    buffer.source = source
    ReturnAliasAnalyzer.analyze(parser.parse(buffer))
  end

  def test_maps_returned_local_attr_to_self_path
    result = analyze(<<~RUBY)
      class Proxy
        def build(*)
          record = Assignment.new
          record.post = owner
          record
        end
      end
    RUBY

    assert_equal({ "Proxy#build" => { post: [:owner] } }, result)
  end

  def test_ignores_write_to_a_non_returned_local
    result = analyze(<<~RUBY)
      class Proxy
        def build
          other = Assignment.new
          other.post = owner
          record = Assignment.new
          record
        end
      end
    RUBY

    assert_empty result
  end

  def test_ignores_non_self_rhs
    result = analyze(<<~RUBY)
      class Proxy
        def build(arg)
          record = Assignment.new
          record.post = arg
          record
        end
      end
    RUBY

    assert_empty result
  end
end
