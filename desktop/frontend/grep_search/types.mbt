// Workspace Search is one file-editor Explorer inventory. This package owns
// its query reducer, request, and view; fileeditor owns the active checkout and
// resets the inventory at the same owner/root boundaries as Files and Changes.

///|
/// Keep the initial DOM comfortably below the Host's 20,000-occurrence result
/// ceiling. The full reply and counts stay available; users reveal additional
/// matching lines explicitly instead of constructing tens of thousands of
/// nodes in one render.
const InitialVisibleSearchLines : Int = 500

///|
const VisibleSearchLineStep : Int = 500

///|
enum Phase {
  Idle
  Debouncing
  Loading
  Ready
  Failed(code~ : String, message~ : String)
} derive(Eq, Debug)

///|
struct Page {
  query : String
  regex : Bool
  case_sensitive : Bool
  whole_word : Bool
  details_open : Bool
  include_glob : String
  exclude_glob : String
  matches : Array[@protocol.TextSearchMatch]
  match_count : Int
  file_count : Int
  limit_hit : Bool
  collapsed : Map[String, Bool]
  visible_lines : Int
  phase : Phase
  generation : Int
  delay_ms : Int
} derive(Eq)

///|
pub struct State {
  priv page : Page
  priv generation : Int
} derive(Eq)

///|
pub fn State::empty() -> State {
  { page: fresh_page(), generation: 0 }
}

///|
pub(all) struct Input {
  owner : @interop.ConversationKey
  root : @common.Uri?
} derive(Eq)

///|
pub fn Input::Input(
  owner~ : @interop.ConversationKey,
  root~ : @common.Uri?,
) -> Input {
  { owner, root }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  ToggleCaseSensitive
  ToggleWholeWord
  ToggleRegex
  ToggleDetails
  IncludeChanged(String)
  ExcludeChanged(String)
  Submit
  Refresh
  ClearResults
  CollapseAll
  ShowMore
  ToggleFile(String)
  RequestStarted(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int
  )
  Loaded(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int,
    reply~ : @protocol.SearchTextReply
  )
  RequestFailed(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int,
    code~ : String,
    message~ : String
  )
}
