// The workbench's host side of the agent-feedback contrib — the role VS
// Code's session/agent host plays: it enables the feedback affordances on
// every opened document (the `getSessionForFile` scope decision) and owns
// persistence. The feedback service reports every store mutation through
// `on_did_change_feedback`; the workbench writes the affected resource's
// items to localStorage and restores them on the resource's first open of
// the session. Submitted feedback is the agent hand-off seam: this shell
// has no agent loop, so `on_did_submit_feedback` is persisted like any
// other change and left in the `Submitted` state.

///|
fn feedback_storage_key(resource : @base_common.Uri) -> String {
  "readonly-editor:agent-feedback:\{resource.to_string()}"
}

///|
/// Items restored from storage get ids in their own namespace so they can
/// never collide with the service's session-scoped `viewer-feedback-N` ids.
let restored_feedback_count : Ref[Int] = Ref(0)

///|
/// Subscribes the workbench to the feedback service's change event and
/// writes the mutated resource's item set back to localStorage.
fn install_feedback_persistence(services : WorkbenchServices) -> Unit {
  services.agent_feedback_handle.on_did_change_feedback(event => {
    persist_feedback_items(services, event.resource)
  })
  |> ignore
}

///|
/// Enables the feedback affordances for the document and restores any
/// persisted items. Runs on every model install.
fn sync_document_feedback(text_model : @model.TextModel) -> Unit {
  let services = workbench_services()
  restore_feedback_items(services, text_model.uri)
  services.agent_feedback.set_feedback_enabled(text_model.uri, true)
}

///|
fn persist_feedback_items(
  services : WorkbenchServices,
  resource : @base_common.Uri,
) -> Unit {
  let items : Array[Json] = []
  for item in services.agent_feedback_handle.get_feedback(resource) {
    items.push(feedback_item_to_json(item))
  }
  @base_browser.local_storage_set(
    feedback_storage_key(resource),
    Json(items).stringify(),
  )
  |> ignore
}

///|
fn feedback_item_to_json(item : @agent_feedback_api.AgentFeedback) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["text"] = item.text.to_json()
  fields["range"] = Json([
    item.range.start_line_number.to_json(),
    item.range.start_column.to_json(),
    item.range.end_line_number.to_json(),
    item.range.end_column.to_json(),
  ])
  fields["kind"] = (match item.kind {
    UserReview => "user"
    AgentReview => "codeReview"
  }).to_json()
  fields["state"] = (match item.state {
    Created => "created"
    Accepted => "accepted"
    Submitted => "submitted"
    Resolved => "resolved"
  }).to_json()
  if !item.replies.is_empty() {
    fields["replies"] = Json(item.replies.map(reply => reply.to_json()))
  }
  Json(fields)
}

///|
/// Rebuilds a resource's items from localStorage. Live service state wins:
/// restore only fills an empty store (the resource's first open this
/// session); after that the in-memory items are the persisted set's
/// superset.
fn restore_feedback_items(
  services : WorkbenchServices,
  resource : @base_common.Uri,
) -> Unit {
  guard services.agent_feedback_handle.get_feedback(resource).is_empty() else {
    return
  }
  let raw = @base_browser.local_storage_get(feedback_storage_key(resource))
  guard raw is Ok(Some(raw)) else { return }
  let parsed = @json.parse(raw) catch { _ => return }
  guard parsed is Array(entries) else { return }
  let items : Array[@agent_feedback_api.AgentFeedback] = []
  for entry in entries {
    if feedback_item_from_json(resource, entry) is Some(item) {
      items.push(item)
    }
  }
  guard !items.is_empty() else { return }
  services.agent_feedback.set_feedback_items(resource, items)
}

///|
fn feedback_item_from_json(
  resource : @base_common.Uri,
  value : Json,
) -> @agent_feedback_api.AgentFeedback? {
  guard value
    is {
      "text": String(text),
      "range": Array(
        [Number(sl, ..), Number(sc, ..), Number(el, ..), Number(ec, ..)]
      ),
      ..
    } else {
    return None
  }
  let kind : @agent_feedback_api.AgentFeedbackKind = if value
    is { "kind": String("codeReview"), .. } {
    AgentReview
  } else {
    UserReview
  }
  let state : @agent_feedback_api.AgentFeedbackState = match value {
    { "state": String("created"), .. } => Created
    { "state": String("submitted"), .. } => Submitted
    { "state": String("resolved"), .. } => Resolved
    _ => Accepted
  }
  let replies : Array[String] = []
  if value is { "replies": Array(reply_items), .. } {
    for reply in reply_items {
      if reply is String(reply_text) {
        replies.push(reply_text)
      }
    }
  }
  restored_feedback_count.val += 1
  Some({
    id: "workbench-restored-\{restored_feedback_count.val.to_string()}",
    text,
    resource,
    range: Range(sl.to_int(), sc.to_int(), el.to_int(), ec.to_int()),
    kind,
    replies,
    state,
  })
}
