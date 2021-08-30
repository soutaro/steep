# CHANGELOG

## master

## 0.46.0 (2021-08-30)

This release updates Steepfile DSL syntax, introducing `stdlib_path` and `configure_code_diagnostics` syntax (methods).

* `stdlib_path` allows configuring core/stdlib RBS file locations.
* `configure_code_diagnostics` allows configuring _severity_ of each type errors.

See the PRs for the explanation of these methods.
You can try `steep init` to generate updated `Steepfile` template.

* Flexible diagnostics configuration ([\#422](https://github.com/soutaro/steep/pull/422), [\#423](https://github.com/soutaro/steep/pull/423))
* Revise Steepfile _path_ DSL ([\#421](https://github.com/soutaro/steep/pull/421))
* Avoid to stop process by invalid jobs_count ([\#419](https://github.com/soutaro/steep/pull/419))
* Fix `Steep::Typing::UnknownNodeError` when hover method with numblock ([\#415](https://github.com/soutaro/steep/pull/415))

## 0.45.0 (2021-08-22)

* Fix error reporting on `RBS::MixinClassError` ([\#411](https://github.com/soutaro/steep/pull/411))
* Compact error reporting for method body type mismatch ([\#414](https://github.com/soutaro/steep/pull/414))
* Fix NoMethodError with csend/numblock ([\#412](https://github.com/soutaro/steep/pull/412))
* LSP completion for RBS files ([\#404](https://github.com/soutaro/steep/pull/404))
* Allow break without value from bot methods ([\#398](https://github.com/soutaro/steep/pull/398))
* Type check on lvar assignments ([\#390](https://github.com/soutaro/steep/pull/390))
* Assign different error code to break without value ([\#387](https://github.com/soutaro/steep/pull/387))
* Support Ruby3 Keyword Arguments ([\#386](https://github.com/soutaro/steep/pull/386))
* LSP hover for RBS files ([\#385](https://github.com/soutaro/steep/pull/385), [\#397](https://github.com/soutaro/steep/pull/397))
* Fix FileLoader to skip files not matching to the given pattern ([\#382](https://github.com/soutaro/steep/pull/382))
* Ruby3 support for numbered block parameters and end-less def ([\#381](https://github.com/soutaro/steep/pull/381))

## 0.44.1 (2021-04-23)

* Disable goto declaration and goto type declaration (because they are not implemented) ([#377](https://github.com/soutaro/steep/pull/377))
* Fix goto from block calls ([#378](https://github.com/soutaro/steep/pull/378))

## 0.44.0 (2021-04-22)

* Implement LSP go to definition/implementation ([#371](https://github.com/soutaro/steep/pull/371), [#375](https://github.com/soutaro/steep/pull/375))
* Fix typing on passing optional block ([#373](https://github.com/soutaro/steep/pull/373))
* Do not crash when completion request `context` is missing ([#370](https://github.com/soutaro/steep/pull/370))
* Update RBS ([#376](https://github.com/soutaro/steep/pull/376))

## 0.43.1 (2021-04-01)

* Fix LSP `textDocument/didSave` notification handling ([#368](https://github.com/soutaro/steep/issues/368))

## 0.43.0 (2021-03-30)

* LSP responsiveness improvements ([\#352](https://github.com/soutaro/steep/issues/352))
* `@implements` annotation in blocks ([#338](https://github.com/soutaro/steep/issues/338))
* Better `steep stats` table formatting ([\#300](https://github.com/soutaro/steep/issues/300))
* Fix retry type checking ([\#293](https://github.com/soutaro/steep/issues/293))
* Better tuple type checking ([\#328](https://github.com/soutaro/steep/issues/328))
* Fix unexpected `add_call` error ([\#358](https://github.com/soutaro/steep/pull/358))
* Ignore passing nil as a block `&nil` ([\#356](https://github.com/soutaro/steep/pull/356))
* Better type checking for non-trivial block parameters ([\#354](https://github.com/soutaro/steep/pull/354))
* Avoid unexpected error on splat assignments ([\#330](https://github.com/soutaro/steep/pull/330))
* Fix constraint solver ([\#343](https://github.com/soutaro/steep/pull/343))
* Ruby 2.7 compatible private method call typing ([\#344](https://github.com/soutaro/steep/pull/344))

## 0.42.0 (2021-03-08)

* Type checking performance improvement ([\#309](https://github.com/soutaro/steep/pull/309), [\#311](https://github.com/soutaro/steep/pull/311), [\#312](https://github.com/soutaro/steep/pull/312), [\#313](https://github.com/soutaro/steep/pull/313), [\#314](https://github.com/soutaro/steep/pull/314), [\#315](https://github.com/soutaro/steep/pull/315), [\#316](https://github.com/soutaro/steep/pull/316), [\#320](https://github.com/soutaro/steep/pull/320), [\#322](https://github.com/soutaro/steep/pull/322))
* Let `watch` command support files ([\#323](https://github.com/soutaro/steep/pull/323))
* Validate _module-self-type_ constraints ([\#308](https://github.com/soutaro/steep/pull/308))
* Add `-j` option to specify number of worker processes ([\#318](https://github.com/soutaro/steep/pull/318), [\#325](https://github.com/soutaro/steep/pull/325))
* Fix `code` of RBS diagnostics ([\#306](https://github.com/soutaro/steep/pull/306))
* Skip printing source code from out of date _expectations_ file ([\#305](https://github.com/soutaro/steep/pull/305))

## 0.41.0 (2021-02-07)

* Add `--with-expectations` and `--save-expectations` option ([#303](https://github.com/soutaro/steep/pull/303))

## 0.40.0 (2021-01-31)

* Report progress with dots ([#287](https://github.com/soutaro/steep/pull/287))
* Diagnostics message improvements ([#297](https://github.com/soutaro/steep/pull/297), [#301](https://github.com/soutaro/steep/pull/301))
* Fix error on implicit `to_proc` syntax when `untyped` is yielded ([#291](https://github.com/soutaro/steep/pull/291))

## 0.39.0 (2020-12-25)

* Update RBS to 1.0.0 ([#282](https://github.com/soutaro/steep/pull/282))
* Better `&&` and `||` typing ([#276](https://github.com/soutaro/steep/pull/276))
* Type case based on literals ([#277](https://github.com/soutaro/steep/pull/277))
* Type case improvements ([#279](https://github.com/soutaro/steep/pull/279), [#283](https://github.com/soutaro/steep/pull/283))
* Improvements on untyped classes/modules, unsupported syntax error handling, and argument types in untyped methods ([#280](https://github.com/soutaro/steep/pull/280))
* Fix `bot` and `top` type format ([#278](https://github.com/soutaro/steep/pull/278))
* Colorfull error messages ([#273](https://github.com/soutaro/steep/pull/273))

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
