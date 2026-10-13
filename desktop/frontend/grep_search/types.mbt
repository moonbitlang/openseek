// Workspace Search is one file-editor Explorer inventory. This package owns
// its query reducer, request, and view; fileeditor owns the active checkout and
// resets the inventory at the same owner/root boundaries as Files and Changes.

///|
/// Keep the initial DOM comfortably below the Host's 20,000-occurrence result
/// ceiling. The full reply and counts stay available; users reveal additional
/// matching lines explicitly instead of constructing tens of thousands of
/// nodes in one render.
const InitialVisibleSearchLines : Int32 = 500

///|
const VisibleSearchLineStep : Int32 = 500

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
enum PatternRepairPhase {
  PatternRepairIdle
  PatternRepairRequested
  PatternRepairInputRequired
  PatternRepairUnavailable
  PatternRepairTimedOut
  PatternRepairValidationFailed
  PatternRepairFailed
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
  match_count : Int32
  file_count : Int32
  limit_hit : Bool
} derive(Eq)

///|
pub(all) enum SemanticResultFilter {
  AllSemanticResults
  SelectedSemanticResults
} derive(Eq, Debug)

///|
struct Page {
  mode : Mode
  text : TextSearchState
  semantic : SemanticSearchState
  details_open : Bool
  include_glob : String
  exclude_glob : String
  match_count : Int32
  file_count : Int32
  limit_hit : Bool
  collapsed : Map[String, Bool]
  // Copy before changing membership so earlier state snapshots stay intact.
  selected : Set[String]
  semantic_selection_revision : Int32
  semantic_filter : SemanticResultFilter
  visible_lines : Int32
  phase : Phase
  pattern_repair_phase : PatternRepairPhase
  pattern_repair_message : String?
  /// A rejected candidate is retained for diagnosis, but is never applied to
  /// the active semantic pattern.
  pattern_repair_candidate : String?
  pattern_repair_trace : Array[String]
  generation : Int32
  delay_ms : Int32
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
struct State {
  page : Page
  generation : Int32
} derive(Eq)

///|
pub fn State::empty() -> State {
  { page: fresh_page(), generation: 0, }
}

///|
/// The semantic hits currently selected in the Search explorer as one
/// composer mention, or `None` when nothing is selected.
pub fn State::selected_semantic_reference(
  self : State,
  root : String,
) -> @mention_context.SemanticSearchReference? {
  let page = self.page
  let matches = selected_semantic_hits(page.semantic.hits, page.selected)
  guard !matches.is_empty() else { return None }
  let patterns = page.semantic.patterns.filter(pattern => {
    !pattern.trim().is_empty()
  })
  Some({
    // The root is payload data; keeping it out of the snapshot id avoids
    // serializing the same absolute path twice in the mention envelope.
    id: "semantic-search-\{page.generation}-\{page.semantic_selection_revision}",
    root,
    patterns,
    include_glob: page.include_glob,
    exclude_glob: page.exclude_glob,
    matches: matches.map(hit => {
      rule_id: hit.rule_id,
      description: hit.description,
      file: hit.path,
      start_line: hit.start_line,
      start_column: hit.start_column,
      end_line: hit.end_line,
      end_column: hit.end_column,
      matched_source: hit.matched_source,
    }),
  })
}

///|
pub(all) struct Input {
  model : String
  thinking : @protocol.OpenSeekThinking?
  owner : @interop.ConversationKey
  root : @common.Uri?
} derive(Eq)

///|
pub fn Input::Input(
  model~ : String,
  thinking~ : @protocol.OpenSeekThinking?,
  owner~ : @interop.ConversationKey,
  root~ : @common.Uri?,
) -> Input {
  { owner, root, model, thinking, }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  ModeChanged(Mode)
  ToggleCaseSensitive
  ToggleWholeWord
  ToggleRegex
  ToggleDetails
  FixPattern
  PatternRepairFinished(
    root~ : String,
    generation~ : Int32,
    reply~ : @protocol.PatternRepairReply?
  )
  IncludeChanged(String)
  ExcludeChanged(String)
  // Semantic-mode settings, mirroring the text-mode toggles.
  PatternChanged(Int32, String)
  AddPattern
  RemovePattern(Int32)
  Submit
  Refresh
  ClearResults
  CollapseAll
  ClearSelection
  ShowMore
  ToggleFile(String)
  ToggleSemanticHit(String)
  // A pattern group, or one file within it.
  ToggleSemanticGroup(pattern~ : String, path~ : String?)
  SetSemanticResultFilter(SemanticResultFilter)
  RequestStarted(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int32
  )
  Loaded(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int32,
    reply~ : @protocol.SearchTextReply
  )
  SemanticLoaded(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int32,
    reply~ : @protocol.SearchSemanticReply
  )
  // One partial batch of a semantic search still in flight. The Host pushes
  // these through the notification channel so a long scan paints hits early;
  // the final `SemanticLoaded` reply replaces them. The session_key/generation
  // pair fences the stream exactly like the reply does.
  SemanticProgress(
    root~ : String,
    session_key~ : String,
    generation~ : Int32,
    matches~ : Array[@protocol.SemanticSearchHit],
    match_count~ : Int32,
    file_count~ : Int32
  )
  RequestFailed(
    owner~ : @interop.ConversationKey,
    root~ : String,
    generation~ : Int32,
    code~ : String,
    message~ : String
  )
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
pub extend SemanticResultFilter with Eq::{equal, not_equal}

///|
pub extend SemanticResultFilter with Debug::{to_repr}

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
pub extend PatternRepairPhase with Debug::{to_repr}

///|
pub extend PatternRepairPhase with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend TextSearchState with Eq::{equal, not_equal}
