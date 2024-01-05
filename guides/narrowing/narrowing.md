# Type Narrowing

Steep supports several types of *type narrowing*. Assume a local variable `x` has type of `String?`, `String` or `nil`. The value of `x` is either an instance of `String` or `nil`, but it cannot be both. Type narrowing is a mechanic to allow the Ruby code distinguish a `String` from `nil` and vice vesa.

```ruby
x = ["foo", "bar", nil].sample    # Type of `x` is `String?`

if x
  # `x` is `String` because of if statement
  puts x.upcase
else
  # `x` is `nil`
end
```

Type narrowing is a feature to recover type `T` from union type `T | S | ...`.

## Conditional narrowing

Conditional in Ruby is one of the most common syntax constructs where type narrowing is expected by the end users.

```ruby
user = User.find_by(email: params[:email]) or raise
```

Optional types `T?` or union types with `false` type are the types that is handled with this narrowing. We can partiton `nil` and `false` from other types.

## Non-nil narrowing

Non-nil narrowing is similar to conditional narrowing, but it's more specific that only `nil` type (not `false` type) can be extracted from other types. This happens typically with safe-navigation-operator. Steep also supports `Kernel#nil?` predicate for better compatibility with convensions.

```ruby
value = [1, false, nil].sample  # `value` is `Integer | nil | false`

value&.yield_self do |value|
  # `value` is `Integer | false`, not a `nil`
end

if value.nil?
  # Steep also supports `Kernel#nil?`
end
```

## `is_a?` narrowing

(TBD)
