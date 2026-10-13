// Port of Monaco/VS Code's CharacterClassifier.
//
// Source: vscode/src/vs/editor/common/core/characterClassifier.ts
//   with toUint8 from vscode/src/vs/base/common/uint.ts
// (checked-in vscode submodule).
//
// A fast character classifier: a dense Uint8 map for ASCII (0..255) plus a
// sparse map for the rest. Values are clamped to a byte.

///|
fn to_uint8(v : Int32) -> Int32 {
  v.clamp(min=0, max=255)
}

///|
/// Classifies char codes into small integer buckets.
struct CharacterClassifier {
  ascii_map : Array[Int32]
  map : Map[Int32, Int32]
  default_value : Int32
}

///|
pub fn CharacterClassifier::CharacterClassifier(
  default_value : Int32,
) -> CharacterClassifier {
  let dv = to_uint8(default_value)
  { ascii_map: Array::make(256, dv), map: Map([]), default_value: dv, }
}

///|
pub fn CharacterClassifier::set(
  self : CharacterClassifier,
  char_code : Int32,
  value : Int32,
) -> Unit {
  let v = to_uint8(value)
  if char_code >= 0 && char_code < 256 {
    self.ascii_map[char_code] = v
  } else {
    self.map[char_code] = v
  }
}

///|
pub fn CharacterClassifier::get(
  self : CharacterClassifier,
  char_code : Int32,
) -> Int32 {
  if char_code >= 0 && char_code < 256 {
    self.ascii_map[char_code]
  } else {
    // Mirrors upstream `this._map.get(charCode) || this._defaultValue`: a stored
    // 0 (falsy) also falls back to the default value.
    match self.map.get(char_code) {
      Some(v) => if v != 0 { v } else { self.default_value }
      None => self.default_value
    }
  }
}

///|
/// A set of char codes, backed by a `CharacterClassifier`.
struct CharacterSet {
  actual : CharacterClassifier
}

///|
fn CharacterSet::new_impl() -> CharacterSet {
  { actual: CharacterClassifier(0), }
}

///|
fn CharacterSet::add_impl(self : CharacterSet, char_code : Int32) -> Unit {
  self.actual.set(char_code, 1)
}

///|
fn CharacterSet::has_impl(self : CharacterSet, char_code : Int32) -> Bool {
  self.actual.get(char_code) == 1
}
