require "test_helper"

class SignatureParsingTest < Minitest::Test
  include TestHelper
  include ASTAssertion
  Names = Steep::Names
  AST = Steep::AST

  def parse(src)
    Steep::Parser.parse_signature(src)
  end

  def test_parsing_class0
    klass, _ = parse(<<-EOS)
class A
end
    EOS

    assert_class_signature klass, name: Names::Module.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3
    assert_nil klass.super_class
  end

  def test_parsing_class1
    klass, _ = parse(<<-EOS)
class A<'a, 'b>
end
    EOS

    assert_class_signature klass, name: Names::Module.parse("::A"), params: [:a, :b]
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3
    assert_location klass.params, start_line: 1, start_column: 7, end_line: 1, end_column: 15

    assert_nil klass.super_class
  end

  def test_parsing_class2
    klass, _ = parse(<<-EOS)
class A < Object
end
    EOS

    assert_class_signature klass, name: Names::Module.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3

    assert_super_class klass.super_class, name: Names::Module.parse("Object")
    assert_location klass.super_class, start_line: 1, start_column: 10, end_line: 1, end_column: 16
  end

  def test_parsing_class3
    klass, _ = parse(<<-EOS)
class A<'x> < Array<Integer>
end
    EOS

    assert_class_signature klass, name: Names::Module.parse("::A")
    assert_location klass, start_line: 1, start_column: 0, end_line: 2, end_column: 3

    assert_super_class klass.super_class, name: Names::Module.parse("Array") do |args|
      assert_equal 1, args.size
      assert_instance_of AST::Types::Name::Instance, args[0]
      assert_equal Names::Module.parse("Integer"), args[0].name
    end
    assert_location klass.super_class, start_line: 1, start_column: 14, end_line: 1, end_column: 28
  end

  def test_parsing_module0
    mod, _ = parse(<<-EOS)
module M
end
    EOS

    assert_module_signature mod, name: Names::Module.parse("::M") do |m|
      assert_nil m.self_type
    end
    assert_location mod, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_parsing_module1
    mod, _ = parse(<<-EOS)
module M<'a, 'b>
end
    EOS

    assert_module_signature mod, name: Names::Module.parse("::M"), params: [:a, :b] do |m|
      assert_nil m.self_type
    end
    assert_location mod, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_parsing_module2
    mod, _ = parse(<<-EOS)
module M: X
end
    EOS

    assert_module_signature mod, name: Names::Module.parse("::M") do |m|
      assert_instance_of AST::Types::Name::Instance, m.self_type
      assert_equal Names::Module.parse("X"), m.self_type.name
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

    assert_class_signature klass, name: Names::Module.parse("::X")

    assert_equal 2, klass.members.size

    assert_include_member klass.members[0], name: Names::Module.parse(:M1), args: []
    assert_location klass.members[0], start_line: 2, start_column: 2, end_line: 2, end_column: 12

    assert_include_member klass.members[1],
                          name: Names::Module.parse(:M1),
                          args: [Steep::AST::Types::Name.new_instance(name: Names::Module.parse(:Integer))]
    assert_location klass.members[1], start_line: 3, start_column: 2, end_line: 3, end_column: 21
  end

  def test_parsing_extend
    klass, _ = parse(<<-EOS)
class X
  extend M1
  extend M1<Integer>
end
    EOS

    assert_class_signature klass, name: Names::Module.parse("::X")

    assert_equal 2, klass.members.size

    assert_extend_member klass.members[0], name: Names::Module.parse(:M1), args: []
    assert_location klass.members[0], start_line: 2, start_column: 2, end_line: 2, end_column: 11

    assert_extend_member klass.members[1],
                         name: Names::Module.parse(:M1),
                         args: [Steep::AST::Types::Name.new_instance(name: :Integer)]
    assert_location klass.members[1], start_line: 3, start_column: 2, end_line: 3, end_column: 20
  end

  def test_parsing_instance_method
    mod, _ = parse(<<-EOS)
module A
  def itself: () -> instance
            | (any) -> any

  def foo: (self: any, ivar: any) -> any
end
    EOS

    assert_module_signature mod, name: Names::Module.parse("::A")

    assert_equal 2, mod.members.size

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

    assert_method_member mod.members[1], name: :foo, kind: :instance, attributes: [] do |types:, **|
      assert_equal 1, types.size
      assert_equal "(self: any, ivar: any) -> any", types.first.location.source
    end
  end

  def test_parsing_constructor_method
    mod, _ = parse(<<-EOS)
module A
  def (constructor) foo: () -> instance
  def (constructor) self.bar: () -> instance
  def (constructor) self?.baz: () -> instance 
end
    EOS

    assert_module_signature mod, name: Names::Module.parse("::A")
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

    assert_module_signature mod, name: Names::Module.parse("::A")

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

    assert_module_signature mod, name: Names::Module.parse("::A")

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

    assert_extension_signature ext, module_name: Names::Module.parse("::Object"), name: :Pathname do |params:, **|
      assert_nil params
    end
    assert_location ext, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_extension1
    ext, _ = parse(<<-EOF)
extension Array<'a> (FOO)
end
    EOF

    assert_extension_signature ext, module_name: Names::Module.parse("::Array"), name: :FOO do |params:, **|
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

    assert_class_signature klass, name: Names::Module.parse("::A") do |members:, **|
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

    assert_interface_signature interface, name: Names::Interface.parse("::_Enumerable") do |params:, **|
      assert_nil params
    end
    assert_location interface, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_interface1
    interface, _ = parse(<<-EOF)
interface _Enumerable<'a>
end
    EOF

    assert_interface_signature interface, name: Names::Interface.parse("::_Enumerable"), params: [:a]
    assert_location interface, start_line: 1, start_column: 0, end_line: 2, end_column: 3
  end

  def test_interface2
    interface, _ = parse(<<-EOF)
interface _Array<'a>
  def []: (Integer) -> 'a
end
    EOF

    assert_interface_signature interface, name: Names::Interface.parse("::_Array"), params: [:a]
    assert_location interface, start_line: 1, start_column: 0, end_line: 3, end_column: 3

    method = interface.methods[0]
    assert_interface_method method, name: :[] do |method_type|
      assert_params_length method_type.params, 1
      assert_required_param method_type.params, index: 0 do |type, params|
        assert_instance_of AST::Types::Name::Instance, type
        assert_equal Names::Module.parse(:Integer), type.name
        assert_location params, start_line: 2, start_column: 11, end_line: 2, end_column: 18
      end

      assert_type_var method_type.return_type, name: :a
      assert_location method_type.return_type, start_line: 2, start_column: 23, end_line: 2, end_column: 25
    end
    assert_location method, start_line: 2, start_column: 2, end_line: 2, end_column: 25
  end

  def test_const
    c1, c2 = parse(<<-EOF)
Foo: Integer
Foo::Bar::Baz: String
    EOF

    assert_instance_of Steep::AST::Signature::Const, c1
    assert_location c1, start_line: 1, start_column: 0, end_line: 1, end_column: 12
    assert_equal Names::Module.parse("::Foo"), c1.name
    assert_equal Steep::AST::Types::Name.new_instance(name: "Integer"), c1.type

    assert_instance_of Steep::AST::Signature::Const, c2
    assert_location c2, start_line: 2, start_column: 0, end_line: 2, end_column: 21
    assert_equal Names::Module.parse("::Foo::Bar::Baz"), c2.name
    assert_equal Steep::AST::Types::Name.new_instance(name: "String"), c2.type
  end

  def test_gvar
    g, _ = parse(<<-EOF)
$PROGRAM_NAME: String
    EOF

    assert_instance_of Steep::AST::Signature::Gvar, g
    assert_location g, start_line: 1, start_column: 0, end_line: 1, end_column: 21
    assert_equal :"$PROGRAM_NAME", g.name
    assert_equal Steep::AST::Types::Name.new_instance(name: "String"), g.type
  end

  def test_ivar
    klass, _ = parse(<<-EOF)
class A
  @name: String
end
    EOF

    assert_class_signature klass, name: Names::Module.parse("::A")

    assert_equal 1, klass.members.size

    klass.members[0].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Ivar, member
      assert_location member, start_line: 2, start_column: 2, end_line: 2, end_column: 15
      assert_equal :"@name", member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
    end
  end

  def test_attr_reader
    klass, _ = parse(<<-EOF)
class A
  attr_reader name: String
  attr_reader name (@name): String
  attr_reader name (): String
end
    EOF

    assert_class_signature klass, name: Names::Module.parse("::A")

    klass.members[0].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 2, start_column: 2, end_line: 2, end_column: 26
      assert_equal :reader, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_nil member.ivar
    end

    klass.members[1].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 3, start_column: 2, end_line: 3, end_column: 34
      assert_equal :reader, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_equal :"@name", member.ivar
    end

    klass.members[2].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 4, start_column: 2, end_line: 4, end_column: 29
      assert_equal :reader, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_equal false, member.ivar
    end
  end

  def test_attr_accessor
    klass, _ = parse(<<-EOF)
class A
  attr_accessor name: String
  attr_accessor name (@name): String
  attr_accessor name (): String
end
    EOF

    assert_class_signature klass, name: Names::Module.parse("::A")

    klass.members[0].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 2, start_column: 2, end_line: 2, end_column: 28
      assert_equal :accessor, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_nil member.ivar
    end

    klass.members[1].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 3, start_column: 2, end_line: 3, end_column: 36
      assert_equal :accessor, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_equal :"@name", member.ivar
    end

    klass.members[2].yield_self do |member|
      assert_instance_of Steep::AST::Signature::Members::Attr, member
      assert_location member, start_line: 4, start_column: 2, end_line: 4, end_column: 31
      assert_equal :accessor, member.kind
      assert_equal :name, member.name
      assert_equal Steep::AST::Types::Name.new_instance(name: "String"), member.type
      assert_equal false, member.ivar
    end
  end

  def test_alias
    sigs = parse(<<-EOF)
type foo = String | Integer
type bar<'a> = foo | Array<'a>
type baz = bar<String>
    EOF

    sigs[0].yield_self do |sig|
      assert_instance_of Steep::AST::Signature::Alias, sig
      assert_equal Steep::Names::Alias.parse("::foo"), sig.name
      assert_nil sig.params
      assert_equal parse_type("String | Integer"), sig.type
    end

    sigs[1].yield_self do |sig|
      assert_instance_of Steep::AST::Signature::Alias, sig
      assert_equal Steep::Names::Alias.parse("::bar"), sig.name
      assert_equal [:a], sig.params.variables
      assert_equal parse_type("foo | Array<'a>"), sig.type
    end
  end

  def test_incompatible_method
    sigs = parse(<<-EOF)
class Foo
  def (constructor, incompatible) method: () -> Method
end
    EOF

    sigs[0].yield_self do |sig|
      assert_instance_of Steep::AST::Signature::Class, sig
      assert_equal 1, sig.members.size
      sig.members[0].yield_self do |method|
        assert_operator method, :constructor?
        assert_operator method, :incompatible?
      end
    end
  end

  def test_private_method
    sigs = parse(<<-EOF)
class Foo
  def (private) method: () -> Method
end
    EOF

    sigs[0].yield_self do |sig|
      assert_instance_of Steep::AST::Signature::Class, sig
      assert_equal 1, sig.members.size
      sig.members[0].yield_self do |method|
        assert_operator method, :private?
      end
    end
  end

  def test_optional_block
    klass, = parse(<<-EOF)
class Foo
  def required_block: (Integer) { } -> Object
  def optional_block: (Integer) ?{ () -> String } -> Object
end
    EOF

    klass.members[0].yield_self do |required_block|
      refute_operator required_block.types[0].block, :optional
      assert_equal "{ }", required_block.types[0].block.location.source
    end

    klass.members[1].yield_self do |required_block|
      assert_operator required_block.types[0].block, :optional
      assert_equal "?{ () -> String }", required_block.types[0].block.location.source
    end
  end
end
