///|
fn event_record(
  data : Json,
  item : @protocol.SessionItem,
) -> @protocol.SessionEvent? {
  guard data is { "engine_sequence": Number(sequence, ..), .. } &&
    sequence > 0 &&
    sequence == sequence.to_int().to_double() else {
    return None
  }
  let ts = if data is { "ts": Number(ts, ..), .. } { Some(ts) } else { None }
  Some({ sequence: sequence.to_int(), ts, item, })
}

///|
fn committed_event(data : Json, kind : String) -> @protocol.SessionEvent? {
  let item : @protocol.SessionItem = @json.from_json({
    "kind": kind,
    "payload": data,
  }) catch {
    _ => return None
  }
  guard !(item is @protocol.Unknown(_)) else { return None }
  event_record(data, item)
}

///|
fn Conversation::assistant_event(
  self : Conversation,
  data : Json,
) -> @protocol.SessionEvent? {
  guard data is Object(fields) else { return None }
  let sent = match fields.get("content") {
    Some(String(content)) => content
    _ => ""
  }
  // A reconnect can begin in the middle of a model response. A suffix
  // must not be mistaken for a complete reply when the marker has no body.
  guard self.response_started || !sent.is_empty() else { return None }
  let payload = fields.copy()
  payload["content"] = Json(
    if self.response_started {
      self.live.response.unwrap_or(sent)
    } else {
      sent
    },
  )
  if self.response_started && self.live.reasoning is Some(reasoning) {
    payload["reasoning_content"] = Json(reasoning.content)
  }
  committed_event(Json(payload), "assistant")
}

///|
fn Conversation::finished_event(
  self : Conversation,
  data : Json,
) -> @protocol.SessionEvent? {
  let status = match data {
    { "result": { "status": String(status), .. }, .. } => status
    { "status": String(status), .. } => status
    _ => return None
  }
  let reason = match data {
    { "reason": String(reason), .. }
    | { "result": { "reason": String(reason), .. }, .. } => reason
    _ => ""
  }
  let terminal : @protocol.SessionTerminal = match status {
    "ok" | "completed" =>
      Finished(
        match data {
          { "result": { "output": { "answer": String(answer), .. }, .. }, .. } if !answer.is_blank() =>
            answer
          _ => self.notification_answer.unwrap_or("")
        },
      )
    "aborted" | "cancelled" => Aborted(reason)
    "interrupted" => Interrupted(reason)
    "max_steps_exhausted" => MaxStepsExhausted
    "context_yield" | "incomplete" => ContextYield(reason)
    "failed" => Failed(reason)
    _ => return None
  }
  event_record(data, @protocol.Terminal(terminal))
}
