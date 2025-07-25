require_relative "test_helper"

# @rbs use Steep::*

class LocatorTest < Minitest::Test
  include Steep
  include TestHelper
  include FactoryHelper

  def test_ruby__find
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
class Foo
end
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
class Foo
  def bar
    puts "hello"
  end
end
      RUBY

      locator = Locator::Ruby.new(source)

      # Test finding at the beginning of 'puts'
      locator.find(3, 4).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :send, result.node.type
        assert_equal 'puts "hello"', result.node.location.expression.source
        assert_equal [:def, :class], result.parents.map(&:type)
      end

      # Test finding in the middle of 'puts'
      locator.find(3, 9).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :str, result.node.type
        assert_equal '"hello"', result.node.location.expression.source
        assert_equal [:send, :def, :class], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__params
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
class Foo
end
      RBS
      source = parse_ruby(<<-'RUBY', factory: factory)
class Foo
  def bar(x, y = 123)
  end
end
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(2, 10).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :arg, result.node.type
        assert_equal 'x', result.node.location.expression.source
        assert_equal [:args, :def, :class], result.parents.map(&:type)
      end

      locator.find(2, 17).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :int, result.node.type
        assert_equal '123', result.node.location.expression.source
        assert_equal [:optarg, :args, :def, :class], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__dstr
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS
      source = parse_ruby(<<-'RUBY', factory: factory)
x = "#{123}"
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 8).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :int, result.node.type
        assert_equal '123', result.node.location.expression.source
        assert_equal [:begin, :dstr, :lvasgn], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__block
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS
      source = parse_ruby(<<-'RUBY', factory: factory)
[1, 2, 3].map {|x| x + 1 }
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 1).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :int, result.node.type
        assert_equal '1', result.node.location.expression.source
        assert_equal [:array, :send, :block], result.parents.map(&:type)
      end

      locator.find(1, 14).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :block, result.node.type
        assert_equal '[1, 2, 3].map {|x| x + 1 }', result.node.location.expression.source
        assert_equal [], result.parents.map(&:type)
      end

      locator.find(1, 22).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :send, result.node.type
        assert_equal 'x + 1', result.node.location.expression.source
        assert_equal [:block], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__heredoc
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS
      source = parse_ruby(<<-'RUBY', factory: factory)
[<<TEXT, <<TEXT2]
hello
TEXT
#{1+2}
TEXT2
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 8).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :array, result.node.type
        assert_equal '[<<TEXT, <<TEXT2]', result.node.location.expression.source
        assert_equal [], result.parents.map(&:type)
      end

      locator.find(1, 3).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :str, result.node.type
        assert_equal '<<TEXT', result.node.location.expression.source
        assert_equal [:array], result.parents.map(&:type)
      end

      locator.find(2, 3).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :str, result.node.type
        assert_equal '<<TEXT', result.node.location.expression.source
        assert_equal [:array], result.parents.map(&:type)
      end

      locator.find(4, 3).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :int, result.node.type
        assert_equal '1', result.node.location.expression.source
        assert_equal [:send, :begin, :dstr, :array], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__assertion
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
path = nil #: Pathname?
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 3).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :lvasgn, result.node.type
        assert_equal 'path = nil #: Pathname?', result.node.location.expression.source
        assert_equal [], result.parents.map(&:type)
      end

      locator.find(1, 11).tap do |result|
        assert_instance_of Locator::TypeAssertionResult, result

        assert_equal 'nil #: Pathname?', result.node.node.location.expression.source
        assert_equal :assertion, result.node.node.type
        assert_equal [:lvasgn], result.node.parents.map(&:type)
      end

      locator.find(1, 8).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :nil, result.node.type
        assert_equal 'nil', result.node.location.expression.source
        assert_equal [:assertion, :lvasgn], result.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__application
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
[].yield_self { nil } #$ String?
[].yield_self { nil } #$
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 3).tap do |result|
        assert_instance_of Locator::NodeResult, result
        assert_equal :send, result.node.type
        assert_equal '[].yield_self', result.node.location.expression.source
        assert_equal [:block, :tapp, :begin], result.parents.map(&:type)
      end

      locator.find(1, 27).tap do |result|
        assert_instance_of Locator::TypeApplicationResult, result
        assert_equal '[].yield_self { nil } #$ String?', result.node.node.location.expression.source
        assert_equal :tapp, result.node.node.type
        assert_equal [:begin], result.node.parents.map(&:type)
      end
    end
  end

  def test_ruby__find__annotations
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
def foo
  # @type self: String?
  123
end
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(2, 5).tap do |result|
        assert_instance_of Locator::AnnotationResult, result
        assert_instance_of Steep::AST::Annotation::SelfType, result.annotation
      end
    end
  end

  def test_ruby__find__comment
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
def foo
  # Returns an integer
  123
end
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(2, 5).tap do |result|
        assert_instance_of Locator::CommentResult, result
        assert_equal "# Returns an integer", result.comment.location.expression.source
      end
    end
  end

  def test_ruby__find__comment__no_node
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      source = parse_ruby(<<-'RUBY', factory: factory)
# Returns an integer
      RUBY

      locator = Locator::Ruby.new(source)

      locator.find(1, 5).tap do |result|
        assert_instance_of Locator::CommentResult, result
        assert_equal "# Returns an integer", result.comment.location.expression.source
        assert_nil result.node
      end
    end
  end

  # @rbs (String, ?path: Pathname) -> RBS::Source::Ruby
  def parse_inline(source, path: Pathname("a.rb"))
    buffer = RBS::Buffer.new(name: path, content: source)
    prism = Prism.parse(source, filepath: path.to_s)
    result = RBS::InlineParser.parse(buffer, prism)
    RBS::Source::Ruby.new(buffer, prism, result.declarations, result.diagnostics)
  end

  def test_inline__nil
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      locator.find(1, 3).tap do |result|
        assert_nil result
      end
    end
  end

  def test_inline__annotation_return
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  # @rbs return: String?
  def foo
  end
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      locator.find(2, 10).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal "@rbs return: String?", result.annotation.location.source
      end

      locator.find(2, 24).tap do |result|
        assert_instance_of Locator::InlineTypeResult, result
        assert_equal "String?", result.type.location.source
      end

      locator.find(2, 20).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::String", result.type_name.to_s
      end
    end
  end

  def test_inline__annotation__colon
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  #: () -> [Foo]
  def foo
  end
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      locator.find(2, 10).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": () -> [Foo]", result.annotation.location.source
      end

      locator.find(2, 11).tap do |result|
        assert_instance_of Locator::InlineTypeResult, result
        assert_equal "[Foo]", result.type.location.source
      end

      locator.find(2, 12).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Foo", result.type_name.to_s
      end
    end
  end

  def test_inline__annotation__method_type
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  # @rbs () -> void
  #    | (Symbol) -> void
  def foo
  end
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      locator.find(2, 10).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal "@rbs () -> void\n  #    | (Symbol) -> void", result.annotation.location.source
      end

      locator.find(2, 18).tap do |result|
        assert_instance_of Locator::InlineTypeResult, result
        assert_equal "void", result.type.location.source
      end

      locator.find(3, 14).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Symbol", result.type_name.to_s
      end
    end
  end

  def test_inline__mixin_type_application
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
module Enumerable[T]
end

class Array[T]
  include Enumerable[T]
end
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  include Enumerable #[String]

  extend Enumerable #[Integer]

  prepend Enumerable #[Symbol]
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      # Test finding on 'String' type name in include type application
      locator.find(2, 24).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::String", result.type_name.to_s
      end

      # Test finding on 'Integer' type name in extend type application
      locator.find(4, 24).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Integer", result.type_name.to_s
      end

      # Test finding on 'Symbol' type name in prepend type application
      locator.find(6, 23).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Symbol", result.type_name.to_s
      end

      # Test finding on the type application annotation itself
      locator.find(2, 22).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal "[String]", result.annotation.location.source
      end
    end
  end

  def test_inline__attr_reader
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  attr_reader :name #: String
  attr_reader :age #: Integer?
  attr_writer :email #: String?
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      # Test finding on the type annotation for :name
      locator.find(2, 22).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": String", result.annotation.location.source
      end

      # Test finding on 'String' type in :name annotation
      locator.find(2, 26).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::String", result.type_name.to_s
      end

      # Test finding on the type annotation for :age
      locator.find(3, 21).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": Integer?", result.annotation.location.source
      end

      # Test finding on 'Integer' type in :age annotation
      locator.find(3, 26).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Integer", result.type_name.to_s
      end

      # Test finding on the type annotation for :email
      locator.find(4, 23).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": String?", result.annotation.location.source
      end

      # Test finding on 'String' type in :email annotation
      locator.find(4, 27).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::String", result.type_name.to_s
      end
    end
  end

  def test_inline__attr_accessor
    with_factory({ "a.rbs" => <<-RBS }) do |factory|
      RBS

      env = factory.env

      env.add_source parse_inline(<<-'RUBY', path: Pathname("a.rb"))
class Foo
  attr_accessor :count #: Integer
  attr_accessor :items #: Array[String]
end
      RUBY

      env = env.resolve_type_names()

      source = env.sources.find { _1.buffer.name == Pathname("a.rb") }

      locator = Locator::Inline.new(source)

      # Test finding on the type annotation for :count
      locator.find(2, 24).tap do |result|
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": Integer", result.annotation.location.source
      end

      # Test finding on 'Integer' type in :count annotation
      locator.find(2, 28).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Integer", result.type_name.to_s
      end

      # Test finding on the type annotation for :items
      locator.find(3, 24).tap do |result| 
        assert_instance_of Locator::InlineAnnotationResult, result
        assert_equal ": Array[String]", result.annotation.location.source
      end

      # Test finding on 'Array' type name in :items annotation
      locator.find(3, 28).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::Array", result.type_name.to_s
      end

      # Test finding on 'String' type name in :items annotation
      locator.find(3, 34).tap do |result|
        assert_instance_of Locator::InlineTypeNameResult, result
        assert_equal "::String", result.type_name.to_s
      end
    end
  end
end
