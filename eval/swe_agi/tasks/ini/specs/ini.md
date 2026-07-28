# INI — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `ini`
package. INI does not have a single authoritative standard; this repo defines a
clear dialect via its API contract and tests.

It is intended to cover the behaviors exercised by the provided test suite.

## Objectives (what the implementation must do)

The `ini` package expects an implementation that can:

1. Parse INI text into an internal `Ini` representation.
2. Reject malformed inputs with a `ParseError`.
3. Produce a stable JSON view via `Ini::to_test_json()` as the test oracle.

## Primary references (informative)

These are useful context for common INI dialects (non-normative for this repo):

- Python `configparser` behavior: https://docs.python.org/3/library/configparser.html
- systemd unit files: https://www.freedesktop.org/software/systemd/man/latest/systemd.syntax.html
- Git config format: https://git-scm.com/docs/git-config

The normative definition for this repository is the test suite plus `ini_spec.mbt`.

## API contract (from `ini/ini_spec.mbt`)

- `parse(input : StringView) -> Result[Ini, ParseError]`
- `Ini::to_test_json(self : Ini) -> Json`
- `ParseError::to_string(self : ParseError) -> String`

### JSON encoding (test oracle)

`Ini::to_test_json()` must encode as:

```json
{
  "": { "global_key": "global_value" },
  "section": { "k": "v" }
}
```

Rules:

- Each section maps to a JSON object of key/value pairs (both strings).
- Global keys (before any section header) belong to a special section named `""`.
- Empty sections are represented as `{}`.

## File structure and parsing rules

### Lines and whitespace

- Input is treated as lines separated by LF or CRLF (tests include CRLF).
- Blank lines are allowed anywhere and ignored.
- Leading whitespace before a key is allowed (tests: `edge/leading-whitespace`).
- Trailing whitespace after a value is allowed (tests: `edge/trailing-whitespace`).

### Comments

- Full-line comments begin with `;` or `#` (after optional leading whitespace).
- Inline comments are supported:
  - `key=value ; comment`
  - `key=value # comment`
- Comment characters inside **quoted** values are not treated as comments (tests
  include quoted values containing `;` and `#`).

### Sections

Section headers have the form:

```
[section name]
```

Rules required by the tests:

- Section names may include spaces and many punctuation characters.
- Empty section name `[]` is invalid.
- Section syntax must be exact:
  - Missing `[` or `]` is invalid.
  - Nested/double brackets like `[[nested]]` are invalid.
  - Certain bracket/angle-bracket forms in invalid tests must be rejected.
- A `[` appearing inside a value is not a section start; section recognition
  is line-based and must not trigger inside a value (tests include `invalid/section-in-value`).

If the same section header appears multiple times, it **overwrites** the prior
section map (“last one wins”) per `valid/section-overwrite`.

### Key/value entries

Key/value lines take one of these separator forms:

- `key=value`
- `key: value` (tests: `valid/colon-separator`)

Rules:

- Keys must be non-empty and must not be only whitespace (tests: `invalid/empty-key`,
  `invalid/key-only-spaces`).
- A line without a separator is invalid (`invalid/no-equals-sign`).
- Values may be empty (`key=` is valid).
- Keys are case-sensitive (tests: `edge/case-sensitivity`).
- Duplicate keys within the same section: **last one wins** (tests: `valid/duplicate-keys-last-wins`).

### Quoted values

Values may be quoted with either:

- Double quotes: `"..."` with escape support for embedded quotes as exercised by tests.
- Single quotes: `'...'` (tests include “complex quoted strings”).

Rules required by invalid tests:

- Unterminated quotes are invalid.
- Mismatched quote pairs are invalid.
- Multiple separators like `key=value=extra` are invalid unless the extra `=`
  appears inside quotes (tests include “value with equals” and “multiple equals
  without quotes”).

### Multiline values (backslash continuation)

The suite defines a continuation convention:

- If a line’s value ends with a backslash `\\` and is immediately followed by a
  newline, the next line continues the same value (tests: `valid/multiline-value-with-backslash`,
  `valid/complex-multiline`, `valid/long-multiline-value`).
- A backslash at end-of-input without a following newline is invalid
  (`invalid/backslash-continuation-no-newline`).
- A newline that appears in the middle of a value without a trailing `\\` on the
  previous line is invalid (`invalid/multiline-without-backslash`).

The precise concatenation rule (whether newlines are preserved or stripped) is
defined by the expected JSON in the tests.

## Error conditions (must reject)

At minimum, the invalid test suite expects rejection for:

- Malformed section headers (unclosed, empty, missing bracket, nested brackets,
  quotes in section name, etc.).
- Missing separator in a key/value line.
- Empty or whitespace-only keys.
- Unterminated or mismatched quoted values.
- Multiple separators without quotes.
- Unpermitted multi-line forms (no trailing backslash continuation, dangling `\\`).
- Control characters in keys (tests include `invalid/control-characters-in-key`).

## Conformance checklist (high value test coverage)

- Global section `""` behavior
- `=` and `:` separators
- `;` and `#` comments (full-line and inline)
- Quoted values and escaped quotes
- Duplicate keys: last-wins
- Section redefinition: last-wins
- Backslash-based multiline values
- Unicode content in keys/values/sections
- CRLF line endings

## Formal-ish grammar (this repo’s dialect)

This is an implementation-oriented grammar; it is not meant to capture all
whitespace/comment subtleties:

```text
ini         := { line }*
line        := ws* ( comment | section | kv | empty ) ws* newline?
comment     := (';' | '#') { any }*
section     := '[' section_name ']'  (no extra '[' or ']' nesting)
kv          := key ws* sep ws* value
sep         := '=' | ':'
key         := nonempty, not all-whitespace, no control chars
value       := quoted | unquoted
quoted      := dq | sq
dq          := '\"' { dq_char } '\"'
sq          := '\\'' { sq_char } '\\''
unquoted    := { any }* (subject to inline comment stripping)
```

Newline:

- The tests include both LF and CRLF; treat CRLF as a single line break.

## Whitespace trimming vs preservation

The tests imply the following policy (treat the expected JSON as canonical):

- Around separators (`=`/`:`): surrounding whitespace is ignored for parsing.
- In unquoted values:
  - trailing inline comments are stripped
  - internal whitespace is preserved
  - leading/trailing whitespace is preserved in some “edge” tests; prefer to
    preserve it unless the test suite expects trimming in a particular case.
- In quoted values:
  - preserve all characters inside quotes (including leading/trailing spaces)
  - comment markers `;` and `#` are literal characters

If you need an explicit rule: preserve value bytes exactly, except for (1)
removing the surrounding quotes in quoted values, and (2) stripping inline
comments in unquoted values.

## Inline comment stripping rules

The suite covers both `;` and `#` inline comments. A conservative rule that
matches common INI dialects and the test expectations is:

- For unquoted values, if a `;` or `#` appears after at least one whitespace
  separator, treat it as the start of an inline comment.
- Otherwise (no separating whitespace), treat it as part of the value.

Quoted values disable inline comment parsing entirely.

## Multiline continuation: concatenation details

The suite defines backslash continuation. Make explicit:

- If the logical value is continued, the resulting stored value is a single
  string.
- Whether to keep or remove the newline between lines is determined by tests.
  Many INI dialects either:
  - remove the trailing backslash and join lines directly, or
  - remove the backslash and join with `\n`.

Treat the provided expected JSON as authoritative for the join rule.

## Keys and sections: validation details

Keys:

- Must not be empty after trimming outer whitespace.
- Must not contain control characters (tests include a `\\n` case).
- Are case-sensitive.
- May contain dots and dashes (tests cover both).

Sections:

- Section name is the substring inside `[...]` and may contain spaces/unicode.
- Reject empty/whitespace-only section names (tests include `invalid/section-only-spaces`).
- Reject nested brackets (`[[...]]`) and other malformed bracket patterns.

