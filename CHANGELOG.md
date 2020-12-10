# CHANGELOG

## master

## 0.38.0 (2020-12-10)

* Improve `break`/`next` typing ([#271](https://github.com/soutaro/steep/pull/271))
* Add LSP `workspace/symbol` feature ([#267](https://github.com/soutaro/steep/pull/267))

## 0.37.0 (2020-12-06)

* Update to RBS 0.20.0 with _singleton attribute_ syntax and _proc types with blocks_. ([#264](https://github.com/soutaro/steep/pull/264))

## 0.36.0 (2020-11-16)

* Flow-sensitive typing improvements with `||` and `&&` ([#260](https://github.com/soutaro/steep/pull/260))
* Type-case improvement ([#259](https://github.com/soutaro/steep/pull/259))
* Subtyping between `bool` and logic types ([#258](https://github.com/soutaro/steep/pull/258))

## 0.35.0 (2020-11-14)

* Support third party RBS repository ([#231](https://github.com/soutaro/steep/pull/231), [#254](https://github.com/soutaro/steep/pull/254), [#255](https://github.com/soutaro/steep/pull/255))
* Boolean type semantics update ([#252](https://github.com/soutaro/steep/pull/252))
* More flexible record typing ([#256](https://github.com/soutaro/steep/pull/256))

## 0.34.0 (2020-10-27)

* Add `steep stats` command to show method call typing stats ([#246](https://github.com/soutaro/steep/pull/246))
* Fix attribute assignment typing ([#243](https://github.com/soutaro/steep/pull/243))
* Let `Range[T]` be covariant ([#242](https://github.com/soutaro/steep/pull/242))
* Fix constant typing ([#247](https://github.com/soutaro/steep/pull/247), [#248](https://github.com/soutaro/steep/pull/248))

## 0.33.0 (2020-10-13)

* Make `!` typing flow sensitive ([#240](https://github.com/soutaro/steep/pull/240))

## 0.32.0 (2020-10-09)

* Let type-case support interface types ([#237](https://github.com/soutaro/steep/pull/237))

## 0.31.1 (2020-10-07)

* Fix `if-then-else` parsing ([#236](https://github.com/soutaro/steep/pull/236))

## 0.31.0 (2020-10-04)

* Fix type checking performance ([#230](https://github.com/soutaro/steep/pull/230))
* Improve LSP completion/hover performance ([#232](https://github.com/soutaro/steep/pull/232))
* Fix instance variable completion ([#234](https://github.com/soutaro/steep/pull/234))
* Relax version requirements on Listen to allow installing on Ruby 3 ([#235](https://github.com/soutaro/steep/pull/235))

## 0.30.0 (2020-10-03)

* Let top-level defs be methods of Object ([#227](https://github.com/soutaro/steep/pull/227))
* Fix error caused by attribute definitions ([#228](https://github.com/soutaro/steep/pull/228))
* LSP worker improvements ([#222](https://github.com/soutaro/steep/pull/222), [#223](https://github.com/soutaro/steep/pull/223), [#226](https://github.com/soutaro/steep/pull/226), [#229](https://github.com/soutaro/steep/pull/229))

## 0.29.0 (2020-09-28)

* Implement reasoning on `is_a?`, `nil?`, and `===` methods. ([#218](https://github.com/soutaro/steep/pull/218))
* Better completion based on interface ([#215](https://github.com/soutaro/steep/pull/215))
* Fix begin-rescue typing ([#221](https://github.com/soutaro/steep/pull/221))

## 0.28.0 (2020-09-17)

* Fix typing case-when with empty body ([#200](https://github.com/soutaro/steep/pull/200))
* Fix lvasgn typing with `void` type hint ([#200](https://github.com/soutaro/steep/pull/200))
* Fix subtype checking between type variables and union types ([#200](https://github.com/soutaro/steep/pull/200))
* Support endless range ([#200](https://github.com/soutaro/steep/pull/200))
* Fix optarg, kwoptarg typing ([#202](https://github.com/soutaro/steep/pull/202))
* Better union/intersection types ([#204](https://github.com/soutaro/steep/pull/204))
* Fix generic method instantiation ([#205](https://github.com/soutaro/steep/pull/205))
* Fix module typing ([#206](https://github.com/soutaro/steep/pull/206))
* Fix shutdown problem ([#209](https://github.com/soutaro/steep/pull/209))
* Update RBS to 0.12.0 ([#210](https://github.com/soutaro/steep/pull/210))
* Improve processing singleton class decls without RBS ([#211](https://github.com/soutaro/steep/pull/211))
* Improve processing block parameter with masgn ([#212](https://github.com/soutaro/steep/pull/212))

## 0.27.0 (2020-08-31)

* Make tuple types _covariant_ ([#195](https://github.com/soutaro/steep/pull/195))
* Support `or_asgn`/`and_asgn` with `send` node lhs ([#194](https://github.com/soutaro/steep/pull/194))
* Performance improvement ([#193](https://github.com/soutaro/steep/pull/193))
* Add specialized versions of `#first` and `#last` on tuples ([#191](https://github.com/soutaro/steep/pull/191))
* Typing bug fix on `[]` (empty array) ([#190](https://github.com/soutaro/steep/pull/190))
* Earlier shutdown with interruption while `steep watch` ([#173](https://github.com/soutaro/steep/pull/173))

## 0.26.0

* Skipped

## 0.25.0 (2020-08-18)

* Improve `op_send` typing ([#186](https://github.com/soutaro/steep/pull/186))
* Improve `op_asgn` typing ([#189](https://github.com/soutaro/steep/pull/189))
* Better multi-assignment support ([#183](https://github.com/soutaro/steep/pull/183), [#184](https://github.com/soutaro/steep/pull/184))
* Support for loop and class variables ([#182](https://github.com/soutaro/steep/pull/182))
* Fix tuple typing ([#181](https://github.com/soutaro/steep/pull/181))

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
