# Features: fusemojo

> A Mojo port of the Fuse.js bitap fuzzy-search engine. Two public APIs — a per-string `BitapSearcher` and a collection-level `Fuse` — backed by a bit-parallel matcher that handles patterns up to 64 codepoints (vs Fuse.js's 32). Ships with a regression test suite, a spec-test surface that documents the gap against Fuse.js, and a benchmark harness using Project Gutenberg corpora.

**Capability areas:**
- **[Collection fuzzy search](#collection-fuzzy-search)** — `Fuse` over `List[String]`, sorted scored results
- **[Per-string bitap engine](#per-string-bitap-engine)** — `BitapSearcher` and `bitap_search` for one-text queries
- **[Scoring & match indices](#scoring--match-indices)** — accuracy + proximity formula, bitmask → ranges
- **[Codepoint plumbing](#codepoint-plumbing)** — Unicode-aware preprocessing and ASCII case folding
- **[Spec-test surface](#spec-test-surface)** — executable docs of Fuse.js parity gaps and extension features
- **[Benchmark harness](#benchmark-harness)** — latency/throughput on five public-domain corpora

---

## Collection fuzzy search

The top-level product surface. Given a `List[String]` and a query, return scored matches sorted best-first. Modeled on Fuse.js's constructor options.

**Key symbols:**
- `fusemojo/fuse.mojo#Fuse` — Owns the collection; carries threshold/distance/location/case/sort settings.
- `fusemojo/fuse.mojo#search` — Build a `BitapSearcher` per query, scan every item, filter by `is_match`, sort by score (selection sort, OK for small result sets). Method on `Fuse`.
- `fusemojo/fuse.mojo#FuseResult` — `{item, index, score, matches}` returned to caller.

**Workflow:** Caller constructs `Fuse(collection^, threshold=..., ignore_location=..., ...)` (takes ownership of the list). `search(query)` constructs a fresh `BitapSearcher` from the query, iterates `collection`, keeps matches, and optionally sorts. Empty query → empty list.

**Constraints:**
- Sort is O(n²) selection sort — fine for short result sets, called out as a known gap vs Fuse.js's TimSort.
- One searcher built per `search()` call (pattern alphabet recomputed every time, but Mojo makes this cheap).
- No multi-key search; collection items are bare strings.

---

## Per-string bitap engine

Low-level matcher for a single (pattern, text) pair. Exposed so callers can integrate fuzzy match into their own loops without `Fuse`'s collection plumbing.

**Key symbols:**
- `fusemojo/bitap.mojo#BitapSearcher` — Holds preprocessed pattern codepoints and the pattern alphabet (bitmask Dict). Reusable across many `search_in(text)` calls.
- `fusemojo/bitap.mojo#search_in` — Case-normalize text → exact-match fast path → delegate to `bitap_search`. Method on `BitapSearcher`.
- `fusemojo/bitap.mojo#bitap_search` — The kernel. Right-to-left scan over the text, incrementing error count outer loop, bit-parallel shift-OR-AND inner loop. Tightens threshold whenever a better match lands. Includes an exact-match acceleration pass before the fuzzy phase.
- `fusemojo/bitap.mojo#SearchResult` — `{is_match, score, indices}`.

**Workflow:** `BitapSearcher(pattern, threshold=..., ...)` → `searcher.search_in(text)` returns a `SearchResult`. The kernel uses a `UInt64` bit array per error level, binary-searches the furthest in-threshold text position, then slides bits across the text with `(bit_arr[j+1] << 1 | 1) & char_match`. Substitution / insertion / deletion bits are OR'd in from `last_bit_arr` for errors ≥ 1.

**Constraints:**
- `MAX_BITS = 64` — patterns longer than 64 codepoints silently return no-match (`is_match=False, score=1.0`). Chunking is an unbuilt feature in the spec tests.
- Pattern alphabet is a `Dict[Int, UInt64]` keyed by codepoint, not byte — Unicode-safe at the pattern level.

---

## Scoring & match indices

The scoring math and the bitmask→range conversion that produces `include_matches` output.

**Key symbols:**
- `fusemojo/bitap.mojo#compute_score` — `score = errors/pattern_len + |actual - expected| / distance`. Clamped: `pattern_len == 0 → 1.0`; `distance == 0` with any proximity → `1.0`; `ignore_location=True` collapses to pure accuracy.
- `fusemojo/bitap.mojo#convert_mask_to_indices` — Scans the per-character `matchmask` list and emits `[MatchRange(start, end)]` for each contiguous run ≥ `min_match_char_length`.
- `fusemojo/bitap.mojo#MatchRange` — `{start, end}` inclusive span.

**Invariants:**
- Final reported score is floor-clamped to `0.001` (exact-match-but-not-at-expected-location stays distinguishable from a true zero).
- If `is_match` is false, score is forced to `1.0` regardless of computed value.
- `include_matches=True` can flip `is_match` to false if the per-char mask produces zero ranges after filtering — match without reportable indices is treated as no match.

---

## Codepoint plumbing

Unicode-aware preprocessing layer between Mojo `String` and the integer-codepoint world the bitap kernel operates in.

**Key symbols:**
- `fusemojo/bitap.mojo#string_to_codepoints` — `String` → `List[Int]` via `s.codepoints()`. Pattern and text always pass through this.
- `fusemojo/bitap.mojo#to_lower_codepoints` — ASCII-only A-Z → a-z. **Known gap:** does not fold Latin Extended (É→é), Greek, Cyrillic, or any non-ASCII; spec-tested in `test_port_gaps.mojo` Part 1A.
- `fusemojo/bitap.mojo#create_pattern_alphabet` — Builds `Dict[Int, UInt64]` where bit `(pattern_len - 1 - i)` of `masks[codepoint]` is set for each occurrence of `codepoint` at position `i` in the pattern.
- `fusemojo/bitap.mojo#codepoints_equal`, `find_exact` — Exact-match helpers used by the exact-acceleration phase and the searcher's fast path.

---

## Spec-test surface

Two test files in `test/` go beyond regression coverage — they are *executable specifications* for work not yet built. Tests in these files mostly print `SKIP` with the full spec in their docstring; the file is the design doc.

**Key symbols:**
- `test/test_port_gaps.mojo` — Six capability gaps against Fuse.js: 1A Unicode case folding (bug), 1B `limit` with max-heap (missing), 1C TimSort + custom `sort_fn` (bug + missing), 1D pattern chunking for >64-char patterns (missing), 1E extended-search operators (`|`, `!`, `^`, `$`, `=`, `'`, `"`; missing), 1F multi-key search with weights (missing).
- `test/test_extended.mojo` — Six extension capabilities beyond Fuse.js: 2A trigram index construction, 2B trigram searcher for long patterns, 2C pre-filtered search pipeline, 2D parallel collection scan, 2E collection mutation, 2F custom scoring functions. All `SKIP` pending the trait/abstraction work in `test_port_gaps` Part 1.
- `test/test_fusemojo.mojo` — 66 regression tests covering the working surface: exact/fuzzy match, Unicode emoji/accents (basic), boundary cases (empty, max-bits, over-max-bits), threshold/distance/location parameter sweeps, `find_all_matches`, `min_match_char_length`, case sensitivity, sort ordering, searcher reuse.

**Convention:** A SKIP test carries the full spec in its docstring so the test output is also the design doc. When a feature lands: drop the SKIP line, fill in the body described in the docstring. See [issue #3](https://github.com/oaustegard/fusemojo/issues/3) for the umbrella context.

---

## Benchmark harness

Measures search latency, throughput, and scaling on real-world prose.

**Key symbols:**
- `test/bench_fusemojo.mojo` — Loads five Gutenberg texts from `test/data/`: Shakespeare (~196K lines, 5.7MB), War and Peace (~65K, 3.3MB), Moby Dick (~22K, 1.3MB), Pride and Prejudice (~14.5K, 725KB), Alice in Wonderland (~3.4K, 170KB), plus a combined ~11MB / 301K-line corpus.
- `test/bench_fusemojo.mojo#load_lines`, `print_corpus` — Corpus loading and stats.

**Workflow:** `mojo run -I . test/bench_fusemojo.mojo`. Uses `std.time.perf_counter_ns` for timing.

**Data:** `test/data/*.txt` are committed public-domain texts (no download step needed).

---

## What's not here

Deliberately scoped out of the current port, all documented as spec tests:
- Search operators (`'word`, `!exclude`, `^prefix`, `suffix$`, `=exact`, `"phrase"`, `|or`).
- Multi-key object search (Fuse.js's `keys: [{name, weight}]` API).
- Result limiting with a max-heap.
- Pattern chunking for queries >64 codepoints.
- Non-ASCII case folding.
- A `Searcher` trait or pluggable scoring — the architectural prerequisite for most of the above.
