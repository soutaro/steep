require_relative "../test_helper"

class Steep::Server::LSPFormatterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include FactoryHelper

  include Steep

  def type_check(content)
    source = Source.parse(content, path: Pathname("a.rb"), factory: factory)
    subtyping = Subtyping::Check.new(factory: factory)
    Services::TypeCheckService.type_check(source: source, subtyping: subtyping)
  end

  def test_ruby_hover_variable
    with_factory do
      content = Services::HoverProvider::Ruby::VariableContent.new(
        node: nil,
        name: :x,
        type: parse_type("::Array[::Integer]"),
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal "`x`: `::Array[::Integer]`", comment
    end
  end

  def test_ruby_hover_method_call
    with_factory do
      typing = type_check(<<RUBY)
"".gsub(/foo/, "bar")
RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::Ruby::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
```rbs
((::Regexp | ::string), ::string) -> ::String
```

- `::String#gsub`

----

**::String#gsub**

```rbs
(::Regexp | ::string pattern, ::string replacement) -> ::String
```

Returns a copy of `self` with all occurrences of the given `pattern` replaced.

See [Substitution Methods](#class-String-label-Substitution+Methods).

Returns an Enumerator if no `replacement` and no block given.

Related: String#sub, String#sub!, String#gsub!.
EOM
    end
  end

  def test_ruby_hover_method_call_special
    with_factory do
      typing = type_check(<<RUBY)
[1, nil].compact
RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::Ruby::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
**💡 Custom typing rule applies**

```rbs
() -> ::Array[::Integer]
```

- `::Array#compact`

----

**::Array#compact**

```rbs
() -> ::Array[Elem]
```

Returns a new Array containing all non-`nil` elements from `self`:
    a = [nil, 0, nil, 1, nil, 2, nil]
    a.compact # => [0, 1, 2]
EOM
    end
  end

  def test_ruby_hover_method_call_csend
    with_factory do
      typing = type_check(<<RUBY)
""&.gsub(/foo/, "bar")
RUBY

      call = typing.call_of(node: typing.source.node)

      content = Services::HoverProvider::Ruby::MethodCallContent.new(
        node: nil,
        method_call: call,
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
```rbs
((::Regexp | ::string), ::string) -> (::String | nil)
```

- `::String#gsub`

----

**::String#gsub**

```rbs
(::Regexp | ::string pattern, ::string replacement) -> ::String
```

Returns a copy of `self` with all occurrences of the given `pattern` replaced.

See [Substitution Methods](#class-String-label-Substitution+Methods).

Returns an Enumerator if no `replacement` and no block given.

Related: String#sub, String#sub!, String#gsub!.
EOM
    end
  end

  def test_ruby_hover_method_def
    with_factory do
      content = Services::HoverProvider::Ruby::DefinitionContent.new(
        node: nil,
        method_name: MethodName("::String#gsub"),
        method_type: parse_method_type("() -> void"),
        definition: factory.definition_builder.build_instance(TypeName("::String")).methods[:gsub],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
```
::String#gsub: () -> void
```

----

Returns a copy of `self` with all occurrences of the given `pattern` replaced.

See [Substitution Methods](#class-String-label-Substitution+Methods).

Returns an Enumerator if no `replacement` and no block given.

Related: String#sub, String#sub!, String#gsub!.

----

- `(::Regexp | ::string pattern, ::string replacement) -> ::String`
- `(::Regexp | ::string pattern, ::Hash[::String, ::String] hash) -> ::String`
- `(::Regexp | ::string pattern) { (::String match) -> ::_ToS } -> ::String`
- `(::Regexp | ::string pattern) -> ::Enumerator[::String, self]`
EOM
    end
  end

  def test_ruby_hover_constant_class
    with_factory({ "foo.rbs" => <<RBS }) do
# ClassHover is a class to do something with String.
#      
class ClassHover[A < String] < BasicObject
end
RBS
      content = Services::HoverProvider::Ruby::ConstantContent.new(
        full_name: TypeName("::ClassHover"),
        type: parse_type("singleton(::ClassHover)"),
        decl: factory.env.class_decls[TypeName("::ClassHover")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
```rbs
class ::ClassHover[A < ::String] < ::BasicObject
```

----

ClassHover is a class to do something with String.
EOM
    end
  end

  def test_ruby_hover_constant_const
    with_factory({ "foo.rbs" => <<-EOF }) do
# The version of ClassHover
#
ClassHover::VERSION: String

class ClassHover
end
    EOF
      content = Services::HoverProvider::Ruby::ConstantContent.new(
        full_name: TypeName("::ClassHover::VERSION"),
        type: parse_type("::String"),
        decl: factory.env.constant_decls[TypeName("::ClassHover::VERSION")],
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal <<EOM.chomp, comment
```rbs
::ClassHover::VERSION: ::String
```

----

The version of ClassHover
EOM
    end
  end

  def test_ruby_hover_type
    with_factory() do
      content = Services::HoverProvider::Ruby::TypeContent.new(
        node: nil,
        type: parse_type("[::String, ::Integer]"),
        location: nil
      )

      comment = Server::LSPFormatter.format_hover_content(content)
      assert_equal "`[::String, ::Integer]`", comment
    end
  end

  def test_rbs_hover_type_alias
    with_factory({ "foo.rbs" => <<RBS }) do
type foo[T, S < Numeric] = [T, S]

# Hello World
type bar = 123
RBS
      Services::HoverProvider::RBS::TypeAliasContent.new(
        decl: factory.env.alias_decls[TypeName("::foo")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<TEXT.chomp, comment
```rbs
type ::foo = [ T, S ]
```
TEXT
      end

      Services::HoverProvider::RBS::TypeAliasContent.new(
        decl: factory.env.alias_decls[TypeName("::bar")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<TEXT.chomp, comment
```rbs
type ::bar = 123
```

----

Hello World
TEXT
      end
    end
  end

  def test_rbs_hover_class
    with_factory({ "foo.rbs" => <<RBS }) do
# This is a class!
#
class HelloWorld[T] < Numeric
end
RBS
      Services::HoverProvider::RBS::ClassContent.new(
        decl: factory.env.class_decls[TypeName("::HelloWorld")].primary.decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<TEXT.chomp, comment
```rbs
class ::HelloWorld[T] < ::Numeric
```

----

This is a class!
TEXT
      end
    end
  end

  def test_rbs_hover_interface
    with_factory({ "foo.rbs" => <<RBS }) do
# This is an interface!
#
interface _HelloWorld[T]
end
RBS
      Services::HoverProvider::RBS::ClassContent.new(
        decl: factory.env.interface_decls[TypeName("::_HelloWorld")].decl,
        location: nil
      ).tap do |content|
        comment = Server::LSPFormatter.format_hover_content(content)
        assert_equal <<TEXT.chomp, comment
```rbs
interface ::_HelloWorld[T]
```

----

This is an interface!
TEXT
      end
    end
  end
end
