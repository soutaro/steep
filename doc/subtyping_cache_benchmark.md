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

## Memory usage (`app` target, `MEM=1`)

Composition of the 80,286 entries:

- **873 distinct contexts** `(self_type, instance_type, class_type, bounds)` — the 5-element key array repeats the same context in ~every entry (the largest context holds 7,704 entries).
- **99.6% of entries have an empty `bounds` hash** — `cache_bounds` allocates a fresh empty `Hash` per `check_type` call, and one is retained per entry.
- Values: `Any` 39,748, `Failure` 15,666, `Success` 12,545, `Expand` 9,480, `All` 2,847; 36% of cached results are successes, 64% failures (failed branches of union checks etc.).
- Cached success values retain their whole derivation tree: 1.48M reachable result-tree node references, but only 65,169 *unique* `Result` objects (subtrees are heavily shared because nested cache hits return the same object into many parents' `branches`). Failure trees: 57,047 unique nodes.
- Memory reachable from the cache: 160 MB / 1.93M objects (shared with the environment and typings).
- Memory *exclusively* retained by the cache (freed by `subtypes.clear`, measured via `ObjectSpace.memsize_of_all`): **70.2 MB** (945k object slots).

## Improvement candidates (all measured, all with identical diagnostics)

| configuration | exclusive cache memory | source check time |
|---|---|---|
| current | 70.2 MB | 37.0–40.6 s |
| 1. collapse successes | 59.7 MB (−15%) | 36.5 s |
| 1+2. + context-keyed storage | 40.6 MB (−42%) | 36.2 s |
| 1+2+3. + skip reflexive entries | 38.8 MB (−45%) | 34.1–36.4 s |
| 4. clear cache per file | bounded by one file's working set | 37.4 s |

1. **Collapse successful results before storing** (`PROTO=collapse`): store `Success.new(relation)` instead of the full `Expand`/`All`/`Any` tree. Derivation trees are only consumed via `#failure_path` on failures (nothing outside `result.rb` reads `#child`/`#branches`), so this is behavior-preserving. Peak RSS also drops ≈20 MB.
2. **Two-level storage keyed by context then relation** (`PROTO=ctxkey`): `subtypes[context][relation]` instead of one 5-element array key per entry. Stores each of the 873 contexts once instead of 80k times, hashes only the relation on the hot path (the 5-element key array was built and hashed twice per call), and makes the shared empty `bounds` problem irrelevant. This is also consistently the fastest configuration.
3. **Do not cache reflexive relations** (`PROTO=noreflex`): `T <: T` succeeds immediately in `check_type0`; skipping lookup and store removes 8.5k entries with no time cost. (A variant worth trying: also skip storing relations whose free variables include unknown constraint variables — those entries are stored today but almost never usable, cf. `Instance <: Var` at 2.4% hits.)
4. **For the long-lived LSP process: evict per file** (`CLEAR_PER_FILE=1`): 79% of hits (89,184 / 112,296) are produced and consumed while checking the same file; clearing the whole cache after every file costs ≈0–6% time on this codebase while bounding cache memory by a single file's working set instead of growing monotonically with every file checked in the session. (In `steep check` the cache dies with the process; in `steep langserver` it lives until the next signature reload, so this matters most there.)

1–3 combined change no diagnostics (1007, byte-identical) and are, if anything, slightly faster than the current cache.

## Cache changes results (known bug)

The full `app` run reports 1007 diagnostics with the cache on and 1009 with it off — with the cache disabled, two additional `UnsatisfiableConstraint` diagnostics appear (in `lib/steep/annotations_helper.rb` and `lib/steep/type_construction.rb`). The cache key does not include the `Constraints` context, and a cached result is reused whenever the relation's free variables have no *unknown* constraint variables — so constraint side effects recorded on the first computation are not replayed on later hits.

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
```
