# CHANGELOG

## master

## 0.24.0 (2020-08-11)

* Update RBS to 0.10 ([#180](https://github.com/soutaro/steep/pull/180))

## 0.23.0 (2020-08-06)

* Fix literal typing with hint ([#179](https://github.com/soutaro/steep/pull/179))
* Fix literal type subtyping ([#178](https://github.com/soutaro/steep/pull/178))

## 0.22.0 (2020-08-03)

* Improve signature validation ([#175](https://github.com/soutaro/steep/pull/175), [#177](https://github.com/soutaro/steep/pull/177))
* Fix boolean literal typing ([#172](https://github.com/soutaro/steep/pull/172))
* Make exit code success when Steep has unreported type errors ([#171](https://github.com/soutaro/steep/pull/171))
* Allow `./` prefix for signature pattern ([#170](https://github.com/soutaro/steep/pull/170))

## 0.21.0 (2020-07-20)

* Fix LSP hover ([#168](https://github.com/soutaro/steep/pull/168))
* Nominal subtyping ([#167](https://github.com/soutaro/steep/pull/167))

## 0.20.0 (2020-07-17)

* Support singleton class definitions ([#166](https://github.com/soutaro/steep/pull/166))

## 0.19.0 (2020-07-12)

* Update RBS. ([#157](https://github.com/soutaro/steep/pull/157))
* No `initialize` in completion. ([#164](https://github.com/soutaro/steep/pull/164))
* Granular typing option setup. ([#163](https://github.com/soutaro/steep/pull/163))

## 0.18.0 (2020-07-06)

* Sort result of `Pathname#glob` ([#154](https://github.com/soutaro/steep/pull/154))
* Sort methods in LanguageServer to return non-inherited methods first ([#159](https://github.com/soutaro/steep/pull/159))

## 0.17.1 (2020-06-15)

* Allow RBS gem to be 0.4 ([#153](https://github.com/soutaro/steep/pull/153))

## 0.17.0 (2020-06-13)

* Fix `steep watch` and `steep langserver` to correctly handle error message filterings based on options ([#152](https://github.com/soutaro/steep/pull/152))
* Fix typing of collections ([#151](https://github.com/soutaro/steep/pull/151))

## 0.16.3

* Fix `steep watch` ([#147](https://github.com/soutaro/steep/pull/147))
* Stop using pry ([#148](https://github.com/soutaro/steep/pull/148))

## 0.16.2 (2020-05-27)

* Update gems ([#144](https://github.com/soutaro/steep/pull/144), [#145](https://github.com/soutaro/steep/pull/145))

## 0.16.1 (2020-05-22)

* Fix constant resolution ([#143](https://github.com/soutaro/steep/pull/143))
* Fix RBS diagnostics line number in LSP ([#142](https://github.com/soutaro/steep/pull/142))
* Fix crash caused by hover on `def` in LSP ([#140](https://github.com/soutaro/steep/pull/140))

## 0.16.0 (2020-05-19)

* Spawn workers for type check performance ([#137](https://github.com/soutaro/steep/pull/137))
* Fix `check` and `signature` methods in Steepfile ([8f3e4c7](https://github.com/soutaro/steep/pull/137/commits/8f3e4c75b29ac26920f02294be06d6c68dbd4dca))

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
