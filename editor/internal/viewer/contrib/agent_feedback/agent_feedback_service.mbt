// The agent-feedback data hub, porting the store/pub-sub role of
// `vscode/src/vs/sessions/contrib/agentFeedback/browser/agentFeedbackService.ts`
// in the `viewer/contrib/comments` service style: items keyed by
// `uri.to_string()` (upstream keys by session resource; the viewer has no
// sessions, so the file resource is the store key), `@base_common.Emitter`
// events, host-facing setters plus contribution-facing mutations. Dropped
// upstream surface: session scoping/`getSessionForFile`, the annotations
// backend (a single in-memory backend remains; the host syncs through
// `set_feedback_items`), PR-review conversion and its events, chat
// attachment/submission plumbing (`submitFeedback` drove the chat widget —
// here `mark_feedback_submitted` flips state and the host reacts to
// `on_did_submit_feedback`), and telemetry-only event payload fields. The
// service is DOM-free, so this package stays multi-target.

///|
/// The agent-feedback store shared by the host app and the viewer's feedback
/// contributions, handed in through `ViewerServices`.
struct AgentFeedbackService {
  did_change_feedback : @base_common.Emitter[
    @agent_feedback_api.AgentFeedbackChangeEvent,
  ]
  did_change_navigation : @base_common.Emitter[@base_common.Uri]
  did_add_feedback : @base_common.Emitter[
    @agent_feedback_api.AgentFeedbackAddedEvent,
  ]
  did_submit_feedback : @base_common.Emitter[
    @agent_feedback_api.AgentFeedbackSubmittedEvent,
  ]
  items_by_resource : Map[String, Array[@agent_feedback_api.AgentFeedback]]
  /// resource key → the item id (an `SessionEditorComment.id`) the prev/next
  /// navigation is anchored on — upstream's `_navigationAnchorBySession`.
  navigation_anchor_by_resource : Map[String, String]
  /// Resources whose editors offer the feedback affordances — the viewer's
  /// stand-in for upstream's `getSessionForFile` scope test (the host knows
  /// which files belong to the session; the viewer only checks membership).
  enabled_resources : Map[String, Bool]
  mut next_feedback_handle : Int
}

///|
/// Creates an empty feedback store.
pub fn AgentFeedbackService::AgentFeedbackService() -> AgentFeedbackService {
  {
    did_change_feedback: Emitter(),
    did_change_navigation: Emitter(),
    did_add_feedback: Emitter(),
    did_submit_feedback: Emitter(),
    items_by_resource: Map([]),
    navigation_anchor_by_resource: Map([]),
    enabled_resources: Map([]),
    next_feedback_handle: 1,
  }
}

///|
pub fn AgentFeedbackService::dispose(self : AgentFeedbackService) -> Unit {
  self.did_change_feedback.dispose()
  self.did_change_navigation.dispose()
  self.did_add_feedback.dispose()
  self.did_submit_feedback.dispose()
}

///|
/// Adapts this concrete store to the dependency-bottom capability consumed by
/// the viewer and its feedback contributions. The service remains caller-owned.
pub fn AgentFeedbackService::agent_feedback_handle(
  self : AgentFeedbackService,
) -> @agent_feedback_api.AgentFeedbackHandle {
  AgentFeedbackHandle(
    on_did_change_feedback=listener => self.on_did_change_feedback(listener),
    on_did_change_navigation=listener => self.on_did_change_navigation(listener),
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

// --- subscriptions -----------------------------------------------------------

///|
/// `onDidChangeFeedback` (`agentFeedbackService.ts`): fired after every store
/// mutation with the resource's full item list.
fn AgentFeedbackService::on_did_change_feedback(
  self : AgentFeedbackService,
  listener : (@agent_feedback_api.AgentFeedbackChangeEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_feedback.event(listener)
}

///|
/// `onDidChangeNavigation`: the navigation anchor moved (also fired after
/// every store mutation, matching upstream's `_handleBackendChange`).
fn AgentFeedbackService::on_did_change_navigation(
  self : AgentFeedbackService,
  listener : (@base_common.Uri) -> Unit,
) -> @base_common.Disposable {
  self.did_change_navigation.event(listener)
}

///|
/// `_handleBackendChange`: re-broadcast the generic feedback + navigation
/// change events after a mutation (the recency ordering upstream maintains
/// here served `getMostRecentSessionForResource`, which is dropped).
fn AgentFeedbackService::handle_items_changed(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
) -> Unit {
  self.did_change_feedback.fire({
    resource,
    feedback_items: self.get_feedback(resource),
  })
  self.did_change_navigation.fire(resource)
}

///|
/// The live per-resource item array, created on demand.
fn AgentFeedbackService::items_for(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
) -> Array[@agent_feedback_api.AgentFeedback] {
  self.items_by_resource.get_or_init(resource.to_string(), () => [])
}

///|
/// `backend.upsert` for an item known to exist: replace-by-id in place.
fn AgentFeedbackService::replace_item(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  updated : @agent_feedback_api.AgentFeedback,
) -> Unit {
  let items = self.items_for(resource)
  if items.search_by(item => item.id == updated.id) is Some(index) {
    items[index] = updated
    self.handle_items_changed(resource)
  }
}

// --- host-facing state ----------------------------------------------------------

///|
/// Turns the editor's feedback affordances (hover "+" glyph, inline input,
/// reserved gutter lane) on or off for a resource. Fires the change event so
/// an attached editor re-syncs.
pub fn AgentFeedbackService::set_feedback_enabled(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  enabled : Bool,
) -> Unit {
  let key = resource.to_string()
  let current = self.is_feedback_enabled(resource)
  if current == enabled {
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
/// Whether the feedback affordances are active for a resource.
fn AgentFeedbackService::is_feedback_enabled(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
) -> Bool {
  self.enabled_resources.get(resource.to_string()).unwrap_or(false)
}

///|
/// Replaces a resource's items wholesale — the viewer's stand-in for
/// upstream's annotations-snapshot path: the host restores persisted
/// feedback or pushes agent-authored items through this.
pub fn AgentFeedbackService::set_feedback_items(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  items : Array[@agent_feedback_api.AgentFeedback],
) -> Unit {
  self.items_by_resource.set(resource.to_string(), items)
  self.handle_items_changed(resource)
}

///|
/// All stored items for a resource, including resolved ones (the editor view
/// filters those out — `get_session_editor_comments`). The array is live service
/// state; mutations go through the service methods so events fire.
fn AgentFeedbackService::get_feedback(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
) -> Array[@agent_feedback_api.AgentFeedback] {
  match self.items_by_resource.get(resource.to_string()) {
    Some(items) => items
    None => []
  }
}

///|
/// `addFeedback` (`agentFeedbackService.ts:385`): stores a new item.
/// `kind`/`state` default like upstream (user-authored, immediately
/// accepted); a system caller passes `state=Created` so the item waits for
/// user acceptance. Only an `Accepted` birth fires `on_did_add_feedback`.
fn AgentFeedbackService::add_feedback(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  range : @base_common.Range,
  text : String,
  kind? : @agent_feedback_api.AgentFeedbackKind = UserReview,
  state? : @agent_feedback_api.AgentFeedbackState = Accepted,
) -> @agent_feedback_api.AgentFeedback {
  let feedback : @agent_feedback_api.AgentFeedback = {
    id: "viewer-feedback-\{self.next_feedback_handle.to_string()}",
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
  if state == Accepted {
    self.did_add_feedback.fire({
      feedback,
      has_existing_feedback_for_file: has_existing_for_file,
    })
  }
  feedback
}

///|
/// `acceptFeedback`: transitions a `Created` item to `Accepted` so it becomes
/// submittable. Items in any other state are left untouched.
fn AgentFeedbackService::accept_feedback(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  guard existing.state == Created else { return }
  self.replace_item(resource, { ..existing, state: Accepted, })
}

///|
/// `removeFeedback`: deletes an item; a navigation anchor pointing at it is
/// cleared (upstream checks the raw id; the viewer also checks the prefixed
/// `SessionEditorComment` id the widget anchors with).
fn AgentFeedbackService::remove_feedback(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
) -> Unit {
  let key = resource.to_string()
  if self.navigation_anchor_by_resource.get(key) is Some(anchor) &&
    (
      anchor == feedback_id ||
      anchor == to_session_editor_comment_id(feedback_id)
    ) {
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
/// `updateFeedback`: replaces an item's text.
fn AgentFeedbackService::update_feedback(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
  new_text : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  self.replace_item(resource, { ..existing, text: new_text, })
}

///|
/// `addReply`: appends a message to an item's thread.
fn AgentFeedbackService::add_reply(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
  reply_text : String,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  let replies = existing.replies.copy()
  replies.push(reply_text)
  let updated : @agent_feedback_api.AgentFeedback = { ..existing, replies, }
  self.replace_item(resource, updated)
}

///|
/// `markFeedbackSubmitted`: moves every `Accepted` item to `Submitted` and
/// fires `on_did_submit_feedback` with the per-kind counts (and, viewer
/// addition, the items themselves — see `AgentFeedbackSubmittedEvent`).
/// No-op when nothing is accepted. Upstream resolves items directly for
/// providers without an agent loop; the viewer's host makes that call via
/// `set_feedback_resolved` instead.
fn AgentFeedbackService::mark_feedback_submitted(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
) -> Unit {
  let items = self.items_for(resource)
  let mut user_count = 0
  let mut agent_review_count = 0
  let mut reply_count = 0
  let submitted : Array[@agent_feedback_api.AgentFeedback] = []
  for index in 0..<items.length() {
    let item = items[index]
    guard item.state == Accepted else { continue }
    match item.kind {
      UserReview => user_count += 1
      AgentReview => agent_review_count += 1
    }
    reply_count += item.replies.length()
    let updated : @agent_feedback_api.AgentFeedback = {
      ..item,
      state: Submitted,
    }
    items[index] = updated
    submitted.push(updated)
  }
  guard !submitted.is_empty() else { return }
  self.handle_items_changed(resource)
  self.did_submit_feedback.fire({
    resource,
    items: submitted,
    user_count,
    agent_review_count,
    reply_count,
  })
}

///|
fn AgentFeedbackService::feedback_by_id(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
) -> @agent_feedback_api.AgentFeedback? {
  let items = self.get_feedback(resource)
  match items.search_by(item => item.id == feedback_id) {
    Some(index) => Some(items[index])
    None => None
  }
}

// --- navigation ------------------------------------------------------------------

///|
/// `setNavigationAnchor`: pins prev/next navigation on an item (by the id the
/// caller navigates over — the editor widgets use `SessionEditorComment.id`) or
/// clears it with `None`. Fires the navigation event either way.
fn AgentFeedbackService::set_navigation_anchor(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  item_id : String?,
) -> Unit {
  let key = resource.to_string()
  match item_id {
    Some(id) => self.navigation_anchor_by_resource.set(key, id)
    None => self.navigation_anchor_by_resource.remove(key)
  }
  self.did_change_navigation.fire(resource)
}

///|
/// `getNavigationBearing`: where the anchor sits in the supplied id order.
fn AgentFeedbackService::get_navigation_bearing(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  item_ids : Array[String],
) -> @agent_feedback_api.AgentFeedbackNavigationBearing {
  let active_idx = match
    self.navigation_anchor_by_resource.get(resource.to_string()) {
    Some(anchor) => item_ids.search_by(id => id == anchor).unwrap_or(-1)
    None => -1
  }
  { active_idx, total_count: item_ids.length(), }
}
