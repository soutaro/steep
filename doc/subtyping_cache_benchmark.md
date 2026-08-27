# Subtyping cache benchmark

How much does `Steep::Subtyping::Cache` help?
This document records measurements taken with `bin/subtyping_cache_bench.rb`, which runs the same pipeline as `steep check` (signature validation + source type checking) in a single process so that one `Subtyping::Check`/`Cache` instance is shared per target, and:

- counts cache hits/misses in `Check#check_type` (`CACHE_STATS=1`)
- compares wall-clock time in three modes (`CACHE_MODE`):
  - `on` — the current behavior
  - `off` — lookups always miss and stores are dropped, but `check_type` still pays the cache bookkeeping (`cache_bounds`, `free_variables`, lookup/store calls)
  - `none` — the caching logic is removed from `check_type` entirely, which is the fair "no cache" baseline
- measures the time spent inside top-level `check_type` calls (`TIME_SHARE=1`) to see how much of type checking is subtyping at all

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
| assumption short-circuits | 0 |
| distinct cache entries at end | 80,286 |

Split by recursion depth:

| | calls | hits | hit rate |
|---|---|---|---|
| top-level (`assumptions` empty) | 80,289 | 58,895 | 73.4% |
| nested (inside `check_type0` recursion) | 114,695 | 53,401 | 46.6% |

A top-level hit skips the whole recursive subtree of the check, so the effective saving is larger than the raw 57.6% hit rate suggests.

## Wall-clock time (`app` target, 3 runs for `on`/`off`, 2 for `none`)

| mode | signature validation | source type check |
|---|---|---|
| `on` | 2.8–3.8 s | 37.0–39.7 s |
| `off` | 3.0–3.4 s | 72.2–73.6 s |
| `none` | 3.2–3.5 s | 61.1–65.5 s |

- Net effect of the cache vs. the fair baseline (`none`): source type checking is **~1.7x faster** (≈63 s → ≈37 s).
- The cache bookkeeping itself (computing `cache_bounds`, `free_variables` sets, key arrays, hash lookups/stores) costs **≈9 s per full run** (`off` ≈72 s vs `none` ≈63 s); the hits save ≈35 s, for a net ≈26 s.
- Signature validation barely changes: its subtype checks (variance, overriding) rarely repeat.

## Share of subtyping in type checking (`TIME_SHARE=1`, cache on)

Top-level `check_type` calls: 80,474, total 6.95 s out of a 33.1 s source-check phase (**≈21%**).
With the cache disabled the same work takes ≈42 s of a ≈72 s run (**≈58%**): the cache is what keeps subtyping from dominating type checking.

## `test` target: the cache does not pay off there

| mode | source type check (72 files) |
|---|---|
| `on` | ≈12.0 s |
| `off` | ≈11.3 s |

Only 7,442 cache entries are created. Test code (minitest blocks, lenient diagnostics, mostly unannotated) produces few repeated subtype queries, so the bookkeeping cost roughly cancels the hits.

## Cache changes results slightly

The full `app` run reports 1007 diagnostics with the cache on and 1009 with it off (`DIAG_DUMP=path` to compare).
The cache key is `[relation, self_type, instance_type, class_type, bounds]` and does not include the `Constraints` context, and cached results are reused whenever the relation's free variables have no *unknown* constraint variables — so a result computed under one constraint context can be replayed under another, and constraint side effects recorded on the first computation are not replayed on a hit.

## Reproducing

```sh
# hit statistics
CACHE_STATS=1 bundle exec ruby bin/subtyping_cache_bench.rb

# timing, no cache at all
CACHE_MODE=none bundle exec ruby bin/subtyping_cache_bench.rb

# subtyping share of type checking
TIME_SHARE=1 bundle exec ruby bin/subtyping_cache_bench.rb

# other targets
TARGETS=test bundle exec ruby bin/subtyping_cache_bench.rb
```
