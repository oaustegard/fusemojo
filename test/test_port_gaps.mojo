"""Test specifications for faithful Fuse.js port gaps.

Tests that define the gap between FuseMojo and Fuse.js behavior.
  - Existing bugs cause FAIL until fixed.
  - Missing features print SKIP with the full specification in the
    docstring, so the spec is visible in test output and in the file.

See https://github.com/oaustegard/fusemojo/issues/3 for full context.
"""

from fusemojo import Fuse, FuseResult
from fusemojo.bitap import (
    bitap_search,
    create_pattern_alphabet,
    string_to_codepoints,
    to_lower_codepoints,
    codepoints_equal,
    BitapSearcher,
    SearchResult,
    MatchRange,
)


# ═══════════════════════════════════════════════════════════════════
# Part 1A: Unicode case folding  (BUG in to_lower_codepoints)
# ═══════════════════════════════════════════════════════════════════
# bitap.mojo:63-72 only maps ASCII A-Z (65-90). All non-English text
# is broken for case-insensitive search.


def test_fold_latin_extended():
    """1A.1 Latin Extended: É(201)→é(233), Ñ(209)→ñ(241), Ü(220)→ü(252)."""
    print("test_fold_latin_extended ... ", end="")
    var cps: List[Int] = [201, 209, 220]
    var lowered = to_lower_codepoints(cps)
    if lowered[0] != 233:
        print("FAIL (É(201) →", lowered[0], ", expected é(233))")
        return
    if lowered[1] != 241:
        print("FAIL (Ñ(209) →", lowered[1], ", expected ñ(241))")
        return
    if lowered[2] != 252:
        print("FAIL (Ü(220) →", lowered[2], ", expected ü(252))")
        return
    print("ok")


def test_fold_greek():
    """1A.2 Greek: Α(913)→α(945), Ω(937)→ω(969)."""
    print("test_fold_greek ... ", end="")
    var cps: List[Int] = [913, 937]
    var lowered = to_lower_codepoints(cps)
    if lowered[0] != 945:
        print("FAIL (Α(913) →", lowered[0], ", expected α(945))")
        return
    if lowered[1] != 969:
        print("FAIL (Ω(937) →", lowered[1], ", expected ω(969))")
        return
    print("ok")


def test_fold_cyrillic():
    """1A.3 Cyrillic: А(1040)→а(1072), Я(1071)→я(1103)."""
    print("test_fold_cyrillic ... ", end="")
    var cps: List[Int] = [1040, 1071]
    var lowered = to_lower_codepoints(cps)
    if lowered[0] != 1072:
        print("FAIL (А(1040) →", lowered[0], ", expected а(1072))")
        return
    if lowered[1] != 1103:
        print("FAIL (Я(1071) →", lowered[1], ", expected я(1103))")
        return
    print("ok")


def test_fold_sharp_s_idempotent():
    """1A.4 ß(223) has no single-char uppercase.

    JavaScript toLowerCase leaves ß unchanged. After a fix, folding a
    lowercase ß MUST remain ß — do not accidentally fold it further.
    """
    print("test_fold_sharp_s_idempotent ... ", end="")
    var cps: List[Int] = [223]
    var lowered = to_lower_codepoints(cps)
    if lowered[0] != 223:
        print("FAIL (ß(223) should remain 223, got", lowered[0], ")")
        return
    print("ok")


def test_case_insensitive_accented_match() raises:
    """1A.5 BitapSearcher should match 'café' against 'CAFÉ'.

    With case_sensitive=False, case-folded codepoints should be equal,
    producing the exact-match fast path (is_match=True, score≈0).
    """
    print("test_case_insensitive_accented_match ... ", end="")
    var searcher = BitapSearcher(
        "café", case_sensitive=False, ignore_location=True
    )
    var result = searcher.search_in("CAFÉ")
    if not result.is_match:
        print("FAIL (case-insensitive 'café' vs 'CAFÉ' should match)")
        return
    if result.score > 0.01:
        print("FAIL (score too high:", result.score, ", expected near 0)")
        return
    print("ok")


def test_case_insensitive_cyrillic_match() raises:
    """1A.6 BitapSearcher should match Cyrillic words across cases."""
    print("test_case_insensitive_cyrillic_match ... ", end="")
    var searcher = BitapSearcher(
        "привет", case_sensitive=False, ignore_location=True
    )
    var result = searcher.search_in("ПРИВЕТ")
    if not result.is_match:
        print("FAIL (case-insensitive Cyrillic should match)")
        return
    if result.score > 0.01:
        print("FAIL (score too high:", result.score, ", expected near 0)")
        return
    print("ok")


# ═══════════════════════════════════════════════════════════════════
# Part 1B: Result limiting with MaxHeap  (MISSING FEATURE)
# ═══════════════════════════════════════════════════════════════════


def test_fuse_limit_top_n():
    """1B.1 SKIP — `limit` kwarg does not exist on Fuse.

    SPEC:
      `Fuse(collection, limit=10)` returns at most 10 results,
      and those 10 are the BEST by score (not the first 10
      encountered during the scan).

      `limit=0` or `limit=-1` returns all (default behavior
      unchanged).

    IMPLEMENTATION:
      MaxHeap keyed by score where the worst score is at the root.
      `should_insert(score)` returns True if `size < limit` OR
      `score < heap[0].score`. On insert when full, replace root
      and sink down.

      When `limit > 0`, wire the heap into Fuse.search instead of
      collecting every match and sorting at the end.

    PERFORMANCE:
      With a 100K+ item collection and limit=10, time should be
      dramatically better than scanning-then-sorting all matches.
      Add a perf regression test once the feature lands.
    """
    print("test_fuse_limit_top_n ... SKIP (no `limit` kwarg)")


def test_fuse_limit_selects_best() -> None:
    """1B.2 SKIP — verify the kept results are the best-scoring."""
    print("test_fuse_limit_selects_best ... SKIP (no `limit` kwarg)")


# ═══════════════════════════════════════════════════════════════════
# Part 1C: Sort fix  (BUG: O(n²) selection sort; MISSING: sort_fn)
# ═══════════════════════════════════════════════════════════════════
# fuse.mojo:143-150 uses selection sort. Fuse.js uses TimSort (O(n log n)).


def test_sort_primary_by_score() raises:
    """1C.1 Results must be sorted by score ascending (best first)."""
    print("test_sort_primary_by_score ... ", end="")
    var collection: List[String] = [
        "the quick brown fox",   # fuzzy match
        "quick",                  # near-exact
        "quickly",                # exact substring
        "slow",                   # no match
    ]
    var fuse = Fuse(collection^, threshold=0.6, ignore_location=True)
    var results = fuse.search("quick")
    if len(results) < 2:
        print("FAIL (expected ≥2 results, got", len(results), ")")
        return
    for i in range(len(results) - 1):
        if results[i].score > results[i + 1].score:
            print(
                "FAIL (scores not ascending at i=", i,
                ": ", results[i].score, ">", results[i + 1].score, ")"
            )
            return
    print("ok")


def test_sort_tiebreak_by_index() raises:
    """1C.2 Equal scores tiebreak by original collection index ascending.

    Insert multiple identical strings; all score 0.0. They must come
    out in original-index order.
    """
    print("test_sort_tiebreak_by_index ... ", end="")
    var collection: List[String] = [
        "apple",
        "banana",
        "apple",
        "cherry",
        "apple",
    ]
    var fuse = Fuse(collection^, threshold=0.3, ignore_location=True)
    var results = fuse.search("apple")
    # Three "apple" matches expected, at indices 0, 2, 4 in that order.
    var apple_indices = List[Int]()
    for i in range(len(results)):
        if results[i].item == "apple":
            apple_indices.append(results[i].index)
    if len(apple_indices) != 3:
        print("FAIL (expected 3 apple matches, got", len(apple_indices), ")")
        return
    if apple_indices[0] != 0 or apple_indices[1] != 2 or apple_indices[2] != 4:
        print(
            "FAIL (tiebreak order wrong:",
            apple_indices[0], apple_indices[1], apple_indices[2], ")"
        )
        return
    print("ok")


def test_sort_large_collection_is_fast():
    """1C.3 SKIP — perf regression test for O(n log n) sort.

    SPEC:
      With ≥10K results in the output, sort completes in "reasonable
      time" (target: <100ms on a modest machine). The current O(n²)
      selection sort grows quadratically and becomes untenable on
      large result sets.

    IMPLEMENTATION:
      Replace the selection sort loop in fuse.mojo:143-150 with a
      proper O(n log n) algorithm (Mojo's stdlib sort when available,
      or a hand-written merge sort / TimSort).

      Must remain stable to preserve the tiebreak-by-index behavior
      verified in test_sort_tiebreak_by_index.
    """
    print("test_sort_large_collection_is_fast ... SKIP (perf harness TBD)")


def test_custom_sort_fn():
    """1C.4 SKIP — Fuse.js exposes a `sortFn` option; FuseMojo does not.

    SPEC:
      `Fuse(collection, sort_fn=my_comparator)` uses `my_comparator`
      to sort results instead of the default (score asc, index asc).

      The comparator signature mirrors a standard `cmp(a, b) -> Int`
      returning negative / zero / positive, called with
      `(FuseResult, FuseResult)`.

      Setting `should_sort=False` still bypasses sorting entirely
      (higher priority than `sort_fn`).
    """
    print("test_custom_sort_fn ... SKIP (no `sort_fn` kwarg)")


# ═══════════════════════════════════════════════════════════════════
# Part 1D: Pattern chunking for patterns > MAX_BITS  (MISSING FEATURE)
# ═══════════════════════════════════════════════════════════════════
# bitap.mojo:216 silently returns (is_match=False, score=1.0) for
# pattern_len > MAX_BITS. Fuse.js splits long patterns into chunks
# of exactly MAX_BITS and averages chunk scores.


def test_pattern_65_exact_match() raises:
    """1D.1 A 65-char exact substring should be findable.

    Currently bitap_search returns no match for any pattern > 64
    chars. After chunking, an exact 65-char substring must be found
    with near-zero score.
    """
    print("test_pattern_65_exact_match ... ", end="")
    # 65 'a's (codepoint 97), embedded in a longer text of x/a/y.
    var pat_cps = List[Int]()
    for _ in range(65):
        pat_cps.append(97)  # 'a'
    var text_cps = List[Int]()
    for _ in range(3):
        text_cps.append(120)  # 'x'
    for _ in range(65):
        text_cps.append(97)  # 'a' * 65
    for _ in range(3):
        text_cps.append(121)  # 'y'
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True, threshold=0.1
    )
    if not result.is_match:
        print(
            "FAIL (65-char exact substring not matched — chunking missing)"
        )
        return
    if result.score > 0.01:
        print("FAIL (score too high:", result.score, ")")
        return
    print("ok")


def test_pattern_100_one_error() raises:
    """1D.2 100-char pattern with a single-character typo.

    Spread across 2+ chunks. Expected score: the chunk containing
    the error has score ~ (1 / chunk_len); clean chunks score 0;
    average is small.
    """
    print("test_pattern_100_one_error ... ", end="")
    # Construct a 100-char pattern cycling through a-z0-9 (36 chars).
    var alphabet = List[Int]()
    for c in range(97, 123):  # a..z
        alphabet.append(c)
    for c in range(48, 58):  # 0..9
        alphabet.append(c)
    var pat_cps = List[Int]()
    for i in range(100):
        pat_cps.append(alphabet[i % 36])
    # Text = pattern with one substitution at position 50 ('Z'=90).
    var text_cps = List[Int]()
    for i in range(100):
        if i == 50:
            text_cps.append(90)  # 'Z' instead of pattern's char
        else:
            text_cps.append(pat_cps[i])
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True, threshold=0.5
    )
    if not result.is_match:
        print(
            "FAIL (100-char pattern with one typo not matched — chunking missing)"
        )
        return
    print("ok (score:", result.score, ")")


def test_pattern_chunk_score_averaging():
    """1D.3 SKIP — verify averaged score matches (sum of chunk scores)/N.

    SPEC (Fuse.js chunking):
      Given pattern length L > MAX_BITS:
        i = 0
        remainder = L % MAX_BITS
        end = L - remainder
        while i < end:
          addChunk(pattern[i : i+MAX_BITS], startIndex=i)
          i += MAX_BITS
        if remainder:
          addChunk(pattern[L-MAX_BITS :], startIndex=L-MAX_BITS)
          # ^ final chunk overlaps the previous chunk

      Final score = mean of per-chunk scores.
      Final indices = mergeIndices(chunk_indices_by_start).

    TESTS to add once chunking exists:
      - 128-char pattern (exactly 2 non-overlapping chunks):
        both chunks must be searched; final score is their mean.
      - 129-char pattern (2 full + 1 overlapping tail):
        the overlapping final chunk must still contribute.
      - Indices from each chunk merge into contiguous ranges.
    """
    print("test_pattern_chunk_score_averaging ... SKIP (no chunking)")


# ═══════════════════════════════════════════════════════════════════
# Part 1E: Extended search operators  (MISSING FEATURE)
# ═══════════════════════════════════════════════════════════════════
# 8 matchers, parsed left-to-right. `|` = OR, whitespace = AND.
#
#   | Syntax   | Name            | Behavior                            |
#   | =term    | exact           | text == pattern, 0 or 1             |
#   | 'term    | include         | substring match, 0 or 1             |
#   | ^term    | prefix-exact    | startswith, 0 or 1                  |
#   | !^term   | inverse-prefix  | !startswith, 0 or 1                 |
#   | term$    | suffix-exact    | endswith, 0 or 1                    |
#   | !term$   | inverse-suffix  | !endswith, 0 or 1                   |
#   | !term    | inverse-exact   | pattern not in text, 0 or 1         |
#   | term     | fuzzy           | BitapSearch, variable score         |


def test_extended_operator_exact():
    """1E.1 SKIP — `=term` matches iff text == term."""
    print("test_extended_operator_exact ... SKIP (no extended search parser)")


def test_extended_operator_include():
    """1E.2 SKIP — `'term` matches iff term in text."""
    print("test_extended_operator_include ... SKIP (no extended search parser)")


def test_extended_operator_prefix_suffix():
    """1E.3 SKIP — `^term` / `term$` and their `!` negations."""
    print("test_extended_operator_prefix_suffix ... SKIP (no extended search parser)")


def test_extended_operator_fuzzy_fallback():
    """1E.4 SKIP — bare `term` falls through to BitapSearcher."""
    print("test_extended_operator_fuzzy_fallback ... SKIP (no extended search parser)")


def test_extended_and_combination():
    """1E.5 SKIP — whitespace-separated tokens ANDed together.

    SPEC:
      `^The world$` matches 'The brave new world' — starts with 'The'
      AND ends with 'world'. All whitespace-separated tokens within
      an OR group must match.
    """
    print("test_extended_and_combination ... SKIP (no extended search parser)")


def test_extended_or_combination():
    """1E.6 SKIP — `|` splits into OR groups.

    SPEC:
      `cat | dog` matches any string containing either 'cat' or 'dog'
      (fuzzy, since bare terms fall through to Bitap).

      Mixed: `^The !evil | ^A good$` — match strings that start with
      'The' AND don't contain 'evil', OR strings that start with 'A'
      AND end with 'good'.
    """
    print("test_extended_or_combination ... SKIP (no extended search parser)")


def test_extended_quoted_tokens():
    """1E.7 SKIP — `="hello world"` treats inner whitespace as literal.

    SPEC:
      Quoted strings inside extended queries are preserved as a single
      token. `="hello world"` tests exact equality to the two-word
      string 'hello world', not the AND of =hello and =world.
    """
    print("test_extended_quoted_tokens ... SKIP (no extended search parser)")


def test_extended_inverse_switches_key_semantics():
    """1E.8 SKIP — inverse operators flip multi-key semantics.

    SPEC (Fuse.js):
      Normally, multi-key search returns a hit if ANY key matches.
      When the query contains an inverse operator (!term / !^term /
      !term$), semantics flip to ALL keys must match — because an
      inverse should not be satisfied by merely failing one key while
      another satisfies it.
    """
    print("test_extended_inverse_switches_key_semantics ... SKIP (no extended search parser)")


# ═══════════════════════════════════════════════════════════════════
# Part 1F: Multi-key search with weights  (MISSING FEATURE)
# ═══════════════════════════════════════════════════════════════════


def test_multikey_two_keys_weighted():
    """1F.1 SKIP — keys=[('title', 2.0), ('author', 1.0)].

    SPEC — scoring (multiplicative):
        total = 1.0
        for (key, norm, score) in matches:
            weight = key.weight if key else 1
            base = EPSILON if (score == 0 and weight) else score
            total *= base ** (weight * norm)

    Key weights are normalized to sum to 1 before scoring.

    TEST: for an item where both title and author match the query,
    but title weight is 2x, ranking must prefer the title-dominant
    score over the author-dominant one.
    """
    print("test_multikey_two_keys_weighted ... SKIP (no multi-key API)")


def test_multikey_equal_weights():
    """1F.2 SKIP — equal weights: all keys contribute equally."""
    print("test_multikey_equal_weights ... SKIP (no multi-key API)")


def test_multikey_zero_weight_raises():
    """1F.3 SKIP — weight=0 must raise (Fuse.js rejects)."""
    print("test_multikey_zero_weight_raises ... SKIP (no multi-key API)")


def test_multikey_field_length_norm():
    """1F.4 SKIP — matches in shorter fields score better.

    SPEC — field-length norm:
        norm = round(1000 / sqrt(num_tokens) ** field_norm_weight) / 1000
      where num_tokens is word count in the field value.

    TEST: same query word matched in a 3-word title vs a 30-word
    abstract — the 3-word match must rank higher.
    """
    print("test_multikey_field_length_norm ... SKIP (no multi-key API)")


def test_multikey_ignore_field_norm():
    """1F.5 SKIP — `ignore_field_norm=True` disables the length-weighting."""
    print("test_multikey_ignore_field_norm ... SKIP (no multi-key API)")


def test_multikey_scoring_is_multiplicative():
    """1F.6 SKIP — total score is a PRODUCT of per-key powers, not a sum.

    SPEC:
      If any key scores exactly 0 it would collapse the product; Fuse.js
      substitutes EPSILON. Verify zero-key behavior matches that, and
      verify overall ordering is product-of-powers, not sum-of-weighted.
    """
    print("test_multikey_scoring_is_multiplicative ... SKIP (no multi-key API)")


# ═══════════════════════════════════════════════════════════════════
# Part 1G: Searcher dispatch  (ARCHITECTURAL)
# ═══════════════════════════════════════════════════════════════════


def test_searcher_trait_exists():
    """1G.1 SKIP — `Searcher` trait enables pluggable search strategies.

    SPEC:
        trait Searcher(Movable):
            def search_in(self, text: String) raises -> SearchResult

      BitapSearcher already fits this shape. Fuse.search should
      accept any `Searcher`, not hardcode `BitapSearcher`. This
      enables:
        - ExtendedSearch as a searcher (Part 1E)
        - TokenSearch as a searcher
        - N-gram searcher from the extension library (Part 2)

    TEST ONCE IT EXISTS:
      - Define a trivial FakeSearcher that returns a fixed result.
      - Pass it to Fuse and verify Fuse.search delegates to it.
      - Verify BitapSearcher still works as a drop-in (regression).
    """
    print("test_searcher_trait_exists ... SKIP (trait not yet defined)")


# ═══════════════════════════════════════════════════════════════════
# Part 1H: String copy avoidance  (BUG / ARCHITECTURAL)
# ═══════════════════════════════════════════════════════════════════
# fuse.mojo:135 does String(self.collection[idx]) — heap alloc per match.


def test_index_is_sufficient_to_retrieve_item() raises:
    """1H.1 `.index` uniquely identifies the item in the collection.

    This verifies the invariant that would let us drop the `.item`
    String copy from FuseResult. It passes today; the architectural
    change (remove `.item`) is a separate SKIP.
    """
    print("test_index_is_sufficient_to_retrieve_item ... ", end="")
    var collection: List[String] = [
        "alpha", "beta", "gamma", "delta", "epsilon"
    ]
    # Keep a parallel copy for post-search assertion (Fuse takes ownership).
    var reference: List[String] = [
        "alpha", "beta", "gamma", "delta", "epsilon"
    ]
    var fuse = Fuse(collection^, threshold=0.5, ignore_location=True)
    var results = fuse.search("alpha")
    if len(results) == 0:
        print("FAIL (expected at least one match)")
        return
    for i in range(len(results)):
        var idx = results[i].index
        if idx < 0 or idx >= len(reference):
            print("FAIL (index out of range:", idx, ")")
            return
        if results[i].item != reference[idx]:
            print("FAIL (item does not match collection[index] at", idx, ")")
            return
    print("ok")


def test_fuse_result_drops_item_field():
    """1H.2 SKIP — architectural: FuseResult.item can be removed.

    SPEC:
      Once callers uniformly use `.index` to retrieve items from
      their own collection reference, FuseResult.item becomes
      redundant. Removing it avoids a String heap-alloc + memcpy
      per match — significant on large result sets.

      The breaking API change belongs in a separate issue and PR.
      Test gates the change: after removal, benchmarks should show
      no per-match allocation from the result builder.
    """
    print("test_fuse_result_drops_item_field ... SKIP (API change pending)")


# ═══════════════════════════════════════════════════════════════════
# Runner
# ═══════════════════════════════════════════════════════════════════


def main() raises:
    print("FuseMojo: Port-Gap Test Suite")
    print("=" * 48)

    print()
    print("Part 1A: Unicode case folding (bug)")
    print("-" * 48)
    test_fold_latin_extended()
    test_fold_greek()
    test_fold_cyrillic()
    test_fold_sharp_s_idempotent()
    test_case_insensitive_accented_match()
    test_case_insensitive_cyrillic_match()

    print()
    print("Part 1B: Result limiting with MaxHeap (missing)")
    print("-" * 48)
    test_fuse_limit_top_n()
    test_fuse_limit_selects_best()

    print()
    print("Part 1C: Sort correctness / custom sort_fn")
    print("-" * 48)
    test_sort_primary_by_score()
    test_sort_tiebreak_by_index()
    test_sort_large_collection_is_fast()
    test_custom_sort_fn()

    print()
    print("Part 1D: Pattern chunking for > MAX_BITS (missing)")
    print("-" * 48)
    test_pattern_65_exact_match()
    test_pattern_100_one_error()
    test_pattern_chunk_score_averaging()

    print()
    print("Part 1E: Extended search operators (missing)")
    print("-" * 48)
    test_extended_operator_exact()
    test_extended_operator_include()
    test_extended_operator_prefix_suffix()
    test_extended_operator_fuzzy_fallback()
    test_extended_and_combination()
    test_extended_or_combination()
    test_extended_quoted_tokens()
    test_extended_inverse_switches_key_semantics()

    print()
    print("Part 1F: Multi-key search with weights (missing)")
    print("-" * 48)
    test_multikey_two_keys_weighted()
    test_multikey_equal_weights()
    test_multikey_zero_weight_raises()
    test_multikey_field_length_norm()
    test_multikey_ignore_field_norm()
    test_multikey_scoring_is_multiplicative()

    print()
    print("Part 1G: Searcher trait dispatch (architectural)")
    print("-" * 48)
    test_searcher_trait_exists()

    print()
    print("Part 1H: String copy avoidance (bug / architectural)")
    print("-" * 48)
    test_index_is_sufficient_to_retrieve_item()
    test_fuse_result_drops_item_field()

    print("=" * 48)
    print("Port-gap tests complete.")
