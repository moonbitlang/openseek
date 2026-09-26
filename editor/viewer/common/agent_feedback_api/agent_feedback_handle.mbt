///|
/// Minimal host/contribution capability boundary for agent feedback. The
/// handle owns no backing state; every callback is supplied by its creator.
struct AgentFeedbackHandle {
  on_did_change_feedback_callback : ((AgentFeedbackChangeEvent) -> Unit) -> @base_common.Disposable
  on_did_change_navigation_callback : ((@base_common.Uri) -> Unit) -> @base_common.Disposable
  is_feedback_enabled_callback : (@base_common.Uri) -> Bool
  get_feedback_callback : (@base_common.Uri) -> Array[AgentFeedback]
  get_navigation_bearing_callback : (@base_common.Uri, Array[String]) -> AgentFeedbackNavigationBearing
  add_feedback_callback : (
    @base_common.Uri,
    @base_common.Range,
    String,
    AgentFeedbackKind?,
    AgentFeedbackState?,
    String?,
  ) -> AgentFeedback
  mark_feedback_submitted_callback : (@base_common.Uri) -> Unit
  remove_feedback_callback : (@base_common.Uri, String) -> Unit
  accept_feedback_callback : (@base_common.Uri, String) -> Unit
  set_navigation_anchor_callback : (@base_common.Uri, String?) -> Unit
  update_feedback_callback : (@base_common.Uri, String, String) -> Unit
  add_reply_callback : (@base_common.Uri, String, String) -> Unit
}

///|
/// Constructs a handle from the complete required callback floor. Captured
/// backing state and its lifecycle remain owned by the caller.
pub fn AgentFeedbackHandle::AgentFeedbackHandle(
  on_did_change_feedback~ : ((AgentFeedbackChangeEvent) -> Unit) -> @base_common.Disposable,
  on_did_change_navigation~ : ((@base_common.Uri) -> Unit) -> @base_common.Disposable,
  is_feedback_enabled~ : (@base_common.Uri) -> Bool,
  get_feedback~ : (@base_common.Uri) -> Array[AgentFeedback],
  get_navigation_bearing~ : (@base_common.Uri, Array[String]) -> AgentFeedbackNavigationBearing,
  add_feedback~ : (
    @base_common.Uri,
    @base_common.Range,
    String,
    AgentFeedbackKind?,
    AgentFeedbackState?,
    String?,
  ) -> AgentFeedback,
  mark_feedback_submitted~ : (@base_common.Uri) -> Unit,
  remove_feedback~ : (@base_common.Uri, String) -> Unit,
  accept_feedback~ : (@base_common.Uri, String) -> Unit,
  set_navigation_anchor~ : (@base_common.Uri, String?) -> Unit,
  update_feedback~ : (@base_common.Uri, String, String) -> Unit,
  add_reply~ : (@base_common.Uri, String, String) -> Unit,
) -> AgentFeedbackHandle {
  {
    on_did_change_feedback_callback: on_did_change_feedback,
    on_did_change_navigation_callback: on_did_change_navigation,
    is_feedback_enabled_callback: is_feedback_enabled,
    get_feedback_callback: get_feedback,
    get_navigation_bearing_callback: get_navigation_bearing,
    add_feedback_callback: add_feedback,
    mark_feedback_submitted_callback: mark_feedback_submitted,
    remove_feedback_callback: remove_feedback,
    accept_feedback_callback: accept_feedback,
    set_navigation_anchor_callback: set_navigation_anchor,
    update_feedback_callback: update_feedback,
    add_reply_callback: add_reply,
  }
}

///|
pub fn AgentFeedbackHandle::on_did_change_feedback(
  self : AgentFeedbackHandle,
  listener : (AgentFeedbackChangeEvent) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_feedback_callback)(listener)
}

///|
pub fn AgentFeedbackHandle::on_did_change_navigation(
  self : AgentFeedbackHandle,
  listener : (@base_common.Uri) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_navigation_callback)(listener)
}

///|
pub fn AgentFeedbackHandle::is_feedback_enabled(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
) -> Bool {
  (self.is_feedback_enabled_callback)(resource)
}

///|
pub fn AgentFeedbackHandle::get_feedback(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
) -> Array[AgentFeedback] {
  (self.get_feedback_callback)(resource)
}

///|
pub fn AgentFeedbackHandle::get_navigation_bearing(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  item_ids : Array[String],
) -> AgentFeedbackNavigationBearing {
  (self.get_navigation_bearing_callback)(resource, item_ids)
}

///|
/// Omitted `kind` and `state` remain `None` at this boundary so the captured
/// backing, rather than the handle, selects their defaults.
/// `selected_text` is forwarded unchanged, including an explicitly empty
/// snapshot, and remains independent of the source range.
pub fn AgentFeedbackHandle::add_feedback(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  range : @base_common.Range,
  text : String,
  kind? : AgentFeedbackKind,
  state? : AgentFeedbackState,
  selected_text? : String,
) -> AgentFeedback {
  (self.add_feedback_callback)(
    resource, range, text, kind, state, selected_text,
  )
}

///|
pub fn AgentFeedbackHandle::mark_feedback_submitted(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
) -> Unit {
  (self.mark_feedback_submitted_callback)(resource)
}

///|
pub fn AgentFeedbackHandle::remove_feedback(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  feedback_id : String,
) -> Unit {
  (self.remove_feedback_callback)(resource, feedback_id)
}

///|
pub fn AgentFeedbackHandle::accept_feedback(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  feedback_id : String,
) -> Unit {
  (self.accept_feedback_callback)(resource, feedback_id)
}

///|
pub fn AgentFeedbackHandle::set_navigation_anchor(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  item_id : String?,
) -> Unit {
  (self.set_navigation_anchor_callback)(resource, item_id)
}

///|
pub fn AgentFeedbackHandle::update_feedback(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  feedback_id : String,
  new_text : String,
) -> Unit {
  (self.update_feedback_callback)(resource, feedback_id, new_text)
}

///|
pub fn AgentFeedbackHandle::add_reply(
  self : AgentFeedbackHandle,
  resource : @base_common.Uri,
  feedback_id : String,
  reply_text : String,
) -> Unit {
  (self.add_reply_callback)(resource, feedback_id, reply_text)
}
