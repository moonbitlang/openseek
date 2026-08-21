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
struct Page {
  mode : Mode
  query : String
  regex : Bool
  case_sensitive : Bool
  whole_word : Bool
  details_open : Bool
  include_glob : String
  exclude_glob : String
  // Semantic-mode settings. `rules_dir` points at a moongrep YAML rules
  // directory; `use_builtin_rules` enables moongrep's embedded rules.
  rules_dir : String
  use_builtin_rules : Bool
  matches : Array[@protocol.TextSearchMatch]
  semantic_hits : Array[@protocol.SemanticSearchHit]
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
  ModeChanged(Mode)
  ToggleCaseSensitive
  ToggleWholeWord
  ToggleRegex
  ToggleDetails
  IncludeChanged(String)
  ExcludeChanged(String)
  // Semantic-mode settings, mirroring the text-mode toggles.
  RulesDirChanged(String)
  ToggleBuiltinRules
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
  SemanticLoaded(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int,
    reply~ : @protocol.SearchSemanticReply
  )
  RequestFailed(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int,
    code~ : String,
    message~ : String
  )
}
