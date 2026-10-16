///|
/// UI ownership is independent of the host transport. Cloud conversations
/// have an account and session, but no device or local filesystem host.
pub(all) enum ConversationIdentity {
  Host(ConversationKey)
  Cloud(account~ : String, session~ : String)
} derive(Eq, Hash, Debug)

///|
pub fn ConversationIdentity::host(
  self : ConversationIdentity,
) -> ConversationKey? {
  match self {
    Host(key) => Some(key)
    Cloud(..) => None
  }
}

///|
pub fn ConversationIdentity::session(self : ConversationIdentity) -> String {
  match self {
    Host(key) => key.session
    Cloud(session~, ..) => session
  }
}

///|
pub fn ConversationIdentity::key(self : ConversationIdentity) -> String {
  match self {
    Host(key) => "host:\{key.channel.uri_authority()}:\{key.session}"
    Cloud(account~, session~) =>
      "cloud:\{account.length()}:\{account}:\{session}"
  }
}

///|
pub extend ConversationIdentity with Eq::{equal, not_equal}

///|
pub extend ConversationIdentity with Hash::{hash, hash_combine}

///|
pub extend ConversationIdentity with Debug::{to_repr}
