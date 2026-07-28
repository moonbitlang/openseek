# Protocol Buffers (binary encoding) — streaming reader/writer specification for this repo

This document is a **practical, test-oriented spec** for the `protobuf`
package. It summarizes the protobuf binary wire format and the streaming
Reader/Writer APIs exercised by this repository’s tests.

It is **not** a verbatim copy of the Protocol Buffers specification.

## Objectives (what the implementation must do)

The `protobuf` package expects an implementation that can:

1. Read protobuf fields from a stream using a generic `Reader`.
2. Write protobuf fields to a stream using a generic `Writer`.
3. Correctly implement wire types, tags, varints, zigzag encoding, and
   length-delimited values.
4. Support packed repeated fields reading/writing where tested.
5. Behave correctly under chunked/partial reads (streaming robustness).

## Primary references

- Local overview + pointers: `protobuf/specs/README.md`
- Local encoding notes used by this repo: `protobuf/specs/encoding.md`
- Protobuf encoding (online): https://protobuf.dev/programming-guides/encoding/

## Scope and explicit non-goals

### Scope

- Wire types:
  - 0: varint
  - 1: 64-bit
  - 2: length-delimited
  - 5: 32-bit
- Core scalar encodings:
  - varint integers (signed/unsigned)
  - zigzag (`sint32`, `sint64`)
  - fixed32/fixed64 + sfixed32/sfixed64
  - float/double (IEEE 754 little-endian)
  - bool and enum as varint
  - bytes/string as length-delimited
- Streaming semantics: readers may return partial data; implementations must
  continue reading until complete values are decoded or EOF/error occurs.

### Non-goals

- `.proto` schema parsing or code generation.
- Unknown-field preservation for roundtrip (unless tests require it).

## API contract (test-oriented overview)

The repository’s API is declared across several `*_spec.mbt` files:

- `reader_spec.mbt`: reading tags and typed values from a `Reader`
- `writer_spec.mbt`: writing tags and typed values to a `Writer`
- `types_spec.mbt`, `sizeof_spec.mbt`: supporting types/constants

The test suite uses these declarations as the contract; implementations must
match them.

## Wire format summary

### Tags

Each field on the wire is encoded as a key (tag) followed by a value:

- `key = (field_number << 3) | wire_type`
- `key` itself is encoded as a varint.

Constraints:

- Field numbers are positive and must fit in the varint encoding used.
- Wire type must be one of the supported values above.

### Varint encoding (wire type 0)

Varints encode unsigned integers in base-128:

- Each byte contributes 7 bits.
- MSB=1 means “more bytes follow”, MSB=0 terminates.

Reader requirements:

- Detect overflow (too many bytes or exceeding target type range).
- Detect truncated input (unexpected EOF in the middle of a varint).

### Zigzag encoding (sint32/sint64)

Zigzag maps signed integers to unsigned so that small negative numbers use few
bytes:

- `zigzag32(n) = (n << 1) ^ (n >> 31)`
- `zigzag64(n) = (n << 1) ^ (n >> 63)`

Writer uses zigzag for `sint*`; reader reverses it.

### Fixed-width (wire types 1 and 5)

- 64-bit (wire type 1): 8 bytes, little-endian.
- 32-bit (wire type 5): 4 bytes, little-endian.

Float/double use IEEE 754 binary formats in these widths.

### Length-delimited (wire type 2)

Used for:

- strings (UTF-8)
- bytes (raw)
- embedded messages
- packed repeated fields

Encoding:

- Length as varint
- Followed by exactly that many payload bytes

Reader requirements:

- Handle chunked reads where payload spans multiple `read` calls.
- Reject invalid UTF-8 where tests require strict string decoding.

## Packed repeated fields (test-relevant)

Packed repeated fields encode repeated numeric scalars as:

- A length-delimited field whose payload is the concatenation of element
  encodings (varint or fixed width depending on the element type).

The repo’s `read_packed` helper (in `reader_spec.mbt`) defines the API shape and
expected behavior.

## Streaming requirements (critical for this suite)

The tests include “chunked reader” scenarios. The reader abstraction may return
fewer bytes than requested; therefore implementations must:

- Loop until the needed bytes for a value are obtained or EOF is reached.
- Correctly handle values split across chunk boundaries.
- Avoid assuming `read` returns the full requested buffer.

## Error conditions (must reject / raise)

The suite expects errors for:

- Truncated varints / truncated fixed-width values / truncated length-delimited
  payloads.
- Integer overflow during varint decoding.
- Invalid tags / invalid wire types where tested.
- Invalid UTF-8 for strings where tested.

## Conformance checklist (high value test coverage)

- Tag encoding/decoding, including field_number/wire_type extraction
- Varint boundaries and overflow detection
- Zigzag encode/decode correctness
- Fixed32/Fixed64 and float/double byte order correctness
- Length-delimited payload reading under chunked reads
- Packed repeated field decoding

## Concrete encoding examples

These examples are useful sanity checks and often appear in protobuf docs:

### Tag/key encoding

Field number 1, wire type 0 (varint):

- key = `(1 << 3) | 0` = `8`
- varint(8) = single byte `0x08`

Field number 3, wire type 2 (length-delimited):

- key = `(3 << 3) | 2` = `26`
- varint(26) = `0x1a`

### Varint encoding example

300 (decimal) in varint:

- 300 = `0b1 0010 1100`
- bytes: `0xac 0x02` (because 300 = 44 + 2*128)

### Zigzag example

- `sint32(-1)` zigzag encodes to `1` (varint `0x01`)
- `sint32(0)` zigzag encodes to `0`
- `sint32(1)` zigzag encodes to `2`

## Varint length limits and overflow policy

To avoid infinite loops and ensure correct overflow detection:

- 32-bit varints should consume at most 5 bytes.
- 64-bit varints should consume at most 10 bytes.

If more bytes are seen without termination (MSB never becomes 0), raise overflow.

Additionally:

- If the decoded unsigned value does not fit the target signed/unsigned range,
  raise overflow or a dedicated error used by this repo’s API.

## Length-delimited limits (safety)

Length-delimited fields include a length varint. Implementations should:

- Reject lengths that exceed remaining input (truncated payload).
- Reject absurdly large lengths that would require huge allocations (either via
  an explicit maximum or by using streaming reads and bounded buffers).

The correct policy is fixture-driven; for safety, prefer bounded behavior.

## Packed field decoding details

Packed payload is a concatenation of element encodings:

- For varint element types: repeated varints back-to-back.
- For fixed32 element types: repeated 4-byte little-endian values.
- For fixed64 element types: repeated 8-byte little-endian values.

Decoder must:

- Consume exactly the packed length (no under/over read).
- Reject leftover bytes that do not form a valid element encoding.

## Streaming reader contract (expanded)

The repo’s `Reader` trait returns:

- `Int?` bytes read, which may be less than requested.

Therefore, implementers must write “read_exactly N bytes” helpers that:

- Loop until N bytes are accumulated.
- Treat `None` or `0` reads as EOF (depending on trait contract).
- Surface IO/truncation errors distinctly where tests require it.

This is critical for streaming correctness.
