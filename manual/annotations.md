# Annotations

## Core Annotations

### Variable type

Variable type annotation tells type of local variable.

#### Example

```
# @type var x: String
# @type var klass: Class
```

#### Syntax

* `@type` `var` *x* `:` *type*

### Self type

Self type annotation tells type of `self`.

#### Example

```
# @type self: Object
```

#### Syntax

* `@type` `self` `:` *type*

### Instance variable type

Instance variable type annotation tells type of instance variable.
This annotation applies to instance variable of current context.
If it's written in `module` declaration, it applies to instance variable of the module, not its instance.

#### Example

```
# @type ivar @owner: Person
```

#### Syntax

* `@type` `ivar` *ivar* `:` *type*

### Global variable type

Global variable type annotation tells type of global variable.

#### Example

```
# @type gvar $LOAD_PATH: Array<String>
```

#### Syntax

* `@type` `gvar` *gvar* `:` *type*

### Constant type

Constant type annotation tells type of constant.
Note that constant resolution is done syntactically.
Annotation on `File::Append` does not apply to `::File::Append`.

#### Example

```
# @type const File::Append : Integer
```

#### Syntax

* `@type` `const` *const* `:` *type*

### Method type annotation

Method type annotation tells type of method being implemented in current scope.

This annotation is used to tell types of method parameters and its body.
Union method type cannot be written.

#### Example

```
# @type method foo: (String) -> any
```

#### Syntax

* `@type` `method` *method* `:` *single method type*

## Module Annotations

Module annotations is about defining modules and classes in Ruby.
This kind of annotations should be written in module context.

### Instance type annotation

Instance type annotation tells type of instance of class or module which is being defined.

#### Example

```
# @type instance: Foo
```

#### Syntax

* `@type` `instance` `:` *type*

### Module type annotation

Module type annotation tells type of module of class or module which is being defined.

#### Example

```
# @type module: Foo.class
```

#### Syntax

* `@type` `module` `:` *type*

### Instance/module ivar type annotation

This annotation tells instance variable of instance.

#### Example

```
# @type instance ivar @x: String
# @type module ivar @klass: String.class
```

#### Syntax

* `@type` `instance` `ivar` *ivar* `:` *type*
* `@type` `module` `ivar` *ivar* `:` *type*

## Method Annotations

Method annotations are about hinting behavior of the method.

This kind of annotations should be written in the method context using annotation notation (ex. `%a{...}`) in the RBS file.

Supported annotations are:

* `pure`: The method is a [pure method](https://github.com/soutaro/steep/wiki/Release-Note-1.1#type-narrowing-on-method-calls-590).  This means the method will return a value of the same type during the block.  Note that there is no validation, enforcement, or proof that the implementations of *pure* methods are actually pure.
* `deprecated`: The method is deprecated.  This means that the method is no longer recommended for use, and may be removed in the future.  Developers can add the description to the annotation (ex. `%a{deprecated: since v0.9}`).
* `steep:deprecated`: Same as `deprecated`.

### Example

```rbs
class Foo
  %a{pure}
  def foo: () -> String
end
```

## Type assertion

Type assertion allows declaring type of an expression inline, without introducing new local variable with variable type annotation.

### Example

```
array = [] #: Array[String]

path = nil #: Pathname?
```

##### Syntax

* `#:` *type*

## Type application

Type application is for generic method calls.

### Example

```
table = accounts.each_with_object({}) do |account, table| #$ Hash[String, Account]
  table[account.email] = account
end
```

The `each_with_object` method has `[T] (T) { (Account, T) -> void } -> T`,
and the type application syntax directly specifies the type of `T`.

So the resulting type is `(Hash[String, Account]) { (Account, Hash[String, Account]) -> void } -> Hash[String, Account]`.

#### Syntax

* `#$` *type*
