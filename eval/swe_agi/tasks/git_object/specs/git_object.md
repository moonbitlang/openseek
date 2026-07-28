# Git loose objects — zlib payload parser specification for this repo

This document is a **practical, test-oriented spec** for the `git_object`
package. It describes how to parse **loose git objects** (zlib-compressed object
files in `.git/objects/..`) into a structured `GitObject` and how to render it to
JSON for the fixture-based tests.

It is **not** a complete specification of all git internals.

## Objectives (what the implementation must do)

The `git_object` package expects an implementation that can:

1. Inflate a zlib stream containing a loose git object payload.
2. Parse the object header: `"type size\\0"` followed by raw content bytes.
3. Validate that `size` matches the content length.
4. Optionally validate the object SHA-1 (when `expected_oid` is provided).
5. Parse content for the supported object kinds (blob/tree/commit/tag) and
   produce stable JSON output matching committed fixtures.

## Primary references

- Git object format (high-level docs):
  - https://git-scm.com/book/en/v2/Git-Internals-Git-Objects
  - https://git-scm.com/docs/githash-object
- This repo vendors relevant upstream git source fragments for reference:
  - `git_object/specs/*.c`, `git_object/specs/*.h`

## API contract (from `git_object/git_object_spec.mbt`)

- `parse_object_bytes(bytes : Bytes, expected_oid? : String) -> GitObject raise GitObjectError`
- `GitObject::to_json(self) -> Json`

Error types:

- `InvalidZlib`, `InvalidHeader`, `InvalidSize`, `InvalidSha1`

## Loose object binary layout

### Outer container: zlib

Loose objects are stored as:

- zlib-compressed stream whose decompressed bytes start with a header and then
  the object content.

If the zlib stream cannot be decoded → `InvalidZlib`.

### Header: `"<type> <size>\\0"`

The decompressed payload begins with ASCII:

```
<type-ascii> SP <decimal-size> NUL
```

- `<type-ascii>` is commonly one of: `blob`, `tree`, `commit`, `tag`.
- `<decimal-size>` is base-10 ASCII digits.
- Header terminator is a single NUL byte (`0x00`).

Header errors that must be rejected:

- Missing NUL terminator
- Missing space separator
- Non-decimal size

### Content bytes

After the NUL terminator come exactly `<size>` bytes of content.

If the available bytes do not match `<size>` → `InvalidSize`.

## SHA-1 validation

When `expected_oid` is provided:

1. Validate that `expected_oid` is a 40-character lowercase hex string; else
   `InvalidSha1`.
2. Compute:
   ```
   sha1( "<type> <size>\\0" + content_bytes )
   ```
3. Set `GitObject.sha1_ok` to whether it matches `expected_oid`.

Note: the fixture set includes “sha1 mismatch” cases which must succeed but set
`sha1_ok = false`.

## Content parsing per kind

### Blob

- Content is arbitrary bytes.
- JSON output includes:
  - `base64`: base64 encoding of the raw content bytes
  - `text`: optional UTF-8 string if and only if content is valid UTF-8

### Tree

Tree content is a sequence of entries:

```
<mode-ascii> SP <name-bytes> NUL <20-byte-raw-oid> ...
```

Where:

- `mode-ascii` is typically like `100644`, `100755`, `040000`, etc.
- `name-bytes` are the filename bytes (not NUL-terminated except by the entry
  delimiter).
- The OID is 20 raw bytes; encode to 40-char lowercase hex in JSON.

The suite’s `GitTreeEntry` expects:

- `mode` as the literal mode string
- `kind` derived from mode/object context as per fixtures
- `oid` as hex string
- `name` as decoded string (treat bytes as UTF-8 when valid; otherwise preserve
  a lossless representation consistent with fixtures)

### Commit and Tag

Commit and tag objects are “header-like” text with a blank line separator:

- A sequence of header lines (`key SP value`) possibly with continuation lines
  beginning with a single space.
- A blank line (`\n\n`) separator.
- The remainder is the message (may contain newlines).

The suite’s `GitCommitContent`/`GitTagContent` store:

- `headers`: array of raw header lines (including continuations) as strings
- `message`: remainder after the blank line

### Unknown kinds

If the object type is not one of the supported kinds, represent it as:

- `GitObjectKind::Unknown(type_string)`
- `GitObjectContent::Unknown(base64_payload)`

## JSON output contract (fixtures)

`GitObject::to_json()` must be stable and match fixtures. At minimum it includes:

- `oid` (string)
- `kind` (string)
- `size` (number)
- `sha1_ok` (bool)
- `content` (kind-specific object)

Exact field names and shapes are fixed by `git_object_spec.mbt` and fixture JSON.

## Conformance checklist (high value test coverage)

- zlib decoding success and `InvalidZlib` failures
- Header parsing failures: missing NUL, missing space
- Size mismatch failures
- SHA-1 validation behavior (both match and mismatch)
- Blob base64 + optional UTF-8 text
- Tree entry parsing and OID hex formatting
- Commit/tag header/message splitting and continuation handling

## Header parsing: exactness and corner cases

The object header must be parsed conservatively:

- `<type>` is ASCII lowercase in most real objects, but the parser should accept
  any non-space byte sequence up to the first space if tests introduce
  `Unknown(...)` object types.
- `<size>` is base-10 digits only; reject signs and non-digits.
- Header terminator must be a single NUL byte; missing NUL is `InvalidHeader`.

Do not accept:

- additional spaces before the size
- missing space separator
- extra bytes before the NUL that do not belong to the decimal size

## SHA-1 validation: exact rules

When `expected_oid` is provided, validate:

- length is exactly 40
- all characters are hex digits
- fixtures generally use lowercase; if you accept uppercase, decide whether to
  normalize or treat as invalid. (If tests expect strict lowercase, reject.)

Computation must be over:

```
ascii(type) + " " + ascii(decimal_size) + "\\0" + raw_content_bytes
```

### “Mismatch” behavior

The suite includes many mismatch fixtures:

- Parsing succeeds.
- `sha1_ok` is `false`.
- `GitObject.oid` still reflects the computed SHA-1 (as expected by fixtures),
  not necessarily the `expected_oid`.

## Blob decoding notes

Blob content is arbitrary bytes. The JSON contract includes:

- `base64`: always present for blobs
- `text`: present only when content is valid UTF-8

UTF-8 detection must be strict and deterministic (no lossy replacement). If
content is not valid UTF-8, `text` must be `null`/`None` in the JSON.

## Tree entry parsing: name bytes and ordering

Tree entries are ordered as they appear in the tree payload; preserve order.

Entry structure:

```
mode SP name NUL oid20
```

Notes:

- `name` is a byte sequence terminated by NUL; it may contain non-UTF8 bytes.
- The suite expects `name` to be a `String`. If name bytes are not UTF-8, choose
  a deterministic decoding consistent with fixtures (often “lossy but stable” is
  wrong; prefer a reversible encoding if fixtures do).
- `oid20` is 20 raw bytes; always encode to lowercase hex.

## Commit/tag parsing: continuations and newlines

Commit/tag headers are lines before the first blank line.

- Continuation lines begin with a single space and are part of the previous
  header field logically, but this repo stores `headers` as raw lines, so:
  - keep each physical line as a separate string element
  - preserve exact line text (excluding trailing newline characters)

The message is everything after the blank line separator, preserving newlines.
