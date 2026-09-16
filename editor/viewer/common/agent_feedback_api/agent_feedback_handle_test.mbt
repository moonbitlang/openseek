///|
fn feedback_fixture(
  resource : @base_common.Uri,
  id? : String = "feedback-1",
) -> @agent_feedback_api.AgentFeedback {
  {
    id,
    text: "note",
    resource,
    range: Range(2, 1, 2, 5),
    kind: UserReview,
    replies: [],
    state: Accepted,
  }
}

///|
test "AgentFeedbackHandle forwards its exact callback floor" {
  let resource = try! @base_common.Uri::parse("memory://session/a.mbt")
  let feedback = feedback_fixture(resource)
  let calls : Array[String] = []
  let changed_ids : Array[String] = []
  let navigated : Array[String] = []
  let handle = @agent_feedback_api.AgentFeedbackHandle(
    on_did_change_feedback=listener => {
      calls.push("subscribe-feedback")
      listener({ resource, feedback_items: [feedback], })
      @base_common.Disposable::from(() => calls.push("dispose-feedback"))
    },
    on_did_change_navigation=listener => {
      calls.push("subscribe-navigation")
      listener(resource)
      @base_common.Disposable::from(() => calls.push("dispose-navigation"))
    },
    is_feedback_enabled=_ => {
      calls.push("enabled")
      true
    },
    get_feedback=_ => {
      calls.push("get")
      [feedback]
    },
    get_navigation_bearing=(_, item_ids) => {
      calls.push("bearing:\{item_ids.join(",")}")
      { active_idx: 1, total_count: item_ids.length(), }
    },
    add_feedback=(_, _, _, kind, state) => {
      let kind_label = match kind {
        None => "none"
        Some(UserReview) => "user"
        Some(AgentReview) => "agent"
      }
      let state_label = match state {
        None => "none"
        Some(Created) => "created"
        Some(Accepted) => "accepted"
        Some(Submitted) => "submitted"
        Some(Resolved) => "resolved"
      }
      calls.push("add:\{kind_label}:\{state_label}")
      feedback
    },
    mark_feedback_submitted=_ => calls.push("submit"),
    remove_feedback=(_, id) => calls.push("remove:\{id}"),
    accept_feedback=(_, id) => calls.push("accept:\{id}"),
    set_navigation_anchor=(_, item_id) => {
      let anchor = item_id.unwrap_or("none")
      calls.push("anchor:\{anchor}")
    },
    update_feedback=(_, id, text) => calls.push("update:\{id}:\{text}"),
    add_reply=(_, id, text) => calls.push("reply:\{id}:\{text}"),
  )
  let feedback_subscription = handle.on_did_change_feedback(event => {
    changed_ids.push(event.feedback_items[0].id)
  })
  let navigation_subscription = handle.on_did_change_navigation(uri => {
    navigated.push(uri.to_string())
  })
  assert_eq(changed_ids.join(","), feedback.id)
  assert_eq(navigated.join(","), resource.to_string())
  assert_true(handle.is_feedback_enabled(resource))
  assert_eq(handle.get_feedback(resource)[0].id, feedback.id)
  assert_eq(handle.get_navigation_bearing(resource, ["a", "b"]), {
    active_idx: 1,
    total_count: 2,
  })
  assert_eq(
    handle.add_feedback(resource, Range(1, 1, 1, 1), "default").id,
    feedback.id,
  )
  handle.add_feedback(
    resource,
    Range(1, 1, 1, 1),
    "explicit",
    kind=AgentReview,
    state=Created,
  )
  |> ignore
  handle.mark_feedback_submitted(resource)
  handle.remove_feedback(resource, "feedback-1")
  handle.accept_feedback(resource, "feedback-2")
  handle.set_navigation_anchor(resource, Some("feedback-2"))
  handle.update_feedback(resource, "feedback-2", "updated")
  handle.add_reply(resource, "feedback-2", "reply")
  feedback_subscription.dispose()
  navigation_subscription.dispose()
  assert_eq(
    calls.join("|"),
    "subscribe-feedback|subscribe-navigation|enabled|get|bearing:a,b|add:none:none|add:agent:created|submit|remove:feedback-1|accept:feedback-2|anchor:feedback-2|update:feedback-2:updated|reply:feedback-2:reply|dispose-feedback|dispose-navigation",
  )
}

///|
test "planned submitted-feedback DTO remains a public value contract" {
  let resource = try! @base_common.Uri::parse("memory://session/a.mbt")
  let feedback = feedback_fixture(resource)
  let submitted : @agent_feedback_api.AgentFeedbackSubmittedEvent = {
    resource,
    items: [feedback],
    user_count: 1,
    agent_review_count: 0,
    reply_count: 2,
  }
  assert_eq(submitted.items[0].id, feedback.id)
  assert_eq(submitted.reply_count, 2)
}
