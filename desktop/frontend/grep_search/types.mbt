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
/// One of the two Search engines, modeled on semgrep's search modes: plain
/// text search runs the Host's bundled ripgrep; semantic search runs
/// moongrep's structural MoonBit code patterns.
enum Mode {
  Text
  Semantic
} derive(Eq, Debug)

///|
struct TextSearchState {
  query : String
  regex : Bool
  case_sensitive : Bool
  whole_word : Bool
  matches : Array[@protocol.TextSearchMatch]
} derive(Eq)

///|
struct SemanticSearchState {
  patterns : Array[String]
  hits : Array[@protocol.SemanticSearchHit]
  partial : Bool
} derive(Eq)

///|
struct SearchResultSummary {
  match_count : Int
  file_count : Int
  limit_hit : Bool
} derive(Eq)

///|
struct Page {
  mode : Mode
  text : TextSearchState
  semantic : SemanticSearchState
  details_open : Bool
  include_glob : String
  exclude_glob : String
  match_count : Int
  file_count : Int
  limit_hit : Bool
  collapsed : Map[String, Bool]
  visible_lines : Int
  phase : Phase
  request_id : String
  delay_ms : Int
} derive(Eq)

///|
/// The workspace-search matches that belong on one open editor model. The
/// ranges are the complete retained result set for the file.
struct EditorHighlights {
  ranges : Array[@common.Range]
} derive(Eq, Debug)

///|
pub fn EditorHighlights::ranges(
  self : EditorHighlights,
) -> Array[@common.Range] {
  self.ranges
}

///|
pub struct State {
  priv page : Page
} derive(Eq)

///|
pub fn State::empty() -> State {
  { page: Page::fresh(@uuid.mint()) }
}

///|
/// Expose the current request UUID to the owning file-editor package. Replies
/// use this UUID directly, without echoing the conversation or checkout root.
pub fn State::request_id(self : State) -> String {
  self.page.request_id
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
  { owner, root, }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  ModeChanged(Mode)
  ToggleCaseSensitive
  ToggleWholeWord
  ToggleRegex
  ToggleDetails
  IncludeChanged(String)
  ExcludeChanged(String)
  // Semantic-mode settings, mirroring the text-mode toggles.
  PatternChanged(Int, String)
  AddPattern
  RemovePattern(Int)
  Submit
  Refresh
  ClearResults
  CollapseAll
  ShowMore
  ToggleFile(String)
  RequestStarted(request_id~ : String)
  Loaded(request_id~ : String, reply~ : @protocol.SearchTextReply)
  SemanticLoaded(request_id~ : String, reply~ : @protocol.SearchSemanticReply)
  // One partial batch of a semantic search still in flight. The Host pushes
  // these through the notification channel so a long scan paints hits early;
  // the final `SemanticLoaded` reply replaces them. The request UUID fences
  // the stream exactly like the reply does.
  SemanticProgress(
    request_id~ : String,
    matches~ : Array[@protocol.SemanticSearchHit],
    match_count~ : Int,
    file_count~ : Int
  )
  RequestFailed(request_id~ : String, code~ : String, message~ : String)
}

///|
pub extend EditorHighlights with Debug::{to_repr}

///|
pub extend EditorHighlights with Eq::{equal, not_equal}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Mode with Debug::{to_repr}

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub extend Page with Eq::{equal, not_equal}

///|
pub extend Phase with Debug::{to_repr}

///|
pub extend Phase with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend SearchResultSummary with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend SemanticSearchState with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend TextSearchState with Eq::{equal, not_equal}
