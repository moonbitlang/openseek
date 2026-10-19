///|
/// The session id of side chat `ordinal` of the conversation `parent`.
///
/// A side chat is a fork of its main conversation that the desktop shows in
/// the dock beside it rather than as a conversation of its own. Its record is
/// a sibling in the main conversation's store, named so the relation needs
/// nothing but the id: like a sub-run's `<parent>-sr-<N>`, the suffix makes it
/// part of the parent's family, so it is archived, restored, and deleted with
/// the parent, and every client can tell which conversation it belongs to.
pub fn side_chat_id(parent : String, ordinal : Int32) -> String {
  "\{parent}-\{SideChatMarker}\{ordinal}"
}

///|
const SideChatMarker : String = "sc-"

///|
/// The main conversation and ordinal behind a side chat's session id, or
/// `None` for any other session — the inverse of `side_chat_id`.
///
/// Only a trailing `-sc-<N>` counts, with the ordinal bounded to nine digits
/// as sub-run ordinals are: an id that merely contains the marker is an
/// ordinary session. A side chat's own sub-run, `<parent>-sc-1-sr-2`, is not
/// a side chat; `@wire.split_child_session_id` names its parent, the side
/// chat.
pub fn split_side_chat_id(id : String) -> (String, Int32)? {
  let marker = "-\{SideChatMarker}"
  guard id.rev_find(marker) is Some(start) && start > 0 else { return None }
  let digits = id[start + marker.length():]
  guard !digits.is_empty() &&
    digits.length() <= 9 &&
    digits.all(c => c.is_ascii_digit()) else {
    return None
  }
  let ordinal = digits.fold(init=0, (ordinal, c) => {
    ordinal * 10 + (c.to_int() - '0'.to_int())
  })
  Some((id[:start].to_owned(), ordinal))
}
