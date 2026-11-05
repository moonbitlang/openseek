///|
/// Fired after a resource's feedback collection changes.
#derive(Debug)
pub(all) struct AgentFeedbackChangeEvent {
  resource : @base_common.Uri
  feedback_items : Array[AgentFeedback]
}

///|
/// The position of a navigation anchor in a caller-supplied item order.
/// `active_idx` is `-1` when no live anchor exists.
#derive(Eq, Debug)
pub(all) struct AgentFeedbackNavigationBearing {
  active_idx : Int32
  total_count : Int32
}

///|
pub extend AgentFeedbackChangeEvent with Debug::{to_repr}

///|
pub extend AgentFeedbackNavigationBearing with Debug::{to_repr}

///|
pub extend AgentFeedbackNavigationBearing with Eq::{equal, not_equal}
