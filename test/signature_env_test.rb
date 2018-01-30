require_relative "test_helper"

class SignatureEnvTest < Minitest::Test
  ModuleName = Steep::ModuleName

  def parse(src)
    Steep::Parser.parse_signature(src)
  end

  def env
    @env ||= Steep::AST::Signature::Env.new
  end

  def test_class
    klass, _ = parse(<<-EOS)
class A
end
    EOS

    env.add(klass)

    assert_equal klass, env.find_class(ModuleName.parse(:A))
  end

  def test_module
    mod, _ = parse(<<-EOS)
module A
end
    EOS

    env.add(mod)

    assert_equal mod, env.find_module(ModuleName.parse(:A))
  end

  def test_class_module_conflict
    klass, mod, _ = parse(<<-EOS)
class A
end

module A
end
    EOS

    env.add(klass)
    assert_raises do
      env.add(mod)
    end
  end

  def test_module_class_conflict
    klass, mod, _ = parse(<<-EOS)
class A
end

module A
end
    EOS

    env.add(mod)
    assert_raises do
      env.add(klass)
    end
  end

  def test_interface
    interface, _ = parse(<<-EOS)
interface _A
end
    EOS

    env.add(interface)

    assert_equal interface, env.find_interface(:_A)
  end

  def test_extension
    extension, _ = parse(<<-EOS)
extension Object (Foo)
end
    EOS

    env.add(extension)

    assert_equal [extension], env.find_extensions(ModuleName.parse(:Object))
  end
end
