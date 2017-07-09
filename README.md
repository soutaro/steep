# Steep - Gradual Typing for Ruby

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'steep'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install steep

## Usage

Run `steep check` command in project dir.

```
$ steep check
$ steep check lib
```

It loads signatures from the global registry and `sig` dir in current dir.
If you want to load signuatres from dir different from `sig`, pass `-I` parameter.

```
$ steep check -I signauture -I sig .
```

Note that when `-I` option is given, `steep` does not load signatures from `sig` dir.

## Type Annotations

You have to write type annotations in your Ruby program.

```rb
# @import ActiveRecord.Try

class Foo
  # @class Foo<A> extends Object
  
  # @attribute results: (readonly) Array<A>
  attr_reader :results
  
  # @type initialize: () -> _
  def initialize()
    @results = []
  end
  
  # @type plus: (Addable<X, A>, X) -> A
  def plus(x, y)
    (x + y).try do |a|
      results << a
      a
    end
  end
end
```

## Signature

Steep does not allow types to be constructed from Ruby programs.
You have to write down signatures by yourself.

### Signature Scaffolding

Steep allows generate a *scaffold* from Ruby programs.

```
$ steep scaffold lib/**/*.rb
```

The generated scaffold includes:

* Signature definition for each class/module defined in the given program
* Method definition stub for each method

The scaffold may be a good starting point for writing signatures.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/steep.

