# Ignore diagnostics

Steep allows you to ignore diagnostics by adding comments to your code.

```ruby
# Ignoring a range of lines

# steep:ignore:start

foo()      # NoMethod is detected, but ignored

# steep:ignore:end
```

```ruby
# Ignoring a specific line

foo() # steep:ignore
foo() # steep:ignore NoMethod
```
