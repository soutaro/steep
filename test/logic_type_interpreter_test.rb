require_relative "test_helper"

class LogicTypeInterpreterTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  LogicTypeInterpreter = Steep::TypeInference::LogicTypeInterpreter

  def test_type_case_select
    with_checker do |checker|
      interpreter = LogicTypeInterpreter.new(subtyping: checker, typing: nil)

      assert_equal [parse_type("::String"), parse_type("bot")],
                   interpreter.type_case_select(parse_type("::String"), TypeName("::String"))

      assert_equal [parse_type("::String"), parse_type("::Integer")],
                   interpreter.type_case_select(parse_type("::String | ::Integer"), TypeName("::String"))

      assert_equal [parse_type("bot"), parse_type("::String | ::Integer")],
                   interpreter.type_case_select(parse_type("::String | ::Integer"), TypeName("::Symbol"))
    end
  end

  def test_type_case_select_untyped
    with_checker do |checker|
      interpreter = LogicTypeInterpreter.new(subtyping: checker, typing: nil)

      assert_equal [parse_type("::String"), parse_type("untyped")],
                   interpreter.type_case_select(parse_type("untyped"), TypeName("::String"))
    end
  end

  def test_type_case_select_top
    with_checker do |checker|
      interpreter = LogicTypeInterpreter.new(subtyping: checker, typing: nil)

      assert_equal [parse_type("::String"), parse_type("top")],
                   interpreter.type_case_select(parse_type("top"), TypeName("::String"))
    end
  end

  def test_type_case_select_subtype
    with_checker(<<-RBS) do |checker|
class TestParent
end

class TestChild1 < TestParent
end

class TestChild2 < TestParent
end
    RBS
      interpreter = LogicTypeInterpreter.new(subtyping: checker, typing: nil)

      assert_equal [parse_type("::TestChild1"), parse_type("::String")],
                   interpreter.type_case_select(parse_type("::TestChild1 | ::String"), TypeName("::TestParent"))
    end
  end

  def test_type_case_select_alias
    with_checker(<<-RBS) do |checker|
class M end
class M1 < M end
class M2 < M end
class M3 < M end
class D end
class D1 < D end
class D2 < D end

type ms = M1 | M2 | M3
type ds = D1 | D2
type dm = ms | ds
    RBS

      interpreter = LogicTypeInterpreter.new(subtyping: checker, typing: nil)

      assert_equal [parse_type("::M1"), parse_type("::M2 | ::M3")],
                   interpreter.type_case_select(parse_type("::ms"), TypeName("::M1"))

      assert_equal [parse_type("::M1"), parse_type("::M2 | ::M3 | ::ds")],
                   interpreter.type_case_select(parse_type("::dm"), TypeName("::M1"))

      assert_equal [parse_type("::M1 | ::M2 | ::M3"), parse_type("::ds")],
                   interpreter.type_case_select(parse_type("::dm"), TypeName("::M"))

      assert_equal [parse_type("::D2"), parse_type("::ms | ::D1")],
                   interpreter.type_case_select(parse_type("::dm"), TypeName("::D2"))
    end
  end
end
