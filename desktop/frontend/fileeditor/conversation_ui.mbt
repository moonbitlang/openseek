///|
/// User choices only. Host requests, watcher generations and checkout caches
/// are reconciled afresh, never resurrected from a parked conversation.
struct ConversationUiState {
  mbti_view_modes : Map[@common.Uri, MbtiViewMode]
  moon_mod_view_modes : Map[@common.Uri, MoonModViewMode]
  tree_open : Bool
  mode : ExplorerMode
  search : @grep_search.State
  expanded : Array[@pathx.Relative]
  tree_focus : @pathx.Relative?
  change_extensions : Array[String?]?
  change_path_filter : String
  change_tree_collapsed : Array[@pathx.Relative]
  changes_collapsed : Bool
  git_graph_collapsed : Bool
} derive(Eq)

///|
fn ConversationUiState::empty() -> ConversationUiState {
  {
    mbti_view_modes: Map([]),
    moon_mod_view_modes: Map([]),
    tree_open: true,
    mode: ExplorerFiles,
    search: @grep_search.State::empty(),
    expanded: [],
    tree_focus: None,
    change_extensions: None,
    change_path_filter: "",
    change_tree_collapsed: [],
    changes_collapsed: false,
    git_graph_collapsed: false,
  }
}

///|
fn State::sidebar_state(self : State) -> ConversationUiState {
  {
    mbti_view_modes: self.mbti_view_modes,
    moon_mod_view_modes: self.moon_mod_view_modes,
    tree_open: self.tree_open,
    mode: self.explorer_mode,
    search: self.search.restore_query(self.search),
    expanded: self.expanded,
    tree_focus: self.tree_focus,
    change_extensions: self.change_extensions,
    change_path_filter: self.change_path_filter,
    change_tree_collapsed: self.change_tree_collapsed,
    changes_collapsed: self.changes_collapsed,
    git_graph_collapsed: self.git_graph_collapsed,
  }
}

///|
fn State::with_sidebar(self : State, ui : ConversationUiState) -> State {
  {
    ..self,
    mbti_view_modes: ui.mbti_view_modes,
    moon_mod_view_modes: ui.moon_mod_view_modes,
    tree_open: ui.tree_open,
    explorer_mode: ui.mode,
    search: self.search.restore_query(ui.search),
    expanded: ui.expanded,
    tree_focus: ui.tree_focus,
    change_extensions: ui.change_extensions,
    change_path_filter: ui.change_path_filter,
    change_tree_collapsed: ui.change_tree_collapsed,
    changes_collapsed: ui.changes_collapsed,
    git_graph_collapsed: ui.git_graph_collapsed,
  }
}

///|
fn State::restore_ui(self : State, owner : @interop.ConversationKey) -> State {
  guard self.owner != Some(owner) else { return self }
  guard self.owner is Some(previous) else { return self }
  let remembered_ui = self.remembered_ui.copy()
  remembered_ui[previous] = self.sidebar_state()
  let saved = remembered_ui.get(owner).unwrap_or(ConversationUiState::empty())
  { ..self, remembered_ui, }.with_sidebar(saved)
}

///|
pub extend ConversationUiState with Eq::{equal, not_equal}
