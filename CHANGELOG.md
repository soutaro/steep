# CHANGELOG

## master

## 0.15.0 (2020-05-05)

* Add type checking configuration to dsl ([#132](https://github.com/soutaro/steep/pull/132))
* More flow sensitive type checking

## 0.14.0 (2020-02-24)

* Implementat LSP _completion_. ([#119](https://github.com/soutaro/steep/pull/119))
* Update ruby-signature. ([#120](https://github.com/soutaro/steep/pull/120))
* Rescue errors during `langserver`. ([#121](https://github.com/soutaro/steep/pull/121))
* Pass hint when type checking `return`. ([#122](https://github.com/soutaro/steep/pull/122))
* Remove trailing spaces from Steepfile. ([#118](https://github.com/soutaro/steep/pull/118))

## 0.13.0 (2020-02-16)

* Improve LSP _hover_ support. ([#117](https://github.com/soutaro/steep/pull/117))

## 0.12.0 (2020-02-11)

* Add `Steepfile` for configuration
* Use the latest version of `ruby-signature`

## 0.11.1 (2019-07-15)

* Relax activesupport versnion requirement (#90)

## 0.11.0 (2019-05-18)

* Skip `alias` nodes type checking (#85)
* Add experimental LSP support (#79. #83)
* Fix logging (#81)

## 0.10.0 (2019-03-05)

* Add `watch` subcommand (#77)
* Automatically `@implements` super class if the class definition inherits
* Fix tuple typing
* Fix `or` typing

## 0.9.0 (2018-11-11)

* Private methods (#72)
* `__skip__` to skip type checking (#73)
* Add `alias` for method types (#75)
* Fix `Names::Base#hash` (#69 @hanachin)
* Add `super` in method types (#76)

## 0.8.2 (2018-11-09)

* Fix ElseOnExhaustiveCase error implementation
* Add some builtin methods

## 0.8.1 (2018-10-29)

* Remove duplicated detected paths (#67)

## 0.8.0 (2018-10-29)

* Load types from gems (#64, #66)
* Fix exit status (#65)
* Fix `--version` handling (#57 @ybiquitous, #58)
* Add `Regexp` and `MatchData` (#58 @ybiquitous)

## 0.7.1 (2018-10-22)

* Rename *hash type* to *record type* (#60)
* Fix keyword typing (#59)

## 0.7.0 (2018-09-24)

* Add some builtin
* Fix array argument typing
* Allow `@type` instance variable declaration in signature
* Fix `@type` annotation parsing
* Fix polymorphic method type inference
* Fix relative module lookup
* Fix module name tokenization

## 0.6.0 (2018-09-23)

* Update ast_utils
* Introduce *hash* type `{ id: Integer, name: String }` (#54)
* Revise signature syntax; use `<` instead of `<:` for inheritance (#53)
* Interface and alias name can be namespaced (#52)
* Grammar formatting (#51 @iliabylich)

## 0.5.1 (2018-08-11)

* Relax dependency requirements (#49, #50)

## 0.5.0 (2018-08-11)

* Support *lambda* `->` (#47)
* Introduce *incompatible* method (#45)
* Add type alias (#44)
* Steep is MIT license (#43)
* Improved block parameter typing (#41)
* Support optional block
* Support attributes in module
* Support `:xstr` node
* Allow missing method definition with `steep check` without `--strict`

## 0.4.0 (2018-06-14)

* Add *tuple* type (#40)
* Add `bool` and `nil` types (#39)
* Add *literal type* (#37)

## 0.3.0 (2018-05-31)

* Add `interface` command to print interface built for given type
* Add `--strict` option for `check` command
* Fix `scaffold` command for empty class/modules
* Type check method definition with empty body
* Add `STDOUT` and `StringIO` minimal definition
* Fix validate command to load stdlib
* Fix parsing keyword argument type

## 0.2.0 (2018-05-30)

* Add `attr_reader` and `attr_accessor` syntax to signature (#33)
* Fix parsing on union with `any`
