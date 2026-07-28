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
/// Trait representing the reader
pub(open) trait Reader {
  /// Reads data into the provided buffer, returns the number of bytes read, or None if end of stream
  fn read(Self, FixedArray[Byte], offset? : Int, max_length? : Int) -> Int? raise
}

///|
pub(open) trait Read {
  fn read(&Reader) -> Self raise = _
  fn read_with_limit(LimitedReader[&Reader]) -> Self raise
}

///|
impl Read with fn read(reader : &Reader) -> Self raise {
  let reader = LimitedReader::new(reader)
  Read::read_with_limit(reader)
}

///|
declare pub type LimitedReader[T]

///|
declare pub fn[T] LimitedReader::new(
  reader : T,
  limit? : Int,
) -> LimitedReader[T]

///|
declare pub type BytesReader

///|
declare pub fn BytesReader::from_bytes(bytes : Bytes) -> BytesReader

///|
declare pub impl[T : Reader] Reader for LimitedReader[T]

///|
declare pub impl Reader for BytesReader

///|
declare pub fn[T : Reader] read_tag(reader : T) -> (UInt, UInt) raise

///|
declare pub fn[T : Reader] read_varint32(reader : T) -> UInt raise

///|
declare pub fn[T : Reader] read_int32(reader : T) -> Int raise

///|
declare pub fn[T : Reader] read_int64(reader : T) -> Int64 raise

///|
declare pub fn[T : Reader] read_uint32(reader : T) -> UInt raise

///|
declare pub fn[T : Reader] read_uint64(reader : T) -> UInt64 raise

///|
declare pub fn[T : Reader] read_sint32(reader : T) -> SInt raise

///|
declare pub fn[T : Reader] read_sint64(reader : T) -> SInt64 raise

///|
declare pub fn[T : Reader] read_fixed32(reader : T) -> UInt raise

///|
declare pub fn[T : Reader] read_fixed64(reader : T) -> UInt64 raise

///|
declare pub fn[T : Reader] read_sfixed32(reader : T) -> Int raise

///|
declare pub fn[T : Reader] read_sfixed64(reader : T) -> Int64 raise

///|
declare pub fn[T : Reader] read_float(reader : T) -> Float raise

///|
declare pub fn[T : Reader] read_double(reader : T) -> Double raise

///|
declare pub fn[T : Reader] read_bool(reader : T) -> Bool raise

///|
declare pub fn[T : Reader] read_enum(reader : T) -> Enum raise

///|
declare pub fn[T : Reader] read_bytes(reader : T) -> Bytes raise

///|
declare pub fn[T : Reader] read_string(reader : T) -> String raise

///|
/// Reads packed repeated field (Array[M])
///
/// Note: packed field are stored as a variable length chunk of data, while regular repeated
/// fields behaves like an iterator, yielding their tag everytime
declare pub fn[M : Sized, R : Reader] read_packed(
  reader : R,
  read_fn : (LimitedReader[R]) -> M raise,
  size : UInt?,
) -> Array[M] raise

///|
declare pub fn[T : Reader] read_unknown(
  reader : T,
  wire_type : UInt,
) -> Unit raise
