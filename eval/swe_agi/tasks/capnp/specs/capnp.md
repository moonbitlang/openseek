# Cap’n Proto encoding — low-level message/arena specification for this repo

This document is a **practical, test-oriented spec** for the `capnp`
package. It summarizes the low-level Cap’n Proto encoding rules and the subset
of features exercised by the repository’s decoder/writer APIs and fixtures.

It is **not** a verbatim copy of the Cap’n Proto specification.

## Objectives (what the implementation must do)

The `capnp` package expects an implementation that can:

1. Decode Cap’n Proto messages from bytes into a random-access “arena” and allow
   traversing pointers to structs/lists.
2. Encode (write) Cap’n Proto messages into bytes, producing correct framing and
   pointer layouts for the tested cases.
3. Correctly implement core pointer types (struct, list, far) and bounds checks.
4. Match the test fixtures (generated from `capnp` tooling) for both decoding
   and encoding/roundtrip.

## Primary references

- Cap’n Proto encoding spec (vendored overview): `capnp/specs/README.md`
- Cap’n Proto encoding spec (online): https://capnproto.org/encoding.html

## Scope and explicit non-goals

### Scope

The repository implements a **low-level**, schema-agnostic API:

- Message framing (segment table) for “unpacked” messages.
- In-segment pointers (struct/list) and inter-segment far pointers (landing pads).
- Struct data section vs pointer section layout.
- List element size classes (including pointer lists and composite lists).
- Reader traversal limits / depth checks where tests assert them.

### Non-goals

- Packed encoding/decoding (unless you add it; tests don’t require it).
- Schema compilation / code generation.
- RPC / capabilities.

## Implementation surfaces in this repo (test-oriented)

The exact public API is defined across `*_spec.mbt` files under `capnp/` (e.g.
`decoder_spec.mbt`, `encoder_spec.mbt`, `segment_spec.mbt`, `pointer_spec.mbt`,
`errors_spec.mbt`). Tests treat these APIs as the contract.

At a high level, the suite assumes the existence of:

- A reader/decoder that can be constructed from a byte slice and exposes a root
  pointer (`root()`), then allows reading primitive fields and following pointers.
- A writer that can allocate/init a root struct, set primitive fields, allocate
  lists/structs, and serialize to bytes.

See `capnp/README.md` for an overview and fixture generation notes.

## Encoding model summary (Cap’n Proto fundamentals)

### Words and alignment

- A “word” is 8 bytes (64 bits).
- All objects are aligned to word boundaries.
- Struct sizes are expressed as:
  - data section size in words
  - pointer section size in words

### Message framing (segment table)

An unpacked message begins with a segment table:

- `segment_count_minus_one` (u32 LE)
- For each segment: `segment_size_in_words` (u32 LE)
- Padding to an even number of u32 entries
- Then the concatenated segment data (each segment is `size_in_words * 8` bytes)

The first word of segment 0 is a pointer to the message’s root struct.

### Pointers (64-bit words)

Cap’n Proto uses 64-bit pointers with a 2-bit “kind” tag in the LSBs:

- Struct pointer (kind 0)
- List pointer (kind 1)
- Far pointer (kind 2)
- Other / reserved (kind 3; used for “capability” in some contexts)

All pointers use a signed **word offset** relative to the end of the pointer
word (except far pointers which carry segment/landing pad metadata).

### Struct pointer (kind 0)

Struct pointer fields (from `capnp/specs/README.md`):

- Offset (30 bits, signed): from end of pointer to start of struct data.
- Data size (16 bits): number of words in data section.
- Pointer size (16 bits): number of words in pointer section.

Struct layout in memory:

```
[ data section (N words) ][ pointer section (M words) ]
```

### List pointer (kind 1)

List pointer fields:

- Offset (30 bits, signed)
- Element size (3 bits): void/bit/byte/2B/4B/8B(non-pointer)/8B(pointer)/composite
- Length (29 bits): element count, or word count for composite lists

Composite lists use a “tag word” at the target describing per-element struct
sizes, followed by element bodies.

### Far pointer (kind 2)

Far pointers encode inter-segment references:

- Carry the target segment ID and offset to a “landing pad”.
- Landing pads contain either:
  - A copy of the target pointer (for single-far), or
  - A far pointer to the object plus a tag word (for double-far with composite)

The test suite includes fixtures that require far-pointer correctness.

## Bounds and traversal safety

Decoders must validate:

- Pointer offsets do not point outside their segment.
- List sizes do not exceed segment bounds.
- Composite list total size fits within bounds.
- Any recursion/traversal limit rules required by tests (e.g. “traversal limit”
  tests in this repo).

On failures, raise the appropriate error types as defined in `errors_spec.mbt`.

## Fixture-driven expectations

Tests are generated from `capnp` tooling and cover:

- Primitive field decoding/encoding (simple fixtures)
- Structs containing multiple primitives and pointers (medium fixtures)
- Nested structs/lists/unions and deeper pointer graphs (difficult fixtures)
- Convert and roundtrip scenarios generated from the reference tooling

Therefore:

- Serialization must match canonical Cap’n Proto encoding for the exercised
  schemas.
- Decoder must preserve ordering and exact numeric values per fixture outputs.

## Conformance checklist (high value test coverage)

- Message framing: segment table parsing/serialization
- Struct pointers: offsets, sizes, reading/writing primitives
- List pointers: all element size classes exercised by fixtures
- Composite lists + tag word handling
- Far pointers + landing pads across segments
- Strict bounds checks and traversal limits

## Segment table encoding (expanded)

Unpacked message framing begins with 32-bit little-endian words:

1. `segment_count_minus_one : u32`
2. `segment_size_in_words[i] : u32` for each segment
3. Optional padding u32 so that the segment table length (in u32s) is even
4. Segment data blobs concatenated

Notes:

- Segment sizes are in 64-bit words; bytes = `words * 8`.
- Segment 0 word 0 is the root pointer.

Practical parser rules:

- Validate that the segment table does not claim more bytes than are available.
- Validate segment_count is at least 1.
- Validate each segment blob is fully present.

## Pointer bitfields (practical decoding)

Pointers are 64-bit little-endian words.

- Low 2 bits = kind:
  - 0: struct
  - 1: list
  - 2: far
  - 3: other (capability/reserved; usually unsupported here)

Offsets:

- Most pointers store a signed 30-bit word offset relative to the end of the
  pointer word.
- The offset is in words, not bytes.

Decoders must carefully sign-extend the 30-bit offset and compute target word
indices with overflow/bounds checks.

## List element size codes (kind 1 lists)

The 3-bit element size code (C) defines packing:

- 0: void (0 bits)
- 1: 1-bit (bool)
- 2: 1 byte
- 3: 2 bytes
- 4: 4 bytes
- 5: 8 bytes (non-pointer)
- 6: 8 bytes (pointer)
- 7: composite (tag word + struct-like elements)

Composite lists:

- The “length” field (D) is words, not element count (excluding tag).
- The first word at the target is a “tag” describing the per-element struct
  size and element count.

## Far pointers and landing pads (expanded)

Far pointers enable inter-segment references. Typical cases:

- Single-far:
  - Far pointer points to a landing pad containing the real struct/list pointer.
- Double-far:
  - Used when the landing pad itself must point elsewhere (e.g. composite list),
    and may involve an extra tag word.

Test fixtures include far-pointer cases, so implement:

- Segment switching by segment ID
- Landing pad reading and following the contained pointer
- Bounds checks across both segments

## Traversal limits and safety

To prevent malicious inputs from causing huge work:

- Enforce maximum traversal/total words visited if the API provides such a limit.
- Detect pointer cycles (Cap’n Proto messages are trees by construction, but
  malformed inputs can violate this).

The implementation must reject inputs that exceed the traversal limit.
