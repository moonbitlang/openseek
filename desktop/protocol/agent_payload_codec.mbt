// Explicit codecs for requests that can start an OpenSeek engine process.
// Unknown fields are ignored for forward evolution. Optional fields accept
// missing or null and are omitted when encoded; known malformed fields fail
// at their exact path instead of silently changing the engine configuration.

///|
fn JsonObject::optional_thinking(
  self : JsonObject,
  name : String,
) -> OpenSeekThinking? raise @json.JsonDecodeError {
  match self.fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(@json.from_json(value, path=self.path.add_key(name)))
  }
}

///|
pub impl FromJson for StartPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.start payload")
  {
    task: object.required_string("task"),
    submission_id: object.optional_string("submission_id"),
    model: object.optional_string("model"),
    thinking: object.optional_thinking("thinking"),
    max_steps: object.optional_int("max_steps"),
    session: object.required_string("session"),
    workspace: object.optional_string("workspace"),
  }
}

///|
pub impl ToJson for StartPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "task": self.task.to_json(),
    "session": self.session.to_json(),
  }
  if self.submission_id is Some(submission_id) {
    fields["submission_id"] = submission_id.to_json()
  }
  if self.model is Some(model) {
    fields["model"] = model.to_json()
  }
  if self.thinking is Some(thinking) {
    fields["thinking"] = thinking.to_json()
  }
  if self.max_steps is Some(max_steps) {
    fields["max_steps"] = max_steps.to_json()
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = workspace.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for QueuePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.queue payload")
  let id = object.required_string("id")
  let action = match object.required_string("action") {
    "add" => QueueAdd(id~, text=object.required_string("text"))
    "edit" => QueueEdit(id~, text=object.required_string("text"))
    "withdraw" => QueueWithdraw(id~)
    "steer" => QueueSteer(id~)
    _ =>
      raise JsonDecodeError(
        (path.add_key("action"), "expected add, edit, withdraw, or steer"),
      )
  }
  { action, run_id: object.required_string("run_id"), }
}

///|
pub impl ToJson for QueuePayload with fn to_json(self) {
  let fields : Map[String, Json] = { "run_id": self.run_id.to_json() }
  match self.action {
    QueueAdd(id~, text~) => {
      fields["action"] = "add".to_json()
      fields["id"] = id.to_json()
      fields["text"] = text.to_json()
    }
    QueueEdit(id~, text~) => {
      fields["action"] = "edit".to_json()
      fields["id"] = id.to_json()
      fields["text"] = text.to_json()
    }
    QueueWithdraw(id~) => {
      fields["action"] = "withdraw".to_json()
      fields["id"] = id.to_json()
    }
    QueueSteer(id~) => {
      fields["action"] = "steer".to_json()
      fields["id"] = id.to_json()
    }
  }
  Json(fields)
}

///|
pub impl FromJson for CompactPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.compact payload")
  {
    session: object.required_string("session"),
    model: object.optional_string("model"),
    thinking: object.optional_thinking("thinking"),
    max_steps: object.optional_int("max_steps"),
    workspace: object.optional_string("workspace"),
  }
}

///|
pub impl ToJson for CompactPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "session": self.session.to_json() }
  if self.model is Some(model) {
    fields["model"] = model.to_json()
  }
  if self.thinking is Some(thinking) {
    fields["thinking"] = thinking.to_json()
  }
  if self.max_steps is Some(max_steps) {
    fields["max_steps"] = max_steps.to_json()
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = workspace.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for GoalPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.goal payload")
  {
    session: object.required_string("session"),
    text: object.optional_string("text"),
    auto: object.optional_bool("auto"),
    model: object.optional_string("model"),
    thinking: object.optional_thinking("thinking"),
    max_steps: object.optional_int("max_steps"),
    workspace: object.optional_string("workspace"),
  }
}

///|
pub impl ToJson for GoalPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "session": self.session.to_json() }
  if self.text is Some(text) {
    fields["text"] = text.to_json()
  }
  if self.auto is Some(auto) {
    fields["auto"] = auto.to_json()
  }
  if self.model is Some(model) {
    fields["model"] = model.to_json()
  }
  if self.thinking is Some(thinking) {
    fields["thinking"] = thinking.to_json()
  }
  if self.max_steps is Some(max_steps) {
    fields["max_steps"] = max_steps.to_json()
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = workspace.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for OpenSeekThinking with fn from_json(json, path) {
  guard json is String(value) else {
    raise JsonDecodeError((path, "expected no, high, or max"))
  }
  guard OpenSeekThinking::parse(value) is Some(thinking) else {
    raise JsonDecodeError((path, "expected no, high, or max"))
  }
  thinking
}

///|
pub impl ToJson for OpenSeekThinking with fn to_json(self) {
  Json(self.wire())
}

///|
/// `agent.approval` carries a decision, so both of the fields that make it one
/// are required: an approval with no `id` answers no particular question, and
/// one with no `allow` did not decide. Neither has a defensible default, and
/// reading either as absent would settle a permission prompt on a guess — the
/// same rule the engine's own wire decoder applies to this command.
///
/// `run_id` is optional and accepts missing or null. It fences the same race a
/// steer's does — a decision taken slowly must not settle a question in a
/// later run — and a caller that does not know the run simply does not fence.
pub impl FromJson for ApprovalPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.approval payload")
  {
    id: object.required_string("id"),
    allow: object.required_bool("allow"),
    run_id: object.optional_string("run_id"),
  }
}

///|
pub impl ToJson for ApprovalPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": self.id.to_json(),
    "allow": self.allow.to_json(),
  }
  if self.run_id is Some(run_id) {
    fields["run_id"] = run_id.to_json()
  }
  Json(fields)
}

///|
/// `delivered` is required: it is the whole of the reply, and a client that
/// read a missing field as `false` would retire a prompt whose question is
/// still waiting for an answer.
pub impl FromJson for ApprovalReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.approval reply")
  { delivered: object.required_bool("delivered"), }
}

///|
pub impl ToJson for ApprovalReply with fn to_json(self) {
  { "delivered": self.delivered.to_json() }
}

///|
/// `agent.runs` is how a client that joins or rejoins mid-run rebuilds what is
/// in flight, so every section is REQUIRED. Desktop ships its frontend and host
/// together, which leaves no version where one of these is legitimately absent;
/// what an absent section would actually mean is drift in the current host, and
/// reading it as empty turns that into silently lost state — a tool left
/// waiting on an approval with no card to answer it, and no deadline behind the
/// question. A decode error says so instead.
///
/// An empty section is still an empty array on the wire, which is what a host
/// with nothing in flight sends.
pub impl FromJson for RunsReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.runs reply")
  let runs : Array[StartedPayload] = []
  for index, raw in object.required_array("runs") {
    runs.push(@json.from_json(raw, path=path.add_key("runs").add_index(index)))
  }
  let settled : Array[RunSettlementPayload] = []
  for index, raw in object.required_array("settled") {
    settled.push(
      @json.from_json(raw, path=path.add_key("settled").add_index(index)),
    )
  }
  let approvals : Array[PendingApprovalPayload] = []
  for index, raw in object.required_array("approvals") {
    approvals.push(
      @json.from_json(raw, path=path.add_key("approvals").add_index(index)),
    )
  }
  { runs, settled, approvals, }
}

///|
pub impl ToJson for RunsReply with fn to_json(self) {
  {
    "runs": Json(self.runs.map(run => run.to_json())),
    "settled": Json(self.settled.map(entry => entry.to_json())),
    "approvals": Json(self.approvals.map(approval => approval.to_json())),
  }
}

///|
/// Every field that says WHICH question this is, and what it is about, is
/// required: a replayed prompt missing its `id` cannot be answered, and one
/// missing `tool_name` or `detail` cannot be rendered. `run_id` and `body` are
/// the two that are legitimately absent — a question asked outside a run, and
/// an asker with nothing to show.
pub impl FromJson for PendingApprovalPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pending approval")
  {
    id: object.required_string("id"),
    session: object.required_string("session"),
    run_id: object.optional_string("run_id"),
    tool_name: object.required_string("tool_name"),
    detail: object.required_string("detail"),
    body: object.optional_string("body"),
  }
}

///|
pub impl ToJson for PendingApprovalPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": self.id.to_json(),
    "session": self.session.to_json(),
    "tool_name": self.tool_name.to_json(),
    "detail": self.detail.to_json(),
  }
  if self.run_id is Some(run_id) {
    fields["run_id"] = run_id.to_json()
  }
  if self.body is Some(body) {
    fields["body"] = body.to_json()
  }
  Json(fields)
}
