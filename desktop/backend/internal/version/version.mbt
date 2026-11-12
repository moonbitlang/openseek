///|
/// A release version, ordered by its numeric `major.minor.patch`. A leading
/// `v`, a pre-release or build suffix (`-beta.1`, `+b410defd5`), and anything
/// after the first space are not part of it, so two builds of one release
/// compare equal.
#derive(Eq, Compare)
struct Version {
  major : Int32
  minor : Int32
  patch : Int32
}

///|
pub extend Version with Eq::{equal, not_equal}

///|
pub extend Version with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
/// Parse a version such as `0.2.0`, `v0.2.0-beta.1`, `0.10.20+b410defd5`, or
/// the `moonc -v` line `v0.10.20+65efd5b93 (2026-11-05)`. `None` unless the
/// release part is exactly three integers.
pub fn parse(text : StringView) -> Version? {
  let text = text.trim()
  let mut release = if text.split_once(" ") is Some((head, _)) {
    head
  } else {
    text
  }
  release = release.strip_prefix("v").unwrap_or(release)
  for stop in ["-", "+"] {
    if release.split_once(stop) is Some((head, _)) {
      release = head
    }
  }
  guard release.split(".").to_array() is [major, minor, patch] else {
    return None
  }
  Some({
    major: @string.parse_int(major),
    minor: @string.parse_int(minor),
    patch: @string.parse_int(patch),
  }) catch {
    _ => None
  }
}
