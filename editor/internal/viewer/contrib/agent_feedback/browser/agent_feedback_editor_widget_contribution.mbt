///|
/// The per-editor state of `AgentFeedbackEditorWidgetContribution`
/// (`agentFeedbackEditorWidgetContribution.ts:1034-1311`), owned by the
/// Viewer's central contribution entry. The `Viewer::` glue in
/// `agent_feedback_widgets_host.mbt` keeps the rebuild/layout role and
/// reads/writes state here through a typed central accessor. Field names follow
/// the source; the widget id pool and the highlight id array are glue-side
/// bookkeeping kept from the port.
pub(all) struct AgentFeedbackEditorWidgetContribution {
  /// `_widgets`: the mounted bubbles.
  widgets : Array[AgentFeedbackEditorWidget]
  /// `_replyDraftState`: reply drafts surviving rebuilds, by comment id.
  reply_drafts : Map[String, String]
  /// The overlay-widget id pool for mounted bubbles.
  mut widget_id_pool : Int32
  /// The item-hover range highlight (`_highlightRange`), as owner-scoped
  /// decoration ids.
  mut highlight_decoration_ids : Array[String]
}

///|
/// Constructs the bare state stored by one central contribution entry.
pub fn AgentFeedbackEditorWidgetContribution::AgentFeedbackEditorWidgetContribution() -> AgentFeedbackEditorWidgetContribution {
  {
    widgets: [],
    reply_drafts: Map([]),
    widget_id_pool: 1,
    highlight_decoration_ids: [],
  }
}

///|
/// Drops the per-model decoration bookkeeping on a model swap: the
/// range-highlight ids belong to the outgoing model's storage.
pub fn AgentFeedbackEditorWidgetContribution::reset_model_state(
  self : AgentFeedbackEditorWidgetContribution,
) -> Unit {
  self.highlight_decoration_ids = []
}
