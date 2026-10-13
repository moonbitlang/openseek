///|
/// Fired after a resource's feedback collection changes.
pub(all) struct AgentFeedbackChangeEvent {
  resource : @base_common.Uri
  feedback_items : Array[AgentFeedback]
} derive(Debug)

///|
/// The position of a navigation anchor in a caller-supplied item order.
/// `active_idx` is `-1` when no live anchor exists.
pub(all) struct AgentFeedbackNavigationBearing {
  active_idx : Int32
  total_count : Int32
} derive(Eq, Debug)

///|
pub extend AgentFeedbackChangeEvent with Debug::{to_repr}

///|
pub extend AgentFeedbackNavigationBearing with Debug::{to_repr}

///|
pub extend AgentFeedbackNavigationBearing with Eq::{equal, not_equal}
