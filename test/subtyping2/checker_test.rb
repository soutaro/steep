require "test_helper"

class Subtyping2CheckerTest < Minitest::Test
  def test_1
    env = Ruby::Signature::Environment.new()

    env_loader = Ruby::Signature::EnvironmentLoader.new(env: env)
    env_loader.load

    builder = Ruby::Signature::DefinitionBuilder.new(env: env)
    checker = Steep::Subtyping2::Checker.new(builder: builder)

    object = Ruby::Signature::Parser.parse_type("::Object")

    assert_operator checker.check(super_type: object, sub_type: object), :success?
  end
end
