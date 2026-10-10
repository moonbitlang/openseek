///|
/// How a mid-turn steer reaches the model.
///
/// The wire spells these `"prompt"` and `"command"`. `Notice` is deliberately
/// absent: the engine synthesizes notices for itself (a background job
/// finishing), and reports them back as `steer_applied` with `kind: "notice"`,
/// but no controller may send one — `decode` has always rejected an unknown
/// kind, and a notice is not a thing a client has to say.
pub(all) enum SteerKind {
  Prompt
  Command
} derive(Eq, Debug)

///|
/// One command a controller writes to `openseek serve`'s stdin.
///
/// The other half of the serve protocol: `Event` is what the engine reports,
/// this is what it is told. Both directions used to be anonymous JSON at each
/// end — the events for ~60 call sites and three decoders, these for one
/// decoder and two encoders that had already drifted apart:
///
/// - the TUI sent `steer` with a `kind`; the desktop sent it without one, and
///   worked only because `parse` falls back to `Prompt`. Neither end wrote that
///   rule down.
/// - the desktop had no `goal` at all, so the same protocol meant different
///   things to its two clients, and nothing said whether that was a decision.
///
/// One type, one encoder, one decoder — the same shape the event direction now
/// has.
pub(all) enum Command {
  /// `submission_id` is the submitting controller's tag for this prompt. The
  /// engine records it on the turn's durable `User` item, so a delivery can
  /// later be reconciled by exact id rather than by matching text. Controllers
  /// that do not reconcile deliveries (the TUI) send none.
  Prompt(content~ : Content, submission_id~ : String?)
  /// The tag follows steering through the runtime queue, durable User item,
  /// and applied/dropped receipt. Untagged controllers send none.
  Steer(kind~ : SteerKind, content~ : Content, submission_id~ : String?)
  Compact
  Cancel
  JobsSnapshot(request_id~ : String)
  JobStop(request_id~ : String, generation~ : String, job_id~ : String)
  /// `auto` arms autonomous continuation toward the goal. No in-repo client
  /// sends it — the TUI's `/goal` always sets a manual goal — but `serve` is a
  /// protocol, not a private channel, and an external controller drives this.
  GoalSet(text~ : String, auto~ : Bool)
  GoalClear
  /// The answer to an `approval_requested` event, addressed by the `id` that
  /// event carried. The only command that replies to the engine rather than
  /// instructing it, and the only one a controller MUST send: until it
  /// arrives, the asking tool is blocked.
  ///
  /// `allow` is deliberately a Bool and not a decision vocabulary. There is
  /// exactly one grant to express — permission for the single action that was
  /// asked about — and a richer answer ("allow for this session", "allow
  /// commands like this one") would have to say what the grant's equivalence
  /// class is, which nothing on either end of this wire can currently define.
  ApprovalDecision(id~ : String, allow~ : Bool)
} derive(Eq, Debug)

///|
/// The command as the line a controller writes.
pub fn Command::to_json(self : Command) -> Json {
  match self {
    Prompt(content~, submission_id~) =>
      if submission_id is Some(id) {
        { "command": "prompt", "content": content, "submission_id": id }
      } else {
        { "command": "prompt", "content": content }
      }
    Steer(kind~, content~, submission_id~) => {
      let fields : Map[String, Json] = {
        "command": "steer",
        "kind": match kind {
          Prompt => "prompt"
          Command => "command"
        },
        "content": content,
      }
      if submission_id is Some(id) {
        fields["submission_id"] = Json(id)
      }
      Json(fields)
    }
    JobsSnapshot(request_id~) =>
      { "command": "jobs_snapshot", "request_id": request_id }
    JobStop(request_id~, generation~, job_id~) =>
      {
        "command": "job_stop",
        "request_id": request_id,
        "generation": generation,
        "job_id": job_id,
      }
    Compact => { "command": "compact" }
    Cancel => { "command": "cancel" }
    // `auto` is written only when set: an engine older than the flag ignores an
    // unknown key, but the field's absence is also what `false` has always
    // looked like on this wire, so omitting it keeps the common line unchanged.
    GoalSet(text~, auto~) =>
      if auto {
        { "command": "goal", "action": "set", "text": text, "auto": true }
      } else {
        { "command": "goal", "action": "set", "text": text }
      }
    GoalClear => { "command": "goal", "action": "clear" }
    ApprovalDecision(id~, allow~) =>
      { "command": "approval", "id": id, "allow": allow }
  }
}

///|
/// Read one stdin line back into a `Command`.
///
/// `Err` carries the text the engine reports to its controller as a
/// `command_error` event, so these strings are themselves wire contract, not
/// diagnostics — they are what a controller reads to learn what it got wrong.
///
/// It reports a line this protocol cannot read, and nothing else. Whether a
/// readable command is *acceptable* is the engine's to say: a blank goal is
/// well-formed and refused, and `serve` refuses it. Were that check here,
/// `GoalSet(text="  ")` would be a value this type holds and `to_json` writes
/// but `parse` rejects — breaking the round-trip below for a value the type
/// itself offers.
///
/// Unlike `parse` for events, this returns a `Result`: an unreadable event is
/// a line to ignore, but an unreadable command is a request that will never be
/// answered, and silence is the one reply a controller cannot act on.
///
/// ## When a field may be absent
///
/// The same rule `parse` states for events, and both of its cases apply here —
/// one field each, verified against `git log -S` for the field versus its
/// command's introducing commit:
///
/// 1. **Added after its command existed.** `steer`'s `kind` arrived in
///    9b2f6c43; `steer` itself in 17562cc1. An engine from between them is sent
///    a `kind` it ignores, and a controller older than the field sends none —
///    so absent means `Prompt`, which is what every controller meant before
///    there was a choice. The desktop was still sending exactly that.
///    `prompt`'s `submission_id` is the same case: it arrived long after
///    `prompt` itself, an engine older than the field ignores the key, and a
///    controller that does not tag its submissions sends none — absent means
///    untagged, which is what every prompt was before there was a tag.
/// 2. **Optional since the command shipped.** `goal`'s `auto` arrived *with*
///    `goal` (c8cc6ad7), so case (1) does not cover it — but the engine has
///    read `auto` as absent-means-false from the first line it ever decoded.
///    It is a flag with a default, not a value that can go missing.
///
/// The distinction matters because only (1) is about talking to an old
/// binary. Message commands require `content`; the legacy `text` field is
/// accepted at the decoding boundary for existing controllers.
pub fn Command::parse(line : Json) -> Result[Command, String] {
  match line {
    { "command": "prompt", .. } => {
      let content = match parse_command_content(line) {
        Ok(content) => content
        Err(error) => return Err(error)
      }
      let submission_id = match line {
        { "submission_id": String(id), .. } => Some(id)
        { "submission_id": _, .. } =>
          return Err("expected a string \"submission_id\" field")
        _ => None
      }
      Ok(Prompt(content~, submission_id~))
    }
    { "command": "steer", .. } => parse_steer(line)
    { "command": "jobs_snapshot", "request_id": String(request_id), .. } if !request_id.is_empty() =>
      Ok(JobsSnapshot(request_id~))
    {
      "command": "job_stop",
      "request_id": String(request_id),
      "generation": String(generation),
      "job_id": String(job_id),
      ..
    } if !request_id.is_empty() &&
      valid_job_component(generation) &&
      valid_job_component(job_id) =>
      Ok(JobStop(request_id~, generation~, job_id~))
    { "command": "jobs_snapshot" | "job_stop", .. } =>
      Err("invalid background job command")
    { "command": "compact", .. } => Ok(Compact)
    { "command": "cancel", .. } => Ok(Cancel)
    // A blank goal decodes: `{"action":"set","text":"  "}` is a well-formed
    // command, and refusing it is the engine's policy, not the wire's shape.
    // Keeping the check here would make `GoalSet(text="  ")` a value this type
    // can hold, `to_json` can write, and `parse` then rejects — a round-trip
    // the type advertises and would not have. `serve` rejects it, in the same
    // words, where the policy lives.
    // The armed line is its own static arm: absent and non-true `auto` both
    // mean false (its default since goal shipped — see the absence rule above),
    // so the two shapes are described rather than tested for twice.
    {
      "command": "goal",
      "action": "set",
      "text": String(text),
      "auto": true,
      ..
    } => Ok(GoalSet(text~, auto=true))
    { "command": "goal", "action": "set", "text": String(text), .. } =>
      Ok(GoalSet(text~, auto=false))
    { "command": "goal", "action": "clear", .. } => Ok(GoalClear)
    { "command": "goal", .. } =>
      Err(
        "expected {\"action\": \"set\", \"text\": ...} or {\"action\": \"clear\"}",
      )
    // Both fields are required. Neither has a defensible default: an approval
    // with no `id` answers no particular question, and one with no `allow` is
    // a decision that did not decide — silently reading either as absent would
    // settle a permission prompt on a guess.
    { "command": "approval", "id": String(id), "allow": true, .. } =>
      Ok(ApprovalDecision(id~, allow=true))
    { "command": "approval", "id": String(id), "allow": false, .. } =>
      Ok(ApprovalDecision(id~, allow=false))
    { "command": "approval", "id": String(_), .. } =>
      Err("expected a boolean \"allow\" field")
    { "command": "approval", .. } => Err("expected a string \"id\" field")
    { "command": String(other), .. } => Err("unknown command: \{other}")
    _ => Err("expected a {\"command\": ...} object")
  }
}

///|
fn parse_steer(line : Json) -> Result[Command, String] {
  let submission_id = match line {
    { "submission_id": String(id), .. } => Some(id)
    { "submission_id": _, .. } =>
      return Err("expected a string \"submission_id\" field")
    _ => None
  }
  let content = match parse_command_content(line) {
    Ok(content) => content
    Err(error) => return Err(error)
  }
  match line {
    { "kind": "prompt", .. } => Ok(Steer(kind=Prompt, content~, submission_id~))
    { "kind": "command", .. } =>
      Ok(Steer(kind=Command, content~, submission_id~))
    { "kind": String(other), .. } => Err("unknown steer kind: \{other}")
    { "kind": _, .. } => Err("expected a string \"kind\" field")
    _ => Ok(Steer(kind=Prompt, content~, submission_id~))
  }
}

///|
/// Current commands carry content directly. Legacy text and image URL fields
/// are accepted only at this boundary; a malformed content field never falls
/// back to the old representation.
fn parse_command_content(line : Json) -> Result[Content, String] {
  match line {
    { "content": value, .. } => {
      let content : Content = @json.from_json(value) catch {
        error => return Err("invalid content: \{error}")
      }
      Ok(content)
    }
    { "text": String(text), .. } => {
      let urls : Array[String] = match line {
        { "images": value, .. } =>
          @json.from_json(value) catch {
            _ => return Err("expected an array of image URLs")
          }
        _ => []
      }
      let parts : Array[ContentPart] = [Text(text)]
      for url in urls {
        let image = Image::from_data_url(url) catch {
          error => return Err("\{error}")
        }
        parts.push(Image(image))
      }
      Ok(Content(parts))
    }
    _ => Err("expected a string \"text\" field")
  }
}

///|
pub extend Command with Debug::{to_repr}

///|
pub extend Command with Eq::{equal, not_equal}

///|
pub extend SteerKind with Debug::{to_repr}

///|
pub extend SteerKind with Eq::{equal, not_equal}
