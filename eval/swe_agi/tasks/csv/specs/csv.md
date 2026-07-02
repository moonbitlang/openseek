# CSV (RFC 4180) — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `csv`
package. It summarizes the parts of CSV required by this repository’s API and
test suite and calls out intentional deviations/choices where the test suite is
more specific than RFC 4180.

It is **not** a verbatim copy of RFC 4180.

## Objectives (what the implementation must do)

The `csv` package expects an implementation that can:

1. Parse a CSV text document into an internal `Csv` representation.
2. Reject malformed CSV inputs with a `ParseError`.
3. Produce a stable JSON view via `Csv::to_test_json()` for snapshot checking.

## Primary references

- RFC 4180 (local copy): `specs/rfc4180.txt`
- RFC 4180 (online): https://www.rfc-editor.org/rfc/rfc4180

## Scope and explicit non-goals

### Scope

- Single CSV document → list of records → list of fields (strings).
- Quoted fields (`"..."`) with RFC-style escaped quotes (`""`).
- Embedded newlines in quoted fields.
- Line endings: LF (`\n`), CRLF (`\r\n`), and **CR (`\r`)** (extra tolerance used
  by this test suite).

### Non-goals

- No type inference (everything is a string).
- No header handling (first row is not treated specially).
- No dialect features like custom separators, trimming, or comment lines.

## API contract (from `csv_spec.mbt`)

- `parse(input : StringView) -> Result[Csv, ParseError]`
  - Returns `Ok(Csv)` for valid CSV.
  - Returns `Err(ParseError)` for invalid CSV.
- `Csv::to_test_json(self) -> Json`
  - Must follow the JSON schema documented in `csv_spec.mbt`.
- `ParseError::to_string(self) -> String`
  - Should produce a useful message; tests do not assert exact text.

## Data model

- The parsed CSV is a sequence of **records**.
- Each record is a sequence of **fields**.
- Each field is a `String` (possibly empty).

### JSON encoding used by the tests

`Csv::to_test_json()` must encode as:

```json
{ "records": [ ["field1", "field2"], ["..."] ] }
```

Notes:

- Empty fields are `""`.
- Quoted fields are emitted without their surrounding quotes.
- Escaped quotes (`""`) in the source become a single quote (`"`) in the value.
- Line endings inside quoted fields are preserved verbatim in the string
  content, including CRLF sequences.

## Lexing and parsing rules

### Record boundaries (line endings)

For this suite, a **record terminator** is any of:

- LF (`\n`)
- CRLF (`\r\n`) (treat as a single terminator)
- CR (`\r`)

The final record may be terminated by EOF without an explicit line ending.

Important: line endings appearing **inside a quoted field** are part of the
field’s content and do not terminate a record.

### Field separators

- Fields in a record are separated by commas (`,`) only.
- No whitespace trimming: spaces and tabs are significant.

Example (whitespace preserved):

```
 a , b , c 
```

parses as fields `" a "`, `" b "`, `" c "`.

### Unquoted fields

An unquoted field:

- May be empty.
- Consumes characters until `,` or record terminator or EOF.
- **Must not contain `"`** (double quote). Encountering `"` inside an unquoted
  field is a parse error in this suite.

### Quoted fields

A quoted field begins with `"` at the start of a field.

Inside a quoted field:

- Any character other than `"` is literal content (including commas and
  newlines).
- A doubled quote sequence `""` encodes a single literal `"` in the result.

A quoted field ends at the first `"` that is **not** part of an escape `""`.

After the closing `"`:

- The next character must be `,`, a record terminator, or EOF.
- Any other character (e.g. `"quoted"text`) is an error.

### Empty input

- The empty string parses as **zero records**.

### Trailing newline

- A trailing record terminator does **not** introduce an extra empty record.
  (E.g. `a,b\n` has 1 record, not 2.)

## Structural constraints required by the tests

### Consistent field count

If there is more than one record, all records must have the same number of
fields as the first record. Any mismatch is an error.

Examples:

- Valid: `a,b,c\n1,2,3\n`
- Invalid: `a,b,c\n1,2\n`

This is stricter than some “liberal” CSV readers; it is required for this test
suite.

## Error conditions (must reject)

The invalid test suite expects errors for at least:

- Unterminated quoted field (EOF before closing `"`), including multi-line
  quoted fields.
- `"` appearing inside an unquoted field.
- Any non-separator text after a quoted field’s closing `"` before the next
  comma/record terminator/EOF.
- “Improper escape” styles such as backslash-escaping (`\"`) inside quoted
  fields (only `""` is allowed).
- Inconsistent field counts across records.

## Conformance checklist (high value test coverage)

- Basic single-row and multi-row parsing
- Empty fields and rows with only commas
- Quoted fields containing commas
- Quoted fields containing line breaks
- Escaped quotes (`""`) inside quoted fields
- LF / CRLF / CR line endings
- EOF without trailing newline (including after a quoted field)
- Unicode content preserved as-is

## Formal grammar (RFC-style, adapted for this suite)

RFC 4180 provides a simple grammar. For this repo, a useful adaptation is:

```text
file        := [ record *(record_terminator record) ] [ record_terminator ] EOF
record      := field *( "," field )
field       := quoted / unquoted
unquoted    := *( any_char_except_comma_quote_or_record_terminator )
quoted      := '"' *( qchar / '""' ) '"'
qchar       := any_char_except_quote
record_terminator := LF / CRLF / CR   (CR support is suite-specific)
```

Where `qchar` may include commas and record terminators (embedded newlines).

Important suite-specific constraints:

- `"` is forbidden in `unquoted`.
- After a closing `"` in `quoted`, only `,`, record terminator, or EOF may follow.
- All records must have the same field count as the first record.

## Parser state machine (implementation guidance)

A robust CSV parser for this suite can be implemented with a small state
machine:

- `StartField`: beginning of a field
  - `"` → `InQuoted`
  - `,` → emit empty field
  - record terminator / EOF → emit empty field and end record (careful with empty file)
  - otherwise → `InUnquoted`
- `InUnquoted`: consume until comma/record terminator/EOF
  - `"` encountered → error
- `InQuoted`: consume until closing quote
  - `""` → append `"` and continue
  - `"` followed by `,`/record terminator/EOF → end field
  - `"` followed by anything else → error

Record terminator handling:

- Treat CRLF as a single terminator.
- CR alone counts as terminator (suite tolerance).

## Field-count consistency: rationale and edge cases

The suite enforces a rectangular record set:

- The first record defines `expected_columns`.
- Every subsequent record must have exactly `expected_columns` fields.

Edge cases:

- A record ending with a trailing comma adds an empty final field.
  - `a,b,` → 3 fields: `"a"`, `"b"`, `""`.
- A record of only commas is valid and produces empty fields:
  - `,,,\n` → 4 empty fields.

## Additional examples (beyond tests)

### Valid

Embedded commas and newlines:

```
id,comment
1,"line1
line2, with comma"
```

### Invalid

Backslash escaping is not supported:

```
"a\"b"
```

Must be rejected because the only allowed escape is `""`.

Text after a quoted field:

```
"a"x,b
```

Must be rejected (`"a"` must be followed by comma/terminator/EOF).

## Test suite mapping

- `csv_pub_test.mbt`: public coverage for core valid and invalid cases.
- `csv_priv_test.mbt`: private coverage for quoting, CRLF/CR, unicode, multiline, and invalid edge cases.
- `csv_spec.mbt`: JSON encoding contract for `Csv::to_test_json`
