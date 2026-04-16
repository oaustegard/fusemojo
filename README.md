# FuseMojo

Lightweight fuzzy search in [Mojo](https://www.modular.com/mojo) -- a port of the [Fuse.js](https://github.com/krisk/Fuse) bitap algorithm to Mojo for native-speed approximate string matching.

## Why Mojo?

The bitap algorithm is *bit-parallel computation* -- its core innovation is encoding NFA state transitions into bitwise operations on machine words. Mojo exposes hardware-level bit manipulation with Python ergonomics, making it a natural fit:

- **UInt64 bitmasks** support patterns up to 64 characters (vs 32 in Fuse.js, limited by JavaScript's 32-bit bitwise ops)
- **No chunking overhead** for typical search queries
- **Zero dependencies**, compiles to native code
- **Familiar API** modeled after Fuse.js

## Quick Start

```mojo
from fusemojo import Fuse

def main() raises:
    var books: List[String] = [
        "The Great Gatsby",
        "The Grapes of Wrath",
        "To Kill a Mockingbird",
        "1984",
        "Brave New World",
    ]

    var fuse = Fuse(books^, threshold=0.4, ignore_location=True)

    # Handles typos gracefully
    var results = fuse.search("graet gatby")
    for i in range(len(results)):
        print(results[i].item, "(score:", results[i].score, ")")
    # Output: The Great Gatsby (score: 0.001)
```

## Running

Requires Mojo 26.2+. Run from the project root:

```bash
# Run tests
mojo -I . test/test_fusemojo.mojo

# Run example
mojo -I . examples/basic.mojo

# Build binary (for benchmarking)
mojo build -I . examples/basic.mojo -o basic && ./basic
```

## API

### `Fuse` -- search a string collection

```mojo
var fuse = Fuse(
    collection,              # List[String] -- takes ownership
    threshold=0.6,           # 0.0 = exact only, 1.0 = match anything
    distance=100,            # How far from `location` a match can be
    location=0,              # Expected position of the pattern
    ignore_location=False,   # If True, score = accuracy only (ignore position)
    case_sensitive=False,     # Case-insensitive by default
    include_matches=False,   # Return character-level match ranges
    find_all_matches=False,  # Continue past first good match
    min_match_char_length=1, # Minimum contiguous match to report
    should_sort=True,        # Sort results by score (best first)
)

var results = fuse.search("query")  # -> List[FuseResult]
# results[i].item   -- matched string
# results[i].index  -- index in original collection
# results[i].score  -- 0.0 (perfect) to 1.0 (worst)
```

### `BitapSearcher` -- search individual strings

```mojo
from fusemojo.bitap import BitapSearcher

var searcher = BitapSearcher("pattern", threshold=0.4, ignore_location=True)
var result = searcher.search_in("text to search")
# result.is_match  -- Bool
# result.score     -- Float64
# result.indices   -- List[MatchRange] (if include_matches=True)
```

### `bitap_search` -- low-level function

```mojo
from fusemojo.bitap import bitap_search, create_pattern_alphabet, string_to_codepoints

var text_cps = string_to_codepoints("hello world")
var pat_cps = string_to_codepoints("helo")
var alpha = create_pattern_alphabet(pat_cps)
var result = bitap_search(text_cps, pat_cps, alpha, threshold=0.5, ignore_location=True)
```

## How It Works

The [bitap algorithm](https://en.wikipedia.org/wiki/Bitap_algorithm) (Baeza-Yates-Gonnet, 1992) uses a bit-parallel simulation of a non-deterministic finite automaton to find approximate matches:

1. **Precompute** a bitmask for each character in the pattern
2. **For each error level** (0 errors, 1 error, ...):
   - Binary-search for the furthest text position that could score within threshold
   - Slide a bit array across the text using bitwise OR/AND/SHIFT
   - Track the best match location and score
3. **Score** = accuracy (errors/length) + proximity (distance from expected location)

The bit-parallel approach processes all pattern positions simultaneously in a single machine word operation, making it extremely fast for short patterns.

## Scoring

Lower scores are better:

| Score | Meaning |
|-------|---------|
| 0.0   | Exact match at expected location |
| 0.001 | Exact match (clamped minimum) |
| 0.1-0.3 | Good fuzzy match (1-2 typos) |
| 0.4-0.6 | Moderate match |
| 1.0 | No match |

The score formula: `accuracy + proximity / distance`
- **accuracy** = errors / pattern_length
- **proximity** = |actual_position - expected_position|
- **distance** = distance parameter (default 100)

Set `ignore_location=True` to score purely on accuracy (useful for searching short strings where position doesn't matter).

## Project Structure

```
fusemojo/
  __init__.mojo   -- Package exports
  bitap.mojo      -- Core bitap algorithm, scoring, BitapSearcher
  fuse.mojo       -- Fuse struct for collection search
test/
  test_fusemojo.mojo
examples/
  basic.mojo
```

## Lineage

This is a faithful port of the bitap engine from [Fuse.js](https://github.com/krisk/Fuse) by Kiro Risk. The algorithm itself is from:

> R. Baeza-Yates and G. Gonnet, "A New Approach to Text Searching," *Communications of the ACM*, 35(10):74-82, 1992.

## License

MIT
