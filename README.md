# Steep - Gradual Typing for Ruby

## Installation

Install via RubyGems.

    $ gem install steep

### Requirements

Steep requires Ruby 2.6 or later.

## Usage

Steep does not infer types from Ruby programs, but requires declaring types and writing annotations.
You have to go on the following three steps.

### 0. `steep init`

Run `steep init` to generate a configuration file.

```
$ steep init       # Generates Steepfile
```

Edit the `Steepfile`:

```rb
target :app do
  check "lib"
  signature "sig"

  library "set", "pathname"
end
```

### 1. Declare Types

Declare types in `.rbs` files in `sig` directory.

```
class Person
  @name: String
  @contacts: Array[Email | Phone]

  def initialize: (name: String) -> untyped
  def name: -> String
  def contacts: -> Array[Email | Phone]
  def guess_country: -> (String | nil)
end

class Email
  @address: String

  def initialize: (address: String) -> untyped
  def address: -> String
end

class Phone
  @country: String
  @number: String

  def initialize: (country: String, number: String) -> untyped
  def country: -> String
  def number: -> String

  def self.countries: -> Hash[String, String]
end
```

* You can use simple *generics*, like `Hash[String, String]`.
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
    # `other` has type of `untyped`, which means type checking is skipped.
    # No type errors can be detected in this method.
    other.is_a?(self.class) && other.address == address
  end

  def hash
    self.class.hash ^ address.hash
  end
end

class Phone
  # @dynamic country, number
  attr_reader :country, :number

  def initialize(country:, number:)
    @country = country
    @number = number
  end

  def ==(other)
    # You cannot use `case` for type case because `other` has type of `untyped`, not a union type.
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
$ steep check
lib/phone.rb:46:0: MethodDefinitionMissing: module=::Phone, method=self.countries (class Phone)
```

You now find `Phone.countries` method is not implemented yet. 🙃

## Prototyping signature

You can use `rbs prototype` command to generate a signature declaration.

```
$ rbs prototype rb lib/person.rb lib/email.rb lib/phone.rb
class Person
  @name: untyped
  @contacts: Array[untyped]
  def initialize: (name: untyped) -> Array[untyped]
  def guess_country: () -> untyped
end

class Email
  @address: untyped
  def initialize: (address: untyped) -> untyped
  def ==: (untyped) -> untyped
  def hash: () -> untyped
end

class Phone
  @country: untyped
  @number: untyped
  def initialize: (country: untyped, number: untyped) -> untyped
  def ==: (untyped) -> void
  def hash: () -> untyped
end
```

It prints all methods, classes, instance variables, and constants.
It can be a good starting point to writing signatures.

Because it just prints all `def`s, you may find some odd points:

* The type of `initialize` in `Person` looks strange.
* There are no `attr_reader` methods extracted.

Generally, these are by our design.

`rbs prototype` offers options: `rbi` to generate prototype from Sorbet RBI and `runtime` to generate from runtime API.

## Examples

You can find examples in `smoke` directory.

## IDEs

Steep implements some of the Language Server Protocol features. 
- For **VSCode** please install [the plugin](https://github.com/soutaro/steep-vscode)
- For **SublimeText** please install [LSP](https://github.com/sublimelsp/LSP) package and follow [instructions](https://lsp.sublimetext.io/language_servers/#steep)

Other LSP supporting tools may work with Steep where it starts the server as `steep langserver`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soutaro/steep.

