///|
/// Bound decoded artifacts independently of the transport envelope. Check the
/// encoded length first, before allocating a decoded copy.
const MaxBinaryBytes : Int = 16777216

///|
fn decode_base64(content : String) -> Bytes raise {
  guard content.length() <= (MaxBinaryBytes + 2) / 3 * 4 else {
    fail("base64 content exceeds the 16 MiB decoded limit")
  }
  guard content.length() % 4 == 0 else {
    fail("content must be canonical padded Base64 without whitespace")
  }
  let bytes = @base64.decode(content) catch {
    _ => fail("content must be canonical padded Base64 without whitespace")
  }
  // The library decoder accepts incomplete padding and stops at '='. Requiring
  // a canonical round trip rejects trailing data and nonzero unused bits too.
  guard @base64.encode(bytes) == content else {
    fail("content must be canonical padded Base64 without whitespace")
  }
  guard bytes.length() <= MaxBinaryBytes else {
    fail("base64 content exceeds the 16 MiB decoded limit")
  }
  bytes
}

///|
/// Base64 is a transport encoding, not a way to bypass source/manifest checks.
fn requires_text(path : String) -> Bool {
  is_mbt_source(path) ||
  path.has_suffix(".mbti") ||
  @manifest_path.is_moon_mod_path(path) ||
  @manifest_path.is_moon_mod_json_path(path) ||
  @manifest_path.is_moon_pkg_path(path)
}
