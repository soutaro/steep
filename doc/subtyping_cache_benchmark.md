# Subtyping cache benchmark

How much does `Steep::Subtyping::Cache` help, what does it cost in memory, and where does it work well?
This document records measurements taken with `bin/subtyping_cache_bench.rb`, which runs the same pipeline as `steep check` (signature validation + source type checking) in a single process so that one `Subtyping::Check`/`Cache` instance is shared per target. See the script header for the measurement modes.

## Environment

- Steep 2.1.0 (this repository, checking itself via its own `Steepfile`)
- Ruby 3.3.6, x86_64-linux, 4 cores, single-threaded in-process runs
- `steep check` normally partitions files across worker processes, each with its own cache; the numbers below are the single-process upper bound for hit rates

## Hit statistics (`app` target: 142 source files, 154 signature files)

| metric | value |
|---|---|
| `check_type` calls | 194,984 |
| cache hits | 112,296 (57.6%) |
| computed (miss) | 82,376 |
| computed (cached but discarded due to unknown constraint vars) | 312 |
| distinct relations | 25,303 |
| distinct cache entries at end | 80,286 |

Split by recursion depth:

| | calls | hits | hit rate |
|---|---|---|---|
| top-level (`assumptions` empty) | 80,289 | 58,895 | 73.4% |
| nested (inside `check_type0` recursion) | 114,695 | 53,401 | 46.6% |

A top-level hit skips the whole recursive subtree of the check, so the effective saving is larger than the raw 57.6% hit rate suggests.

## Wall-clock time (`app` target)

| mode | source type check |
|---|---|
| cache on | 37.0–40.6 s |
| cache disabled (`CACHE_MODE=off`: always miss, still pays bookkeeping) | 72.2–73.6 s |
| cache removed (`CACHE_MODE=none`: no cache code at all) | 61.1–65.5 s |

- Net effect of the cache vs. the fair baseline (`none`): source type checking is **~1.7x faster** (≈63 s → ≈37 s).
- The cache bookkeeping itself (computing `cache_bounds`, `free_variables` sets, key arrays, hash lookups/stores) costs **≈9 s per full run** (`off` ≈72 s vs `none` ≈63 s); the hits save ≈35 s, for a net ≈26 s.
- Signature validation (~3 s) barely changes in any mode: its subtype checks rarely repeat.

Share of subtyping in type checking (`TIME_SHARE=1`): with the cache on, top-level `check_type` calls take 6.95 s out of a 33.1 s source-check phase (**≈21%**). With the cache disabled the same work takes ≈42 s of a ≈72 s run (**≈58%**) — the cache is what keeps subtyping from dominating type checking.

### `test` target: the cache does not pay off there

`on` ≈10.7–12.0 s vs `off` ≈11.3–12.6 s for 72 files; only 7,442 entries, hit rate 81.8% but just 8,559 computes. Test code produces few and cheap subtype queries, so the bookkeeping cost roughly cancels the hits.

## Which relations benefit

Per-kind statistics (`CACHE_STATS=1 KIND=1`), top kinds by call count. `tl time` is the total wall-clock of top-level (non-nested) computes of that kind:

| kind | calls | hit rate | computes | tl time | avg tl compute |
|---|---|---|---|---|---|
| `Instance <: Instance` | 122,757 | 60.0% | 49,063 | 1.50 s | 0.21 ms |
| `Literal <: Literal` | 13,735 | 83.7% | 2,237 | 0.11 s | 0.07 ms |
| `Instance <: Union` | 8,470 | 39.4% | 5,129 | 0.62 s | 0.85 ms |
| `Interface <: Instance` | 4,008 | 82.4% | 707 | — | (nested only) |
| `Union <: Union` | 3,002 | 34.5% | 1,966 | 1.87 s | 2.52 ms |
| `Union <: Alias` | 2,316 | 66.1% | 786 | 1.03 s | 1.74 ms |
| `Alias <: Union` | 581 | 52.3% | 277 | 0.64 s | 5.64 ms |
| `Instance <: Var` | 573 | 2.4% | 559 | 0.02 s | 0.06 ms |

Observations:

- **`Instance <: Instance` dominates volume** (63% of all calls, 60% hit rate). Each compute is cheap (~0.2 ms), but 74k hits add up — this is where most of the ≈35 s saving comes from.
- **Union/Alias-related checks are where a single hit saves the most**: a `Union <: Union` compute averages 2.5 ms and `Alias <: Union` 5.6 ms (branch expansion), an order of magnitude above `Instance <: Instance`.
- **`Interface <: Instance` hits 82%** — structural interface checks are expensive and repeat a lot, an ideal cache customer.
- **Constraint-generating relations are effectively uncacheable**: `Instance <: Var` hits 2.4% — cached results are discarded whenever an unknown constraint variable is involved, but the entries are still stored.
- **Reflexive relations (`T <: T`) are 18.6% of all calls** (36,360; 27,804 of them "hits") and 10.6% of entries (8,488). `check_type0` resolves them immediately via `same_type?`, so for these the cache only replaces one trivial compute with one hash lookup — and permanently retains an entry.

Most frequent individual relations: `::Symbol <: ::Symbol` (1,931 calls), `::String <: ::String` (1,920), `::Integer <: ::Integer` (1,356), `(::Symbol | ::string) <: ::interned` (1,075), `::Parser::AST::Node <: ::Parser::AST::Node` (1,005), symbol-literal reflexive checks (`:type <: :type`, …), and `::Object <: ::Steep::AST::Types::*` from case analysis in Steep's own code — i.e., mostly reflexive or near-trivial checks, plus repeated alias expansions.

## Context keying fragments the cache

The cache key includes the `(self_type, instance_type, class_type, bounds)` context, which changes with the class being type checked — so every cached result becomes unreachable as soon as checking moves to a class with a different `self`. That context only affects the result when the relation's types contain the `self`/`instance`/`class` placeholder types or type variables; for *ground* relations (no free variables — `Check#cacheable?` is exactly this predicate, currently unused) the result is context-independent, yet they are cached per context.

Measured on Steep itself (`steep check -j2`): **55–70% of all computes per worker are ground relations that were already computed under another context** (the `context-fragmented misses` line in the stats report). The effect grows with the number of classes in the project, because more classes means more distinct contexts — a Rails-scale codebase fragments harder than Steep does. It also duplicates entries: the app-target run stores 80,286 entries for 25,303 distinct relations, roughly 3 copies per relation.

The fix is to key ground relations by the relation alone (one flat `relation → result` table, no context), keeping the context key only for relations with free variables. This converts the majority of misses into hits on both time and memory: fewer computes, and one entry per ground relation instead of one per context.

## Implemented: Phase 1 optimizations

Three changes, now implemented in `Check#check_type` and `Cache`:

1. **Ground relations are cached without the context** (`Cache#ground_subtypes`): relations without free variables — `cacheable?` — go to a flat `relation → result` table. The ground path also skips `cache_bounds` (a fresh, almost always empty `Hash` per call), the `free_variables` set union, and the unknown-constraint check.
2. **Trivially successful relations are not cached**: `T <: T` (by `==`), `untyped` on either side, `top`/`void` as super type, `bot` as sub type — resolved by the first branches of `check_type0` — return success immediately without touching the cache.
3. **Successful results are stored without their derivation tree** (`Check#cache_value`): the tree is only read through `#failure_path` to explain failures.

Measured on Steep itself (app target, single process):

| metric | before | after |
|---|---|---|
| `check_type` calls | 194,984 | 121,781 (avoided computes also drop their nested calls) |
| computed | 82,688 | **23,784 (−71%)** |
| hit rate (of cache lookups) | 57.6% | **71.3%** (plus 38,906 uncached trivial shortcuts) |
| context-fragmented misses | ~55–70% of computes | 1,155 |
| cache entries | 80,286 | **21,450 (−73%)** (18,961 ground + 2,489 context-keyed) |
| memory exclusively retained | 70.2 MB | **24.1 MB (−66%)** |
| peak RSS of the run | ~800 MB | ~676 MB |
| top-level compute time | 6.95 s | 4.62 s |
| source type check wall-clock | 37–41 s | 39–43 s (unchanged within noise) |

Wall-clock on Steep itself is unchanged because subtyping was already only ~20% of the source-check phase here; the compute reduction matters most on codebases where fragmented misses hit expensive kinds (`Instance <: Interface`, Union/Alias expansion). Diagnostics are identical on all pre-existing code (the only diff is hints on the newly added code itself and line-number shifts).

The remaining 1,155 repeated ground computes come from a second `Subtyping::Check` instance created by `Interface::Builder` for shape building, which has its own cache — sharing the ground table between them is a possible follow-up.

## Memory usage (`app` target, `MEM=1`)

Composition of the 80,286 entries:

- **873 distinct contexts** `(self_type, instance_type, class_type, bounds)` — the 5-element key array repeats the same context in ~every entry (the largest context holds 7,704 entries).
- **99.6% of entries have an empty `bounds` hash** — `cache_bounds` allocates a fresh empty `Hash` per `check_type` call, and one is retained per entry.
- Values: `Any` 39,748, `Failure` 15,666, `Success` 12,545, `Expand` 9,480, `All` 2,847; 36% of cached results are successes, 64% failures (failed branches of union checks etc.).
- Cached success values retain their whole derivation tree: 1.48M reachable result-tree node references, but only 65,169 *unique* `Result` objects (subtrees are heavily shared because nested cache hits return the same object into many parents' `branches`). Failure trees: 57,047 unique nodes.
- Memory reachable from the cache: 160 MB / 1.93M objects (shared with the environment and typings).
- Memory *exclusively* retained by the cache (freed by `subtypes.clear`, measured via `ObjectSpace.memsize_of_all`): **70.2 MB** (945k object slots).

## Literal types: hash collisions and union membership

Two changes target literal-heavy codebases (enum-like aliases such as `type status = :draft | :published | ...`), where every literal is a distinct relation and caching alone cannot help.

**`Literal#hash` ignored the value.** It returned `self.class.hash` for every literal while `#==` compares values, so every literal type landed in the same bucket of any type-keyed `Hash` — the subtyping cache above all. Lookups and stores of literal relations degraded into linear scans of the colliding chain, and the cost grows with the number of distinct literal relations accumulated in the cache. A synthetic benchmark (4,000 checks of 200 distinct literals against a 200-literal union alias, so ~400 distinct literal relations) improves from 152 ms to 121 ms (−20%); codebases holding thousands of distinct literal relations per worker see a much larger effect, because the chain is that much longer.

**Membership fast path.** `Literal <: Union` used to expand the union and test the branches one by one, building an `Any` result with a failure branch for every literal that did not match. When the union has no free variables and contains an equal literal, `check_type0` now returns a plain `Success` instead — success derivations are never inspected, so the result is indistinguishable. Unions with unknown type variables keep the branching path so that constraint recording is not skipped, and failures keep it so that diagnostics do not change. Enum-like aliases reach this path after alias expansion.

The fast path only makes *computes* cheaper, so a benchmark dominated by cache hits (like the synthetic one above) barely registers it; it shows up in the `top-level compute` time of the `Literal <: Union` and `Literal <: Alias` rows of the stats report.

## Remaining candidates

1. **For the long-lived LSP process: evict the context-keyed table per file** (`CLEAR_PER_FILE=1` in the benchmark): 79% of hits are produced and consumed while checking the same file, and context-keyed entries are bound to the file's classes anyway. Keeping the ground table (now the vast majority of entries, valid forever until a signature reload) and clearing the context-keyed table per file bounds memory with almost no hit-rate cost.
2. **Share the ground table between the `Subtyping::Check` instances** created per target and by `Interface::Builder` (see above).
3. **Skip storing relations whose free variables include unknown constraint variables**: stored today but almost never usable (cf. `Instance <: Var` at 2.4% hits), and related to the known constraints-replay bug below.
4. **Shape building, not subtyping, is now the larger cost** — see below.

Historical note: prototype measurements of earlier candidates (collapse-only −15%, context-two-level −42%, plus reflexive-skip −45% memory) led to the Phase 1 design above, which supersedes them.

## Shape building is now the larger cost

With the subtyping compute reduced, `Interface::Builder#shape` dominates. Measured with `STEEP_SUBTYPING_STATS=1` on Steep itself (`-j2`): 18,768–34,206 shape calls taking **9.7–15.4 s per worker**, against 2.2–2.8 s of subtyping compute — 4–5x. The report breaks the time down by the kind of the shape target; on Steep the largest are `Instance`, `Singleton`, `self` and `Union`.

Three observations for that work:

- Warming every type up front (`bin/shape_warmup_bench.rb`) costs 16.7 s and 270 MB for all 1,809 types of Steep's own environment (5.0 s / 86 MB for the 583 project types alone), split as 3.1 s of RBS `Definition` building and 12.5 s of Steep-side shape assembly. So the cost to attack is the assembly, not RBS.
- The assembly converts **858,957 `type_def`s of which only 23,550 are unique** by `(method name, type)` — RBS definitions are flattened, so the methods of `Object`, `Kernel` and every mixin are re-converted for each of the 1,809 types. The conversion is a pure function of `(method name, type_def)` (`method_name_for` uses `implemented_in || defined_in`); the sole type-name-dependent step is `replace_kernel_class`, which only rewrites `Kernel#class`. Memoizing the conversion is therefore the single largest available win, and it applies to lazy building just as much as to warming.
- `self_shape` has no cache of its own. `object_shape`/`singleton_shape` results are cached, but each `self` shape wraps them in a fresh `Shape`, whose lazily resolved methods (`Methods#resolved_methods`) are rebuilt per call. On Steep that is 6,450 calls and 1.2 s per worker; the substituted result depends only on the self type in the common branches, so it looks memoizable.

`GC` accounts for ~37% of samples during warming, but `GC.disable` makes it *worse* (12.5 s → 19.3 s): the GC time is a symptom of allocation volume, so the fix is to allocate less (i.e. the memoization above), not to tune the GC.

## Cache changes results (known bug)

The full `app` run reports 1007 diagnostics with the cache on and 1009 with it off — with the cache disabled, two additional `UnsatisfiableConstraint` diagnostics appear (in `lib/steep/annotations_helper.rb` and `lib/steep/type_construction.rb`). The cache key does not include the `Constraints` context, and a cached result is reused whenever the relation's free variables have no *unknown* constraint variables — so constraint side effects recorded on the first computation are not replayed on later hits.

## Measuring your own codebase with a normal `steep check`

The stats collection is built into Steep itself (`Steep::Subtyping::Stats`) and is activated by environment variables, so it works with a plain `steep check` — each worker process reports its own statistics when it exits. To use it on another codebase, point your Gemfile at this branch:

```ruby
gem "steep", github: "soutaro/steep", branch: "claude/subtyping-cache-performance-034hwm", require: false
```

Then:

```sh
# Summary to stderr, per worker process.
# Contains only counts and type KINDS (`Instance <: Union`, ...) — no type names
# from your codebase — so it is safe to share as-is.
STEEP_SUBTYPING_STATS=1 bundle exec steep check

# Additionally append one JSON object per worker process to a file.
# NOTE: the JSON includes the most frequent relations (top_relations), the
# relations with the highest top-level compute time
# (top_relations_by_compute_time), and the most expensive shape targets
# (top_shapes_by_time) as strings, i.e. type names from your codebase. Keep it
# local, or strip those keys before sharing.
STEEP_SUBTYPING_STATS=1 STEEP_SUBTYPING_STATS_FILE=steep-stats.jsonl bundle exec steep check

# Additionally measure the memory exclusively retained by the cache
# (clears the cache on exit and compares ObjectSpace.memsize_of_all;
# makes process exit a few seconds slower).
STEEP_SUBTYPING_STATS=1 STEEP_SUBTYPING_STATS_MEMORY=1 bundle exec steep check
```

Notes for interpreting the numbers:

- One report per worker process (`-j`): files are partitioned across workers, each with its own cache, so per-worker hit rates are the real-world behavior (a single process would hit more). `-j1` gives one aggregate report.
- A worker checking several targets reports them combined.
- Overhead of the collection is a few percent; with the variables unset it is a nil check per `check_type` call.

Example output (per worker):

```
[steep 2.1.0] subtyping cache stats (pid 8406)
  check_type calls: 73837 (reflexive: 19875, distinct relations: 14420)
  cache hits: 32525 (44.0%; top-level: 15326, reflexive: 0)
  computed: 14864 (top-level: 5994, taking 2.18s; cached but unusable: 235)
  trivial shortcuts (uncached): 26448
  context-fragmented misses: 2319 (15.6% of computes are ground relations already computed in another context)
  assumption successes: 0
  cache entries: 14629 (ground: 13242, contexts: 100, reflexive: 0, successes: 6006)
  top kinds by calls:
    Instance <: Instance                        37015 calls  61.0% hit     6793 computes     0.30s top-level compute
    ...
```

The remaining `context-fragmented misses` after Phase 1 come from the second `Subtyping::Check` instance `Interface::Builder` creates for shape building — the counter treats a relation computed in either cache as "already computed".

## Reproducing

```sh
# hit statistics, per-kind statistics, hit locality
CACHE_STATS=1 KIND=1 LOCALITY=1 bundle exec ruby bin/subtyping_cache_bench.rb

# timing, no cache at all
CACHE_MODE=none bundle exec ruby bin/subtyping_cache_bench.rb

# memory analysis
MEM=1 bundle exec ruby bin/subtyping_cache_bench.rb

# memory analysis with all prototype changes
MEM=1 PROTO=collapse,ctxkey,noreflex bundle exec ruby bin/subtyping_cache_bench.rb

# per-file eviction
CLEAR_PER_FILE=1 bundle exec ruby bin/subtyping_cache_bench.rb

# subtyping share of type checking
TIME_SHARE=1 bundle exec ruby bin/subtyping_cache_bench.rb

# boot cost of pre-building all shapes (zygote sizing); works on any project:
#   bundle exec ruby "$(bundle info steep --path)/bin/shape_warmup_bench.rb"
bundle exec ruby bin/shape_warmup_bench.rb
```
