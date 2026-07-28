///|
/// # WebAssembly Binary Decoder & Validator - API Specification
///
/// This test suite targets two distinct phases:
/// - **Decoding**: parsing a `.wasm` binary into a `Module` AST
/// - **Validation**: checking the decoded module for structural/semantic validity
///
/// The tests in this directory are extracted/derived from `wasmoon`.
declare pub(all) type Module

///|
/// Errors raised while decoding/parsing a `.wasm` binary.
pub suberror DecodeError {
  UnexpectedEnd
  LengthOutOfBounds
  InvalidMagicNumber
  UnsupportedVersion
  ParseError(String)
}

///|
declare pub fn DecodeError::to_string(self : DecodeError) -> String

///|
/// Decode a WebAssembly binary module.
///
/// - Raises `DecodeError` for malformed binaries (bad header, truncated sections, etc.).
declare pub fn decode_module(data : Bytes) -> Module raise DecodeError

///|
/// Errors raised while validating a decoded module.
pub suberror ValidationError {
  InvalidModule(String)
}

///|
declare pub fn ValidationError::to_string(self : ValidationError) -> String

///|
/// Print a decoded module in text format.
///
/// The expected output for spec-tests is the canonical text format emitted by
/// `wasm-tools print` (the generator snapshots that output).
declare pub fn Module::print(self : Module) -> String

///|
/// Validate a decoded WebAssembly module.
///
/// - Raises `ValidationError` for invalid modules (e.g. inconsistent indices/types).
declare pub fn validate_module(mod_ : Module) -> Unit raise ValidationError
