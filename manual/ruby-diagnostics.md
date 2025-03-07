# Ruby Code Diagnostics

## Configuration Templates
Steep provides several templates to configure diagnostics for Ruby code.
You can use these templates or customize them to suit your needs via `#configure_code_diagnostics` method in `Steepfile`.

The following templates are available:

<dl>
<dt><code>Ruby.all_error</code></dt>
<dd>This template reports everything as an error.

</dd>
<dt><code>Ruby.default</code></dt>
<dd>This template detects inconsistencies between RBS and Ruby code APIs.

</dd>
<dt><code>Ruby.lenient</code></dt>
<dd>This template detects inconsistent definition in Ruby code with respect to your RBS definition.

</dd>
<dt><code>Ruby.silent</code></dt>
<dd>This template reports nothing.

</dd>
<dt><code>Ruby.strict</code></dt>
<dd>This template helps you keeping your codebase (almost) type-safe.

You can start with this template to review the problems reported on the project,
and you can ignore some kind of errors.

</dd>
</dl>

<a name='Ruby::AnnotationSyntaxError'></a>
## Ruby::AnnotationSyntaxError

A type annotation has a syntax error.

### Ruby code

```ruby
# @type var foo: () ->
```

### Diagnostic

```
test.rb:1:2: [error] Type annotation has a syntax error: Syntax error caused by token `pEOF`
│ Diagnostic ID: Ruby::AnnotationSyntaxError
│
└ # @type method foo: () ->
    ~~~~~~~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | error | - |

<a name='Ruby::ArgumentTypeMismatch'></a>
## Ruby::ArgumentTypeMismatch

A method call has an argument that has an incompatible type to the type of the parameter.

### Ruby code

```ruby
'1' + 1
```

### Diagnostic

```
test.rb:1:6: [error] Cannot pass a value of type `::Integer` as an argument of type `::string`
│   ::Integer <: ::string
│     ::Integer <: (::String | ::_ToStr)
│       ::Integer <: ::String
│         ::Numeric <: ::String
│           ::Object <: ::String
│             ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::ArgumentTypeMismatch
│
└ '1' + 1
        ~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::BlockBodyTypeMismatch'></a>
## Ruby::BlockBodyTypeMismatch

The type of the block body is incompatible with the expected type.

### RBS

```rbs
class Foo
  def foo: () { () -> Integer } -> void
end
```

### Ruby code

```ruby
Foo.new.foo { "" }
```

### Diagnostic

```
test.rb:1:12: [warning] Cannot allow block body have type `::String` because declared as type `::Integer`
│   ::String <: ::Integer
│     ::Object <: ::Integer
│       ::BasicObject <: ::Integer
│
│ Diagnostic ID: Ruby::BlockBodyTypeMismatch
│
└ Foo.new.foo { "" }
              ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | information | - |

<a name='Ruby::BlockTypeMismatch'></a>
## Ruby::BlockTypeMismatch

A method call passes an object as a block, but the type is incompatible with the method type.

### Ruby code

```ruby
multi = ->(x, y) { x * y } #: ^(Integer, Integer) -> Integer
[1, 2, 3].map(&multi)
```

### Diagnostic

```
test.rb:2:14: [error] Cannot pass a value of type `^(::Integer, ::Integer) -> ::Integer` as a block-pass-argument of type `^(::Integer) -> U(1)`
│   ^(::Integer, ::Integer) -> ::Integer <: ^(::Integer) -> U(1)
│     (Params are incompatible)
│
│ Diagnostic ID: Ruby::BlockTypeMismatch
│
└ [1, 2, 3].map(&multi)
                ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | information | - |

<a name='Ruby::BreakTypeMismatch'></a>
## Ruby::BreakTypeMismatch

A `break` statement has a value that has an incompatible type to the type of the destination.

### Ruby code

```ruby
123.tap { break "" }
```

### Diagnostic

```
test.rb:1:10: [error] Cannot break with a value of type `::String` because type `::Integer` is assumed
│   ::String <: ::Integer
│     ::Object <: ::Integer
│       ::BasicObject <: ::Integer
│
│ Diagnostic ID: Ruby::BreakTypeMismatch
│
└ 123.tap { break "" }
            ~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | hint | - |

<a name='Ruby::ClassModuleMismatch'></a>
## Ruby::ClassModuleMismatch

A class (or module) definition in Ruby code has a module (or class) in RBS.

### Ruby code

```ruby
module Object
end

class Kernel
end
```

### Diagnostic

```
test.rb:1:7: [error] ::Object is declared as a class in RBS
│ Diagnostic ID: Ruby::ClassModuleMismatch
│
└ module Object
         ~~~~~~

test.rb:4:6: [error] ::Kernel is declared as a module in RBS
│ Diagnostic ID: Ruby::ClassModuleMismatch
│
└ class Kernel
        ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | - | - |

<a name='Ruby::DeprecatedReference'></a>
## Ruby::DeprecatedReference

Method call or constant reference is deprecated.

### RBS

```rbs
%a{deprecated} class Foo end

class Bar
  %a{deprecated: since v0.9} def self.bar: () -> void
end
```

### Ruby code

```ruby
Foo

Bar.bar()
```

### Diagnostic

```
lib/deprecated.rb:1:0: [warning] The constant is deprecated
│ Diagnostic ID: Ruby::DeprecatedReference
│
└ Foo
  ~~~

lib/deprecated.rb:3:4: [warning] The method is deprecated: since v0.9
│ Diagnostic ID: Ruby::DeprecatedReference
│
└ Bar.bar()
      ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | warning | warning | - |

<a name='Ruby::DifferentMethodParameterKind'></a>
## Ruby::DifferentMethodParameterKind

The method has a parameter with different kind from the RBS definition.

### RBS

```rbs
class Foo
  def foo: (String?) -> void
end
```

### Ruby code

```ruby
class Foo
  def foo(x=nil)
  end
end
```

### Diagnostic

```
test.rb:2:10: [hint] The method parameter has different kind from the declaration `((::String | nil)) -> void`
│ Diagnostic ID: Ruby::DifferentMethodParameterKind
│
└   def foo(x=nil)
            ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::FallbackAny'></a>
## Ruby::FallbackAny

Unable to determine the type of an expression for any reason.

### Ruby code

```ruby
@foo
```

### Diagnostic

```
test.rb:1:0: [error] Cannot detect the type of the expression
│ Diagnostic ID: Ruby::FallbackAny
│
└ @foo
  ~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | hint | - | - |

<a name='Ruby::FalseAssertion'></a>
## Ruby::FalseAssertion

The type assertion cannot hold.

### Ruby code

```ruby
array = [] #: Array[Integer]
hash = array #: Hash[Symbol, String]
```

### Diagnostic

```
test.rb:2:7: [error] Assertion cannot hold: no relationship between inferred type (`::Array[::Integer]`) and asserted type (`::Hash[::Symbol, ::String]`)
│ Diagnostic ID: Ruby::FalseAssertion
│
└ hash = array #: Hash[Symbol, String]
         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::ImplicitBreakValueMismatch'></a>
## Ruby::ImplicitBreakValueMismatch

A `break` statement without a value is used to leave from a block that requires non-nil type.

### Ruby code

```ruby
123.tap { break }
```

### Diagnostic

```
test.rb:1:10: [error] Breaking without a value may result an error because a value of type `::Integer` is expected
│   nil <: ::Integer
│
│ Diagnostic ID: Ruby::ImplicitBreakValueMismatch
│
└ 123.tap { break }
            ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | - | - |

<a name='Ruby::IncompatibleAnnotation'></a>
## Ruby::IncompatibleAnnotation

Detected a branch local annotation is incompatible with outer context.

### Ruby code

```ruby
a = [1,2,3]

if _ = 1
  # @type var a: String
  a + ""
end
```

### Diagnostic

```
test.rb:5:2: [error] Type annotation about `a` is incompatible since ::String <: ::Array[::Integer] doesn't hold
│   ::String <: ::Array[::Integer]
│     ::Object <: ::Array[::Integer]
│       ::BasicObject <: ::Array[::Integer]
│
│ Diagnostic ID: Ruby::IncompatibleAnnotation
│
└   a + ""
    ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::IncompatibleArgumentForwarding'></a>
## Ruby::IncompatibleArgumentForwarding

Argument forwarding `...` cannot be done safely, because of:

1. The arguments are incompatible, or
2. The blocks are incompatible

### RBS

```rbs
class Foo
  def foo: (*Integer) -> void

  def bar: (*String) -> void
end
```

### Ruby code

```ruby
class Foo
  def foo(*args)
  end

  def bar(...)
    foo(...)
  end
end
```

### Diagnostic

```
test.rb:8:8: [error] Cannot forward arguments to `foo`:
│   (*::Integer) <: (*::String)
│     ::String <: ::Integer
│       ::Object <: ::Integer
│
│ Diagnostic ID: Ruby::IncompatibleArgumentForwarding
│
└     foo(...)
          ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | information | - |

<a name='Ruby::IncompatibleAssignment'></a>
## Ruby::IncompatibleAssignment

An assignment has a right hand side value that has an incompatible type to the type of the left hand side.

### Ruby code

```ruby
# @type var x: Integer
x = "string"
```

### Diagnostic

```
test.rb:2:0: [error] Cannot assign a value of type `::String` to a variable of type `::Integer`
│   ::String <: ::Integer
│     ::Object <: ::Integer
│       ::BasicObject <: ::Integer
│
│ Diagnostic ID: Ruby::IncompatibleAssignment
│
└ x = "string"
  ~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | hint | - |

<a name='Ruby::InsufficientKeywordArguments'></a>
## Ruby::InsufficientKeywordArguments

A method call needs more keyword arguments.

### RBS

```rbs
class Foo
  def foo: (a: untyped, b: untyped) -> void
end
```

### Ruby code

```ruby
Foo.new.foo(a: 1)
```

### Diagnostic

```
test.rb:5:8: [error] More keyword arguments are required: b
│ Diagnostic ID: Ruby::InsufficientKeywordArguments
│
└ Foo.new.foo(a: 1)
          ~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::InsufficientPositionalArguments'></a>
## Ruby::InsufficientPositionalArguments

An method call needs more positional arguments.

### RBS

```ruby
class Foo
  def foo: (a, b) -> void
end
```

### Ruby code

```ruby
Foo.new.foo(1)
```

### Diagnostic

```
test.rb:1:8: [error] More positional arguments are required
│ Diagnostic ID: Ruby::InsufficientPositionalArguments
│
└ Foo.new.foo(1)
          ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::InsufficientTypeArgument'></a>
## Ruby::InsufficientTypeArgument

A type application needs more type arguments.

### RBS

```rbs
class Foo
  def foo: [T, S] (T, S) -> [T, S]
end
```

### Ruby code

```ruby
Foo.new.foo(1, 2) #$ Integer
```

### Diagnostic

```
test.rb:8:0: [error] Requires 2 types, but 1 given: `[T, S] (T, S) -> [T, S]`
│ Diagnostic ID: Ruby::InsufficientTypeArgument
│
└ Foo.new.foo(1, 2) #$ Integer
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::InvalidIgnoreComment'></a>
## Ruby::InvalidIgnoreComment

`steep:ignore` comment is invalid.

### Ruby code

```ruby
# steep:ignore:start
```

### Diagnostic

```
test.rb:1:0: [error] Invalid ignore comment
│ Diagnostic ID: Ruby::InvalidIgnoreComment
│
└ # steep:ignore:start
  ~~~~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | warning | warning | - |

<a name='Ruby::MethodArityMismatch'></a>
## Ruby::MethodArityMismatch

The method definition has missing parameters with respect to the RBS definition.

### RBS

```rbs
class Foo
  def foo: (String, String) -> void
end
```

### Ruby code

```ruby
class Foo
  def foo(x)
  end
end
```

### Diagnostic

```
test.rb:2:9: [error] Method parameters are incompatible with declaration `(::String, ::String) -> void`
│ Diagnostic ID: Ruby::MethodArityMismatch
│
└   def foo(x)
           ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::MethodBodyTypeMismatch'></a>
## Ruby::MethodBodyTypeMismatch

The type of the method body has different type from the RBS definition.

### RBS

```rbs
class Foo
  def foo: () -> String
end
```

### Ruby code

```ruby
class Foo
  def foo = 123
end
```

### Diagnostic

```
test.rb:2:6: [error] Cannot allow method body have type `::Integer` because declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::MethodBodyTypeMismatch
│
└   def foo = 123
        ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | warning | - |

<a name='Ruby::MethodDefinitionInUndeclaredModule'></a>
## Ruby::MethodDefinitionInUndeclaredModule

A `def` syntax doesn't have method type because the module/class is undefined in RBS.

### Ruby code

```ruby
class UndeclaredClass
  def to_s = 123
end
```

### Diagnostic

```
test.rb:2:6: [error] Method `to_s` is defined in undeclared module
│ Diagnostic ID: Ruby::MethodDefinitionInUndeclaredModule
│
└   def to_s = 123
        ~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | information | hint | - |

<a name='Ruby::MethodDefinitionMissing'></a>
## Ruby::MethodDefinitionMissing

The class/module definition doesn't have a `def` syntax for the method.

### RBS

```rbs
class Foo
  def foo: () -> String
end
```

### Ruby code

```ruby
class Foo
  attr_reader :foo
end
```

### Diagnostic

```
test.rb:1:6: [hint] Cannot find implementation of method `::Foo#foo`
│ Diagnostic ID: Ruby::MethodDefinitionMissing
│
└ class Foo
        ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | hint | - | - | - |

<a name='Ruby::MethodParameterMismatch'></a>
## Ruby::MethodParameterMismatch

The method definition has an extra parameter with respect to the RBS definition.

### RBS

```rbs
class Foo
  def foo: (String) -> void
end
```

### Ruby code

```ruby
class Foo
  def foo(x, y)
  end
end
```

### Diagnostic

```
test.rb:2:13: [error] The method parameter is incompatible with the declaration `(::String) -> void`
│ Diagnostic ID: Ruby::MethodParameterMismatch
│
└   def foo(x, y)
               ~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | warning | - |

<a name='Ruby::MethodReturnTypeAnnotationMismatch'></a>
## Ruby::MethodReturnTypeAnnotationMismatch

**Deprecated** Related to the `@type method` annotation.


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::MultipleAssignmentConversionError'></a>
## Ruby::MultipleAssignmentConversionError

The `#to_ary` of RHS of multiple assignment is called, but returns not tuple nor Array.

### RBS

```rbs
class Foo
  def to_ary: () -> Integer
end
```

### Ruby code

```ruby
a, b = Foo.new()
```

### Diagnostic

```
test.rb:1:6: [error] Cannot convert `::Foo` to Array or tuple (`#to_ary` returns `::Integer`)
│ Diagnostic ID: Ruby::MultipleAssignmentConversionError
│
└ a,b = Foo.new
        ~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::NoMethod'></a>
## Ruby::NoMethod

A method call calls a method that is not defined on the receiver.

### Ruby code

```ruby
"".non_existent_method
```

### Diagnostic

```
test.rb:1:3: [error] Type `::String` does not have method `non_existent_method`
│ Diagnostic ID: Ruby::NoMethod
│
└ "".non_existent_method
     ~~~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::ProcHintIgnored'></a>
## Ruby::ProcHintIgnored

Type hint is given to a proc/lambda but it was ignored.

1. Because the hint is incompatible to `::Proc` type
2. More than one *proc type* is included in the hint

### Ruby code

```ruby
# @type var proc: (^(::Integer) -> ::String) | (^(::String, ::String) -> ::Integer)
proc = -> (x) { x.to_s }
```

### Diagnostic

```
test.rb:2:7: [error] The type hint given to the block is ignored: `(^(::Integer) -> ::String | ^(::String, ::String) -> ::Integer)`
│ Diagnostic ID: Ruby::ProcHintIgnored
│
└ proc = -> (x) { x.to_s }
         ~~~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | - | - |

<a name='Ruby::ProcTypeExpected'></a>
## Ruby::ProcTypeExpected

The block parameter has non-proc type.

### Ruby code

```ruby
-> (&block) do
  # @type var block: Integer
end
```

### Diagnostic

```
test.rb:1:4: [error] Proc type is expected but `::Integer` is specified
│ Diagnostic ID: Ruby::ProcTypeExpected
│
└ -> (&block) do
      ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::RBSError'></a>
## Ruby::RBSError

RBS embedded in the Ruby code has validation error.

### Ruby code

```ruby
a = 1 #: Int
```

### Diagnostic

```
test.rb:1:9: [error] Cannot find type `::Int`
│ Diagnostic ID: Ruby::RBSError
│
└ a = 1 #: Int
           ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | information | information | - |

<a name='Ruby::RequiredBlockMissing'></a>
## Ruby::RequiredBlockMissing

A method that requires a block is called without a block.

### RBS

```rbs
class Foo
  def foo: { () -> void } -> void
end
```

### Ruby code

```ruby
Foo.new.foo
```

### Diagnostic

```
test.rb:1:8: [error] The method cannot be called without a block
│ Diagnostic ID: Ruby::RequiredBlockMissing
│
└ Foo.new.foo
          ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | hint | - |

<a name='Ruby::ReturnTypeMismatch'></a>
## Ruby::ReturnTypeMismatch

A `return` statement has a value that has an incompatible type to the return type of the method.

### RBS

```rbs
class Foo
  def foo: () -> Integer
end
```

### Ruby code

```ruby
class Foo
  def foo
    return "string"
  end
end
```

### Diagnostic

```
test.rb:3:2: [error] The method cannot return a value of type `::String` because declared as type `::Integer`
│   ::String <: ::Integer
│     ::Object <: ::Integer
│       ::BasicObject <: ::Integer
│
│ Diagnostic ID: Ruby::ReturnTypeMismatch
│
└   return "string"
    ~~~~~~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | warning | - |

<a name='Ruby::SetterBodyTypeMismatch'></a>
## Ruby::SetterBodyTypeMismatch

Setter method, which has a name ending with `=`, has different type from the method type.

This is a special diagnostic for setter methods because the return value is not used with ordinal call syntax.

### RBS

### Ruby code

```ruby
class Foo
  # Assume `name=` has method type of `(String) -> String`
  def name=(value)
    @value = value
    value.strip!
  end
end
```

### Diagnostic

```
test.rb:2:6: [information] Setter method `name=` cannot have type `(::String | nil)` because declared as type `::String`
│   (::String | nil) <: ::String
│     nil <: ::String
│
│ Diagnostic ID: Ruby::SetterBodyTypeMismatch
│
└   def name=(value)
        ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | information | - | - |

<a name='Ruby::SetterReturnTypeMismatch'></a>
## Ruby::SetterReturnTypeMismatch

Setter method, which has a name ending with `=`, returns different type from the method type.
This is a special diagnostic for setter methods because the return value is not used with ordinal call syntax.

### RBS

```rbs
class Foo
  def name=: (String) -> String
end
```

### Ruby code

```ruby
class Foo
  def name=(value)
    return if value.empty?
    @value = value
  end
end
```

### Diagnostic

```
test.rb:3:4: [information] The setter method `name=` cannot return a value of type `nil` because declared as type `::String`
│   nil <: ::String
│
│ Diagnostic ID: Ruby::SetterReturnTypeMismatch
│
└     return if value.empty?
      ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | information | - | - |

<a name='Ruby::SyntaxError'></a>
## Ruby::SyntaxError

The Ruby code has a syntax error.

### Ruby code

```ruby
if x == 1
  puts "Hello"
```

### Diagnostic

```
test.rb:2:14: [error] SyntaxError: unexpected token $end
│ Diagnostic ID: Ruby::SyntaxError
│
└   puts "Hello"
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | information | information | - |

<a name='Ruby::TypeArgumentMismatchError'></a>
## Ruby::TypeArgumentMismatchError

The type application doesn't satisfy generic constraints.

### RBS

```rbs
class Foo
  def foo: [T < Numeric] (T) -> T
end
```

### Ruby code

```ruby
Foo.new.foo("") #$ String
```

### Diagnostic

```
test.rb:7:19: [error] Cannot pass a type `::String` as a type parameter `T < ::Numeric`
│   ::String <: ::Numeric
│     ::Object <: ::Numeric
│       ::BasicObject <: ::Numeric
│
│ Diagnostic ID: Ruby::TypeArgumentMismatchError
│
└ Foo.new.foo("") #$ String
                     ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::UnannotatedEmptyCollection'></a>
## Ruby::UnannotatedEmptyCollection

An empty array/hash has no type assertion.

They are typed as `Array[untyped]` or `Hash[untyped, untyped]`,
which allows any element to be added.

```rb
a = []
b = {}

a << 1
a << ""
```

Add type annotation to make your assumption explicit.

```rb
a = [] #: Array[Integer]
b = {} #: untyped

a << 1
a << ""     # => Type error
```

### Ruby code

```ruby
a = []
b = {}
```

### Diagnostic

```
test.rb:1:4: [error] Empty array doesn't have type annotation
│ Diagnostic ID: Ruby::UnannotatedEmptyCollection
│
└ a = []
      ~~

test.rb:2:4: [error] Empty hash doesn't have type annotation
│ Diagnostic ID: Ruby::UnannotatedEmptyCollection
│
└ b = {}
      ~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | hint | - |

<a name='Ruby::UndeclaredMethodDefinition'></a>
## Ruby::UndeclaredMethodDefinition

A `def` syntax doesn't have corresponding RBS method definition.

### RBS

```rbs
class Foo
end
```

### Ruby code

```ruby
class Foo
  def undeclared = nil
end
```

### Diagnostic

```
test.rb:2:6: [error] Method `::Foo#undeclared` is not declared in RBS
│ Diagnostic ID: Ruby::UndeclaredMethodDefinition
│
└   def undeclared = nil
        ~~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | warning | information | - |

<a name='Ruby::UnexpectedBlockGiven'></a>
## Ruby::UnexpectedBlockGiven

A method that doesn't accept block is called with a block.

### RBS

```rbs
class Foo
  def foo: () -> void
end
```

### Ruby code

```ruby
Foo.new.foo { 123 }
```

### Diagnostic

```
test.rb:1:12: [warning] The method cannot be called with a block
│ Diagnostic ID: Ruby::UnexpectedBlockGiven
│
└ Foo.new.foo { 123 }
              ~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | hint | - |

<a name='Ruby::UnexpectedDynamicMethod'></a>
## Ruby::UnexpectedDynamicMethod

A `@dynamic` annotation has unknown method name.

Note that this diagnostic emits only if the class definition in RBS has method definitions.

### RBS

```rbs
class Foo
  def foo: () -> void
end
```

### Ruby code

```ruby
class Foo
  # @dynamic foo, bar
end
```

### Diagnostic

```
test.rb:1:6: [error] @dynamic annotation contains unknown method name `bar`
│ Diagnostic ID: Ruby::UnexpectedDynamicMethod
│
└ class Foo
        ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | - | - |

<a name='Ruby::UnexpectedError'></a>
## Ruby::UnexpectedError

Unexpected error is raised during type checking. Maybe a bug.


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | hint | - |

<a name='Ruby::UnexpectedJump'></a>
## Ruby::UnexpectedJump

Detected a `break` or `next` statement in invalid context.

### Ruby code

```ruby
break
```

### Diagnostic

```
test.rb:1:0: [error] Cannot jump from here
│ Diagnostic ID: Ruby::UnexpectedJump
│
└ break
  ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::UnexpectedJumpValue'></a>
## Ruby::UnexpectedJumpValue

A `break` or `next` statement has a value, but the value will be ignored.

### Ruby code

```ruby
while true
  next 3
end
```

### Diagnostic

```
test.rb:2:2: [error] The value given to next will be ignored
│ Diagnostic ID: Ruby::UnexpectedJumpValue
│
└   next 3
    ~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::UnexpectedKeywordArgument'></a>
## Ruby::UnexpectedKeywordArgument

A method call has an extra keyword argument.

### RBS

```rbs
class Foo
  def foo: (x: untyped) -> void
end
```

### Ruby code

```ruby
Foo.new.foo(x: 1, y: 2)
```

### Diagnostic

```
test.rb:7:18: [error] Unexpected keyword argument
│ Diagnostic ID: Ruby::UnexpectedKeywordArgument
│
└ Foo.new.foo(x: 1, y: 2)
                    ~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::UnexpectedPositionalArgument'></a>
## Ruby::UnexpectedPositionalArgument

A method call has an extra positional argument.

### RBS

```rbs
class Foo
  def foo: (untyped) -> void
end
```

### Ruby code

```ruby
Foo.new.foo(1, 2)
```

### Diagnostic

```
test.rb:7:15: [error] Unexpected positional argument
│ Diagnostic ID: Ruby::UnexpectedPositionalArgument
│
└ Foo.new.foo(1, 2)
                 ~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::UnexpectedSuper'></a>
## Ruby::UnexpectedSuper

A method definition has `super` syntax while no super method is defined in RBS.

### RBS

```rbs
class Foo
  def foo: () -> void
end
```

### Ruby code

```ruby
class Foo
  def foo = super
end
```

### Diagnostic

```
test.rb:2:12: [information] No superclass method `foo` defined
│ Diagnostic ID: Ruby::UnexpectedSuper
│
└   def foo = super
              ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | information | - | - |

<a name='Ruby::UnexpectedTypeArgument'></a>
## Ruby::UnexpectedTypeArgument

An extra type application is given to a method call.

### RBS

```rbs
class Foo
  def foo: [T] (T) -> T
end
```

### Ruby code

```ruby
Foo.new.foo(1) #$ Integer, Integer
```

### Diagnostic

```
test.rb:8:27: [error] Unexpected type arg is given to method type `[T] (T) -> T`
│ Diagnostic ID: Ruby::UnexpectedTypeArgument
│
└ Foo.new.foo(1) #$ Integer, Integer
                             ~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | - | - |

<a name='Ruby::UnexpectedYield'></a>
## Ruby::UnexpectedYield

A method definition without block has `yield` syntax.

### RBS

```rbs
class Foo
  def foo: () -> void
end
```

### Ruby code

```ruby
class Foo
  def foo
    yield
  end
end
```

### Diagnostic

```
test.rb:3:4: [hint] Cannot detect the type of the expression
│ Diagnostic ID: Ruby::FallbackAny
│
└     yield
      ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | information | - |

<a name='Ruby::UnknownConstant'></a>
## Ruby::UnknownConstant

A constant is not defined in the RBS definition.

### Ruby code

```ruby
FOO
```

### Diagnostic

```
test.rb:1:0: [error] Cannot find the declaration of constant: `FOO`
│ Diagnostic ID: Ruby::UnknownConstant
│
└ FOO
  ~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | hint | - |

<a name='Ruby::UnknownGlobalVariable'></a>
## Ruby::UnknownGlobalVariable

Short explanation ending with `.`

### Ruby code

```ruby
$foo
```

### Diagnostic

```
test.rb:1:0: [error] Cannot find the declaration of global variable: `$foo`
│ Diagnostic ID: Ruby::UnknownGlobalVariable
│
└ $foo
  ~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | warning | hint | - |

<a name='Ruby::UnknownInstanceVariable'></a>
## Ruby::UnknownInstanceVariable

An instance variable is not defined in RBS definition.

### Ruby code

```ruby
class Foo
  def foo
    @foo = 'foo'
  end
end
```

### Diagnostic

```
test.rb:3:4: [error] Cannot find the declaration of instance variable: `@foo`
│ Diagnostic ID: Ruby::UnknownInstanceVariable
│
└     @foo = 'foo'
      ~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | information | hint | - |

<a name='Ruby::UnknownRecordKey'></a>
## Ruby::UnknownRecordKey

An unknown key is given to record type.

### Ruby code

```ruby
{ name: "soutaro", email: "soutaro@example.com" } #: { name: String }
```

### Diagnostic

```
test.rb:1:19: [error] Unknown key `:email` is given to a record type
│ Diagnostic ID: Ruby::UnknownRecordKey
│
└ { name: "soutaro", email: "soutaro@example.com" } #: { name: String }
                     ~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | information | hint | - |

<a name='Ruby::UnreachableBranch'></a>
## Ruby::UnreachableBranch

A conditional always/never hold.

### Ruby code

```ruby
if false
  1
end
```

### Diagnostic

```
test.rb:1:0: [error] The branch is unreachable
│ Diagnostic ID: Ruby::UnreachableBranch
│
└ if false
  ~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | hint | - |

<a name='Ruby::UnreachableValueBranch'></a>
## Ruby::UnreachableValueBranch

A branch has a type other than `bot`, but unreachable.

This diagnostic skips the `bot` branch because we often have `else` branch to make the code defensive.

### Ruby code

```ruby
x = 1

case x
when Integer
  "one"
when String
  "two"
when Symbol
  raise "Unexpected value"
end
```

### Diagnostic

```
test.rb:5:0: [error] The branch may evaluate to a value of `::String` but unreachable
│ Diagnostic ID: Ruby::UnreachableValueBranch
│
└ when String
  ~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | warning | hint | hint | - |

<a name='Ruby::UnresolvedOverloading'></a>
## Ruby::UnresolvedOverloading

A method call has type errors, no more specific explanation cannot be reported.

### Ruby code

```ruby
3 + "foo"
```

### Diagnostic

```
test.rb:1:0: [error] Cannot find compatible overloading of method `+` of type `::Integer`
│ Method types:
│   def +: (::Integer) -> ::Integer
│        | (::Float) -> ::Float
│        | (::Rational) -> ::Rational
│        | (::Complex) -> ::Complex
│
│ Diagnostic ID: Ruby::UnresolvedOverloading
│
└ 3 + "foo"
  ~~~~~~~~~
```


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | error | information | - |

<a name='Ruby::UnsatisfiableConstraint'></a>
## Ruby::UnsatisfiableConstraint

Failed to solve constraint collected from a method call typing.


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | error | hint | hint | - |

<a name='Ruby::UnsupportedSyntax'></a>
## Ruby::UnsupportedSyntax

The syntax is not currently supported by Steep.


### Severity

| all_error | strict | default | lenient | silent |
| - | - | - | - | - |
| error | information | hint | hint | - |

