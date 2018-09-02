require_relative "test_helper"

class SignatureEnvTest < Minitest::Test
  ModuleName = Steep::ModuleName
  Namespace = Steep::AST::Namespace
  InterfaceName = Steep::InterfaceName
  AliasName = Steep::AliasName

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

    assert_equal klass, env.find_class(ModuleName.parse("::A"))
  end

  def test_class_path
    klass, _ = parse(<<-EOS)
class A::B::C
end
    EOS

    env.add(klass)

    assert_equal klass, env.find_class(ModuleName.parse("::A::B::C"))
    assert_equal klass, env.find_class(ModuleName.parse("C"), current_module: Namespace.parse("::A::B"))
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

    assert_equal abc_object, env.find_class(ModuleName.parse("Object"), current_module: Namespace.parse("::A::B::C"))
    assert_equal ab_object, env.find_class(ModuleName.parse("Object"), current_module: Namespace.parse("::A::B"))
    assert_equal object, env.find_class(ModuleName.parse("Object"), current_module: Namespace.parse("::A"))
  end

  def test_module
    mod, _ = parse(<<-EOS)
module A
end
    EOS

    env.add(mod)

    assert_equal mod, env.find_module(ModuleName.parse("::A"))
    assert_equal mod, env.find_module(ModuleName.parse("A"))
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

    assert_equal interface, env.find_interface(InterfaceName.new(name: :_A))
  end

  def test_extension
    extension, _ = parse(<<-EOS)
extension Object (Foo)
end
    EOS

    env.add(extension)

    assert_equal [extension], env.find_extensions(ModuleName.parse(:Object).absolute!)
  end

  def test_constant
    const, _ = parse(<<-EOS)
Steep::Version: Integer
    EOS

    env.add(const)

    assert_equal const, env.find_const(ModuleName.parse("::Steep::Version"))
    assert_equal const, env.find_const(ModuleName.parse("Steep::Version"))
    assert_equal const, env.find_const(ModuleName.parse("Version"), current_module: Namespace.parse("::Steep"))
    assert_nil env.find_const(ModuleName.parse("Steep"))

    assert env.const_name?(ModuleName.parse("::Steep::Version"))
  end

  def test_gvar
    gvar, _ = parse(<<-EOS)
$VERSION: Integer
    EOS

    env.add(gvar)

    assert_equal gvar, env.find_gvar(:"$VERSION")
    assert_nil env.find_gvar(:"$HOGE")
  end

  def test_alias
    a, _ = parse(<<-EOS)
type foo = String | Integer
    EOS

    env.add(a)

    assert_equal a, env.find_alias(AliasName.new(name: :foo))
    assert_nil env.find_alias(AliasName.new(name: :bar))
  end
end
