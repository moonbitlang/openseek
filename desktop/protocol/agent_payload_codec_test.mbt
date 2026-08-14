///|
test "agent start preserves all engine settings" {
  let payload : @protocol.StartPayload = @json.from_json({
    "task": "inspect",
    "submission_id": "submission-1",
    "model": "deepseek-v4-pro",
    "thinking": "max",
    "max_steps": 42,
    "session": "session-1",
    "workspace": "/work/project",
    "future_field": true,
  })
  assert_eq(payload.thinking, Some(ThinkingMax))
  @debug.assert_eq(payload.to_json(), {
    "task": "inspect",
    "submission_id": "submission-1",
    "model": "deepseek-v4-pro",
    "thinking": "max",
    "max_steps": 42,
    "session": "session-1",
    "workspace": "/work/project",
  })
}

///|
test "queue payloads expose only valid operation-specific data" {
  let add : @protocol.QueuePayload = @json.from_json({
    "action": "add",
    "id": "queue-1",
    "text": "first",
    "run_id": "run-1",
  })
  assert_true(add.action is QueueAdd(id="queue-1", text="first"))
  @debug.assert_eq(add.to_json(), {
    "action": "add",
    "id": "queue-1",
    "text": "first",
    "run_id": "run-1",
  })

  let withdraw : @protocol.QueuePayload = @json.from_json({
    "action": "withdraw",
    "id": "queue-1",
    "run_id": "run-1",
  })
  assert_true(withdraw.action is QueueWithdraw(id="queue-1"))
  @debug.assert_eq(withdraw.to_json(), {
    "action": "withdraw",
    "id": "queue-1",
    "run_id": "run-1",
  })

  let missing_text : @protocol.QueuePayload? = Some(
    @json.from_json({ "action": "edit", "id": "queue-1", "run_id": "run-1" }),
  ) catch {
    _ => None
  }
  let missing_run : @protocol.QueuePayload? = Some(
    @json.from_json({ "action": "steer", "id": "queue-1" }),
  ) catch {
    _ => None
  }
  assert_true(missing_text is None)
  assert_true(missing_run is None)
}

///|
test "OpenSeek thinking values round-trip through their closed codec" {
  let off : @protocol.OpenSeekThinking = @json.from_json(Json("no"))
  let high : @protocol.OpenSeekThinking = @json.from_json(Json("high"))
  let max : @protocol.OpenSeekThinking = @json.from_json(Json("max"))
  assert_eq(off, ThinkingOff)
  assert_eq(high, ThinkingHigh)
  assert_eq(max, ThinkingMax)
  @debug.assert_eq(off.to_json(), Json("no"))
  @debug.assert_eq(high.to_json(), Json("high"))
  @debug.assert_eq(max.to_json(), Json("max"))
}

///|
test "agent payload optional fields accept null and encode absence by omission" {
  let compact : @protocol.CompactPayload = @json.from_json({
    "session": "session-1",
    "model": null,
    "thinking": null,
    "max_steps": null,
    "workspace": null,
  })
  @debug.assert_eq(compact.to_json(), { "session": "session-1" })
  let goal : @protocol.GoalPayload = @json.from_json({
    "session": "session-1",
    "text": null,
    "auto": null,
  })
  @debug.assert_eq(goal.to_json(), { "session": "session-1" })
}

///|
test "agent payload codecs reject malformed known and missing required fields" {
  let malformed_thinking : @protocol.StartPayload? = Some(
    @json.from_json({ "task": "inspect", "session": "session-1", "thinking": 7 }),
  ) catch {
    _ => None
  }
  assert_true(malformed_thinking is None)
  let malformed_auto : @protocol.GoalPayload? = Some(
    @json.from_json({ "session": "session-1", "auto": "yes" }),
  ) catch {
    _ => None
  }
  assert_true(malformed_auto is None)
  let missing_session : @protocol.CompactPayload? = Some(
    @json.from_json({ "thinking": "high" }),
  ) catch {
    _ => None
  }
  assert_true(missing_session is None)
}

///|
test "agent payload codecs reject unsupported thinking values uniformly" {
  let start : @protocol.StartPayload? = Some(
    @json.from_json({
      "task": "inspect",
      "session": "session-1",
      "thinking": "invalid",
    }),
  ) catch {
    _ => None
  }
  assert_true(start is None)
  let compact : @protocol.CompactPayload? = Some(
    @json.from_json({ "session": "session-1", "thinking": "invalid" }),
  ) catch {
    _ => None
  }
  assert_true(compact is None)
  let goal : @protocol.GoalPayload? = Some(
    @json.from_json({ "session": "session-1", "thinking": "invalid" }),
  ) catch {
    _ => None
  }
  assert_true(goal is None)
  let padded : @protocol.StartPayload? = Some(
    @json.from_json({
      "task": "inspect",
      "session": "session-1",
      "thinking": " high ",
    }),
  ) catch {
    _ => None
  }
  assert_true(padded is None)
}

///|
/// Both fields that make an approval a decision are required, and neither has
/// a defensible default: an id-less approval answers no particular question,
/// and an `allow`-less one did not decide. Reading either as absent would
/// settle a permission prompt on a guess.
test "an approval payload requires the fields that make it a decision" {
  let missing_id : @protocol.ApprovalPayload? = Some(
    @json.from_json({ "allow": true }),
  ) catch {
    _ => None
  }
  assert_true(missing_id is None)
  let missing_allow : @protocol.ApprovalPayload? = Some(
    @json.from_json({ "id": "ap-1" }),
  ) catch {
    _ => None
  }
  assert_true(missing_allow is None)
  // Explicit null is not a decision either — it is the same absence spelled
  // out, and the optional-field helpers are the only ones that accept it.
  let null_allow : @protocol.ApprovalPayload? = Some(
    @json.from_json({ "id": "ap-1", "allow": null }),
  ) catch {
    _ => None
  }
  assert_true(null_allow is None)
  let malformed_allow : @protocol.ApprovalPayload? = Some(
    @json.from_json({ "id": "ap-1", "allow": "yes" }),
  ) catch {
    _ => None
  }
  assert_true(malformed_allow is None)
}

///|
/// `run_id` fences the same race a steer's does — a decision taken slowly must
/// not settle a question in a later run — and a caller that does not know the
/// run simply does not fence. Missing and null are the same thing, and the
/// encoder omits it rather than writing a null.
test "an approval payload's run fence is optional and omitted when absent" {
  let unfenced : @protocol.ApprovalPayload = @json.from_json({
    "id": "ap-1",
    "allow": true,
    "run_id": null,
  })
  assert_true(unfenced.run_id is None)
  @debug.assert_eq(unfenced.to_json(), { "id": "ap-1", "allow": true })
  let fenced : @protocol.ApprovalPayload = @json.from_json({
    "id": "ap-1",
    "allow": false,
    "run_id": "r-7",
  })
  @debug.assert_eq(fenced.to_json(), {
    "id": "ap-1",
    "allow": false,
    "run_id": "r-7",
  })
  // Unknown fields are ignored, like every other payload here, so a newer
  // client can add one without breaking this host.
  let extra : @protocol.ApprovalPayload = @json.from_json({
    "id": "ap-1",
    "allow": true,
    "why": "because",
  })
  assert_eq(extra.id, "ap-1")
}

///|
/// `delivered` is the whole of the reply. A client that read a missing field
/// as `false` would retire a prompt whose question is still waiting.
test "an approval reply requires its one field" {
  let missing : @protocol.ApprovalReply? = Some(@json.from_json({})) catch {
    _ => None
  }
  assert_true(missing is None)
  let reply : @protocol.ApprovalReply = @json.from_json({ "delivered": true })
  assert_true(reply.delivered)
  @debug.assert_eq(reply.to_json(), { "delivered": true })
}

///|
/// Every section of the runs snapshot is required. Desktop ships its frontend
/// and host together, so an absent section is drift in the current host — and
/// reading it as empty loses live state silently: a tool left waiting on an
/// approval with no card to answer it, and no deadline behind the question.
test "the runs snapshot requires each of its sections" {
  for missing in ["runs", "settled", "approvals"] {
    let fields : Map[String, Json] = {
      "runs": Json(([] : Array[Json])),
      "settled": Json(([] : Array[Json])),
      "approvals": Json(([] : Array[Json])),
    }
    fields.remove(missing)
    let decoded : @protocol.RunsReply? = Some(@json.from_json(Json(fields))) catch {
      _ => None
    }
    if decoded is Some(_) {
      fail("a snapshot without \{missing} decoded")
    }
  }
  // An empty section is an empty array, which is what a host with nothing in
  // flight sends.
  let empty : @protocol.RunsReply = @json.from_json({
    "runs": [],
    "settled": [],
    "approvals": [],
  })
  assert_eq(empty.approvals.length(), 0)
}
