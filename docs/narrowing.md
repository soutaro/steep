# Narrowing implementation

> This is an internal doc for developers. [Narrowing guide](../guides/narrowing/narrowing.md) is for users.

The challenge is Ruby has special type predicate methods that should be supported by type checkers.
`#nil?` is used instead of `unless` statement to test if a value is a `nil` or not.
`#is_a?` or `#===` are used to confirm if a object is an instance of a class.
Negation and equaility are implemented as methods -- `#!` and `#==`.

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
x = [1, ""].sample

if x.is_a?(String)      # 1. The condition expression has `RECEIVER_IS_NIL`
  x.upcase              # 2. Steep overrides the type of `x` to `String` in *then* clause
else
                        # 3. Steep overrides the type of `x` to `Integer?` in *else* clause
end
```

## Logical types

We extend *type* with *logical types* as follows:

```
type ::= ...
       | NOT
       | RECEIVER_IS_NIL
       | RECEIVER_IS_NOT_NIL
       | RECEIVER_IS_ARG
       | ARG_IS_RECEIVER
       | ARG_EQUALS_RECEIVER
       | ENV(truthy_env, falsy_env)
```

## Syntax vs method calls


## Narrowing syntaxes

### Assignments

### `if`, `unless`

### `and`, `or`

### `case-when`

### `case-in`
