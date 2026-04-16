"""FuseMojo Performance Benchmark

Measures search latency, throughput, and scaling using public-domain
literature from Project Gutenberg:

  - Complete Shakespeare   (~196 000 lines,  5.7 MB)
  - War and Peace          ( ~65 000 lines,  3.3 MB)
  - Moby Dick              ( ~22 000 lines,  1.3 MB)
  - Pride and Prejudice    ( ~14 500 lines,  725 KB)
  - Alice in Wonderland    (  ~3 400 lines,  170 KB)
  - Combined mega-corpus   (~301 000 lines, ~11  MB)

Usage:
    mojo run -I . test/bench_fusemojo.mojo
"""

from std.time import perf_counter_ns as _perf_counter_ns


def tns() -> Int:
    """Return current time in nanoseconds as Int."""
    return Int(_perf_counter_ns())
from fusemojo import Fuse
from fusemojo.bitap import (
    BitapSearcher,
    bitap_search,
    create_pattern_alphabet,
    string_to_codepoints,
)


# ── Helpers ────────────────────────────────────────────────────────


def load_lines(path: String) raises -> List[String]:
    """Load non-empty lines from a text file."""
    var content: String
    with open(path, "r") as f:
        content = f.read()
    var raw = content.split("\n")
    var lines = List[String]()
    for i in range(len(raw)):
        if len(raw[i]) > 1:
            lines.append(String(raw[i]))
    return lines^


def print_corpus(name: String, lines: List[String]):
    """Print corpus stats."""
    var total = 0
    var longest = 0
    for i in range(len(lines)):
        var n = len(lines[i])
        total += n
        if n > longest:
            longest = n
    print(
        "  ", name,
        "  lines=", len(lines),
        "  chars=", total,
        "  longest=", longest,
    )


def bench_fuse(
    label: String,
    var collection: List[String],
    query: String,
    threshold: Float64,
    distance: Int,
    ignore_location: Bool,
    iterations: Int,
) raises:
    """Benchmark a single Fuse.search configuration."""
    var fuse = Fuse(
        collection^,
        threshold=threshold,
        distance=distance,
        ignore_location=ignore_location,
    )
    # Warm-up
    _ = fuse.search(query)

    var total_ns: Int = 0
    var min_ns: Int = 9_999_999_999_999
    var result_count = 0
    for _ in range(iterations):
        var t0 = tns()
        var results = fuse.search(query)
        var elapsed = tns() - t0
        total_ns += elapsed
        if elapsed < min_ns:
            min_ns = elapsed
        result_count = len(results)
    var avg_us = total_ns // iterations // 1000
    var min_us = min_ns // 1000
    print(
        "  ", label,
        " → ", result_count, " hits",
        "  avg ", avg_us, " µs",
        "  best ", min_us, " µs",
    )


# ── Main ───────────────────────────────────────────────────────────


def main() raises:
    print("FuseMojo Performance Benchmark")
    print("=" * 70)

    # ── Load all corpora ───────────────────────────────────────────

    print("Loading corpora...")
    var t_load = tns()
    var shakespeare = load_lines("test/data/complete_shakespeare.txt")
    var war_peace = load_lines("test/data/war_and_peace.txt")
    var moby = load_lines("test/data/moby_dick.txt")
    var pride = load_lines("test/data/pride_and_prejudice.txt")
    var alice = load_lines("test/data/alice_in_wonderland.txt")
    var load_ms = (tns() - t_load) // 1_000_000
    print("Loaded in ", load_ms, " ms")
    print()

    print_corpus("Shakespeare        ", shakespeare)
    print_corpus("War and Peace      ", war_peace)
    print_corpus("Moby Dick          ", moby)
    print_corpus("Pride & Prejudice  ", pride)
    print_corpus("Alice in Wonderland", alice)

    # Build mega-corpus
    var mega = List[String]()
    for i in range(len(shakespeare)):
        mega.append(shakespeare[i])
    for i in range(len(war_peace)):
        mega.append(war_peace[i])
    for i in range(len(moby)):
        mega.append(moby[i])
    for i in range(len(pride)):
        mega.append(pride[i])
    for i in range(len(alice)):
        mega.append(alice[i])
    print_corpus("MEGA (all combined)", mega)
    print()

    # ════════════════════════════════════════════════════════════════
    # 1.  Core bitap_search — single-line micro-benchmark
    # ════════════════════════════════════════════════════════════════

    print("1. Core bitap_search  (single-line, 10 000 iterations)")
    print("-" * 70)

    var sample = pride[700]
    var sample_cps = string_to_codepoints(sample)
    print("  text (", len(sample_cps), " cps): ", sample)
    print()

    var bitap_pats = List[String]()
    bitap_pats.append("truth")
    bitap_pats.append("trtuh")
    bitap_pats.append("acknowledged")
    bitap_pats.append("acknowledgd")
    bitap_pats.append("xyzxyz")

    var iters_bitap = 10000
    for pi in range(len(bitap_pats)):
        var pat = String(bitap_pats[pi])
        var pat_cps = string_to_codepoints(pat)
        var alpha = create_pattern_alphabet(pat_cps)
        var matched = False
        var best_score: Float64 = 1.0
        var t0 = tns()
        for _ in range(iters_bitap):
            var r = bitap_search(
                sample_cps, pat_cps, alpha,
                ignore_location=True, threshold=0.4,
            )
            matched = r.is_match
            best_score = r.score
        var elapsed = tns() - t0
        var avg_ns = elapsed // iters_bitap
        print(
            "  \"", pat, "\"",
            "  match=", matched,
            "  score=", best_score,
            "  avg ", avg_ns, " ns",
        )
    print()

    # ════════════════════════════════════════════════════════════════
    # 2.  Fuse search — individual corpora (varied queries)
    # ════════════════════════════════════════════════════════════════

    print("2. Fuse Search — Pride & Prejudice  (",
          len(pride), " lines, 5 iters)")
    print("-" * 70)

    bench_fuse("Elizabeth (exact)",
        pride.copy(), "Elizabeth", 0.4, 100, True, 5)
    bench_fuse("Darcy     (exact)",
        pride.copy(), "Darcy", 0.4, 100, True, 5)
    bench_fuse("Elizbeth  (typo) ",
        pride.copy(), "Elizbeth", 0.4, 100, True, 5)
    bench_fuse("Dracy     (swap) ",
        pride.copy(), "Dracy", 0.4, 100, True, 5)
    bench_fuse("universally ack..",
        pride.copy(), "universally acknowledged", 0.4, 100, True, 5)
    bench_fuse("xyzxyzxyz (none) ",
        pride.copy(), "xyzxyzxyz", 0.4, 100, True, 5)
    print()

    print("   Fuse Search — Complete Shakespeare  (",
          len(shakespeare), " lines, 3 iters)")
    print("-" * 70)

    bench_fuse("Hamlet   (exact) ",
        shakespeare.copy(), "Hamlet", 0.4, 100, True, 3)
    bench_fuse("Hmalet   (typo)  ",
        shakespeare.copy(), "Hmalet", 0.4, 100, True, 3)
    bench_fuse("Romeo    (exact) ",
        shakespeare.copy(), "Romeo", 0.4, 100, True, 3)
    bench_fuse("to be or not     ",
        shakespeare.copy(), "to be or not to be", 0.4, 100, True, 3)
    bench_fuse("xyzxyzxyz (none) ",
        shakespeare.copy(), "xyzxyzxyz", 0.4, 100, True, 3)
    print()

    print("   Fuse Search — War and Peace  (",
          len(war_peace), " lines, 3 iters)")
    print("-" * 70)

    bench_fuse("Natasha  (exact) ",
        war_peace.copy(), "Natasha", 0.4, 100, True, 3)
    bench_fuse("Napoleon (exact) ",
        war_peace.copy(), "Napoleon", 0.4, 100, True, 3)
    bench_fuse("Napleon  (typo)  ",
        war_peace.copy(), "Napleon", 0.4, 100, True, 3)
    bench_fuse("Prince Andrei    ",
        war_peace.copy(), "Prince Andrei", 0.4, 100, True, 3)
    print()

    print("   Fuse Search — Moby Dick  (",
          len(moby), " lines, 5 iters)")
    print("-" * 70)

    bench_fuse("whale    (exact) ",
        moby.copy(), "whale", 0.4, 100, True, 5)
    bench_fuse("Ahab     (exact) ",
        moby.copy(), "Ahab", 0.4, 100, True, 5)
    bench_fuse("Queeqeug (typo)  ",
        moby.copy(), "Queeqeug", 0.4, 100, True, 5)
    bench_fuse("white whale      ",
        moby.copy(), "white whale", 0.4, 100, True, 5)
    print()

    # ════════════════════════════════════════════════════════════════
    # 3.  MEGA corpus — 300K lines
    # ════════════════════════════════════════════════════════════════

    print("3. MEGA Corpus  (", len(mega), " lines, 3 iters)")
    print("-" * 70)

    bench_fuse("Elizabeth        ",
        mega.copy(), "Elizabeth", 0.4, 100, True, 3)
    bench_fuse("Hamlet           ",
        mega.copy(), "Hamlet", 0.4, 100, True, 3)
    bench_fuse("whale            ",
        mega.copy(), "whale", 0.4, 100, True, 3)
    bench_fuse("Elizbeth (typo)  ",
        mega.copy(), "Elizbeth", 0.4, 100, True, 3)
    bench_fuse("acknowledged     ",
        mega.copy(), "acknowledged", 0.4, 100, True, 3)
    bench_fuse("xyzxyzxyz (none) ",
        mega.copy(), "xyzxyzxyz", 0.4, 100, True, 3)
    bench_fuse("the (3-char)     ",
        mega.copy(), "the", 0.4, 100, True, 3)
    var long_q = "it is a truth universally acknowledged that a single man in"
    bench_fuse("60-char phrase   ",
        mega.copy(), long_q, 0.4, 100, True, 3)
    print()

    # ════════════════════════════════════════════════════════════════
    # 4.  Scaling by collection size  (100 → 300K lines)
    # ════════════════════════════════════════════════════════════════

    print("4. Scaling  (query: \"Elizabeth\", threshold=0.4)")
    print("-" * 70)

    var sizes = List[Int]()
    sizes.append(100)
    sizes.append(500)
    sizes.append(1000)
    sizes.append(5000)
    sizes.append(10000)
    sizes.append(50000)
    sizes.append(100000)
    sizes.append(200000)
    sizes.append(len(mega))

    for si in range(len(sizes)):
        var sz = sizes[si]
        if sz > len(mega):
            sz = len(mega)
        var subset = List[String]()
        for i in range(sz):
            subset.append(mega[i])
        var label = String(sz) + " lines"
        bench_fuse(label, subset^, "Elizabeth", 0.4, 100, True, 3)
    print()

    # ════════════════════════════════════════════════════════════════
    # 5.  Threshold sweep
    # ════════════════════════════════════════════════════════════════

    print("5. Threshold Sweep  (query: \"Elizbeth\", Shakespeare)")
    print("-" * 70)

    var thresholds = List[Float64]()
    thresholds.append(0.1)
    thresholds.append(0.2)
    thresholds.append(0.3)
    thresholds.append(0.4)
    thresholds.append(0.5)
    thresholds.append(0.6)
    thresholds.append(0.8)

    for ti in range(len(thresholds)):
        var th = thresholds[ti]
        var label = "threshold=" + String(th)
        bench_fuse(label, shakespeare.copy(), "Elizbeth", th, 100, True, 3)
    print()

    # ════════════════════════════════════════════════════════════════
    # 6.  Distance sweep
    # ════════════════════════════════════════════════════════════════

    print("6. Distance Sweep  (query: \"Elizabeth\", Shakespeare, location=0)")
    print("-" * 70)

    var distances = List[Int]()
    distances.append(1)
    distances.append(10)
    distances.append(50)
    distances.append(100)
    distances.append(500)
    distances.append(1000)

    for di in range(len(distances)):
        var d = distances[di]
        var label = "distance=" + String(d)
        bench_fuse(label, shakespeare.copy(), "Elizabeth", 0.4, d, False, 3)
    print()

    # ════════════════════════════════════════════════════════════════
    # 7.  BitapSearcher reuse — scan entire mega-corpus
    # ════════════════════════════════════════════════════════════════

    print("7. BitapSearcher Scan  (all ", len(mega), " lines)")
    print("-" * 70)

    var scan_patterns = List[String]()
    scan_patterns.append("Elizabeth")
    scan_patterns.append("Hamlet")
    scan_patterns.append("whale")
    scan_patterns.append("the")
    scan_patterns.append("acknowledged")
    scan_patterns.append("xyzxyz")

    for spi in range(len(scan_patterns)):
        var pat = String(scan_patterns[spi])
        var searcher = BitapSearcher(
            pat, threshold=0.4, ignore_location=True,
        )
        var match_count = 0
        var t0 = tns()
        for i in range(len(mega)):
            var r = searcher.search_in(mega[i])
            if r.is_match:
                match_count += 1
        var elapsed_us = (tns() - t0) // 1000
        print(
            "  \"", pat, "\"",
            "  → ", match_count, "/", len(mega), " lines",
            "  total ", elapsed_us, " µs",
        )
    print()

    # ════════════════════════════════════════════════════════════════
    # 8.  Feature flags overhead  (mega-corpus)
    # ════════════════════════════════════════════════════════════════

    print("8. Feature Flags Overhead  (Shakespeare, \"Hamlet\", 3 iters)")
    print("-" * 70)

    bench_fuse("baseline              ",
        shakespeare.copy(), "Hamlet", 0.4, 100, True, 3)

    # include_matches
    var fuse_im = Fuse(
        shakespeare.copy(), threshold=0.4, ignore_location=True,
        include_matches=True,
    )
    _ = fuse_im.search("warmup")
    var im_total: Int = 0
    var im_count = 0
    for _ in range(3):
        var t0 = tns()
        var r = fuse_im.search("Hamlet")
        im_total += tns() - t0
        im_count = len(r)
    print(
        "  include_matches=True    ",
        " → ", im_count, " hits",
        "  avg ", im_total // 3 // 1000, " µs",
    )

    # find_all_matches
    var fuse_fa = Fuse(
        shakespeare.copy(), threshold=0.4, ignore_location=True,
        find_all_matches=True,
    )
    _ = fuse_fa.search("warmup")
    var fa_total: Int = 0
    var fa_count = 0
    for _ in range(3):
        var t0 = tns()
        var r = fuse_fa.search("Hamlet")
        fa_total += tns() - t0
        fa_count = len(r)
    print(
        "  find_all_matches=True   ",
        " → ", fa_count, " hits",
        "  avg ", fa_total // 3 // 1000, " µs",
    )

    # Both
    var fuse_both = Fuse(
        shakespeare.copy(), threshold=0.4, ignore_location=True,
        include_matches=True, find_all_matches=True,
    )
    _ = fuse_both.search("warmup")
    var both_total: Int = 0
    var both_count = 0
    for _ in range(3):
        var t0 = tns()
        var r = fuse_both.search("Hamlet")
        both_total += tns() - t0
        both_count = len(r)
    print(
        "  both flags              ",
        " → ", both_count, " hits",
        "  avg ", both_total // 3 // 1000, " µs",
    )
    print()

    # ════════════════════════════════════════════════════════════════
    # 9.  Pattern length sweep  (mega-corpus)
    # ════════════════════════════════════════════════════════════════

    print("9. Pattern Length  (MEGA corpus, 3 iters)")
    print("-" * 70)

    bench_fuse("3-char  \"the\"    ",
        mega.copy(), "the", 0.4, 100, True, 3)
    bench_fuse("5-char  \"whale\"  ",
        mega.copy(), "whale", 0.4, 100, True, 3)
    bench_fuse("9-char  \"Elizabeth\"",
        mega.copy(), "Elizabeth", 0.4, 100, True, 3)
    bench_fuse("13-char \"acknowledged\"",
        mega.copy(), "acknowledged", 0.4, 100, True, 3)
    bench_fuse("24-char phrase   ",
        mega.copy(), "universally acknowledged", 0.4, 100, True, 3)
    bench_fuse("60-char phrase   ",
        mega.copy(), long_q, 0.4, 100, True, 3)
    print()

    print("=" * 70)
    print("Benchmark complete.")
