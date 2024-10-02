# Diagnostics for Ruby
Each error description will follow the format below.

````
## Error Name

**Description**: Brief error description

**Example:**

```ruby
Ruby code that detects the error
```

```
Error messages obtained by running `steep check`
```

**severity**:

A table showing how the severity of the corresponding error is set in Steep's error presets
````


## Ruby::ArgumentTypeMismatch

**Description**: Occurs when the method types do not match.

**Example**:

```ruby
'1' + 1
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::BlockBodyTypeMismatch

**Description**: Occurs when the return type of the block body does not match the expected type.

**Example**:

```ruby
lambda {|x| x + 1 } #: ^(Integer) -> String
```

```
test.rb:1:7: [error] Cannot allow block body have type `::Integer` because declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::BlockBodyTypeMismatch
│
└ lambda {|x| x + 1 } #: ^(Integer) -> String
         ~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | information | nil |

## Ruby::BlockTypeMismatch

**Description**: Occurs when the block type does not match the expected type.

**Example**:

```ruby
multi = ->(x, y) { x * y } #: ^(Integer, Integer) -> Integer
[1, 2, 3].map(&multi)
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | information | nil |

## Ruby::BreakTypeMismatch

**Description**: Occurs when the type of `break` does not match the expected type.

**Example**:

```ruby
123.tap { break "" }
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | hint | nil |

## Ruby::DifferentMethodParameterKind

**Description**: Occurs when the types of method parameters do not match. This often happens when you forget to prefix optional arguments with `?`.

**Example**:

```ruby
# @type method bar: (name: String) -> void
def bar(name: "foo")
end
```

```
test.rb:2:8: [error] The method parameter has different kind from the declaration `(name: ::String) -> void`
│ Diagnostic ID: Ruby::DifferentMethodParameterKind
│
└ def bar(name: "foo")
          ~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::FallbackAny

**Description**: Indicates that untyped is used when the type is unknown. This often occurs in implementations where a value is initialized with `[]` and then reassigned later.

**Example**:

```ruby
a = []
a << 1
```

```
test.rb:1:4: [error] Cannot detect the type of the expression
│ Diagnostic ID: Ruby::FallbackAny
│
└ a = []
      ~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | warning | nil | nil |

## Ruby::FalseAssertion

**Description**: Occurs when Steep's type assertions are incorrect.

**Example**:

```ruby
array = [] #: Array[Integer]
hash = array #: Hash[Symbol, String]
```

```
test.rb:2:7: [error] Assertion cannot hold: no relationship between inferred type (`::Array[::Integer]`) and asserted type (`::Hash[::Symbol, ::String]`)
│ Diagnostic ID: Ruby::FalseAssertion
│
└ hash = array #: Hash[Symbol, String]
         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::ImplicitBreakValueMismatch

**Description**: Occurs when the value of an argument-less `break` (`nil`) does not match the expected return type of the method.

**Example**:

```ruby
class Foo
  # @rbs () { (String) -> Integer } -> String
  def foo
    ''
  end
end

Foo.new.foo do |x|
  break
end
```

```
test.rb:9:2: [error] Breaking without a value may result an error because a value of type `::String` is expected
│   nil <: ::String
│
│ Diagnostic ID: Ruby::ImplicitBreakValueMismatch
│
└   break
    ~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | nil | nil |

## Ruby::IncompatibleAnnotation

**Description**: Occurs when type annotations are inappropriate or do not match.

**Example**:

```ruby
a = [1,2,3]

if _ = 1
  # @type var a: String
  a + ""
end
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::IncompatibleArgumentForwarding

**Description**: Occurs when forwarding method arguments using `...` and the argument types do not match.

**Example**:

```ruby
class Foo
  # @rbs (*Integer) -> void
  def foo(*args)
  end

  # @rbs (*String) -> void
  def bar(...)
    foo(...)
  end
end
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | information | nil |

## Ruby::IncompatibleAssignment

**Description**: Occurs when the type in an assignment is inappropriate or does not match.

**Example**:

```ruby
# @type var x: Integer
x = "string"
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | hint | nil |

## Ruby::InsufficientKeywordArguments

**Description**: Occurs when keyword arguments are missing.

**Example**:

```ruby
class Foo
  def foo(a:, b:)
  end
end
Foo.new.foo(a: 1)
```

```
test.rb:5:8: [error] More keyword arguments are required: b
│ Diagnostic ID: Ruby::InsufficientKeywordArguments
│
└ Foo.new.foo(a: 1)
          ~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::InsufficientPositionalArguments

**Description**: Occurs when positional arguments are missing.

**Example**:

```ruby
class Foo
  def foo(a, b)
  end
end
Foo.new.foo(1)
```

```
test.rb:5:8: [error] More keyword arguments are required: b
│ Diagnostic ID: Ruby::InsufficientKeywordArguments
│
└ Foo.new.foo(a: 1)
          ~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::InsufficientTypeArgument

**Description**: Occurs when type annotations for type arguments are missing.

**Example**:

```ruby
class Foo
  # @rbs [T, S] (T, S) -> [T, S]
  def foo(x, y)
    [x, y]
  end
end

Foo.new.foo(1, 2) #$ Integer
```

```
test.rb:8:0: [error] Requires 2 types, but 1 given: `[T, S] (T, S) -> [T, S]`
│ Diagnostic ID: Ruby::InsufficientTypeArgument
│
└ Foo.new.foo(1, 2) #$ Integer
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::InvalidIgnoreComment

**Description**: Occurs when there are invalid comments, such as a `steep:ignore:start` comment without a corresponding `steep:ignore:end` comment.

**Example**:

```ruby
# steep:ignore:start
```

```
test.rb:1:0: [error] Invalid ignore comment
│ Diagnostic ID: Ruby::InvalidIgnoreComment
│
└ # steep:ignore:start
  ~~~~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | warning | warning | nil |

## Ruby::MethodArityMismatch

**Description**: Occurs when the method argument types do not match, such as describing a keyword argument as a positional argument.

**Example**:

```ruby
class Foo
  # @rbs (Integer x) -> Integer
  def foo(x:)
    x
  end
end
```

```
test.rb:3:9: [error] Method parameters are incompatible with declaration `(::Integer) -> ::Integer`
│ Diagnostic ID: Ruby::MethodArityMismatch
│
└   def foo(x:)
           ~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::MethodBodyTypeMismatch

**Description**: Occurs when the return type of a method does not match the expected type.

**Example**:

```ruby
class Foo
  # @rbs () -> String
  def foo
    1
  end
end
```

```
test.rb:3:6: [error] Cannot allow method body have type `::Integer` because declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::MethodBodyTypeMismatch
│
└   def foo
        ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | warning | nil |

## Ruby::MethodDefinitionMissing

**Description**: Occurs when a method's type definition exists, but the implementation is missing.

**Example**:

```ruby
class Foo
  # @rbs!
  #   def bar: () -> void
end
```

```
test.rb:1:6: [error] Cannot find implementation of method `::Foo#bar`
│ Diagnostic ID: Ruby::MethodDefinitionMissing
│
└ class Foo
        ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | nil | hint | nil | nil |

## Ruby::MethodParameterMismatch

**Description**: Occurs when the types of method parameters do not match.

**Example**:

```ruby
class Foo
  # @rbs (Integer x) -> Integer
  def foo(x:)
    x
  end
end
```

```
test.rb:3:10: [error] The method parameter is incompatible with the declaration `(::Integer) -> ::Integer`
│ Diagnostic ID: Ruby::MethodParameterMismatch
│
└   def foo(x:)
            ~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | warning | nil |

## Ruby::MethodReturnTypeAnnotationMismatch

**Description**: Occurs when the return type annotation of a method does not match the expected type.

**Example**:

```ruby
class Foo
  # @rbs () -> String
  def foo
    # @type return: Integer
    123
  end
end
```

```
test.rb:3:2: [error] Annotation `@type return` specifies type `::Integer` where declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::MethodReturnTypeAnnotationMismatch
│
└   def foo
    ~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::MultipleAssignmentConversionError

**Description**: Occurs when the conversion of multiple assignments fails.

**Example**:

```ruby
class WithToAry
  # @rbs () -> Integer
  def to_ary
    1
  end
end

a, b = WithToAry.new()
```

```
test.rb:8:8: [error] Cannot convert `::WithToAry` to Array or tuple (`#to_ary` returns `::Integer`)
│ Diagnostic ID: Ruby::MultipleAssignmentConversionError
│
└ (a, b = WithToAry.new())
          ~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::NoMethod

**Description**: Occurs when a method without a type definition is called.

**Example**:

```ruby
"".non_existent_method
```

```
test.rb:1:3: [error] Type `::String` does not have method `non_existent_method`
│ Diagnostic ID: Ruby::NoMethod
│
└ "".non_existent_method
     ~~~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::ProcHintIgnored

**Description**: Occurs when type annotations related to `Proc` are ignored.

**Example**:

```ruby
# @type var proc: (^(::Integer) -> ::String) | (^(::String, ::String) -> ::Integer)
proc = -> (x) { x.to_s }
```

```
test.rb:2:7: [error] The type hint given to the block is ignored: `(^(::Integer) -> ::String | ^(::String, ::String) -> ::Integer)`
│ Diagnostic ID: Ruby::ProcHintIgnored
│
└ proc = -> (x) { x.to_s }
         ~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | nil | nil |

## Ruby::ProcTypeExpected

**Description**: Occurs when a `Proc` type is expected.

**Example**:

```ruby
-> (&block) do
  # @type var block: Integer
end
```

```
test.rb:1:4: [error] Proc type is expected but `::Integer` is specified
│ Diagnostic ID: Ruby::ProcTypeExpected
│
└ -> (&block) do
      ~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::RBSError

**Description**: Occurs when the RBS type written in type assertions or type applications causes an error.

**Example**:

```ruby
a = 1 #: Int
```

```
test.rb:1:9: [error] Cannot find type `::Int`
│ Diagnostic ID: Ruby::RBSError
│
└ a = 1 #: Int
           ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | information | error | information | nil |

## Ruby::RequiredBlockMissing

**Description**: Occurs when a required block is missing during a method call.

**Example**:

```ruby
class Foo
  # @rbs () { () -> void } -> void
  def foo
    yield
  end
end
Foo.new.foo
```

```
test.rb:7:8: [error] The method cannot be called without a block
│ Diagnostic ID: Ruby::RequiredBlockMissing
│
└ Foo.new.foo
          ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | hint | nil |

## Ruby::ReturnTypeMismatch

**Description**: Occurs when the type of return does not match the method's `return` type.

**Example**:

```ruby
# @type method foo: () -> Integer
def foo
  return "string"
end
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | warning | nil |

## Ruby::SetterBodyTypeMismatch

**Description**: Occurs when the return type of a setter method does not match the expected type.

**Example**:

```ruby
class Foo
  # @rbs (String) -> String
  def foo=(value)
    123
  end
end
```

```
test.rb:3:6: [error] Setter method `foo=` cannot have type `::Integer` because declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::SetterBodyTypeMismatch
│
└   def foo=(value)
        ~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | information | error | nil | nil |

## Ruby::SetterReturnTypeMismatch

**Description**: Occurs when the `return` type of a setter method does not match the expected type.

**Example**:

```ruby
class Foo
  # @rbs (String) -> String
  def foo=(value)
    return 123
  end
end
```

```
test.rb:4:4: [error] The setter method `foo=` cannot return a value of type `::Integer` because declared as type `::String`
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::SetterReturnTypeMismatch
│
└     return 123
      ~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | information | error | nil | nil |

## Ruby::SyntaxError

**Description**: Occurs when a Ruby syntax error is encountered.

**Example**:

```ruby
if x == 1
  puts "Hello"
```

```
test.rb:2:14: [error] SyntaxError: unexpected token $end
│ Diagnostic ID: Ruby::SyntaxError
│
└   puts "Hello"
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | hint | hint | nil |

## Ruby::TypeArgumentMismatchError

**Description**: Occurs when the type argument does not match the expected type.

**Example**:

```ruby
class Foo
  # @rbs [T < Numeric] (T) -> T
  def foo(x)
    x
  end
end
Foo.new.foo("") #$ String
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::UnexpectedBlockGiven

**Description**: Occurs when a block is passed in a context where it is not expected.

**Example**:

```ruby
[1].at(1) { 123 }
```

```
test.rb:1:10: [error] The method cannot be called with a block
│ Diagnostic ID: Ruby::UnexpectedBlockGiven
│
└ [1].at(1) { 123 }
            ~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | hint | nil |

## Ruby::UnexpectedDynamicMethod

**Description**: Occurs when a dynamically defined method does not exist.

**Example**:

```ruby
class Foo
  # @dynamic foo

  def bar
  end
end
```

```
test.rb:1:6: [error] @dynamic annotation contains unknown method name `foo`
│ Diagnostic ID: Ruby::UnexpectedDynamicMethod
│
└ class Foo
        ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | nil | nil |

## Ruby::UnexpectedError

**Description**: Occurs when an unexpected general error is encountered.

**Example**:

```ruby
class Foo
  # @rbs () -> String123
  def foo
  end
end
```

```
test.rb:1:0: [error] UnexpectedError: sig/generated/test.rbs:5:17...5:26: Could not find String123(RBS::NoTypeFoundError)
│ ...
│   (36 more backtrace)
│
│ Diagnostic ID: Ruby::UnexpectedError
│
└ class Foo
  ~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | hint | nil |

## Ruby::UnexpectedJump

**Description**: Occurs when an unexpected jump is encountered.

**Example**:

```ruby
break
```

```
test.rb:1:0: [error] Cannot jump from here
│ Diagnostic ID: Ruby::UnexpectedJump
│
└ break
  ~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::UnexpectedJumpValue

**Description**: Occurs when the value passed in a jump is ignored.

**Example**:

```ruby
while true
  next 3
end
```

```
test.rb:2:2: [error] The value given to next will be ignored
│ Diagnostic ID: Ruby::UnexpectedJumpValue
│
└   next 3
    ~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::UnexpectedKeywordArgument

**Description**: Occurs when an unexpected keyword argument is passed.

**Example**:

```ruby
class Foo
  # @rbs (x: Integer) -> void
  def foo(x:)
  end
end

Foo.new.foo(x: 1, y: 2)
```

```
test.rb:7:18: [error] Unexpected keyword argument
│ Diagnostic ID: Ruby::UnexpectedKeywordArgument
│
└ Foo.new.foo(x: 1, y: 2)
                    ~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::UnexpectedPositionalArgument

**Description**: Occurs when an unexpected positional argument is passed.

**Example**:

```ruby
class Foo
  # @rbs (Integer) -> void
  def foo(x)
  end
end

Foo.new.foo(1, 2)
```

```
test.rb:7:15: [error] Unexpected positional argument
│ Diagnostic ID: Ruby::UnexpectedPositionalArgument
│
└ Foo.new.foo(1, 2)
                 ~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::UnexpectedSuper

**Description**: Occurs when `super` is used in an unexpected context, such as when there is no method with the same name defined in the parent class.

**Example**:

```ruby
class Foo
  def foo
    super
  end
end
```

```
test.rb:3:4: [error] No superclass method `foo` defined
│ Diagnostic ID: Ruby::UnexpectedSuper
│
└     super
      ~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | information | error | nil | nil |

## Ruby::UnexpectedTypeArgument

**Description**: Occurs when an unexpected type argument is passed.

**Example**:

```ruby
class Foo
  # @rbs [T] (T) -> T
  def foo(x)
    x
  end
end

Foo.new.foo(1) #$ Integer, Integer
```

```
test.rb:8:27: [error] Unexpected type arg is given to method type `[T] (T) -> T`
│ Diagnostic ID: Ruby::UnexpectedTypeArgument
│
└ Foo.new.foo(1) #$ Integer, Integer
                             ~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | nil | nil |

## Ruby::UnexpectedYield

**Description**: Occurs when `yield` is used in an unexpected context.

**Example**:

```ruby
class Foo
  # @rbs () -> void
  def foo
    yield
  end
end
```

```
test.rb:4:4: [error] No block given for `yield`
│ Diagnostic ID: Ruby::UnexpectedYield
│
└     yield
      ~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | information | nil |

## Ruby::UnknownConstant

**Description**: Occurs when an unknown constant is referenced.

**Example**:

```ruby
FOO
```

```
test.rb:1:0: [error] Cannot find the declaration of constant: `FOO`
│ Diagnostic ID: Ruby::UnknownConstant
│
└ FOO
  ~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | hint | nil |

## Ruby::UnknownGlobalVariable

**Description**: Occurs when an unknown global variable is referenced.

**Example**:

```ruby
$foo
```

```
test.rb:1:0: [error] Cannot find the declaration of global variable: `$foo`
│ Diagnostic ID: Ruby::UnknownGlobalVariable
│
└ $foo
  ~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | warning | error | hint | nil |

## Ruby::UnknownInstanceVariable

**Description**: Occurs when an unknown instance variable is referenced.

**Example**:

```ruby
class Foo
  def foo
    @foo = 'foo'
  end
end
```

```
test.rb:3:4: [error] Cannot find the declaration of instance variable: `@foo`
│ Diagnostic ID: Ruby::UnknownInstanceVariable
│
└     @foo = 'foo'
      ~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | information | error | hint | nil |

## Ruby::UnreachableBranch

**Description**: Occurs when there are unreachable branches due to `if` or `unless`.

**Example**:

```ruby
if false
  1
end
```

```
test.rb:1:0: [error] The branch is unreachable
│ Diagnostic ID: Ruby::UnreachableBranch
│
└ if false
  ~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | hint | nil |

## Ruby::UnreachableValueBranch

**Description**: Occurs when there are unreachable branches due to `case when`, and the type of the branches is not `bot`.

**Example**:

```ruby
x = 1
case x
when Integer
  "one"
when String
  "two"
end
```

```
test.rb:5:0: [error] The branch may evaluate to a value of `::String` but unreachable
│ Diagnostic ID: Ruby::UnreachableValueBranch
│
└ when String
  ~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | warning | hint | nil |

## Ruby::UnresolvedOverloading

**Description**: Occurs when the type cannot be resolved for an overloaded method.

**Example**:

```ruby
3 + "foo"
```

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

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | error | error | information | nil |

## Ruby::UnsatisfiableConstraint

**Description**: Occurs when type constraints cannot be satisfied, such as when there is a mismatch between RBS and type annotations.

**Example**:

```ruby
class Foo
  # @rbs [A, B] (A) { (A) -> void } -> B
  def foo(x)
  end
end

test = Foo.new

test.foo(1) do |x|
  # @type var x: String
end
```

```
test.rb:9:0: [error] Unsatisfiable constraint `::Integer <: A(1) <: ::String` is generated through (A(1)) { (A(1)) -> void } -> B(2)
│   ::Integer <: ::String
│     ::Numeric <: ::String
│       ::Object <: ::String
│         ::BasicObject <: ::String
│
│ Diagnostic ID: Ruby::UnsatisfiableConstraint
│
└ test.foo(1) do |x|
  ~~~~~~~~~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | error | hint | nil |

## Ruby::UnsupportedSyntax

**Description**: Occurs when syntax that is not supported by Steep is used.

**Example**:

```ruby
(_ = []).[]=(*(_ = nil))
```

```
test.rb:1:13: [error] Unsupported splat node occurrence
│ Diagnostic ID: Ruby::UnsupportedSyntax
│
└ (_ = []).[]=(*(_ = nil))
               ~~~~~~~~~~
```

**severity**:

| all_error | default | strict | lenient | silent |
| --- | --- | --- | --- | --- |
| error | hint | information | hint | nil |
