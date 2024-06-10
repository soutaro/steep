# Shapes

A *shape* is a data structure, which contains the set of available methods and their types, which is associated with a type. Steep uses shapes to type check method calls -- it calculates the shape of the type of the receiver, checks if the called method is defined on the shape and the arguments are compatible with the method, and calculates the return type.

Assume an interface `_Foo` is defined as follows:

```rbs
interface _Foo
  def foo: () -> String

  def bar: () -> self
end
```

The shape of `_Foo` will be the following:

```
Shape (_Foo) {
  foo: () -> String,
  bar: () -> _Foo
}
```

Note that the `self` type in the example is resolved to `_Foo` during shape calculation.

The shape calculation of an object is straightforward. Calculate a `RBS::Definition` of a class singleton/instance, or an interface, and translate the data structure to a `Shape` object. But there are a few things to consider.

## Tuple, record, and proc types

The shape of tuple, record, or proc types are based on their base types -- Array, Hash, or Proc classes --, but with specialized method types.

```
Shape ([Integer, String]) {
  []: (0) -> Integer
    | (1) -> String
    | (Integer) -> (Integer | String)
  ...
}
```

The specialization is implemented as a part of shape calculation.

## Special methods

Steep recognizes some special methods for type narrowing, including `#is_a?`, `#===`, `#nil?`, ... These methods are defined with normal RBS syntax, but the method types in shapes are transformed to types using logic types.

The shape calculation inserts the specialized methods with these special methods.

## `self` types

There are two cases of `self` types to consider during shape calculation.

1. `self` types included in the shape of a type
2. `self` types included in given types

### 1. `self` types included in the shape of a type

`self` types may be included in a class or interface definition.

```rbs
interface _Foo
  def itself: () -> self
end
```

The `self` types included in the shape of `_Foo` type should be resolved to `_Foo` type.

```
Shape (_Foo) {
  itself: () -> _Foo
}
```

### 2. `self` types included in given types

Unlike `self` types included in definitions, `self` types in given types should be preserved.

```rbs
interface _Foo[A]
  def get: () -> A
end
```

The shape of `_Foo[self]` has `self` type as its type argument, and we want the `self` type preserved after the shape calculation.

```
Shape (_Foo[self]) {
  get: () -> self
}
```

We often use `self` types as the return type of a method.

```rbs
class Foo
  def foo: () -> self
end
```

So, the implementation of `foo` might use `self` node to return `self` type.

```rb
class Foo
  def foo
    # @type var foo: _Foo[self]
    foo = ...
    foo.get
  end
end
```

We want the type of `foo.get` to be `self`, not `Foo`, to avoid a type error being detected.

## Shape of `self` types

We also want `self` type if `self` is the type of the shape.

```rb
class Foo
  def foo
    self.itself
  end
end
```

This is a straightforward case, because the type of `self` is `self` itself. Calculate the shape of it, but keep the `self` types in the shape.

```
Shape (self) {
  itself: () -> self
}
```

If `self` is a union type, or something built with a type constructor, the shape calculation gets complicated.

```rbs
class Foo
  def foo: () -> Integer
end

class Bar
  def foo: () -> self
end
```

What is the expected shape of `self` where the type of `self` is `Foo | Bar`?

The shape of a union type is straightforward. It calculates the shape of each type, and then it calculates a union of the shape.

We do the same for the case with `self` types, but it results in slightly incorrect shapes.

```
Shape (Foo) {
  foo: () -> Integer
}

Shape (Bar) {
  foo: () -> self   # self is preserved, because the shape of `self` is being calculated
}

Shape (Foo | Bar) {
  foo: () -> (Integer | self)
}
```

So, the resulting type of `self.foo` where the type of `self` is `Foo | Bar`, would be `Integer | Foo | Bar`. But, actually, it won't be `Foo` because the `self` comes from `Bar`.

This is an incorrect result, but Steep is doing this right now.

## `class` and `instance` types

The shape calculation provides limited support for `class` and `instance` types.

1. `class`/`instance` types from the definition are resolved
2. `class`/`instance` types in generics type arguments of interfaces/instances are preserved
3. Shape of `class`/`instance` types are resolved to configuration's `class_type` and `instance_type`, and the translated types are used to calculate the shape

It's different from `self` types except case #2. The relationship between `self`/`class`/`instance` is not trivial in Ruby. All of them might be resolved to any type, which means calculating one from another of them is simply impossible.

## Public methods, private methods

`Shape` objects have a flag of if the shape is for *public* method calls or *private* method calls. Private method call is a form of `foo()` or `self.foo()` -- when the receiver is omitted or `self`. Public method calls are anything else.

The shape calculation starts with *private methods*, and the `Shape#public_shape` method returns another shape that only has *public* methods.

> Note that the private shape calculation is required even on public method calls. This means a possible chance of future optimizations.

## Lazy method type calculation

We rarely need all of the methods available for an object. If we want to type check a method call, we only need the method type of that method. All other methods can be just ignored.

*Lazy method type calculation* is introduced for that case. Instead of calculating the types of all of the methods, it registers a block that computes the method type.

It is implemented in `Steep::Interface::Shape::Entry` and used to make the shape calculation of a union type faster.
