# Getting Started with Steep in 5 minutes

## Installing Steep

Add the lines to Gemfile:

```rb
group :development do
  gem "steep", require: false
end
```

and install the gems.

```
$ bundle install
```

You can install it with the gem command.

```
$ gem install steep
```

Execute the following command to confirm if the command is successfully installed.

```
$ steep version
$ bundle exec steep version         # When you install with bundler
```

We omit the `bundle exec` prefix from the following commands. Run commands with the prefix if you install Steep with bundler.

## Type checking your first Ruby script

Run steep init command to generate the configuration file, Steepfile.

```
$ steep init
```

Open `Steepfile` in your text editor, and replace the content with the following lines:

```rb
target :lib do
  signature "sig"
  check "lib"
end
```

Type the following Ruby code in your editor, and save it as `lib/hello.rb`.

```rb
currencies = { US: "$", JP: "¥", UK: "£" }
country = %w(US JP UK).sample()

puts "Hello! The price is #{currencies[country.to_sym]}100. 💸"
```

And type check it with Steep.

```
$ steep check
```

The output will report a type error.

```
# Type checking files:

........................................................F

lib/hello.rb:4:39: [error] Cannot pass a value of type `(::String | nil)` as an argument of type `::Symbol`
│   (::String | nil) <: ::Symbol
│     ::String <: ::Symbol
│       ::Object <: ::Symbol
│         ::BasicObject <: ::Symbol
│
│ Diagnostic ID: Ruby::ArgumentTypeMismatch
│
└ puts "Hello! The price is #{currencies[country]}100. 💸"
                                         ~~~~~~~

Detected 1 problem from 1 file
```

The error says that the type of the country variable causes a type error. It is expected to be a Symbol, but String or nil will be given.

Let's see how we can fix the error.

## Fixing the type error

The first step is converting the string value to a symbol. We can add to_sym call.

```rb
currencies = { US: "$", JP: "¥", UK: "£" }
country = %w(US JP UK).sample()

puts "Hello! The price is #{currencies[country.to_sym]}100. 💸"
```

The `#to_sym` call will convert a string into a symbol. Does it solve the problem??

```
$ steep check
# Type checking files:

........................................................F

lib/hello.rb:4:47: [error] Type `(::String | nil)` does not have method `to_sym`
│ Diagnostic ID: Ruby::NoMethod
│
└ puts "Hello! The price is #{currencies[country.to_sym]}100. 💸"
                                                 ~~~~~~

Detected 1 problem from 1 file
```

It detects another problem. The first error was `Ruby::ArgumentTypeMismatch`, but the new error is `Ruby::NoMethod`. The value of `country` may be `nil`, and it doesn't have the `#to_sym` method.

This would be annoying, but one of the most common sources of a type error. The value of an expression may be `nil` unexpectedly, and using the value of the expression may cause an error.

In this case, the `sample()` call introduces the `nil`. `Array#sample()` returns `nil` when the array is empty. We know the receiver of the `sample` call cannot be `nil`, because it is an array literal. But the type checker doesn't know of it. The source code detects the `Array#sample()` method is called, but it ignores the fact that the receiver cannot be empty.

Instead, we can simply tell the type checker that the value of the country cannot be `nil`.

# Satisfying the type checker by adding a guard

The underlying type system supports flow-sensitive typing similar to TypeScript and Rust. It detects conditional expressions testing the value of a variable and propagates the knowledge that the value cannot be `nil`.

We can fix the type error with an or construct.

```rb
currencies = { US: "$", JP: "¥", UK: "£" }
country = %w(US JP UK).sample() or raise

puts "Hello! The price is #{currencies[country.to_sym]}100. 💸"
```

The change let the type checking succeed.

```
$ steep check
# Type checking files:

.........................................................

No type error detected. 🧉
```

The `raise` method is called when `sample()` returns `nil`. Steep can reason the possible control flow based on the semantics of or in Ruby:

* The value of `country` is the return value of `sample()` method call
* The value of `country` may be `nil`
  * If the value of `country` is `nil`, the right hand side of the or is evaluated
  * It calls the `raise` method, which results in an exception and jumps to somewhere
  * So, when the execution continues to the puts line, the value of `country` cannot be `nil`

There are two possibilities of the type of the result of the `sample()` call, `nil` or a string. We humans can reason that we can safely ignore the case of `nil`. But, the type checker cannot. We have to add `or raise` to tell the type checker it can stop considering the case of `nil` safely.

## Next steps

This is a really quick introduction to using Steep. You may have noticed that I haven't explained anything about defining new classes or modules. See the RBS guide for more examples!

