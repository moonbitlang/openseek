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
/// The inventory's lifecycle. `Debouncing` and `Loading` carry the UUID of
/// the one Host request the page waits for, so leaving either arm is itself
/// the staleness fence: a reply naming a retired UUID finds no arm to settle.
enum Phase {
  Idle
  Debouncing(request_id~ : String)
  Loading(request_id~ : String)
  Ready
  Failed(code~ : String, message~ : String)
} derive(Eq, Debug)

///|
fn Phase::request_id(self : Phase) -> String? {
  match self {
    Debouncing(request_id~) | Loading(request_id~) => Some(request_id)
    Idle | Ready | Failed(..) => None
  }
}

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
struct State {
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
pub fn State::empty() -> State {
  {
    mode: Text,
    text: {
      query: "",
      regex: false,
      case_sensitive: false,
      whole_word: false,
      matches: [],
    },
    semantic: { patterns: [""], hits: [], partial: false, },
    details_open: false,
    include_glob: "",
    exclude_glob: "",
    match_count: 0,
    file_count: 0,
    limit_hit: false,
    collapsed: Map([]),
    visible_lines: InitialVisibleSearchLines,
    phase: Idle,
  }
}

///|
/// The UUID this page is waiting for, or `None` when nothing is armed.
/// Exposed so the owning file-editor package can drive the inventory through
/// its public messages.
pub fn State::pending_request_id(self : State) -> String? {
  self.phase.request_id()
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
  Loaded(reply~ : @protocol.SearchTextReply)
  SemanticLoaded(reply~ : @protocol.SearchSemanticReply)
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
