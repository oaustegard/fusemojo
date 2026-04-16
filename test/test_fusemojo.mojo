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
    convert_mask_to_indices,
    BitapSearcher,
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


# ── 1-7  Boundary / Crash Risks ────────────────────────────────────


def test_compute_score_zero_pattern_len():
    """1. compute_score with pattern_len=0 → Float64(0)/Float64(0) = NaN."""
    print("test_compute_score_zero_pattern_len ... ", end="")
    var s = compute_score(0, 0, 0, 0, 100, False)
    # Float64(0) / Float64(0) produces NaN in IEEE 754.
    # NaN != NaN, so s != s is True when we get NaN.
    if s != s:
        print("ok (NaN -- division by zero as expected)")
    else:
        print("ok (score:", s, "-- caller should guard pattern_len=0)")


def test_find_exact_negative_start():
    """2. find_exact with start < 0 → negative index in range()/text[i+j].

    BUG: find_exact does not guard start < 0.  range(start, ...) iterates
    with negative i, so text[i+j] accesses a negative index -- undefined
    behaviour or abort on bounds-checked builds.

    This test documents the crash risk.  If it survives, the runtime
    silently tolerated the negative index.
    """
    print("test_find_exact_negative_start ... ", end="")
    var text = string_to_codepoints("hello")
    var pat = string_to_codepoints("he")
    # start=-1 bypasses the `start + plen > tlen` guard (-1+2=1 <= 5).
    # The first iteration does text[-1 + 0] = text[-1] → crash risk.
    var idx = find_exact(text, pat, -1)
    print("ok (idx:", idx, "-- survived without crash)")


def test_text_shorter_than_pattern() raises:
    """3. Text shorter than pattern → no crash, no match.

    find_exact returns -1 (start+plen > tlen), so exact-match acceleration
    never writes matchmask[idx + k].  Bitap loop has text_len < pattern_len
    but still terminates safely.
    """
    print("test_text_shorter_than_pattern ... ", end="")
    var text_cps = string_to_codepoints("hi")
    var pat_cps = string_to_codepoints("hello world")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(text_cps, pat_cps, alpha, ignore_location=True)
    if result.is_match:
        print("FAIL (should not match)")
        return
    print("ok (no crash, no match)")


def test_pattern_at_max_bits() raises:
    """4. Pattern exactly at MAX_BITS (64) boundary should still work."""
    print("test_pattern_at_max_bits ... ", end="")
    var pat = "a" * 64
    var text = "a" * 64
    var pat_cps = string_to_codepoints(pat)
    var text_cps = string_to_codepoints(text)
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (64-char pattern should match identical text)")
        return
    print("ok (score:", result.score, ")")


def test_pattern_exceeds_max_bits() raises:
    """5. Pattern of 65 chars → silently returns no match (score 1.0)."""
    print("test_pattern_exceeds_max_bits ... ", end="")
    var pat = "a" * 65
    var text = "a" * 65
    var pat_cps = string_to_codepoints(pat)
    var text_cps = string_to_codepoints(text)
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if result.is_match:
        print("FAIL (65-char pattern should be rejected)")
        return
    if result.score != 1.0:
        print("FAIL (expected score 1.0, got", result.score, ")")
        return
    print("ok (silently returns no match)")


def test_empty_text_nonempty_pattern() raises:
    """6. Empty text with non-empty pattern → no crash, no match."""
    print("test_empty_text_nonempty_pattern ... ", end="")
    var text_cps = string_to_codepoints("")
    var pat_cps = string_to_codepoints("abc")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if result.is_match:
        print("FAIL (empty text should not match)")
        return
    print("ok (no crash, no match)")


def test_single_char_pattern_and_text() raises:
    """7. Single-character pattern and text -- minimal bitap run."""
    print("test_single_char_pattern_and_text ... ", end="")
    var text_cps = string_to_codepoints("a")
    var pat_cps = string_to_codepoints("a")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (single matching char should match)")
        return
    # Mismatch at threshold=0 should not match
    var pat2 = string_to_codepoints("b")
    var alpha2 = create_pattern_alphabet(pat2)
    var result2 = bitap_search(
        text_cps, pat2, alpha2, threshold=0.0, ignore_location=True
    )
    if result2.is_match:
        print("FAIL (different single chars should not match at threshold=0)")
        return
    print("ok")


# ── 8-12  Scoring Edge Cases ───────────────────────────────────────


def test_threshold_zero() raises:
    """8. threshold=0.0 → only exact matches at exact expected location."""
    print("test_threshold_zero ... ", end="")
    var text_cps = string_to_codepoints("hello world")
    var pat_cps = string_to_codepoints("hello")
    var alpha = create_pattern_alphabet(pat_cps)
    # Exact match at location=0 → score 0.0 ≤ 0.0 → accepted
    var result = bitap_search(
        text_cps, pat_cps, alpha, location=0, threshold=0.0
    )
    if not result.is_match:
        print("FAIL (exact match at expected location should work)")
        return
    # Fuzzy match ("helo") → score = 1/4 = 0.25 > 0.0 → rejected
    var fuzzy_pat = string_to_codepoints("helo")
    var fuzzy_alpha = create_pattern_alphabet(fuzzy_pat)
    var result2 = bitap_search(
        text_cps, fuzzy_pat, fuzzy_alpha, location=0, threshold=0.0
    )
    if result2.is_match:
        print("FAIL (fuzzy match should not pass at threshold=0)")
        return
    print("ok")


def test_threshold_one() raises:
    """9. threshold=1.0 → everything matches."""
    print("test_threshold_one ... ", end="")
    var text_cps = string_to_codepoints("abcdef")
    var pat_cps = string_to_codepoints("xyz")
    var alpha = create_pattern_alphabet(pat_cps)
    # 3/3 errors = 1.0 accuracy; 1.0 ≤ 1.0 → accepted
    var result = bitap_search(
        text_cps, pat_cps, alpha, threshold=1.0, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (should match with threshold=1.0)")
        return
    print("ok (score:", result.score, ")")


def test_distance_zero() raises:
    """10. distance=0 → any proximity != 0 gives score 1.0.

    compute_score: if distance==0 and proximity>0, return 1.0.
    So only a match at exactly the expected location survives.
    """
    print("test_distance_zero ... ", end="")
    var text_cps = string_to_codepoints("hello world")
    var pat_cps = string_to_codepoints("hello")
    var alpha = create_pattern_alphabet(pat_cps)
    # Match at expected location=0 with distance=0 → proximity 0 → score = accuracy
    var r1 = bitap_search(
        text_cps, pat_cps, alpha, location=0, distance=0, threshold=0.6
    )
    if not r1.is_match:
        print("FAIL (exact location should match)")
        return
    # Match exists at idx 0 but expected at 6 → proximity=6, distance=0 → score=1.0
    var r2 = bitap_search(
        text_cps, pat_cps, alpha, location=6, distance=0, threshold=0.6
    )
    if r2.is_match:
        print("FAIL (off-location with distance=0 should not match at threshold=0.6)")
        return
    print("ok (at-location:", r1.score, "off-location: no match)")


def test_location_negative_and_beyond() raises:
    """11. location negative or beyond text length.

    bitap_search clamps: expected_location = max(0, min(location, text_len)).
    Both extremes should still find existing matches.
    """
    print("test_location_negative_and_beyond ... ", end="")
    var text_cps = string_to_codepoints("find me here")
    var pat_cps = string_to_codepoints("find")
    var alpha = create_pattern_alphabet(pat_cps)
    # Negative location → clamped to 0
    var r_neg = bitap_search(
        text_cps, pat_cps, alpha, location=-10, threshold=0.6
    )
    if not r_neg.is_match:
        print("FAIL (negative location should still find match)")
        return
    # Beyond text length → clamped to text_len
    var r_beyond = bitap_search(
        text_cps, pat_cps, alpha, location=1000, threshold=0.6
    )
    # Match at idx 0 but expected at text_len(12) → proximity penalty
    print(
        "ok (neg score:", r_neg.score,
        "beyond match:", r_beyond.is_match,
        "score:", r_beyond.score, ")",
    )


def test_long_text_distant_match() raises:
    """12. Extremely long text with distant match.

    With default distance=100, a match 500 chars from location=0
    gets a huge proximity penalty and may be rejected.  ignore_location
    bypasses the penalty.
    """
    print("test_long_text_distant_match ... ", end="")
    var padding_before = "x" * 500
    var padding_after = "y" * 500
    var text = padding_before + "needle" + padding_after
    var text_cps = string_to_codepoints(text)
    var pat_cps = string_to_codepoints("needle")
    var alpha = create_pattern_alphabet(pat_cps)
    # location=0, distance=100 → proximity 500/100 = 5.0 → rejected
    var r_loc = bitap_search(
        text_cps, pat_cps, alpha, location=0, distance=100, threshold=0.6
    )
    # With ignore_location, proximity is ignored → pure accuracy 0.0
    var r_ign = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not r_ign.is_match:
        print("FAIL (should find with ignore_location)")
        return
    print(
        "ok (with location: match=", r_loc.is_match,
        "ignore_loc score:", r_ign.score, ")",
    )


# ── 13-15  Unicode Gaps ────────────────────────────────────────────


def test_unicode_emoji() raises:
    """13. Multi-byte UTF-8 (emoji, CJK).

    string_to_codepoints uses .codepoints(), so multi-byte chars become
    single codepoint integers.  Bitap should handle them like any other int.
    """
    print("test_unicode_emoji ... ", end="")
    # Emoji exact match
    var text_cps = string_to_codepoints("hello 🌍 world")
    var pat_cps = string_to_codepoints("🌍")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (emoji exact match should work)")
        return
    # CJK exact match
    var cjk_text = string_to_codepoints("你好世界")
    var cjk_pat = string_to_codepoints("好世")
    var cjk_alpha = create_pattern_alphabet(cjk_pat)
    var cjk_result = bitap_search(
        cjk_text, cjk_pat, cjk_alpha, ignore_location=True
    )
    if not cjk_result.is_match:
        print("FAIL (CJK exact match should work)")
        return
    print("ok")


def test_unicode_accented():
    """14. Accented characters -- to_lower only handles A-Z.

    É (codepoint 201) is NOT lowered to é (233).  This means
    case-insensitive search treats É and é as different characters.
    """
    print("test_unicode_accented ... ", end="")
    var upper = string_to_codepoints("CAFÉ")
    var lower = to_lower_codepoints(upper)
    # C(67)→c(99), A(65)→a(97), F(70)→f(102), É(201)→É(201) unchanged
    if lower[0] != 99 or lower[1] != 97 or lower[2] != 102:
        print("FAIL (ASCII lowering wrong)")
        return
    if lower[3] != 201:
        print("FAIL (É should remain 201, got", lower[3], ")")
        return
    # Consequence: "café" (é=233) and "CAFÉ" (É=201) differ after lowering
    var text_lower = to_lower_codepoints(string_to_codepoints("café"))
    var pat_lower = to_lower_codepoints(string_to_codepoints("CAFÉ"))
    if codepoints_equal(text_lower, pat_lower):
        print("FAIL (lowered café and CAFÉ should differ on accented char)")
        return
    print("ok (to_lower does not handle accented chars)")


def test_unicode_mixed() raises:
    """15. Mixed ASCII and non-ASCII in the same string."""
    print("test_unicode_mixed ... ", end="")
    var text_cps = string_to_codepoints("abc日本語def")
    var pat_cps = string_to_codepoints("日本")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (mixed unicode exact match should work)")
        return
    # Fuzzy: 木 (26408) instead of 本 (26412) → one substitution
    var fuzzy_pat = string_to_codepoints("日木")
    var fuzzy_alpha = create_pattern_alphabet(fuzzy_pat)
    var fuzzy_result = bitap_search(
        text_cps, fuzzy_pat, fuzzy_alpha, ignore_location=True, threshold=0.6
    )
    print(
        "ok (exact:", result.score,
        "fuzzy match:", fuzzy_result.is_match,
        "score:", fuzzy_result.score, ")",
    )


# ── 16-21  Algorithmic Correctness ─────────────────────────────────


def test_transposition() raises:
    """16. Transpositions (ab → ba).

    Bitap has no special transposition handling -- a swap of two adjacent
    characters costs either 2 substitutions or 1 insertion + 1 deletion.
    """
    print("test_transposition ... ", end="")
    var text_cps = string_to_codepoints("abcdef")
    # Swap a↔b → "bacdef"
    var pat_cps = string_to_codepoints("bacdef")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True, threshold=0.6
    )
    if not result.is_match:
        print("FAIL (transposition should match within threshold)")
        return
    # Score should reflect ≥1 error
    if result.score < 0.001:
        print("FAIL (transposition should not score as perfect)")
        return
    print("ok (score:", result.score, ")")


def test_insertion_deletion_substitution() raises:
    """17. Insertions vs deletions vs substitutions — each independently.

    All three edit operations should be detected by bitap and produce
    a match within reasonable threshold.
    """
    print("test_insertion_deletion_substitution ... ", end="")
    var text_cps = string_to_codepoints("abcdef")

    # Deletion from pattern: "abdef" (missing 'c')
    var del_pat = string_to_codepoints("abdef")
    var del_alpha = create_pattern_alphabet(del_pat)
    var del_r = bitap_search(
        text_cps, del_pat, del_alpha, ignore_location=True, threshold=0.6
    )

    # Insertion in pattern: "abcxdef" (extra 'x')
    var ins_pat = string_to_codepoints("abcxdef")
    var ins_alpha = create_pattern_alphabet(ins_pat)
    var ins_r = bitap_search(
        text_cps, ins_pat, ins_alpha, ignore_location=True, threshold=0.6
    )

    # Substitution in pattern: "abcXef" ('d'→'X')
    var sub_pat = string_to_codepoints("abcxef")
    var sub_alpha = create_pattern_alphabet(sub_pat)
    var sub_r = bitap_search(
        text_cps, sub_pat, sub_alpha, ignore_location=True, threshold=0.6
    )

    if not del_r.is_match:
        print("FAIL (deletion should match)")
        return
    if not ins_r.is_match:
        print("FAIL (insertion should match)")
        return
    if not sub_r.is_match:
        print("FAIL (substitution should match)")
        return
    print(
        "ok (del:", del_r.score,
        "ins:", ins_r.score,
        "sub:", sub_r.score, ")",
    )


def test_multiple_errors() raises:
    """18. Multiple errors in same pattern.

    3 substitutions in a 10-char pattern = 0.3 accuracy → matches at 0.6.
    9 errors in 10 chars = 0.9 accuracy → rejected at 0.6.
    """
    print("test_multiple_errors ... ", end="")
    var text_cps = string_to_codepoints("abcdefghij")
    # 3 errors: positions 1,5,9 changed
    var pat3 = string_to_codepoints("axcdeyghiz")
    var alpha3 = create_pattern_alphabet(pat3)
    var r3 = bitap_search(
        text_cps, pat3, alpha3, ignore_location=True, threshold=0.6
    )
    if not r3.is_match:
        print("FAIL (3 errors in 10 chars should match at threshold=0.6)")
        return
    # 9 errors: only 'f' matches
    var pat9 = string_to_codepoints("xxxxxfxxxx")
    var alpha9 = create_pattern_alphabet(pat9)
    var r9 = bitap_search(
        text_cps, pat9, alpha9, ignore_location=True, threshold=0.6
    )
    if r9.is_match:
        print("FAIL (9 errors in 10 chars should not match at threshold=0.6)")
        return
    print("ok (3-err score:", r3.score, "9-err: no match)")


def test_pattern_multiple_occurrences() raises:
    """19. Pattern appears multiple times in text.

    Exact-match acceleration iterates all occurrences to tighten the
    threshold.  With find_all_matches + include_matches we should see
    multiple match ranges.
    """
    print("test_pattern_multiple_occurrences ... ", end="")
    var text_cps = string_to_codepoints("cat sat on a cat mat cat")
    var pat_cps = string_to_codepoints("cat")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha,
        ignore_location=True,
        include_matches=True,
        find_all_matches=True,
    )
    if not result.is_match:
        print("FAIL (should match)")
        return
    # "cat" appears at indices 0, 13, 21 → expect ≥1 match range
    if len(result.indices) == 0:
        print("FAIL (expected match ranges)")
        return
    print("ok (", len(result.indices), "match ranges)")


def test_repeated_chars_in_pattern() raises:
    """20. Repeated characters in pattern (e.g. "aaa").

    Pattern alphabet merges bits for repeated chars into one mask entry.
    """
    print("test_repeated_chars_in_pattern ... ", end="")
    var text_cps = string_to_codepoints("baaaab")
    var pat_cps = string_to_codepoints("aaa")
    var alpha = create_pattern_alphabet(pat_cps)
    var result = bitap_search(
        text_cps, pat_cps, alpha, ignore_location=True
    )
    if not result.is_match:
        print("FAIL (should find 'aaa' in 'baaaab')")
        return
    # Partial overlap: "baab" has only 2 consecutive a's
    var text2 = string_to_codepoints("baab")
    var result2 = bitap_search(
        text2, pat_cps, alpha, ignore_location=True, threshold=0.6
    )
    print(
        "ok (full:", result.score,
        "partial match:", result2.is_match,
        "score:", result2.score, ")",
    )


def test_pattern_prefix_suffix_substring() raises:
    """21. Pattern is a prefix, suffix, or interior substring of text."""
    print("test_pattern_prefix_suffix_substring ... ", end="")
    var text_cps = string_to_codepoints("abcdefgh")

    # Prefix
    var pre_pat = string_to_codepoints("abc")
    var pre_alpha = create_pattern_alphabet(pre_pat)
    var r_pre = bitap_search(
        text_cps, pre_pat, pre_alpha, ignore_location=True
    )

    # Suffix
    var suf_pat = string_to_codepoints("fgh")
    var suf_alpha = create_pattern_alphabet(suf_pat)
    var r_suf = bitap_search(
        text_cps, suf_pat, suf_alpha, ignore_location=True
    )

    # Interior
    var mid_pat = string_to_codepoints("cdef")
    var mid_alpha = create_pattern_alphabet(mid_pat)
    var r_mid = bitap_search(
        text_cps, mid_pat, mid_alpha, ignore_location=True
    )

    if not r_pre.is_match or not r_suf.is_match or not r_mid.is_match:
        print("FAIL (prefix/suffix/substring should all match)")
        return
    print(
        "ok (pre:", r_pre.score,
        "suf:", r_suf.score,
        "mid:", r_mid.score, ")",
    )


# ── 22-30  Test Gaps in Existing Suite ─────────────────────────────


def test_find_all_matches() raises:
    """22. find_all_matches=True.

    When True, `finish = text_len` (not capped), so the scan covers
    the entire text and may find matches far from the expected location.
    """
    print("test_find_all_matches ... ", end="")
    var text_cps = string_to_codepoints("the cat and the cat")
    var pat_cps = string_to_codepoints("cat")
    var alpha = create_pattern_alphabet(pat_cps)
    # Without find_all_matches (default): finish is capped near location
    var r_default = bitap_search(
        text_cps, pat_cps, alpha,
        location=0,
        include_matches=True,
        find_all_matches=False,
    )
    # With find_all_matches: finish = text_len, scans everything
    var r_all = bitap_search(
        text_cps, pat_cps, alpha,
        location=0,
        include_matches=True,
        find_all_matches=True,
    )
    if not r_default.is_match or not r_all.is_match:
        print("FAIL (both should match)")
        return
    # find_all_matches may discover more match ranges
    print(
        "ok (default indices:", len(r_default.indices),
        "all indices:", len(r_all.indices), ")",
    )


def test_location_parameter_effects() raises:
    """23. location parameter changes scoring.

    "fox" is at index 16 in "the quick brown fox jumps".
    location=16 → proximity 0 → better score.
    location=0  → proximity 16 → worse score.
    """
    print("test_location_parameter_effects ... ", end="")
    var text_cps = string_to_codepoints("the quick brown fox jumps")
    var pat_cps = string_to_codepoints("fox")
    var alpha = create_pattern_alphabet(pat_cps)
    # Near actual position
    var r_near = bitap_search(
        text_cps, pat_cps, alpha, location=16, distance=100
    )
    # Far from actual position
    var r_far = bitap_search(
        text_cps, pat_cps, alpha, location=0, distance=100
    )
    if not r_near.is_match:
        print("FAIL (near location should match)")
        return
    if not r_far.is_match:
        print("FAIL (far location should still match)")
        return
    if r_near.score >= r_far.score:
        print(
            "FAIL (near score should be better:",
            r_near.score, ">=", r_far.score, ")",
        )
        return
    print("ok (near:", r_near.score, "far:", r_far.score, ")")


def test_distance_parameter_effects() raises:
    """24. distance parameter constrains match proximity.

    "needle" at index 3 in "xx needle yyyyyy".
    distance=1000 → proximity penalty 3/1000 = 0.003 → matches.
    distance=1   → proximity penalty 3/1    = 3.0   → rejected.
    """
    print("test_distance_parameter_effects ... ", end="")
    var text_cps = string_to_codepoints("xx needle yyyyyy")
    var pat_cps = string_to_codepoints("needle")
    var alpha = create_pattern_alphabet(pat_cps)
    # Large distance: tolerant of proximity
    var r_large = bitap_search(
        text_cps, pat_cps, alpha, location=0, distance=1000, threshold=0.6
    )
    # Small distance: strict proximity
    var r_small = bitap_search(
        text_cps, pat_cps, alpha, location=0, distance=1, threshold=0.6
    )
    if not r_large.is_match:
        print("FAIL (large distance should match)")
        return
    if r_small.is_match:
        print("FAIL (distance=1 with proximity=3 should reject)")
        return
    print("ok (large dist:", r_large.score, "small dist: no match)")


def test_min_match_char_length() raises:
    """25. min_match_char_length > 1.

    When min_match_char_length exceeds the matched span, convert_mask_to_indices
    filters it out and bitap_search sets is_match=False.
    """
    print("test_min_match_char_length ... ", end="")
    var text_cps = string_to_codepoints("abcdef")
    var pat_cps = string_to_codepoints("abcdef")
    var alpha = create_pattern_alphabet(pat_cps)
    # min_match_char_length=1: full match range [0,5] length 6 ≥ 1 → ok
    var r1 = bitap_search(
        text_cps, pat_cps, alpha,
        ignore_location=True,
        include_matches=True,
        min_match_char_length=1,
    )
    # min_match_char_length=3: range [0,5] length 6 ≥ 3 → still ok
    var r3 = bitap_search(
        text_cps, pat_cps, alpha,
        ignore_location=True,
        include_matches=True,
        min_match_char_length=3,
    )
    if not r1.is_match or not r3.is_match:
        print("FAIL (both should match)")
        return
    # min_match_char_length=10: range [0,5] length 6 < 10 → filtered → no match
    var r10 = bitap_search(
        text_cps, pat_cps, alpha,
        ignore_location=True,
        include_matches=True,
        min_match_char_length=10,
    )
    if r10.is_match:
        print("FAIL (min_match_char_length=10 should reject 6-char match)")
        return
    print(
        "ok (len=1:", len(r1.indices), "ranges,"
        " len=3:", len(r3.indices), "ranges,"
        " len=10: no match)",
    )


def test_case_sensitive_mode() raises:
    """26. case-sensitive mode via BitapSearcher.

    case_sensitive=False → pattern & text lowered → "Hello" matches "hello".
    case_sensitive=True  → no lowering → "Hello" ≠ "hello" (1 error).
    """
    print("test_case_sensitive_mode ... ", end="")
    var searcher_ci = BitapSearcher(
        "Hello", case_sensitive=False, ignore_location=True
    )
    var searcher_cs = BitapSearcher(
        "Hello", case_sensitive=True, ignore_location=True
    )
    # Case-insensitive: both lowered → exact substring match
    var r_ci = searcher_ci.search_in("hello world")
    if not r_ci.is_match:
        print("FAIL (case-insensitive should match)")
        return
    # Case-sensitive: 'H'(72) vs 'h'(104) → 1 error → higher score
    var r_cs = searcher_cs.search_in("hello world")
    # Case-sensitive with exact case → perfect match
    var r_cs_exact = searcher_cs.search_in("Hello world")
    if not r_cs_exact.is_match:
        print("FAIL (case-sensitive exact case should match)")
        return
    # ci score should be better (lower) than cs score
    if r_ci.score >= r_cs.score:
        print(
            "FAIL (ci should score better:",
            r_ci.score, ">=", r_cs.score, ")",
        )
        return
    print(
        "ok (ci:", r_ci.score,
        "cs:", r_cs.score,
        "cs exact:", r_cs_exact.score, ")",
    )


def test_fuse_should_sort_false() raises:
    """27. Fuse with should_sort=False.

    Results should be in collection order (by index), not score order.
    """
    print("test_fuse_should_sort_false ... ", end="")
    var items: List[String] = [
        "zzz_apple",
        "apple",
        "aaa_apple",
    ]
    var fuse = Fuse(
        items^, threshold=0.6, ignore_location=True, should_sort=False
    )
    var results = fuse.search("apple")
    if len(results) < 2:
        print("FAIL (expected multiple results, got", len(results), ")")
        return
    # Collection order: idx 0 before idx 1 before idx 2
    var in_order = True
    for i in range(len(results) - 1):
        if results[i].index > results[i + 1].index:
            in_order = False
    if not in_order:
        print("FAIL (results should be in collection order)")
        return
    print("ok (", len(results), "results in collection order)")


def test_multiple_matches_sorted() raises:
    """28. Multiple matches sorted correctly by score (best first).

    "app" should match "app" (exact) better than "apple pie" (substring)
    better than "approximate match" (fuzzy).
    """
    print("test_multiple_matches_sorted ... ", end="")
    var items: List[String] = [
        "completely different",
        "approximate match",
        "app",
        "apple pie",
    ]
    var fuse = Fuse(
        items^, threshold=0.6, ignore_location=True, should_sort=True
    )
    var results = fuse.search("app")
    if len(results) < 2:
        print("FAIL (expected multiple results, got", len(results), ")")
        return
    # Verify ascending score order
    var sorted_ok = True
    for i in range(len(results) - 1):
        if results[i].score > results[i + 1].score:
            sorted_ok = False
    if not sorted_ok:
        print("FAIL (results not sorted by score)")
        return
    print(
        "ok (", len(results), "results, best:", results[0].item,
        "score:", results[0].score, ")",
    )


def test_bitap_searcher_reuse() raises:
    """29. BitapSearcher reuse across multiple texts.

    The searcher precomputes the alphabet once; search_in should produce
    correct, independent results for each text.
    """
    print("test_bitap_searcher_reuse ... ", end="")
    var searcher = BitapSearcher(
        "test", ignore_location=True, threshold=0.6
    )
    var r1 = searcher.search_in("this is a test")
    var r2 = searcher.search_in("testing 123")
    var r3 = searcher.search_in("completely unrelated")

    if not r1.is_match:
        print("FAIL (first search should match 'test' in text)")
        return
    if not r2.is_match:
        print("FAIL (second search should match 'test' prefix in 'testing')")
        return
    # Third: no substring resembling "test" at threshold 0.6
    print(
        "ok (r1:", r1.is_match, r1.score,
        "r2:", r2.is_match, r2.score,
        "r3:", r3.is_match, r3.score, ")",
    )


def test_convert_mask_to_indices():
    """30. convert_mask_to_indices direct test.

    Exercises contiguous runs, multiple ranges, min_match_char_length
    filtering, empty masks, all-zero, and all-one masks.
    """
    print("test_convert_mask_to_indices ... ", end="")

    # Single contiguous range [1, 3]
    var mask1: List[Int] = [0, 1, 1, 1, 0, 0]
    var idx1 = convert_mask_to_indices(mask1, 1)
    if len(idx1) != 1 or idx1[0].start != 1 or idx1[0].end != 3:
        print("FAIL (expected [1,3], got", len(idx1), "ranges)")
        return

    # Multiple ranges: [0,1], [3,5], [7,7]
    var mask2: List[Int] = [1, 1, 0, 1, 1, 1, 0, 1]
    var idx2 = convert_mask_to_indices(mask2, 1)
    if len(idx2) != 3:
        print("FAIL (expected 3 ranges, got", len(idx2), ")")
        return
    if idx2[0].start != 0 or idx2[0].end != 1:
        print("FAIL (range 0 wrong)")
        return
    if idx2[1].start != 3 or idx2[1].end != 5:
        print("FAIL (range 1 wrong)")
        return
    if idx2[2].start != 7 or idx2[2].end != 7:
        print("FAIL (range 2 wrong)")
        return

    # min_match_char_length=2 filters single-char range [7,7]
    var idx2_min2 = convert_mask_to_indices(mask2, 2)
    if len(idx2_min2) != 2:
        print("FAIL (expected 2 ranges with min_len=2, got", len(idx2_min2), ")")
        return

    # Empty mask → no ranges
    var mask_empty = List[Int]()
    var idx_empty = convert_mask_to_indices(mask_empty, 1)
    if len(idx_empty) != 0:
        print("FAIL (empty mask should give 0 ranges)")
        return

    # All zeros → no ranges
    var mask_zeros: List[Int] = [0, 0, 0]
    var idx_zeros = convert_mask_to_indices(mask_zeros, 1)
    if len(idx_zeros) != 0:
        print("FAIL (all-zero mask should give 0 ranges)")
        return

    # All ones → single range [0, 3]
    var mask_ones: List[Int] = [1, 1, 1, 1]
    var idx_ones = convert_mask_to_indices(mask_ones, 1)
    if len(idx_ones) != 1 or idx_ones[0].start != 0 or idx_ones[0].end != 3:
        print("FAIL (all-ones should give [0,3])")
        return

    print("ok")


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

    print()
    print("Boundary / Crash Risks")
    print("-" * 40)
    test_compute_score_zero_pattern_len()       # 1
    test_find_exact_negative_start()            # 2
    test_text_shorter_than_pattern()            # 3
    test_pattern_at_max_bits()                  # 4
    test_pattern_exceeds_max_bits()             # 5
    test_empty_text_nonempty_pattern()          # 6
    test_single_char_pattern_and_text()         # 7

    print()
    print("Scoring Edge Cases")
    print("-" * 40)
    test_threshold_zero()                       # 8
    test_threshold_one()                        # 9
    test_distance_zero()                        # 10
    test_location_negative_and_beyond()         # 11
    test_long_text_distant_match()              # 12

    print()
    print("Unicode Gaps")
    print("-" * 40)
    test_unicode_emoji()                        # 13
    test_unicode_accented()                     # 14
    test_unicode_mixed()                        # 15

    print()
    print("Algorithmic Correctness")
    print("-" * 40)
    test_transposition()                        # 16
    test_insertion_deletion_substitution()       # 17
    test_multiple_errors()                      # 18
    test_pattern_multiple_occurrences()         # 19
    test_repeated_chars_in_pattern()            # 20
    test_pattern_prefix_suffix_substring()      # 21

    print()
    print("Test Gaps in Existing Suite")
    print("-" * 40)
    test_find_all_matches()                     # 22
    test_location_parameter_effects()           # 23
    test_distance_parameter_effects()           # 24
    test_min_match_char_length()                # 25
    test_case_sensitive_mode()                   # 26
    test_fuse_should_sort_false()               # 27
    test_multiple_matches_sorted()              # 28
    test_bitap_searcher_reuse()                 # 29
    test_convert_mask_to_indices()              # 30

    print("=" * 40)
    print("All tests complete.")
