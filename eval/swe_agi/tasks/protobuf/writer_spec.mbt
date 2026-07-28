// Copyright 2024 International Digital Economy Academy
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
/// Trait representing the Writer
pub(open) trait Writer {
  fn write(Self, BytesView) -> Unit raise
}

///|
pub impl Writer for @buffer.Buffer with fn write(self, bytes : BytesView) raise {
  self.write_bytesview(bytes)
}

///|
declare pub fn[T : Writer] write_varint(
  writer : T,
  input : UInt64,
) -> Unit raise

///|
declare pub fn[T : Writer] write_tag(
  writer : T,
  tag : (UInt, UInt),
) -> Unit raise

///|
declare pub fn[T : Writer] write_int32(writer : T, v : Int) -> Unit raise

///|
declare pub fn[T : Writer] write_int64(writer : T, v : Int64) -> Unit raise

///|
declare pub fn[T : Writer] write_uint32(writer : T, v : UInt) -> Unit raise

///|
declare pub fn[T : Writer] write_uint64(writer : T, v : UInt64) -> Unit raise

///|
declare pub fn[T : Writer] write_sint32(writer : T, v : Int) -> Unit raise

///|
declare pub fn[T : Writer] write_sint64(writer : T, v : Int64) -> Unit raise

///|
declare pub fn[T : Writer] write_fixed32(writer : T, v : UInt) -> Unit raise

///|
declare pub fn[T : Writer] write_fixed64(writer : T, v : UInt64) -> Unit raise

///|
declare pub fn[T : Writer] write_sfixed32(writer : T, v : Int) -> Unit raise

///|
declare pub fn[T : Writer] write_sfixed64(writer : T, v : Int64) -> Unit raise

///|
declare pub fn[T : Writer] write_float(writer : T, v : Float) -> Unit raise

///|
declare pub fn[T : Writer] write_double(writer : T, v : Double) -> Unit raise

///|
declare pub fn[T : Writer] write_bool(writer : T, v : Bool) -> Unit raise

///|
declare pub fn[T : Writer] write_enum(writer : T, v : Enum) -> Unit raise

///|
declare pub fn[T : Writer] write_bytes(writer : T, v : Bytes) -> Unit raise

///|
declare pub fn[T : Writer] write_string(writer : T, v : String) -> Unit raise
