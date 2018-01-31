require "test_helper"

class SignatureParsingTest < Minitest::Test
  include TestHelper
  include ASTAssertion
  TypeName = Steep::TypeName
  ModuleName = Steep::ModuleName

  def parse(src)
    Steep::Parser.parse_signature(src)
  end

  def test_parsing_class0
    klass, _ = parse(<<-EOS)
class A
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3
    assert_nil klass.super_class
  end

  def test_parsing_class1
    klass, _ = parse(<<-EOS)
class A<'a, 'b>
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::A"), params: [:a, :b]
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3
    assert_location klass.params, start_line: 1, start_column: 7, end_line: 1, end_column: 15

    assert_nil klass.super_class
  end

  def test_parsing_class2
    klass, _ = parse(<<-EOS)
class A <: Object
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3

    assert_super_class klass.super_class, name: ModuleName.parse("Object")
    assert_location klass.super_class, start_line: 1, start_column: 11, end_line: 1, end_column: 17
  end

  def test_parsing_class3
    klass, _ = parse(<<-EOS)
class A <: Array<Integer>
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3

    assert_super_class klass.super_class, name: ModuleName.parse("Array") do |args|
      assert_equal 1, args.size
      assert_named_type args[0], name: ModuleName.parse("Integer"), kind: :instance
    end
    assert_location klass.super_class, start_line: 1, start_column: 11, end_line: 1, end_column: 25
  end

  def test_parsing_module0
    mod, _ = parse(<<-EOS)
module M
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::M") do |m|
      assert_nil m.self_type
    end
    assert_location mod, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_parsing_module1
    mod, _ = parse(<<-EOS)
module M<'a, 'b>
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::M"), params: [:a, :b] do |m|
      assert_nil m.self_type
    end
    assert_location mod, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_parsing_module2
    mod, _ = parse(<<-EOS)
module M: X
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::M") do |m|
      assert_named_type m.self_type, name: ModuleName.parse(:X), kind: :instance
    end
    assert_location mod, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_parsing_include
    klass, _ = parse(<<-EOS)
class X
  include M1
  include M1<Integer>
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::X")

    assert_equal 2, klass.members.size

    assert_include_member klass.members[0], name: ModuleName.parse(:M1), args: []
    assert_location klass.members[0], start_line: 2, start_column: 2, end_line: 2, end_column: 12

    assert_include_member klass.members[1],
                          name: ModuleName.parse(:M1),
                          args: [Steep::AST::Types::Name.new_instance(name: ModuleName.parse(:Integer))]
    assert_location klass.members[1], start_line: 3, start_column: 2, end_line: 3, end_column: 21
  end

  def test_parsing_extend
    klass, _ = parse(<<-EOS)
class X
  extend M1
  extend M1<Integer>
end
    EOS

    assert_class_signature klass, name: ModuleName.parse("::X")

    assert_equal 2, klass.members.size

    assert_extend_member klass.members[0], name: ModuleName.parse(:M1), args: []
    assert_location klass.members[0], start_line: 2, start_column: 2, end_line: 2, end_column: 11

    assert_extend_member klass.members[1],
                         name: ModuleName.parse(:M1),
                         args: [Steep::AST::Types::Name.new_instance(name: :Integer)]
    assert_location klass.members[1], start_line: 3, start_column: 2, end_line: 3, end_column: 20
  end

  def test_parsing_instance_method
    mod, _ = parse(<<-EOS)
module A
  def itself: () -> instance
            | (any) -> any
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::A")

    assert_equal 1, mod.members.size

    assert_method_member mod.members[0], name: :itself, kind: :instance, attributes: [] do |types:, **|
      assert_equal 2, types.size

      assert_nil types[0].params
      assert_instance_type types[0].return_type
      assert_location types[0], start_line: 2, start_column: 14, end_line: 2, end_column: 28

      assert_params_length types[1].params, 1
      assert_any_type types[1].return_type
      assert_location types[1], start_line: 3, start_column: 14, end_line: 3, end_column: 26
    end
    assert_location mod.members[0], start_line: 2, start_column: 2, end_line: 3, end_column: 26
  end

  def test_parsing_constructor_method
    mod, _ = parse(<<-EOS)
module A
  def (constructor) foo: () -> instance
  def (constructor) self.bar: () -> instance
  def (constructor) self?.baz: () -> instance 
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::A")
    assert_equal 3, mod.members.size
    mod.members.each do |member|
      assert_method_member member
      assert_operator member, :constructor?
    end
  end

  def test_parsing_module_method
    mod, _ = parse(<<-EOS)
module A
  def self.foo: () -> instance
              | (any) -> any
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::A")

    assert_equal 1, mod.members.size

    assert_method_member mod.members[0], name: :foo, kind: :module, attributes: [] do |types:, **|
      assert_equal 2, types.size

      assert_nil types[0].params
      assert_instance_type types[0].return_type
      assert_location types[0], start_line: 2, start_column: 16, end_line: 2, end_column: 30

      assert_params_length types[1].params, 1
      assert_any_type types[1].return_type
      assert_location types[1], start_line: 3, start_column: 16, end_line: 3, end_column: 28
    end
    assert_location mod.members[0], start_line: 2, start_column: 2, end_line: 3, end_column: 28
  end

  def test_parsing_module_instance_method
    mod, _ = parse(<<-EOS)
module A
  def self?.foo: () -> instance
               | (any) -> any
end
    EOS

    assert_module_signature mod, name: ModuleName.parse("::A")

    assert_equal 1, mod.members.size

    assert_method_member mod.members[0], name: :foo, kind: :module_instance, attributes: [] do |types:, **|
      assert_equal 2, types.size

      assert_nil types[0].params
      assert_instance_type types[0].return_type
      assert_location types[0], start_line: 2, start_column: 17, end_line: 2, end_column: 31

      assert_params_length types[1].params, 1
      assert_any_type types[1].return_type
      assert_location types[1], start_line: 3, start_column: 17, end_line: 3, end_column: 29
    end
    assert_location mod.members[0], start_line: 2, start_column: 2, end_line: 3, end_column: 29
  end

  def test_extension
    ext, _ = parse(<<-EOF)
extension Object (Pathname)
end
    EOF

    assert_extension_signature ext, module_name: ModuleName.parse("::Object"), name: :Pathname do |params:, **|
      assert_nil params
    end
    assert_location ext, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_extension1
    ext, _ = parse(<<-EOF)
extension Array<'a> (FOO)
end
    EOF

    assert_extension_signature ext, module_name: ModuleName.parse("::Array"), name: :FOO do |params:, **|
      assert_equal params.variables, [:a]
      assert_location params, start_line: 1, start_column: 15, end_line: 1, end_column: 19
    end
    assert_location ext, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_shift
    klass, _ = parse(<<-EOF)
class A
  def >>: (any) -> any
end
    EOF

    assert_class_signature klass, name: ModuleName.parse("::A") do |members:, **|
      assert_equal 1, members.size
      assert_method_member members[0], name: :>>
    end
  end

  def test_shift_failure
    assert_raises Racc::ParseError do
      parse(<<-EOF)
class A
  def > >: (any) -> any
end
      EOF
    end
  end

  def test_interface
    interface, _ = parse(<<-EOF)
interface _Enumerable
end
    EOF

    assert_interface_signature interface, name: :_Enumerable do |params:, **|
      assert_nil params
    end
    assert_location interface, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_interface1
    interface, _ = parse(<<-EOF)
interface _Enumerable<'a>
end
    EOF

    assert_interface_signature interface, name: :_Enumerable, params: [:a]
    assert_location interface, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_interface2
    interface, _ = parse(<<-EOF)
interface _Array<'a>
  def []: (Integer) -> 'a
end
    EOF

    assert_interface_signature interface, name: :_Array, params: [:a]
    assert_location interface, start_line: 1, start_column: 0, end_line: 3, end_column: 3

    method = interface.methods[0]
    assert_interface_method method, name: :[] do |method_type|
      assert_params_length method_type.params, 1
      assert_required_param method_type.params, index: 0 do |type, params|
        assert_named_type type, name: ModuleName.parse(:Integer)
        assert_location params, start_line: 2, start_column: 11, end_line: 2, end_column: 18
      end

      assert_type_var method_type.return_type, name: :a
      assert_location method_type.return_type, start_line: 2, start_column: 23, end_line: 2, end_column: 25
    end
    assert_location method, start_line: 2, start_column: 2, end_line: 2, end_column: 25
  end
end
