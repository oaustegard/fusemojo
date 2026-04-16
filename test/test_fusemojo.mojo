"""FuseMojo test suite."""

from fusemojo import Fuse, FuseResult
from fusemojo.bitap import (
    bitap_search,
    create_pattern_alphabet,
    string_to_codepoints,
    to_lower_codepoints,
    codepoints_equal,
    find_exact,
    compute_score,
    SearchResult,
    MatchRange,
)


def test_exact_match() raises:
    """Exact match should return is_match=True with near-zero score."""
    print("test_exact_match ... ", end="")
    var text_cps = string_to_codepoints("hello world")
    var pat_cps = string_to_codepoints("hello")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (not matched)")
        return
    if result.score > 0.01:
        print("FAIL (score too high:", result.score, ")")
        return
    print("ok")


def test_fuzzy_one_error() raises:
    """One-character typo should still match with a reasonable score."""
    print("test_fuzzy_one_error ... ", end="")
    var text_cps = string_to_codepoints("hello world")
    var pat_cps = string_to_codepoints("helo")  # missing 'l'
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True, threshold=0.5
    )
    if not result.is_match:
        print("FAIL (not matched)")
        return
    if result.score < 0.001 or result.score > 0.5:
        print("FAIL (score out of range:", result.score, ")")
        return
    print("ok (score:", result.score, ")")


def test_fuzzy_substitution() raises:
    """Character substitution should match."""
    print("test_fuzzy_substitution ... ", end="")
    var text_cps = string_to_codepoints("javascript")
    var pat_cps = string_to_codepoints("javscript")  # missing 'a'
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True, threshold=0.5
    )
    if not result.is_match:
        print("FAIL (not matched)")
        return
    print("ok (score:", result.score, ")")


def test_no_match() raises:
    """Completely unrelated pattern should not match at low threshold."""
    print("test_no_match ... ", end="")
    var text_cps = string_to_codepoints("hello world")
    var pat_cps = string_to_codepoints("xyz")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, threshold=0.2, ignore_location=True
    )
    if result.is_match:
        print("FAIL (should not match)")
        return
    print("ok")


def test_case_insensitive():
    """Case-insensitive codepoint lowering should work."""
    print("test_case_insensitive ... ", end="")
    var upper = string_to_codepoints("HELLO")
    var lower = to_lower_codepoints(upper)
    var expected = string_to_codepoints("hello")
    if not codepoints_equal(lower, expected):
        print("FAIL (lowering mismatch)")
        return
    print("ok")


def test_find_exact_helper():
    """Locates substring positions correctly."""
    print("test_find_exact_helper ... ", end="")
    var text = string_to_codepoints("the quick brown fox")
    var pat = string_to_codepoints("quick")
    var idx = find_exact(text, pat, 0)
    if idx != 4:
        print("FAIL (expected 4, got", idx, ")")
        return
    var pat2 = string_to_codepoints("slow")
    var idx2 = find_exact(text, pat2, 0)
    if idx2 != -1:
        print("FAIL (expected -1, got", idx2, ")")
        return
    print("ok")


def test_score_computation():
    """Score should be 0 for exact match at expected location."""
    print("test_score_computation ... ", end="")
    var s = compute_score(5, 0, 0, 0, 100, False)
    if s != 0.0:
        print("FAIL (expected 0.0, got", s, ")")
        return
    var s2 = compute_score(5, 1, 0, 0, 100, False)
    if s2 < 0.19 or s2 > 0.21:
        print("FAIL (expected ~0.2, got", s2, ")")
        return
    print("ok")


def test_fuse_search() raises:
    """Fuse struct should find fuzzy matches in a collection."""
    print("test_fuse_search ... ", end="")
    var books: List[String] = [
        "The Great Gatsby",
        "The Grapes of Wrath",
        "To Kill a Mockingbird",
        "1984",
        "Brave New World",
    ]
    var fuse = Fuse(books^, threshold=0.4, ignore_location=True)
    var results = fuse.search("great gatsby")
    if len(results) == 0:
        print("FAIL (no results)")
        return
    if results[0].index != 0:
        print("FAIL (wrong best match, index:", results[0].index, ")")
        return
    print("ok (found", len(results), "results, best:", results[0].item, ")")


def test_fuse_typo() raises:
    """Fuse should handle typos."""
    print("test_fuse_typo ... ", end="")
    var items: List[String] = [
        "apple",
        "banana",
        "grape",
        "orange",
        "pineapple",
    ]
    var fuse = Fuse(items^, threshold=0.4, ignore_location=True)
    var results = fuse.search("aple")  # typo for "apple"
    if len(results) == 0:
        print("FAIL (no results for 'aple')")
        return
    var found_apple = False
    for i in range(len(results)):
        if results[i].item == "apple":
            found_apple = True
    if not found_apple:
        print("FAIL (apple not in results)")
        return
    print("ok (found", len(results), "results)")


def test_empty_query() raises:
    """Empty query should return no results."""
    print("test_empty_query ... ", end="")
    var items: List[String] = ["hello", "world"]
    var fuse = Fuse(items^)
    var results = fuse.search("")
    if len(results) != 0:
        print("FAIL (expected 0 results, got", len(results), ")")
        return
    print("ok")


def test_match_indices() raises:
    """Include_matches should return match ranges."""
    print("test_match_indices ... ", end="")
    var text_cps = string_to_codepoints("world")
    var pat_cps = string_to_codepoints("world")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps,
        pat_cps,
        alpha,
        ignore_location=True,
        include_matches=True,
    )
    if not result.is_match:
        print("FAIL (not matched)")
        return
    if len(result.indices) == 0:
        print("FAIL (no indices returned)")
        return
    # Exact match on "world" should cover [0, 4]
    if result.indices[0].start != 0 or result.indices[0].end != 4:
        print("FAIL (expected 0-4, got", result.indices[0].start, "-", result.indices[0].end, ")")
        return
    print("ok (indices:", result.indices[0].start, "-", result.indices[0].end, ")")


def main() raises:
    print("FuseMojo Test Suite")
    print("=" * 40)

    test_exact_match()
    test_fuzzy_one_error()
    test_fuzzy_substitution()
    test_no_match()
    test_case_insensitive()
    test_find_exact_helper()
    test_score_computation()
    test_fuse_search()
    test_fuse_typo()
    test_empty_query()
    test_match_indices()

    print("=" * 40)
    print("All tests complete.")
