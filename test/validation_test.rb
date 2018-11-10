require_relative 'test_helper'

class ValidationTest < Minitest::Test
  include TestHelper
  include SubtypingHelper

  def test_visibility_validation
    checker = new_subtyping_checker(<<-EOF)
class Super
  def foo: () -> void
end

class Child < Super
  def (private) foo: () -> void
end
    EOF

    assert_raises Steep::Interface::Instantiated::PrivateOverrideError do
      checker.resolve(parse_type("::Child"), with_private: true).validate(checker)
    end
  end

  def test_visibility_validation2
    checker = new_subtyping_checker(<<-EOF)
class Super
  def (private) foo: () -> void
end

class Child < Super
  def foo: () -> void
end
    EOF

    checker.resolve(parse_type("::Child"), with_private: true).validate(checker)
  end
end
