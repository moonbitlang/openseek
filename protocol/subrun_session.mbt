///|
/// The parent session id and sub-run ordinal behind a child session id, or
/// `None` for an ordinary session.
///
/// A sub-run of a DURABLE parent persists its own transcript under
/// `<parent session id>-sr-<N>`, where `N` is the ordinal of the `sr-N` that
/// the `SubrunStarted`/`SubrunFinished` brackets carry. The derivation lives
/// here, next to those events, because every reader of the stream also reads
/// the store: the desktop sidebar folds children under their parent, the
/// viewer nests their transcripts, and both would otherwise reinvent this
/// parse.
///
/// Nesting is textual and the INNERMOST suffix wins: `a-sr-1-sr-2` is child
/// 2 of `a-sr-1`, not child 1 of `a`. The ordinal is bounded to nine digits
/// so a pathological session name cannot overflow it — beyond that the id is
/// simply not a child id, which is the fail-closed reading (it renders as an
/// ordinary session rather than folding under a parent it may not have).
pub fn split_child_session_id(id : String) -> (String, Int)? {
  let marker = "-sr-"
  let mut offset = 0
  let mut last = None
  while offset < id.length() {
    match id[offset:].find(marker) {
      Some(found) => {
        let start = offset + found
        last = Some(start)
        offset = start + marker.length()
      }
      None => break
    }
  }
  guard last is Some(start) else { return None }
  guard start > 0 else { return None }
  let digits = id[start + marker.length():]
  guard !digits.is_empty() &&
    digits.length() <= 9 &&
    digits.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  let ordinal = for c in digits; ordinal = 0 {
    continue ordinal * 10 + (c.to_int() - '0'.to_int())
  } nobreak {
    ordinal
  }
  Some((id[:start].to_owned(), ordinal))
}
