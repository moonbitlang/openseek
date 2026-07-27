// Desktop owns the feedback state handed to the embedded Viewer. This mutable
// store is imperative widget state, like the Viewer itself: it deliberately
// stays outside the Rabbita model so update remains pure and old model
// snapshots cannot observe later mutations.

///|
/// The Desktop-owned backing for the public agent-feedback capability consumed
/// by the Viewer. The Viewer sees only `AgentFeedbackHandle`; Desktop keeps the
/// concrete store so it can enable comments and turn accepted user feedback
/// into composer chips.
struct DesktopFeedbackService {
  did_change_feedback : @common.Emitter[
    @agent_feedback_api.AgentFeedbackChangeEvent,
  ]
  did_change_navigation : @common.Emitter[@common.Uri]
  did_add_feedback : @common.Emitter[
    @agent_feedback_api.AgentFeedbackAddedEvent,
  ]
  items_by_resource : Map[String, Array[@agent_feedback_api.AgentFeedback]]
  navigation_anchor_by_resource : Map[String, String]
  enabled_resources : Map[String, Bool]
  mut next_feedback_handle : Int
}

///|
pub fn DesktopFeedbackService::DesktopFeedbackService() -> DesktopFeedbackService {
  {
    did_change_feedback: @common.Emitter(),
    did_change_navigation: @common.Emitter(),
    did_add_feedback: @common.Emitter(),
    items_by_resource: Map([]),
    navigation_anchor_by_resource: Map([]),
    enabled_resources: Map([]),
    next_feedback_handle: 1,
  }
}

///|
/// Projects this store into the callback-only contract used by the Viewer.
pub fn DesktopFeedbackService::agent_feedback_handle(
  self : DesktopFeedbackService,
) -> @agent_feedback_api.AgentFeedbackHandle {
  @agent_feedback_api.AgentFeedbackHandle(
    on_did_change_feedback=listener => self.did_change_feedback.event(listener),
    on_did_change_navigation=listener => {
      self.did_change_navigation.event(listener)
    },
    is_feedback_enabled=resource => self.is_feedback_enabled(resource),
    get_feedback=resource => self.get_feedback(resource),
    get_navigation_bearing=(resource, item_ids) => {
      self.get_navigation_bearing(resource, item_ids)
    },
    add_feedback=(resource, range, text, kind, state) => {
      self.add_feedback(resource, range, text, kind?, state?)
    },
    mark_feedback_submitted=resource => self.mark_feedback_submitted(resource),
    remove_feedback=(resource, feedback_id) => {
      self.remove_feedback(resource, feedback_id)
    },
    accept_feedback=(resource, feedback_id) => {
      self.accept_feedback(resource, feedback_id)
    },
    set_navigation_anchor=(resource, item_id) => {
      self.set_navigation_anchor(resource, item_id)
    },
    update_feedback=(resource, feedback_id, new_text) => {
      self.update_feedback(resource, feedback_id, new_text)
    },
    add_reply=(resource, feedback_id, reply_text) => {
      self.add_reply(resource, feedback_id, reply_text)
    },
  )
}

///|
/// Subscribes to newly accepted feedback. This host-only event is intentionally
/// separate from `AgentFeedbackHandle`: the Viewer consumes the handle while
/// Desktop turns the accepted item into a composer chip.
pub fn DesktopFeedbackService::on_did_add_feedback(
  self : DesktopFeedbackService,
  listener : (@agent_feedback_api.AgentFeedbackAddedEvent) -> Unit,
) -> @common.Disposable {
  self.did_add_feedback.event(listener)
}

///|
/// Notifies the Viewer after any stored feedback mutation.
fn DesktopFeedbackService::handle_items_changed(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Unit {
  self.did_change_feedback.fire({
    resource,
    feedback_items: self.get_feedback(resource),
  })
  self.did_change_navigation.fire(resource)
}

///|
/// Returns the live array owned by this store, creating it on first mutation.
fn DesktopFeedbackService::items_for(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Array[@agent_feedback_api.AgentFeedback] {
  let key = resource.to_string()
  if self.items_by_resource.get(key) is Some(items) {
    items
  } else {
    let created : Array[@agent_feedback_api.AgentFeedback] = []
    self.items_by_resource.set(key, created)
    created
  }
}

///|
/// Replaces one existing feedback value and publishes the new collection.
fn DesktopFeedbackService::replace_item(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  updated : @agent_feedback_api.AgentFeedback,
) -> Unit {
  let items = self.items_for(resource)
  if items.search_by(item => item.id == updated.id) is Some(index) {
    items[index] = updated
    self.handle_items_changed(resource)
  }
}

///|
/// Enables or disables feedback controls for one document.
pub fn DesktopFeedbackService::set_feedback_enabled(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  enabled : Bool,
) -> Unit {
  let key = resource.to_string()
  if self.is_feedback_enabled(resource) == enabled {
    return
  }
  if enabled {
    self.enabled_resources.set(key, true)
  } else {
    self.enabled_resources.remove(key)
  }
  self.handle_items_changed(resource)
}

///|
fn DesktopFeedbackService::is_feedback_enabled(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Bool {
  self.enabled_resources.get(resource.to_string()).unwrap_or(false)
}

///|
fn DesktopFeedbackService::get_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Array[@agent_feedback_api.AgentFeedback] {
  self.items_by_resource.get(resource.to_string()).unwrap_or([])
}

///|
/// Removes every displayed item and navigation anchor for one document.
pub fn DesktopFeedbackService::clear_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Unit {
  let key = resource.to_string()
  self.navigation_anchor_by_resource.remove(key)
  self.items_by_resource.remove(key)
  self.handle_items_changed(resource)
}

///|
/// Adds one feedback item. Accepted user feedback fires the Desktop-only event
/// that creates a composer chip; staged annotations use `Submitted` and do not.
pub fn DesktopFeedbackService::add_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  range : @common.Range,
  text : String,
  kind? : @agent_feedback_api.AgentFeedbackKind = @agent_feedback_api.UserReview,
  state? : @agent_feedback_api.AgentFeedbackState = @agent_feedback_api.Accepted,
) -> @agent_feedback_api.AgentFeedback {
  let feedback : @agent_feedback_api.AgentFeedback = {
    id: "viewer-feedback-" + self.next_feedback_handle.to_string(),
    text,
    resource,
    range,
    kind,
    replies: [],
    state,
  }
  self.next_feedback_handle += 1
  let items = self.items_for(resource)
  let has_existing_for_file = !items.is_empty()
  items.push(feedback)
  self.handle_items_changed(resource)
  if state == @agent_feedback_api.Accepted {
    self.did_add_feedback.fire({
      feedback,
      has_existing_feedback_for_file: has_existing_for_file,
    })
  }
  feedback
}

///|
/// Accepts one newly created feedback item.
fn DesktopFeedbackService::accept_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  feedback_id : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  guard existing.state == @agent_feedback_api.Created else { return }
  let updated : @agent_feedback_api.AgentFeedback = {
    ..existing,
    state: @agent_feedback_api.Accepted,
  }
  self.replace_item(resource, updated)
}

///|
/// Removes one feedback item and any navigation anchor that points to it.
pub fn DesktopFeedbackService::remove_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  feedback_id : String,
) -> Unit {
  let key = resource.to_string()
  if self.navigation_anchor_by_resource.get(key) is Some(anchor) &&
    (anchor == feedback_id || anchor == "agentFeedback:" + feedback_id) {
    self.navigation_anchor_by_resource.remove(key)
  }
  let items = self.items_for(resource)
  if items.search_by(item => item.id == feedback_id) is Some(index) {
    items.remove(index) |> ignore
    if items.is_empty() {
      self.items_by_resource.remove(key)
    }
    self.handle_items_changed(resource)
  }
}

///|
/// Replaces the text of one existing feedback item.
fn DesktopFeedbackService::update_feedback(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  feedback_id : String,
  new_text : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  self.replace_item(resource, { ..existing, text: new_text })
}

///|
/// Appends one reply while preserving prior snapshots of the feedback value.
fn DesktopFeedbackService::add_reply(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  feedback_id : String,
  reply_text : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  let replies = existing.replies.copy()
  replies.push(reply_text)
  self.replace_item(resource, { ..existing, replies, })
}

///|
/// Moves every accepted item to submitted after the Viewer completes its local
/// submission flow.
fn DesktopFeedbackService::mark_feedback_submitted(
  self : DesktopFeedbackService,
  resource : @common.Uri,
) -> Unit {
  let items = self.items_for(resource)
  let mut changed = false
  for index, item in items {
    if item.state == @agent_feedback_api.Accepted {
      items[index] = { ..item, state: @agent_feedback_api.Submitted }
      changed = true
    }
  }
  if changed {
    self.handle_items_changed(resource)
  }
}

///|
fn DesktopFeedbackService::feedback_by_id(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  feedback_id : String,
) -> @agent_feedback_api.AgentFeedback? {
  let items = self.get_feedback(resource)
  items.search_by(item => item.id == feedback_id).map(index => items[index])
}

///|
/// Moves or clears the comment-navigation anchor.
fn DesktopFeedbackService::set_navigation_anchor(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  item_id : String?,
) -> Unit {
  let key = resource.to_string()
  if item_id is Some(id) {
    self.navigation_anchor_by_resource.set(key, id)
  } else {
    self.navigation_anchor_by_resource.remove(key)
  }
  self.did_change_navigation.fire(resource)
}

///|
/// Reports the current anchor's position in the Viewer's visible item order.
fn DesktopFeedbackService::get_navigation_bearing(
  self : DesktopFeedbackService,
  resource : @common.Uri,
  item_ids : Array[String],
) -> @agent_feedback_api.AgentFeedbackNavigationBearing {
  let active_idx = self.navigation_anchor_by_resource
    .get(resource.to_string())
    .map(anchor => item_ids.search_by(id => id == anchor).unwrap_or(-1))
    .unwrap_or(-1)
  { active_idx, total_count: item_ids.length() }
}
