// Host-facing agent-feedback values shared by custom backings and the
// concrete contribution service. The model is ported from
// `vscode/src/vs/sessions/contrib/agentFeedback/browser/agentFeedbackModel.ts`
// and `agentFeedbackService.ts`, trimmed to the viewer's file-scoped store.

///|
/// The origin of a feedback item. The upstream `PRReview` case is absent
/// because the viewer has no pull-request machinery.
#derive(Eq, Debug)
pub(all) enum AgentFeedbackKind {
  UserReview
  AgentReview
}

///|
/// Lifecycle state for one feedback item.
#derive(Eq, Debug)
pub(all) enum AgentFeedbackState {
  Created
  Accepted
  Submitted
  Resolved
}

///|
/// One file-scoped feedback item. `range` is expressed in model coordinates;
/// mutations replace the stored value so change events remain observable.
/// `selected_text` preserves the user's rendered selection when it differs
/// from that source range. Markdown image-only selections capture their mapped
/// source instead. `None` means no snapshot was supplied; hosts may use source
/// context when a supplied snapshot has no visible text.
#derive(Debug)
pub(all) struct AgentFeedback {
  id : String
  text : String
  resource : @base_common.Uri
  range : @base_common.Range
  selected_text : String?
  kind : AgentFeedbackKind
  replies : Array[String]
  state : AgentFeedbackState
}

///|
pub extend AgentFeedback with Debug::{to_repr}

///|
pub extend AgentFeedbackKind with Debug::{to_repr}

///|
pub extend AgentFeedbackKind with Eq::{equal, not_equal}

///|
pub extend AgentFeedbackState with Debug::{to_repr}

///|
pub extend AgentFeedbackState with Eq::{equal, not_equal}
