# Directives

Steep allows to mark up Ruby source code with directives to control type checking behavior.

## Syntax

```markdown
_ignore-block_ ::= _ignore-start_ _RUBY_ _ignore-end_

_ignore-start_ ::= `steep:ignore` _diagnostics_

_diagnostics_ ::= `all`
                | _diagnostic_ ...

_diagnostic_ ::= _error_name_

_ignore-end_ ::= `steep:ignore end`
```

## Ignore All diagnostics

```ruby
# steep:ignore all
''.hello  #=> NoMethod will be ignored inside `steep:ignore all` block
# steep:ignore end
```

## Ignore specific diagnostics

```ruby
# steep:ignore NoMethod
''.hello  #=> NoMethod will be ignored inside `steep:ignore NoMethod` block
p :never_reach if false  #=> Other diagnostics (ex. UnreachableBranch) will be reported
# steep:ignore end
```
