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
  active_idx : Int
  total_count : Int
} derive(Eq, Debug)

///|
#deprecated
pub extend AgentFeedbackChangeEvent with Debug::{to_repr}

///|
#deprecated
pub extend AgentFeedbackNavigationBearing with Debug::{to_repr}

///|
pub extend AgentFeedbackNavigationBearing with Eq::{equal, not_equal}
