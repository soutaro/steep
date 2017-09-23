# Steep - Gradual Typing for Ruby

## Installation

Install via RubyGems.

    $ gem install steep --pre

Note that Steep is not released yet (pre-released). Add `--pre` for `gem install`.

### Requirements

Steep requires Ruby 2.4.

## Usage

Steep does not infer types from Ruby programs, but requires declaring types and writing annotations.
You have to go on the following three steps.

### 1. Declare Signatures

Declare signatures in `.rbi` files.

```
interface _Foo {
  def do_something: (String) -> any
}

module Fooable : _Foo {
  def foo: (Array<String>) { (String) -> String } -> any
}

class SuperFoo {
  include Fooable

  def name: -> String
  def do_something: (String) -> any
  def bar: (?Symbol, size: Integer) -> Symbol
}
```

### 2. Annotate Ruby Code

Write annotations to your Ruby code.

```rb
class Foo
  # @implements SuperFoo
  # @type const Helper: FooHelper

  # @dynamic name
  attr_reader :name

  def do_something(string)
    # ...
  end

  def bar(symbol = :default, size:)
    Helper.run_bar(symbol, size: size)
  end
end
```

### 3. Type Check

Run `steep check` command to type check.

```
$ steep check lib/foo.rb
foo.rb:41:18: NoMethodError: type=FooHelper, method=run_bar
foo.rb:42:24: NoMethodError: type=String, method==~
```

## Commandline

`steep check` is the command to run type checking.

### Signature Directory

Use `-I` option to specify signature file or signature directory.

    $ steep check -I my-types.rbi test.rb

If you don't specify `-I` option, it assumes `sig` directory.

### Detecting Fallback

When Steep finds a node which cannot be typed, it assumes the type of the node is *any*.
*any* type does not raise any type error so that fallback to *any* may hide some type errors.

Using `--fallback-any-is-error` option prints the fallbacks.

    $ steep check --fallback-any-is-error test.rb

### Dump All Types

When you are debugging, printing all types of all node in the source code may help.

Use `--dump-all-types` for that.

    $ steep check --dump-all-types test.rb

## Examples

You can find examples in `smoke` directory.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soutaro/steep.

