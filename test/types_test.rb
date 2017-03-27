require "test_helper"

class TypesTest < Minitest::Test
  T = Steep::Types

  def test_assignable
    interface1 = T::Interface.new()
  end
end
