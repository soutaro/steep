# Ruby Code Diagnostics

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


## Ruby::InsufficientKeywordArguments

A method call needs more keyword arguments.

### Ruby code

```ruby
class Foo
  def foo(a:, b:)
  end
end

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


## Ruby::InsufficientPositionalArguments

An method call needs more positional arguments.

### Ruby code

```ruby
class Foo
  def foo(a, b)
  end
end

Foo.new.foo(1)
```

### Diagnostic

```
test.rb:5:8: [error] More keyword arguments are required: b
│ Diagnostic ID: Ruby::InsufficientKeywordArguments
│
└ Foo.new.foo(a: 1)
          ~~~~~~~~~
```


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


## Ruby::ReturnTypeMismatch

A `return` statement has a value that has an incompatible type to the return type of the method.

### Ruby code

```ruby
# @rbs () -> Integer
def foo
  return "string"
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


## Ruby::UnexpectedKeywordArgument

A method call has an extra keyword argument.

### Ruby code

```ruby
class Foo
  # @rbs (x: Integer) -> void
  def foo(x:)
  end
end

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


## Ruby::UnexpectedPositionalArgument

A method call has an extra positional argument.

### Ruby code

```ruby
class Foo
  def foo(x)
  end
end

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


