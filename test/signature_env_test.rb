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

    assert_equal klass, env.find_class(ModuleName.parse(:A).absolute!)
  end

  def test_class_path
    klass, _ = parse(<<-EOS)
class A::B::C
end
    EOS

    env.add(klass)

    assert_equal klass, env.find_class(ModuleName.parse("A::B::C").absolute!)
    assert_equal klass, env.find_class(ModuleName.parse("C"), current_module: ModuleName.parse("::A::B"))
  end

  def test_nested_path_lookup
    abc_object, ab_object, object, _ = parse(<<-EOS)
class A::B::C::Object
end

class A::B::Object
end

class Object
end
    EOS

    env.add(abc_object)
    env.add(ab_object)
    env.add(object)

    assert_equal abc_object, env.find_class(ModuleName.parse("Object"), current_module: ModuleName.parse("::A::B::C"))
    assert_equal ab_object, env.find_class(ModuleName.parse("Object"), current_module: ModuleName.parse("::A::B"))
    assert_equal object, env.find_class(ModuleName.parse("Object"), current_module: ModuleName.parse("::A"))
  end

  def test_module
    mod, _ = parse(<<-EOS)
module A
end
    EOS

    env.add(mod)

    assert_equal mod, env.find_module(ModuleName.parse(:A).absolute!)
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

    assert_equal [extension], env.find_extensions(ModuleName.parse(:Object).absolute!)
  end
end
