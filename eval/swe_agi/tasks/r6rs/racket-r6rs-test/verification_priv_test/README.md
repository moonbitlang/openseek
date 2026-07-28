# R6RS Test Verification Results

This directory contains MoonBit test cases migrated from the Racket R6RS test suite, along with a verification script to validate the expected outputs against Racket's R6RS implementation.

## Files

- `r6rs_*_test.mbt` - MoonBit test files covering various R6RS modules
- `verify-r6rs-tests.rkt` - Racket script to verify expected outputs

## Running Verification

```bash
# Run all tests
racket verify-r6rs-tests.rkt

# Show only failures
racket verify-r6rs-tests.rkt --only-failures

# Verbose output (show all results)
racket verify-r6rs-tests.rkt --verbose

# Filter by test name pattern
racket verify-r6rs-tests.rkt --filter "unicode"
```

## Verification Results

**Pass Rate: 98.9%** (1335/1350 tests)

| Status | Count | Percentage |
|--------|-------|------------|
| Passed | 1335 | 98.9% |
| Failed | 3 | 0.2% |
| Errors | 1 | 0.1% |
| Skipped | 11 | 0.8% |

## Known Failures

### 1. `r6rs_exceptions/3` - Behavioral Difference

**Expected:** `(out in out in)`
**Actual:** `(out in)`

This is a known difference between Racket's R6RS implementation and the R6RS specification. The test involves `guard` and `dynamic-wind` interaction where the spec expects the dynamic-wind thunks to be called twice (when re-entering and re-exiting during guard handling), but Racket only calls them once.

### 2. `r6rs_mutable_strings/2` - Racket Limitation

**Error:** `string-set!: contract violation - expected: mutable-string?`

Racket's R6RS implementation uses immutable strings by default. The test requires `string-set!` which only works on mutable strings created with `(string-copy)` or similar.

### 3. `r6rs_syntax_case/6` and `r6rs_syntax_case/7` - Preprocessing Limitation

**Expected:** `(1 #f "s" #vu8(9) #(5 7))`
**Actual:** `(1 #f "s" (bytes 9) #(5 7))`

The verification script uses regex-based preprocessing to convert R6RS `#vu8(...)` bytevector syntax to Racket's `(bytes ...)`. When bytevectors appear inside quoted lists (as in syntax-case tests), the preprocessing converts them to symbols instead of actual bytevector values.

## Skipped Tests

11 tests are skipped because they test "unspecified behavior" - cases where the R6RS spec doesn't mandate a specific return value (e.g., `when` with false condition, `unless` with true condition).

## Test Categories

The migrated suite covers arithmetic, base language forms, bytevectors,
conditions, control flow, enums, evaluation, exceptions, hashtables, I/O,
lists, mutable data, programs, R5RS compatibility, reader syntax, records,
sorting, syntax-case, and Unicode.

## Original Test Source

These tests were migrated from the [Racket R6RS test suite](https://github.com/racket/r6rs)
