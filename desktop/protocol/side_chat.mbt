///|
/// The session id of the side chat `token` of the conversation `parent`.
///
/// A side chat is a fork of its main conversation that the desktop shows in
/// the dock beside it rather than as a conversation of its own. Its record is
/// a sibling in the main conversation's store, named so the relation needs
/// nothing but the id: like a sub-run's `<parent>-sr-<N>`, the suffix makes it
/// part of the parent's family, so it is archived, restored, and deleted with
/// the parent, and every client can tell which conversation it belongs to.
///
/// `token` is `SideChatTokenLength` lowercase hex digits, random, so an id
/// is never given to a second side chat after the first is deleted. It only
/// has to differ from the parent's other side chats; the host draws again on
/// a collision.
pub fn side_chat_id(parent : String, token : String) -> String {
  "\{parent}\{SideChatMarker}\{token}"
}

///|
const SideChatMarker : String = "-sc-"

///|
pub const SideChatTokenLength : Int32 = 8

///|
/// The main conversation behind a side chat's session id, or `None` for any
/// other session — the inverse of `side_chat_id`.
///
/// Only a trailing `-sc-` followed by exactly `SideChatTokenLength` lowercase
/// hex digits counts: an id that merely contains the marker is an ordinary
/// session. A side chat's own sub-run, `<parent>-sc-<token>-sr-2`, is not a
/// side chat; `@wire.split_child_session_id` names its parent, the side chat.
pub fn split_side_chat_id(id : String) -> String? {
  guard id.rev_find(SideChatMarker) is Some(start) && start > 0 else {
    return None
  }
  let token = id[start + SideChatMarker.length():]
  guard token.length() == SideChatTokenLength &&
    token.all(c => c is ('0'..<='9' | 'a'..<='f')) else {
    return None
  }
  Some(id[:start].to_owned())
}

///|
/// The conversation that `id` sits beside, when `id` is a side chat or a
/// record of one (a side chat's own sub-run), or `None` for any other
/// session. Such a record is never a conversation of its own: it shows in the
/// dock beside that conversation, not in a list of conversations.
pub fn side_chat_parent(id : String) -> String? {
  let mut current = id
  for ;; {
    if split_side_chat_id(current) is Some(parent) {
      return Some(parent)
    }
    guard @wire.split_child_session_id(current) is Some((parent, _)) else {
      return None
    }
    current = parent
  }
}
