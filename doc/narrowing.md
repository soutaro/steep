# Narrowing Implementation

> This is an internal doc for Steep developers. [Narrowing guide](../guides/narrowing/narrowing.md) is for users.

The challenge is Ruby has special type predicate methods that should be supported by type checkers. `#nil?` is used instead of `unless` statement to test if a value is a `nil` or not. `#is_a?` or `#===` are used to confirm if an object is an instance of a class. Negation and equality are implemented as methods -- `#!` and `#==`.

Steep supports those methods by introducing special types for those methods.

```rbs
# This is not a valid RBS type definition.
# Steep implements a transformation from valid RBS syntax to those special types.
module Kernel
  def nil?: () -> RECEIVER_IS_NIL

  def is_a?: (Class klass) -> RECEIVER_IS_ARG
end
```

When type checking a conditional resulted in `RECEIVER_IS_NIL` type, the type checker overrides the type of the expressions inside the *then* and *else* clauses.

```ruby
x = [1, ""].sample      # The type of `x` is `String | Integer | nil`

unless x.is_a?(String)  # 1. The condition expression has `RECEIVER_IS_NIL`
  x.upcase              # 2. Steep overrides the type of `x` to `String` in *then* clause
else
                        # 3. Steep overrides the type of `x` to `Integer | nil` in *else* clause
end
```
## Logical types

We extend *type* with *logical types* as follows:

```
type ::= ...
       | NOT                           # Negation of type of receiver
       | RECEIVER_IS_NIL               # Receiver is nil when it evaluates to truthy
       | RECEIVER_IS_NOT_NIL           # Receiver is not nil when it evaluates to truthy
       | RECEIVER_IS_ARG               # Receiver is an instance of argument when it evaluates to truthy
       | ARG_IS_RECEIVER               # Argument is an instance of receiver when it evaluates to truthy
       | ARG_EQUALS_RECEIVER           # Argument is equal to receiver when it evaluates to truthy
       | ENV(original_type, truthy_env, falsy_env)    # Two type environments for truthy and falsy
```
### ENV type

`ENV` looks a bit different from others because it takes arguments. The type is used for `and` and `or`.

Consider the example with local variables `x` and `y` where both of them have type `String?`.

```ruby
(x && y) && (x + y)   # Parens added for ease of reading
```

The type of the whole expression is `String?`. When `x` or `y` is `nil`, it evaluates to `nil`. If both of `x` and `y` is a `String`, `x + y` evaluates to `String` because of the definition of `String#+`.

The type narrowing starts with the top expression.

```ruby
(...) && (x + y)
```

It immediately type checks the left hand side, but with *conditional mode*. Conditional mode is a special flag that the type checking result should keep as many of the environments as possible.

```ruby
x && y
```

Going down again, it gets a typing `x: String?` and `y: String?`. It runs a type narrowing, to obtain a result both of `x` and `y` are `String` for truthy result, both of `x` and `y` are `String?` for falsy result. The two environments should be propagated to the upper node, because the parent node is also `&&` which is a subject of type narrowing. So, it returns an `ENV` type, `String?` for original type, `{ x: String, y: String }` for truthy result, and `{ x: String?, y: String? }` for falsy result.

Going up to the outer `&&` expression. The left hand side has `ENV` type, and then the right hand side is type checked based on the truthy environment (because of the semantics of `&&` expression.) Both `x` and `y` are `String` and it type checks. The type of the whole expression union of `String` and the falsy part of the original type -- `nil`.
## Union type partition

We introduce *partition* function for union types. It returns a pair of two types -- truthy parts and falsy parts. We need a slightly different variant for *non-nil* partition to support safe-navigation-operator.

```
Pt(T) -> T? ⨉ T?    # Truthy partition
Pn(T) -> T? ⨉ T?    # Non-nil partition
```

Both return a pair of optional types for non-falsy/non-nil types.

```
Pt(false?)  -> ∅ ⨉ false?
Pn(false)   -> false ⨉ ∅
```

Note that we cannot partition non-regular recursive types, but that types are prohibited in RBS.
## Type environment

Type environment is a mapping from local variables to their types. It's extended in Steep to support overriding type of *pure* expressions.

```
E ::= ∅
    | x : T, E       # Type of a local variable -- `x`
    | p : T, E       # Type of a pure expression -- `p`
```

Pure expressions are defined recursively as following:

* *Value expressions* are pure
* Call expressions of *pure methods* with pure arguments are pure

Note that expression purity depends on the result of type checking of the expression because it requires to detect if a method call is *pure* or not.
## Logic type interpreter
Logic type interpreter is an additional layer to support type narrowing. It is a function that takes an expression and it's typing, and returns a pair of type environments -- one for the case the value of the expr is *truthy* and another for the case the value is *falsy*.

```
I(expr : T) -> E ⨉ E
```

It takes account of assignments to local variables.

```
I(x = y : String?) -> { x: String, y: String } ⨉ { x: nil, y: nil }
```

It also calculates the reachability to truthy and falsy results which can be used to detect unreachable branches.
## Narrowing syntaxes
### Simple conditionals -- `if`, `while`, `and`, ...
Type checking those syntaxes are simple. It type checks the condition expression with conditional mode, passes the expression to logic type interpreter, uses the type environments to type check then and else clauses.

Steep also reports unreachable branch issues based on the reachability calculated by logic type interpreter.
### `case-when`
The easier case is if `case-when` doesn't have a node just after `case` token.

```ruby
case
when x == 1
  ...
end
```

This is the same with simple conditionals.

The difficult case is if `case-when` syntax has a node.

```ruby
case foo()
when Integer
  ...
when String
  ...
end
```

Ruby uses the `===` operator to test if the value of `foo()` matches the condition, while we don't want to type check `foo()` calls every time. It may be a pure expression, and we can give better type narrowing using the *falsy* results of predecessor `when` clauses.

So, we transform the condition expression given to the logic type interpreter to value form.

```ruby
__case_when:x01jg9__ = foo()
if Integer === __case_when:x01jg9__
  ...
elsif String === __case_when:x01jg9__
  ...
end
```

It generates a fresh local variable and assigns the expression to it. Uses the variable inside the patterns.

We also need to propagate the type of local variables which are included in the expression.

```ruby
case x = foo()
when Integer
  x.abs      # x should be Integer
when String
  x.upcase   # x should be String
end
```

The local variable insertion is done at the outermost non-assignment position to support the local variable propagation.

```ruby
__case_when:x01jg9__ = foo()
if Integer === (x = __case_when:x01jg9__)
  ...
elsif String === (x = __case_when:x01jg9__)
  ...
end
```

The last trick to type check case-when is *pure call* narrowing in the bodies.

```ruby
__case_when:x01jg9__ = foo()
if Integer === (x = __case_when:x01jg9__)
  foo.abs
elsif String === (x = __case_when:x01jg9__)
  foo.upcase
end
```

To support this, we propagate the type of the fresh local variable to the type of right hand side expression, if it's a pure call.

