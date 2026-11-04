///|
/// What an approval reviewer decided about one permission request.
pub(all) enum Decision {
  /// Grant the action once.
  Allow
  /// Refuse the action.
  Deny
  /// The reviewer could not settle it; a person decides instead, or, where
  /// nobody can be asked, the action is refused.
  Escalate
} derive(Debug, Eq)

///|
/// The wire word for a decision.
fn Decision::word(self : Decision) -> String {
  match self {
    Allow => "allow"
    Deny => "deny"
    Escalate => "escalate"
  }
}

///|
fn Decision::parse(word : StringView) -> Decision? {
  match word {
    "allow" => Some(Allow)
    "deny" => Some(Deny)
    "escalate" => Some(Escalate)
    _ => None
  }
}

///|
/// The reviewer's answer: the `approval` kind's report, and what the parent's
/// approval channel acts on. The JSON shape is
/// `{"decision": "allow" | "deny" | "escalate", "reason": String}`.
struct Verdict {
  decision : Decision
  reason : String
} derive(Debug, Eq)

///|
/// What the reviewer decided.
pub fn Verdict::decision(self : Verdict) -> Decision {
  self.decision
}

///|
/// Parse and validate a verdict: both the submit tool and the parent's trust
/// boundary hold a report to this one check.
pub fn Verdict::parse(json : Json) -> Result[Verdict, String] {
  guard json is { "decision": String(word), "reason": String(reason), .. } else {
    return Err("a verdict needs a string decision and a string reason")
  }
  guard Decision::parse(word) is Some(decision) else {
    return Err("unknown decision: \{word} (use allow, deny, or escalate)")
  }
  guard !reason.is_blank() else { return Err("reason must not be empty") }
  Ok({ decision, reason, })
}

///|
pub impl ToJson for Verdict with fn to_json(self) {
  {
    "decision": Json::string(self.decision.word()),
    "reason": Json::string(self.reason),
  }
}

///|
/// One permission request, as the reviewer reads it: the tool's own account
/// of what would be granted, the operation it would perform, and the user's
/// recent messages — the only source of authorization the reviewer accepts.
/// The `approval` kind's input.
struct ReviewRequest {
  tool_name : String
  detail : String
  body : String?
  intent : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// `intent` is the user's recent messages, oldest first.
pub fn ReviewRequest::ReviewRequest(
  ask : @agent_runtime.ApprovalAsk,
  intent~ : Array[String],
) -> ReviewRequest {
  { tool_name: ask.tool_name, detail: ask.detail, body: ask.body, intent, }
}

///|
/// Parse and validate the `approval` kind's input.
pub fn ReviewRequest::parse(json : Json) -> Result[ReviewRequest, String] {
  let request : ReviewRequest = @json.from_json(json) catch {
    error => return Err("invalid approval request: \{error}")
  }
  guard !request.tool_name.is_blank() && !request.detail.is_blank() else {
    return Err("an approval request needs a non-empty tool_name and detail")
  }
  Ok(request)
}
