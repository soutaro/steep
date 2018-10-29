# Steep - Gradual Typing for Ruby

## Installation

Install via RubyGems.

    $ gem install steep

### Requirements

Steep requires Ruby 2.5.

## Usage

Steep does not infer types from Ruby programs, but requires declaring types and writing annotations.
You have to go on the following three steps.

### 1. Declare Types

Declare types in `.rbi` files in `sig` directory.

```
class Person
  @name: String
  @contacts: Array<Email | Phone>

  def initialize: (name: String) -> any
  def name: -> String
  def contacts: -> Array<Email | Phone>
  def guess_country: -> (String | nil)
end

class Email
  @address: String

  def initialize: (address: String) -> any
  def address: -> String
end

class Phone
  @country: String
  @number: String

  def initialize: (country: String, number: String) -> any
  def country: -> String
  def number: -> String

  def self.countries: -> Hash<String, String>
end
```

* You can use simple *generics*, like `Hash<String, String>`.
* You can use *union types*, like `Email | Phone`.
* You have to declare not only public methods but also private methods and instance variables.
* You can declare *singleton methods*, like `self.countries`.
* There is `nil` type to represent *nullable* types.

### 2. Write Ruby Code

Write Ruby code with annotations.

```rb
class Person
  # `@dynamic` annotation is to tell steep that
  # the `name` and `contacts` methods are defined without def syntax.
  # (Steep can skip checking if the methods are implemented.)

  # @dynamic name, contacts
  attr_reader :name
  attr_reader :contacts

  def initialize(name:)
    @name = name
    @contacts = []
  end

  def guess_country()
    contacts.map do |contact|
      # With case expression, simple type-case is implemented.
      # `contact` has type of `Phone | Email` but in the `when` clause, contact has type of `Phone`.
      case contact
      when Phone
        contact.country
      end
    end.compact.first
  end
end

class Email
  # @dynamic address
  attr_reader :address

  def initialize(address:)
    @address = address
  end

  def ==(other)
    # `other` has type of `any`, which means type checking is skipped.
    # No type errors can be detected in this method.
    other.is_a?(self.class) && other.address == address
  end

  def hash
    self.class.hash ^ address.hash
  end
end

class Phone
  # @dynamic country, number

  def initialize(country:, number:)
    @country = country
    @number = number
  end

  def ==(other)
    # You cannot use `case` for type case because `other` has type of `any`, not a union type.
    # You have to explicitly declare the type of `other` in `if` expression.

    if other.is_a?(Phone)
      # @type var other: Phone
      other.country == country && other.number == number
    end
  end

  def hash
    self.class.hash ^ country.hash ^ number.hash
  end
end
```

### 3. Type Check

Run `steep check` command to type check. 💡

```
$ steep check lib
lib/phone.rb:46:0: MethodDefinitionMissing: module=::Phone, method=self.countries (class Phone)
```

You now find `Phone.countries` method is not implemented yet. 🙃

## Scaffolding

You can use `steep scaffold` command to generate a signature declaration.

```
$ steep scaffold lib/*.rb
class Person
  @name: any
  @contacts: Array<any>
  def initialize: (name: any) -> Array<any>
  def guess_country: () -> any
end

class Email
  @address: any
  def initialize: (address: any) -> any
  def ==: (any) -> any
  def hash: () -> any
end

class Phone
  @country: any
  @number: any
  def initialize: (country: any, number: any) -> any
  def ==: (any) -> void
  def hash: () -> any
end
```

It prints all methods, classes, instance variables, and constants.
It can be a good starting point to writing signatures.

Because it just prints all `def`s, you may find some odd points:

* The type of `initialize` in `Person` looks strange.
* There are no `attr_reader` methods extracted.

Generally, these are by our design.

## Commandline

`steep check` is the command to run type checking.

### Signature Directory

Use `-I` option to specify signature file or signature directory.

    $ steep check -I my-types.rbi test.rb

If you don't specify `-I` option, it assumes `sig` directory.

### Detecting Fallback

When Steep finds an expression which cannot be typed, it assumes the type of the node is *any*.
*any* type does not raise any type error so that fallback to *any* may hide some type errors.

Using `--fallback-any-is-error` option prints the fallbacks.

    $ steep check --fallback-any-is-error test.rb

### Dump All Types

When you are debugging, printing all types of all node in the source code may help.

Use `--dump-all-types` for that.

    $ steep check --dump-all-types test.rb

### Verbose Option

Try `-v` option to report more information about type checking.

### Loading Type definitions from Gems

You can pass `-G` option to specify name of gems to load type definitions.

```
$ steep check -G strong_json lib
```

When you are using bundler, Steep load type definitions from bundled gems automatically.

```
$ bundle exec steep check lib
```

To disable automatic gem detection from bundler, you can specify `--no-bundler` option.

```
$ bundle exec steep check --no-bundler -G strong_json lib
```

## Making a Gem with Type Definition

Put your type definition file in a directory, ship that in your gem, and let `metadata` of the gemspec to contain `"steep_types" => dir_name`.

```rb
spec.metadata = { "steep_types" => "sig" }
```

We recommend using `sig` as a name of the directory for type definitions, but you can use any directory.

## Examples

You can find examples in `smoke` directory.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soutaro/steep.

