// Host-facing agent-feedback payloads. Neither has a production consumer in
// this repository, so both live here rather than beside the generic handle
// events: the visibility is owed to hosts outside the repository, and a
// future API-narrowing pass reading only in-repo call sites would otherwise
// read them as dead surface and remove them.

///|
/// Fired when a brand-new feedback item enters the accepted state. A host that
/// runs its own feedback store publishes this from its own emitter, so it
/// needs the payload without consuming the viewer's service — which is why
/// this is a shared contract while the reply notification stays private to
/// the concrete service. `moonbitlang/openseek` consumes it.
pub(all) struct AgentFeedbackAddedEvent {
  feedback : AgentFeedback
  has_existing_feedback_for_file : Bool
} derive(Debug)

///|
/// Accepted feedback submitted for one resource, including host-forwardable
/// items and the per-kind/reply counts.
pub(all) struct AgentFeedbackSubmittedEvent {
  resource : @base_common.Uri
  items : Array[AgentFeedback]
  user_count : Int
  agent_review_count : Int
  reply_count : Int
} derive(Debug)

///|
pub extend AgentFeedbackAddedEvent with Debug::{to_repr}

///|
pub extend AgentFeedbackSubmittedEvent with Debug::{to_repr}
