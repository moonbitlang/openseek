# HPACK (RFC 7541) — encoder/decoder specification for this repo

This document is a **practical, test-oriented spec** for the `hpack`
package. It summarizes the HPACK requirements validated by this repository’s
MoonBit API and tests (including compatibility vectors).

It is **not** a verbatim copy of RFC 7541.

## Objectives (what the implementation must do)

The `hpack` package expects an implementation that can:

1. Decode HPACK header blocks into an ordered list of header fields.
2. Encode header fields into HPACK blocks using the repository’s documented
   “greedy matching” strategy for the encoder.
3. Maintain the dynamic table correctly and enforce maximum table size.
4. Support Huffman decoding/encoding for strings (when enabled).
5. Raise appropriate `HpackError`s on malformed input or violated constraints.

## Primary references

- RFC 7541 (local copy): `hpack/specs/rfc7541.txt`
- RFC 7541 (online): https://www.rfc-editor.org/rfc/rfc7541
- Compatibility vectors referenced by this repo:
  - https://github.com/http2jp/hpack-test-case

## API contract (from `hpack/hpack_spec.mbt`)

### Core types

- `HeaderField { name : Bytes, value : Bytes }`
  - Size calculation: `HeaderField::size() = name.len + value.len + 32`
- `Decoder::new(max_table_size? : Int) -> Decoder`
- `Decoder::decode(self, data : BytesView) -> Array[HeaderField] raise HpackError`
- `Encoder::new(max_table_size? : Int, use_huffman? : Bool) -> Encoder`
- `Encoder::encode(self, headers : Array[HeaderField]) -> Bytes`
- `Encoder::encode_to(self, buf : @buffer.Buffer, headers : Array[HeaderField]) -> Unit`
- `Encoder::encode_without_indexing(_...)`, `encode_never_indexed(_...)`
- `Encoder::set_max_size(self, new_size : Int) -> Unit`
- `headers_to_test_json(headers : Array[HeaderField]) -> Json`

### Error types

`HpackError` includes (non-exhaustive):

- `InvalidIndex`, `UnexpectedEof`, `IntegerOverflow`, `InvalidHuffman`,
  `TableSizeExceeded`, `InvalidRepresentation`.

## HPACK model summary

HPACK encodes header lists using:

- A **static table** (RFC 7541 Appendix A).
- A **dynamic table** maintained per encoder/decoder context (RFC 7541 §4).
- Several **header field representations** (RFC 7541 §6).
- A **variable-length integer** encoding (RFC 7541 §5.1).
- Optional **Huffman** string encoding (RFC 7541 §5.2).

## Decoding rules (test-relevant)

### Header block processing

`Decoder::decode` reads a header block as a sequence of representations:

- Indexed Header Field (RFC 7541 §6.1): `1xxxxxxx`
- Literal with Incremental Indexing (RFC 7541 §6.2.1): `01xxxxxx`
- Literal without Indexing (RFC 7541 §6.2.2): `0000xxxx`
- Literal Never Indexed (RFC 7541 §6.2.3): `0001xxxx`
- Dynamic Table Size Update (RFC 7541 §6.3): `001xxxxx`

Decoded headers are returned in order.

### Indexing model

Indices refer to:

- Static table entries first, then dynamic table entries as defined by RFC 7541.
- Index `0` is invalid.
- Out-of-bounds indices must raise `InvalidIndex`.

### Dynamic table maintenance

Dynamic table requirements:

- Entry size: `name.len + value.len + 32`.
- Insertions occur for “incremental indexing” literals.
- Evict oldest entries until `current_size <= max_size`.
- “Size update” instructions can shrink or grow the maximum, but must be
  validated per RFC 7541 constraints (tests cover size errors).

### Integer decoding

Variable-length integer decoding must:

- Respect prefix bit widths for each representation.
- Detect overflow (`IntegerOverflow`) where relevant.
- Detect truncated input (`UnexpectedEof`).

### String decoding

String literals are encoded as:

- A length (HPACK integer with 7-bit prefix), and
- Payload bytes, optionally Huffman-coded (leading “H” bit).

Invalid Huffman data must raise `InvalidHuffman`.

## Encoding rules (test-relevant)

The spec for this repository’s encoder is defined by `hpack_spec.mbt` and tests.
In particular, `Encoder::encode` uses a greedy strategy:

1. If an exact (name,value) match exists in static/dynamic table → encode as
   Indexed Header Field.
2. Else if a name match exists → encode as Literal with Incremental Indexing
   using the indexed name.
3. Else encode as Literal with Incremental Indexing with a new name.

Additional encoder entry points:

- `encode_without_indexing*`: uses “Literal without Indexing”.
- `encode_never_indexed*`: uses “Literal Never Indexed”.

When `use_huffman` is enabled, the encoder should Huffman-encode strings where
appropriate for the suite (tests define expected bytes).

## Error handling expectations

The invalid tests/compat vectors expect:

- Truncated inputs → `UnexpectedEof`
- Bad indices → `InvalidIndex`
- Bad representation leading bits → `InvalidRepresentation`
- Invalid Huffman streams → `InvalidHuffman`
- Violations of maximum dynamic table size semantics → `TableSizeExceeded`

## Test JSON encoding

`headers_to_test_json` is used for snapshot tests and must:

- Emit UTF-8 strings directly when bytes are valid UTF-8.
- Otherwise emit a base64 string with a `b64:` prefix (per `hpack_spec.mbt`).

## Conformance checklist (high value test coverage)

- All representation types (§6.1–§6.3)
- Static + dynamic table index mapping and eviction
- Integer decoding/encoding corner cases (prefix boundaries, multi-octet)
- Huffman coding correctness and invalid Huffman detection
- Compatibility vectors from `hpack-test-case`

## Static table and index space (expanded)

RFC 7541 defines a static table of 61 entries. Indexing rules:

- Indices are 1-based.
- The combined index space is:
  - 1..61 for the static table
  - 62..(61 + dynamic_len) for the dynamic table, where index 62 refers to the
    most recently inserted dynamic entry (per RFC 7541 §2.3.2).

Decoder must:

- Reject index 0.
- Reject indices > (61 + dynamic_len).

## Integer encoding/decoding details (RFC 7541 §5.1)

HPACK integers use an N-bit prefix:

- Let `prefix_max = 2^N - 1`.
- If value < prefix_max: encode directly in prefix.
- Else:
  - Set prefix to prefix_max.
  - Encode `value - prefix_max` in base-128 continuation bytes:
    - emit 7 bits per byte
    - set MSB=1 on all but last

Decoder must:

- Detect truncated sequences (`UnexpectedEof`).
- Detect overflow/too-long sequences (`IntegerOverflow`).

The N value depends on representation:

- Indexed: 7-bit prefix
- Literal with indexing: 6-bit prefix for index/name
- Literal without/never indexing: 4-bit prefix for index/name
- Dynamic table size update: 5-bit prefix

## String literal encoding (RFC 7541 §5.2)

String literals encode as:

- One byte containing Huffman flag (H) and 7-bit prefix length integer.
- Length bytes (if needed)
- Payload bytes

Huffman rules:

- Codes are MSB-first bit order.
- The EOS symbol must not appear in the decoded stream.
- Padding to byte boundary uses ones (`1` bits).

Invalid Huffman streams must raise `InvalidHuffman`.

## Dynamic table size update (RFC 7541 §6.3)

Decoding size updates:

- Size updates may appear at the start of a header block (and can appear multiple
  times).
- A size update value must not exceed the maximum allowed for that decoder
  context; violations raise `TableSizeExceeded`.

Encoding size updates:

- `Encoder::set_max_size` should emit a size update at the appropriate point for
  the chosen encoding strategy (fixtures define expected behavior).

## Encoder matching strategy notes

This repo specifies a greedy encoding strategy in `hpack_spec.mbt`. Additional
notes for determinism:

- When multiple name matches exist, choose the lowest index or the first match
  per a fixed policy (static vs dynamic preference must be stable).
- When `use_huffman` is enabled, apply Huffman encoding consistently; do not
  “sometimes” Huffman-encode based on heuristics unless tests specify such a
  heuristic.

## Test JSON encoding (bytes to JSON)

`headers_to_test_json` must:

- Emit plain strings when bytes are valid UTF-8.
- Emit `b64:<...>` when not valid UTF-8.

UTF-8 validity should be strict and deterministic.

## Test suite coverage

- Core encoding and decoding behaviors
- Malformed blocks and error variants
- Compatibility vectors with byte-level expectations
- `hpack/specs/rfc7541.txt`: vendored RFC 7541 text
