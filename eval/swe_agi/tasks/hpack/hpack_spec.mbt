// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// A header field (name-value pair)
/// Both name and value are treated as opaque sequences of octets
pub(all) struct HeaderField {
  name : Bytes
  value : Bytes
} derive(Debug, Eq)

///|
/// Calculate entry size per RFC 7541 Section 4.1
/// Size = name_length + value_length + 32
declare pub fn HeaderField::size(self : HeaderField) -> Int

///|
/// Error types for HPACK encoding/decoding
pub(all) suberror HpackError {
  /// Invalid index (0 or out of bounds)
  InvalidIndex(Int)
  /// Integer overflow during decoding
  IntegerOverflow
  /// Unexpected end of input
  UnexpectedEof
  /// Invalid Huffman encoding
  InvalidHuffman(String)
  /// Dynamic table size exceeds protocol limit
  TableSizeExceeded(size~ : Int, max~ : Int)
  /// Dynamic table size update not at the beginning of a header block
  InvalidTableSizeUpdate
  /// Invalid representation type byte
  InvalidRepresentation(Byte)
} derive(Debug, Eq)

///|
/// HPACK Decoder context
declare pub type Decoder

///|
/// Create a new HPACK decoder
///
/// Parameters:
/// - `max_table_size`: Maximum size of the dynamic table (default: 4096)
declare pub fn Decoder::new(max_table_size? : Int) -> Decoder

///|
/// Decode a header block into a list of header fields
///
/// Implements RFC 7541 header block decoding:
/// - Section 6.1: Indexed Header Field (1xxxxxxx)
/// - Section 6.2.1: Literal with Incremental Indexing (01xxxxxx)
/// - Section 6.2.2: Literal without Indexing (0000xxxx)
/// - Section 6.2.3: Literal Never Indexed (0001xxxx)
/// - Section 6.3: Dynamic Table Size Update (001xxxxx)
///
/// Raises:
/// - `HpackError::InvalidIndex` if index is 0 or out of bounds
/// - `HpackError::UnexpectedEof` if data is truncated
/// - `HpackError::IntegerOverflow` on integer overflow
/// - `HpackError::InvalidHuffman` on invalid Huffman encoding
/// - `HpackError::TableSizeExceeded` if table size exceeds protocol limit
/// - `HpackError::InvalidRepresentation` for invalid representation type
declare pub fn Decoder::decode(
  self : Decoder,
  data : BytesView,
) -> Array[HeaderField] raise HpackError

///|
/// HPACK Encoder context
declare pub type Encoder

///|
/// Create a new HPACK encoder
///
/// Parameters:
/// - `max_table_size`: Maximum size of the dynamic table (default: 4096)
/// - `use_huffman`: Whether to use Huffman encoding (default: true)
declare pub fn Encoder::new(
  max_table_size? : Int,
  use_huffman? : Bool,
) -> Encoder

///|
/// Encode a list of header fields into a header block
///
/// Uses greedy matching:
/// 1. Exact match -> Indexed Header Field
/// 2. Name match -> Literal with Incremental Indexing
/// 3. No match -> Literal with Incremental Indexing (new name)
declare pub fn Encoder::encode(
  self : Encoder,
  headers : Array[HeaderField],
) -> Bytes

///|
/// Encode a list of header fields to a buffer
declare pub fn Encoder::encode_to(
  self : Encoder,
  buf : @buffer.Buffer,
  headers : Array[HeaderField],
) -> Unit

///|
/// Encode a header field without adding to dynamic table
/// Uses Literal Header Field without Indexing (Section 6.2.2)
declare pub fn Encoder::encode_without_indexing(
  self : Encoder,
  header : HeaderField,
) -> Bytes

///|
/// Encode a header field without adding to dynamic table (buffer variant)
declare pub fn Encoder::encode_without_indexing_to(
  self : Encoder,
  buf : @buffer.Buffer,
  header : HeaderField,
) -> Unit

///|
/// Encode a header field that should never be indexed (sensitive data)
/// Uses Literal Header Field Never Indexed (Section 6.2.3)
declare pub fn Encoder::encode_never_indexed(
  self : Encoder,
  header : HeaderField,
) -> Bytes

///|
/// Encode a header field that should never be indexed (buffer variant)
declare pub fn Encoder::encode_never_indexed_to(
  self : Encoder,
  buf : @buffer.Buffer,
  header : HeaderField,
) -> Unit

///|
/// Set the dynamic table maximum size
/// Triggers eviction if new size is smaller than current entries
declare pub fn Encoder::set_max_size(self : Encoder, new_size : Int) -> Unit

///|
/// Convert an array of header fields to JSON for test inspection
///
/// Each header is encoded as:
/// ```json
/// {"name": "<base64-or-string>", "value": "<base64-or-string>"}
/// ```
///
/// String values are used when the bytes are valid UTF-8,
/// otherwise base64 encoding is used with a "b64:" prefix.
declare pub fn headers_to_test_json(headers : Array[HeaderField]) -> Json
