# CHANGELOG

## master

## 1.6.0 (2023-11-09)

Nothing changed from 1.6.0.pre.4.

## 1.6.0.pre.4 (2023-11-02)

### Language server

* Fix LSP text synchronization problems ([#954](https://github.com/soutaro/steep/pull/954))

## 1.6.0.pre.3 (2023-11-01)

### Type checker core

* Object methods are moved to Kernel ([#952](https://github.com/soutaro/steep/pull/952))
* Check if `rescue` body has `bot` type ([#953](https://github.com/soutaro/steep/pull/953))

## 1.6.0.pre.2 (2023-10-31)

### Type checker core

* Assign types on method calls in mlhs node ([#951](https://github.com/soutaro/steep/pull/951))
* Change severity of block diagnostics ([#950](https://github.com/soutaro/steep/pull/950))

### Commandline tool

* Match with `**` in pattern ([#949](https://github.com/soutaro/steep/pull/949))

## 1.6.0.pre.1 (2023-10-27)

### Type checker core

* Test if a parameter is `_` ([#946](https://github.com/soutaro/steep/pull/946))
* Let `[]=` call have correct type ([#945](https://github.com/soutaro/steep/pull/945))
* Support type narrowing by `Module#<` ([#877](https://github.com/soutaro/steep/pull/877))
* Fewer `UnresolvedOverloading` ([#941](https://github.com/soutaro/steep/pull/941))
* Fix ArgumentTypeMismatch for PublishDiagnosticsParams ([#895](https://github.com/soutaro/steep/pull/895))
* Add types for LSP::Constant::MessageType ([#894](https://github.com/soutaro/steep/pull/894))
* `nil` is not a `NilClass` ([#920](https://github.com/soutaro/steep/pull/920))
* Fix unexpected error when DifferentMethodParameterKind ([#917](https://github.com/soutaro/steep/pull/917))

### Commandline tool

* Fix space in file path crash ([#944](https://github.com/soutaro/steep/pull/944))
* refactor: Rename driver objects to command ([#893](https://github.com/soutaro/steep/pull/893))
* Run with `--jobs=2` automatically on CI ([#924](https://github.com/soutaro/steep/pull/924))
* Fix type alias validation ([#922](https://github.com/soutaro/steep/pull/922))

### Language server

* Let goto definition work from `UnresolvedOverloading` error calls ([#943](https://github.com/soutaro/steep/pull/943))
* Let label be whole method type in SignatureHelp ([#942](https://github.com/soutaro/steep/pull/942))
* Set up file watcher ([#936](https://github.com/soutaro/steep/pull/936))
* Reset file content on `didOpen` notification ([#935](https://github.com/soutaro/steep/pull/935))
* Start type check on change ([#934](https://github.com/soutaro/steep/pull/934))
* Better completion with module alias and `use` directives ([#923](https://github.com/soutaro/steep/pull/923))

### Miscellaneous

* Drop 2.7 support ([#928](https://github.com/soutaro/steep/pull/928))
* Type check `subtyping/check.rb` ([#921](https://github.com/soutaro/steep/pull/921))
* Type check constant under `self` ([#908](https://github.com/soutaro/steep/pull/908))

## 1.5.3 (2023-08-10)

### Type checker core

* Fix type checking parenthesized conditional nodes ([#896](https://github.com/soutaro/steep/pull/896))

## 1.5.2 (2023-07-27)

### Type checker core

* Avoid inifinite loop in `#shape` ([#884](https://github.com/soutaro/steep/pull/884))
* Fix `nil?` typing with `untyped` receiver ([#882](https://github.com/soutaro/steep/pull/882))

### Language server

* Avoid breaking the original source code through `CompletionProvider` ([#883](https://github.com/soutaro/steep/pull/883))

## 1.5.1 (2023-07-20)

### Type checker core

* Support unreachable branch detection with `elsif` ([#879](https://github.com/soutaro/steep/pull/879))
* Give an optional type hint to lhs of `||` ([#874](https://github.com/soutaro/steep/pull/874))

### Miscellaneous

* Update steep ([#878](https://github.com/soutaro/steep/pull/878))
* Update inline type comments ([#875](https://github.com/soutaro/steep/pull/875))

## 1.5.0 (2023-07-13)

### Type checker core

* Fix for the case `untyped` is the proc type hint ([#868](https://github.com/soutaro/steep/pull/868))
* Type case with type variable ([#869](https://github.com/soutaro/steep/pull/869))
* Filx `nil?` unreachability detection ([#867](https://github.com/soutaro/steep/pull/867))

### Commandline tool

* Update `#configure_code_diagnostics` type ([#873](https://github.com/soutaro/steep/pull/873))
* Update diagnostics templates ([#871](https://github.com/soutaro/steep/pull/871))
* Removed "set" from "libray" in init.rb and README ([#870](https://github.com/soutaro/steep/pull/870))

### Language server

* Use RBS::Buffer method to calculate position ([#872](https://github.com/soutaro/steep/pull/872))

## 1.5.0.pre.6 (2023-07-11)

### Type checker core

* Report RBS validation errors in Ruby code ([#859](https://github.com/soutaro/steep/pull/859))
* Fix proc type assignment ([#858](https://github.com/soutaro/steep/pull/858))
* Report `UnexpectedKeywordArgument` even if no keyword param is accepted ([#856](https://github.com/soutaro/steep/pull/856))
* Unfold type alias on unwrap optional ([#855](https://github.com/soutaro/steep/pull/855))

### Language server

* Keyword completion in block call ([#865](https://github.com/soutaro/steep/pull/865))
* Indicate the current or next argument on signature help ([#850](https://github.com/soutaro/steep/pull/850))
* Support completion for keyword arguments ([#851](https://github.com/soutaro/steep/pull/851))
* Let hover show the type of method call node ([#864](https://github.com/soutaro/steep/pull/864))
* Fix UnknownNodeError in SignatureHelp ([#863](https://github.com/soutaro/steep/pull/863))
* hover: Fix NoMethodError on generating hover for not supported files ([#853](https://github.com/soutaro/steep/pull/853))

## 1.5.0.pre.5 (2023-07-07)

### Type checker core

* Unreachability improvements ([#845](https://github.com/soutaro/steep/pull/845))
* Fix type inference problem ([#843](https://github.com/soutaro/steep/pull/843))

## 1.5.0.pre.4 (2023-07-06)

### Type checker core

* Fix unreachability test ([#842](https://github.com/soutaro/steep/pull/842))
* Make type of `case` node `untyped` rather than `nil` ([#841](https://github.com/soutaro/steep/pull/841))
* Fix `#partition_union` ([#840](https://github.com/soutaro/steep/pull/840))
* Fix type-case ([#839](https://github.com/soutaro/steep/pull/839))

## 1.5.0.pre.3 (2023-07-05)

### Type checker core

* Resolve type names from TypeAssertion and TypeApplication ([#836](https://github.com/soutaro/steep/pull/836))

### Commandline tool

* Replace ElseOnExhaustiveCase by UnreachableBranch from steep/diagnostic/ruby.rb ([#833](https://github.com/soutaro/steep/pull/833))

### Language server

* Reuse the latest result to keep SignatureHelp opened while typing ([#835](https://github.com/soutaro/steep/pull/835))

## 1.5.0.pre.2 (2023-07-05)

### Language server

* Fix signature help is not shown for the optional chaining (&.) ([#832](https://github.com/soutaro/steep/pull/832))

## 1.5.0.pre.1 (2023-07-05)

### Type checker core

* Refactor occurrence typing ([#831](https://github.com/soutaro/steep/pull/831))
* Better flow-sensitive typing ([#825](https://github.com/soutaro/steep/pull/825))
* Fix interface type inference ([#816](https://github.com/soutaro/steep/pull/816))
* Make `nth_ref` and `:back_ref` nodes optional ([#815](https://github.com/soutaro/steep/pull/815))
* Add new diagnostic for setter methods ([#809](https://github.com/soutaro/steep/pull/809))
* Better hint type handling given to lambda ([#807](https://github.com/soutaro/steep/pull/807))
* Fix type assertion parsing error ([#805](https://github.com/soutaro/steep/pull/805))
* Distribute `untyped` to block params ([#798](https://github.com/soutaro/steep/pull/798))
* Should escape underscore for method name ([#770](https://github.com/soutaro/steep/pull/770))
* Give a special typing rule to `#lambda` calls ([#811](https://github.com/soutaro/steep/pull/811))
* Support early return code using "and return" ([#828](https://github.com/soutaro/steep/pull/828))
* Validate type applications in ancestors ([#810](https://github.com/soutaro/steep/pull/810))
* Convert block-pass-arguments with `#to_proc` ([#806](https://github.com/soutaro/steep/pull/806))

### Commandline tool

* Ensure at least one type check worker runs ([#814](https://github.com/soutaro/steep/pull/814))
* Improve worker process handling ([#801](https://github.com/soutaro/steep/pull/801))
* Add `Steep::Diagnostic::Ruby.silent` template to suppress all warnings ([#800](https://github.com/soutaro/steep/pull/800))
* Suppress `UnsupportedSyntax` warnings by default ([#799](https://github.com/soutaro/steep/pull/799))
* Infer method return types using hint ([#789](https://github.com/soutaro/steep/pull/789))
* Handling splat nodes in `super` ([#788](https://github.com/soutaro/steep/pull/788))
* Add handling splat node in tuple type checking ([#786](https://github.com/soutaro/steep/pull/786))
* Let `return` have multiple values ([#785](https://github.com/soutaro/steep/pull/785))
* Remove trailing extra space from Steepfile generated by steep init ([#774](https://github.com/soutaro/steep/pull/774))

### Language server

* Completion in annotations ([#818](https://github.com/soutaro/steep/pull/818))
* Implement *go to type definition* ([#784](https://github.com/soutaro/steep/pull/784))
* completion: Support completion for optional chaining (&.) ([#827](https://github.com/soutaro/steep/pull/827))
* signature helps are not shown if the target code has comments ([#829](https://github.com/soutaro/steep/pull/829))

### Miscellaneous

* Typecheck sources ([#820](https://github.com/soutaro/steep/pull/820))
* Relax concurrent-ruby requirement ([#812](https://github.com/soutaro/steep/pull/812))
* Cast from union for faster type checking ([#830](https://github.com/soutaro/steep/pull/830))

## 1.4.0 (2023-04-25)

### Type checker core

* Return immediately if blocks are incompatible ([#765](https://github.com/soutaro/steep/pull/765))
* Fix location of no method error ([#763](https://github.com/soutaro/steep/pull/763))
* Support `gvasgn` in assignment variants ([#762](https://github.com/soutaro/steep/pull/762))
* Set up break contexts correctly for untyped blocks ([#752](https://github.com/soutaro/steep/pull/752))
* Fix flow sensitive on `case` without condition ([#751](https://github.com/soutaro/steep/pull/751))
* Support `...` syntax ([#750](https://github.com/soutaro/steep/pull/750))
* Fix constant declaration type checking ([#738](https://github.com/soutaro/steep/pull/738))
* Fix errors caused by non-ascii variable names ([#703](https://github.com/soutaro/steep/pull/703))
* Update RBS to 3.0 ([#716](https://github.com/soutaro/steep/pull/716), [#754](https://github.com/soutaro/steep/pull/754))

### Language server

* Implement signature help, better completion and hover ([#759](https://github.com/soutaro/steep/pull/759), [#761](https://github.com/soutaro/steep/pull/761), [#766](https://github.com/soutaro/steep/pull/766))

### Miscellaneous

* Remove pathname from runtime_dependency ([#739](https://github.com/soutaro/steep/pull/739))
* `parallel` out, `concurrent-ruby` in ([#760](https://github.com/soutaro/steep/pull/760))

## 1.3.2 (2023-03-17)

### Miscellaneous

* Remove pathname from runtime_dependency ([#740](https://github.com/soutaro/steep/pull/740))

## 1.3.1 (2023-03-08)

### Miscellaneous

* Require rbs-2.8.x ([#732](https://github.com/soutaro/steep/pull/732))

## 1.3.0 (2022-11-25)

### Type checker core

* Type check types ([#676](https://github.com/soutaro/steep/pull/676))

## 1.3.0.pre.2 (2022-11-23)

### Type checker core

* Add missing `#level` method ([\#671](https://github.com/soutaro/steep/pull/671))
* Cache `constant_resolver` among files in a target([\#673](https://github.com/soutaro/steep/pull/673))
* Early return from type checking overloads ([\#674](https://github.com/soutaro/steep/pull/674))

### Commandline tool

* Spawn worker processes if `--steep-command` is specified ([\#672](https://github.com/soutaro/steep/pull/672))

## 1.3.0.pre.1 (2022-11-22)

### Type checker core

* Add type assertion syntax ([#665](https://github.com/soutaro/steep/pull/665))
* Add type application syntax ([#670](https://github.com/soutaro/steep/pull/670))

### Commandline tool

* Fork when available for quicker startup ([#664](https://github.com/soutaro/steep/pull/664))

### Miscellaneous

* Fixes for some RBS errors within steep gem ([#668](https://github.com/soutaro/steep/pull/668))
* Upgrade to RBS 2.8 (pre) ([#669](https://github.com/soutaro/steep/pull/669))

## 1.2.1 (2022-10-22)

### Type checker core

* Fix type narrowing on case-when ([#662](https://github.com/soutaro/steep/pull/662))

## 1.2.0 (2022-10-08)

### Commandline tool

* Refactor `--jobs` and `--steep-command` option handling ([#654](https://github.com/soutaro/steep/pull/654))

### Miscellaneous

* Delete debug prints ([#653](https://github.com/soutaro/steep/pull/653))
* Update RBS to 2.7.0 ([#655](https://github.com/soutaro/steep/pull/655))

## 1.2.0.pre.1 (2022-10-06)

### Type checker core

* Support type checking block/proc self type binding ([#637](https://github.com/soutaro/steep/pull/637))
* Type check multiple assignment on block parameters ([#641](https://github.com/soutaro/steep/pull/641), [#643](https://github.com/soutaro/steep/pull/643))
* Make more multiple assignments type check ([#630](https://github.com/soutaro/steep/pull/630))
* Refactor *shape* calculation ([#635](https://github.com/soutaro/steep/pull/635), [#649](https://github.com/soutaro/steep/pull/649))
* Report type errors if argument mismatch on yield ([#640](https://github.com/soutaro/steep/pull/640))
* Relax caching requirements to cache more results ([#651](https://github.com/soutaro/steep/pull/651))

### Commandline tool

* Add `steep checkfile` command ([#650](https://github.com/soutaro/steep/pull/650))

### Miscellaneous

* Add docs for sublime text integration ([#633](https://github.com/soutaro/steep/pull/633))

## 1.1.1 (2022-07-31)

### Type checker core

* Ignore special local variables -- `_`, `__any__` and `__skip__` ([#617](https://github.com/soutaro/steep/pull/617), [#627](https://github.com/soutaro/steep/pull/627))
* Fix type narrowing on assignments ([#622](https://github.com/soutaro/steep/pull/622))

## 1.1.0 (2022-07-27)

### Type checker core

* Fix `#each_child_node` ([#612](https://github.com/soutaro/steep/pull/612))

## 1.1.0.pre.1 (2022-07-26)

### Type checker core

* Type refinement with method calls ([#590](https://github.com/soutaro/steep/issues/590))
* Better multiple assignment type checking ([\#605](https://github.com/soutaro/steep/pull/605))
* Fix generics issues around proc types ([\#609](https://github.com/soutaro/steep/pull/609), [\#611](https://github.com/soutaro/steep/pull/611))
* Fix type application validation ([#607](https://github.com/soutaro/steep/pull/607); backport from 1.0.2)
* Add class variable validation ([\#593](https://github.com/soutaro/steep/pull/593))
* Fix type application validation ([\#607](https://github.com/soutaro/steep/pull/607))

### Commandline tool

* Appends "done!" to the watch output when the type check is complete ([\#596](https://github.com/soutaro/steep/pull/596))

### Language server

* Fix hover on multiple assignment ([\#606](https://github.com/soutaro/steep/pull/606))

## 1.0.2 (2022-07-19)

This is another patch release for Steep 1.0.

### Type checker core

* Fix type application validation ([#607](https://github.com/soutaro/steep/pull/607))

## 1.0.1 (2022-06-16)

This is the first patch release for Steep 1.0.
However, this release includes one non-trivial type system update, [\#570](https://github.com/soutaro/steep/pull/570), which adds a special typing rule for `Hash#compact` like `Array#compact`.
The change will make type checking more permissive and precise, so no new error won't be reported with the fix.

### Type checker core

* Support shorthand hash for Ruby 3.1 ([\#567](https://github.com/soutaro/steep/pull/567))
* Fix super and zsuper with block ([\#568](https://github.com/soutaro/steep/pull/568))
* Apply logic-type evaluation only if the node is `:send` ([\#569](https://github.com/soutaro/steep/pull/569))
* Add support for `Hash#compact` ([\#570](https://github.com/soutaro/steep/pull/570))
* Use given `const_env` when making a new `ModuleContext` ([\#575](https://github.com/soutaro/steep/pull/575))
* Graceful, hopefully, error handling with undefined outer module ([\#576](https://github.com/soutaro/steep/pull/576))
* Type check anonymous block forwarding ([\#577](https://github.com/soutaro/steep/pull/577))
* Incompatible default value is a type error ([\#578](https://github.com/soutaro/steep/pull/578))
* Load `ChildrenLevel` helper in `AST::Types::Proc` ([\#584](https://github.com/soutaro/steep/pull/584))
* Type check `gvar` and `gvasgn` in methods([\#579](https://github.com/soutaro/steep/pull/579))
* Avoid `UnexpectedError` when assigning untyped singleton class ([\#586](https://github.com/soutaro/steep/pull/586))

### Commandline tool

* Improve Windows support ([\#561](https://github.com/soutaro/steep/pull/561), [\#573](https://github.com/soutaro/steep/pull/573))
* Test if `.ruby-version` exists before `rvm do` in binstub ([\#558](https://github.com/soutaro/steep/pull/558))
* Fix typo ([\#564](https://github.com/soutaro/steep/pull/564))
* Ignore `untitled:` URIs in LSP ([\#580](https://github.com/soutaro/steep/pull/580))

### Miscellaneous

* Fix test name ([\#565](https://github.com/soutaro/steep/pull/565), [\#566](https://github.com/soutaro/steep/pull/566), [\#585](https://github.com/soutaro/steep/pull/585))
* Remove some unused code except tests ([\#587](https://github.com/soutaro/steep/pull/587))

## 1.0.0 (2022-05-20)

* Add special typing rule for `Array#compact` ([\#555](https://github.com/soutaro/steep/pull/555))
* Add custom method type of `#fetch` on tuples and records ([\#554](https://github.com/soutaro/steep/pull/554))
* Better `masgn` ([\#553](https://github.com/soutaro/steep/pull/553))
* Fix method parameter type checking ([\#552](https://github.com/soutaro/steep/pull/552))

## 0.52.2 (2022-05-02)

* Handle class declaration with non-const super class ([\#546](https://github.com/soutaro/steep/pull/546))
* Remove `#to_a` error message ([\#545](https://github.com/soutaro/steep/pull/545))
* Add `#filter_map` shim ([\#544](https://github.com/soutaro/steep/pull/544))

## 0.52.1 (2022-04-25)

* Better union type inference (it type checks `Array#filter_map` now!) ([\#531](https://github.com/soutaro/steep/pull/531))
* Improve method call hover message ([\#537](https://github.com/soutaro/steep/pull/537), [\#538](https://github.com/soutaro/steep/pull/538))
* Make `NilClass#!` a special method to improve flow-sensitive typing ([\#539](https://github.com/soutaro/steep/pull/539))
* Fix `steep binstub` ([\#540](https://github.com/soutaro/steep/pull/540), [\#541](https://github.com/soutaro/steep/pull/541))

## 0.52.0 (2022-04-05)

* Add `steep binstub` command ([\#527](https://github.com/soutaro/steep/pull/527))
* Let hover and completion work in heredoc ([\#528](https://github.com/soutaro/steep/pull/528))
* Better constant typing ([\#529](https://github.com/soutaro/steep/pull/529))

## 0.51.0 (2022-04-01)

* Completion for constant ([\#524](https://github.com/soutaro/steep/pull/524))
* Better hover/completion message ([\#525](https://github.com/soutaro/steep/pull/525))
* Show available commands when using `--help` ([\#523](https://github.com/soutaro/steep/pull/523))

## 0.50.0 (2022-03-22)

* CLI option for override steep command at spawn worker ([\#511](https://github.com/soutaro/steep/pull/511))
* LSP related improvements for Sublime LSP ([\#513](https://github.com/soutaro/steep/pull/513))
* Support Windows environment ([\#514](https://github.com/soutaro/steep/pull/514))
* Let `&:foo` proc work with methods with optional parameters ([\#516](https://github.com/soutaro/steep/pull/516))
* Fix unexpected error when or-asgn/and-asgn ([\#517](https://github.com/soutaro/steep/pull/517))
* Fix goto-definition from method call inside block ([\#518](https://github.com/soutaro/steep/pull/518))
* Better splat in array typing ([\#519](https://github.com/soutaro/steep/pull/519))

## 0.49.1 (2022-03-11)

* Fix lambda typing ([\#506](https://github.com/soutaro/steep/pull/506))
* Validate type descendants ([\#507](https://github.com/soutaro/steep/pull/507))
* Fix print error with absolute path ([\#508](https://github.com/soutaro/steep/pull/508))
* Skip non-target ruby code on `steep stats` ([\#509](https://github.com/soutaro/steep/pull/509))

## 0.49.0 (2022-03-08)

* Better typing for `#flat_map` ([\#504](https://github.com/soutaro/steep/pull/504))
* Support lambdas (`->`) with block ([\#503](https://github.com/soutaro/steep/pull/503))
* Let proc type be `::Proc` class instance ([\#502](https://github.com/soutaro/steep/pull/502))
* Disable contextual typing on `bool` type ([\#501](https://github.com/soutaro/steep/pull/501))
* Type check `return` without value ([\#500](https://github.com/soutaro/steep/pull/500))

## 0.48.0 (2022-03-07)

Steep supports all of the new features of RBS 2. 🎉
It now requires RBS >= 2.2 and support all of the features.

* Update RBS ([\#495](https://github.com/soutaro/steep/pull/495))
* Support generic type aliases ([\#496](https://github.com/soutaro/steep/pull/496))
* Support bounded generics ([\#499](https://github.com/soutaro/steep/pull/499))

## 0.47.1 (2022-02-17)

This update lets Steep run with Active Support 7.

* Fix ActiveSupport requirement in `lib/steep.rb` ([#484](https://github.com/soutaro/steep/pull/484))

## 0.47.0 (2021-11-30)

This update contains update for RBS 1.7.

* RBS 1.7 ([#455](https://github.com/soutaro/steep/pull/455))
* Bug fixes related to `SendArgs` ([#444](https://github.com/soutaro/steep/pull/444), [#449](https://github.com/soutaro/steep/pull/449), [#451](https://github.com/soutaro/steep/pull/451))
* LSP completion item formatting improvement ([#442](https://github.com/soutaro/steep/pull/442))

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
