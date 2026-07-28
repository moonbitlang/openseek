# ZIP (PKWARE APPNOTE) — tolerant metadata parser specification for this repo

This document is a **practical, test-oriented spec** for the `zip`
package. It summarizes the ZIP structures and the repository-specific behavior
expected by the test suite: **tolerant parsing** that salvages central-directory
metadata where possible.

It is **not** a verbatim copy of the ZIP specification.

## Objectives (what the implementation must do)

The `zip` package expects an implementation that can:

1. Parse ZIP archives from:
   - A seekable file (`parse_file`)
   - A streaming reader (`parse_stream`)
2. Produce a `ZipReport` containing:
   - A list of central-directory entries (`ZipEntry`)
   - A summary (`ZipSummary`)
   - An `invalid` flag indicating structural problems
3. Be **error tolerant**: broken archives should still yield any recoverable
   entries instead of returning an empty result.
4. Match JSON fixtures used by tests via `ZipReport::to_json()`.

## Primary references

- PKWARE APPNOTE (local copy): `zip/specs/appnote_iz.txt`
- PKWARE APPNOTE (online): https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

## Scope and explicit non-goals

### Scope

Metadata parsing with an emphasis on:

- End of Central Directory (EOCD) discovery
- Central directory iteration (CDE parsing)
- ZIP64 EOCD and ZIP64 extra fields where needed
- Filename decoding (UTF-8 flag, Unicode Path extra field, CP437 fallback)
- Data descriptor presence (for size/CRC behavior in some cases), as required to
  interpret metadata correctly

### Non-goals

- Full extraction/decompression of file contents.
- Strong cryptography / encryption support.
- Full correctness for every historical ZIP variant; focus is the provided test
  corpus and fixtures.

## API contract (from `zip/zip_spec.mbt`)

- `parse_file(file : @fs.File, name? : String) -> ZipReport raise ZipError`
  - `file` must be seekable.
- `parse_stream(reader : &@io.Reader, name? : String) -> ZipReport raise ZipError`
  - Must not rely on seeking; should match `parse_file` as closely as possible.
- `ZipReport::to_json(self) -> Json`
  - Must match the fixture schema described in `zip_spec.mbt`.

Key types:

- `ZipEntry` is a **central directory entry** in the reference output style.
- `ZipSummary` contains aggregate numbers (optional for broken archives).
- `ZipReport.invalid` flags archives the reference pipeline considers invalid.

## ZIP structures (test-oriented summary)

### End of Central Directory (EOCD)

EOCD record signature: `0x06054b50`.

The parser must be able to find EOCD near the end of the file/stream even when:

- There is an archive comment (EOCD includes a comment length).
- There is trailing junk (some “valid” fixtures have trailing data).
- There is leading junk (“self-extracting”/prefix style).

### Central Directory (CD)

Central directory file header signature: `0x02014b50`.

Each CD entry provides:

- file name
- compression method
- sizes (compressed/uncompressed)
- timestamps
- “version needed to extract”, “host OS”
- offset to local file header
- extra fields (ZIP64, Unicode path, etc.)

The suite’s output is driven by a **reference metadata pipeline**; this package
is expected to recreate that metadata view (not necessarily a full ZIP reader).

### ZIP64

ZIP64 may be present via:

- ZIP64 EOCD record + locator, and/or
- ZIP64 extended information extra field in entries.

The test corpus includes both valid ZIP64 archives and invalid ZIP64 scenarios.
Implementations must:

- Correctly interpret ZIP64 sizes/offsets when 32-bit fields are `0xFFFF`/`0xFFFFFFFF`.
- Mark the archive invalid where inconsistencies occur, but still salvage
  entries where possible.

## Filename decoding (required by tests)

Per `zip_spec.mbt`, `ZipEntry.name` must be decoded using:

1. UTF-8 if the “UTF-8” general purpose bit flag is set.
2. Otherwise, prefer Unicode Path extra field (`0x7075`) when present.
3. Otherwise decode with CP437.

Preserve the decoded string as-is (including any unusual characters).

## Error tolerance rules (repo-specific)

This repository requires **tolerant parsing**:

- If the archive has structural issues but CD entries can still be read, return
  a `ZipReport` with those entries and set `invalid = true`.
- Only raise `ZipError::Invalid` when the archive is so broken that no partial
  report can reasonably be produced (tests include cases that should still
  produce partial results).
- For pure non-zip inputs (random files), the suite expects a report marked
  invalid rather than an empty success unless fixtures specify otherwise.

## JSON fixture contract

`ZipReport::to_json()` must emit:

```json
{
  "archive": "<name>",
  "entries": [ { ...ZipEntry... }, ... ],
  "summary": { ...ZipSummary... },
  "invalid": true|false
}
```

Exact field formatting (e.g. `mode`, `host_os`, `version`, `mod_date`, `mod_time`,
`compression_method`, `attrs`) must match the committed fixtures.

## Conformance checklist (high value test coverage)

- EOCD discovery under comments, prefix junk, and trailing junk
- Central directory parsing across many tool-produced archives (7zip, winrar,
  winzip, infozip, jar files)
- ZIP64 handling (valid + invalid)
- Filename decoding and Unicode path extra field handling
- Tolerant behavior: salvage entries and mark `invalid` rather than failing
- Consistency between `parse_file` (seekable) and `parse_stream` (streaming)

## ZIP structure details (expanded)

This suite is metadata-centric. A practical implementation focuses on the
central directory and EOCD, while being aware of local headers and streaming
constraints.

### Local File Header (LFH)

Signature: `0x04034b50`.

Even if the implementation doesn’t decompress file data, LFHs matter for:

- Validating central-directory offsets.
- Detecting truncation/short reads.
- Understanding when “data descriptor” mode is used.

### Data descriptor

Some ZIP writers set the “data descriptor” flag and omit size/CRC from the LFH,
writing them after the file data (sometimes preceded by signature `0x08074b50`).

The test corpus includes archives named like `dd.zip` and similar. For this repo:

- Prefer central directory sizes/CRC as the authoritative metadata, when present.
- Streaming must still be able to skip file data safely even when sizes are not
  known up front (bounded buffering or incremental scanning).

## EOCD discovery algorithms (seekable vs streaming)

### Seekable (`parse_file`)

Recommended approach:

- Read the last `min(file_size, 64KiB + 22)` bytes (EOCD min size is 22).
- Search backwards for EOCD signature `PK\\x05\\x06`.
- Parse EOCD fields, then locate the central directory.

This handles:

- Archive comments (EOCD includes comment length).
- Trailing junk (scan backwards rather than assume EOCD at EOF).
- Prefix junk/SFX stubs (offsets are relative to file start).

### Streaming (`parse_stream`)

Streaming cannot seek. Practical strategies include:

- Keep a rolling tail buffer (64KiB+22) while reading; after EOF, search for EOCD.

After you find EOCD in streaming mode, you may not be able to “go back” to the
central directory. Approaches to align with `parse_file` results:

- Parse local entries as they stream and build an entry list on the fly.
- Or buffer enough of the stream to reconstruct the central directory when EOCD
  is discovered (trade memory for fidelity).

The required behavior is “as consistent as possible” with `parse_file`; fixture
outputs define what is acceptable.

## Central directory entry formatting

The suite’s fixtures encode fields like `mode`, `host_os`, `version`, `attrs`,
`compression_method`, `mod_date`, `mod_time` as **strings**. Therefore:

- Formatting is part of conformance, not an implementation detail.
- If the fixtures were generated from a particular tool (e.g. unzip/infozip),
  the implementation may need to emulate those formatting conventions.

## ZIP64 expanded notes

ZIP64 affects:

- EOCD via ZIP64 EOCD record + locator, and/or
- Per-entry sizes/offsets via ZIP64 extended information extra field.

The corpus includes invalid ZIP64 cases; tolerant parsing should:

- Set `invalid = true` on inconsistencies.
- Still salvage and report any entries that can be parsed.

## Summary computation

For valid archives, compute:

- `entries`: number of recovered central directory entries
- `compressed_size` and `uncompressed_size`: sums across entries
- `compression_ratio`: formatted per fixtures (exact formatting is fixture-defined)

For invalid archives, fields may be `None` if the fixture indicates they are
unknown or unreliable.
