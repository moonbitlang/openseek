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
  Prompt(text~ : String, submission_id~ : String?)
  Steer(kind~ : SteerKind, text~ : String)
  Compact
  Cancel
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
    // Like `auto` below, the tag is written only when present: omission is
    // what an untagged prompt has always looked like on this wire, so the
    // common line stays byte for byte what every controller has written.
    Prompt(text~, submission_id~) =>
      if submission_id is Some(id) {
        { "command": "prompt", "text": text, "submission_id": id }
      } else {
        { "command": "prompt", "text": text }
      }
    Steer(kind~, text~) =>
      {
        "command": "steer",
        "kind": match kind {
          Prompt => "prompt"
          Command => "command"
        },
        "text": text,
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
/// binary. A field that is merely unread — `text` on a command nobody
/// inspects — is still required: its absence means the line is not what it
/// claims.
pub fn Command::parse(line : Json) -> Result[Command, String] {
  match line {
    { "command": "prompt", "text": String(text), .. } =>
      match line {
        { "submission_id": String(id), .. } =>
          Ok(Prompt(text~, submission_id=Some(id)))
        { "submission_id": _, .. } =>
          Err("expected a string \"submission_id\" field")
        // An untagged prompt: see the absence rule above.
        _ => Ok(Prompt(text~, submission_id=None))
      }
    { "command": "steer", .. } => parse_steer(line)
    { "command": "prompt", .. } => Err("expected a string \"text\" field")
    { "command": "compact", .. } => Ok(Compact)
    { "command": "cancel", .. } => Ok(Cancel)
    // A blank goal decodes: `{"action":"set","text":"  "}` is a well-formed
    // command, and refusing it is the engine's policy, not the wire's shape.
    // Keeping the check here would make `GoalSet(text="  ")` a value this type
    // can hold, `to_json` can write, and `parse` then rejects — a round-trip
    // the type advertises and would not have. `serve` rejects it, in the same
    // words, where the policy lives.
    { "command": "goal", "action": "set", "text": String(text), .. } =>
      Ok(GoalSet(text~, auto=line is { "auto": True, .. }))
    { "command": "goal", "action": "clear", .. } => Ok(GoalClear)
    { "command": "goal", .. } =>
      Err(
        "expected {\"action\": \"set\", \"text\": ...} or {\"action\": \"clear\"}",
      )
    // Both fields are required. Neither has a defensible default: an approval
    // with no `id` answers no particular question, and one with no `allow` is
    // a decision that did not decide — silently reading either as absent would
    // settle a permission prompt on a guess.
    { "command": "approval", "id": String(id), "allow": True, .. } =>
      Ok(ApprovalDecision(id~, allow=true))
    { "command": "approval", "id": String(id), "allow": False, .. } =>
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
  // `text` is required whatever the kind says, so it is checked once here
  // rather than restated in three arms, where the precedence between "no text"
  // and "bad kind" was emergent from their order.
  guard line is { "text": String(text), .. } else {
    return Err("expected a string \"text\" field")
  }
  match line {
    { "kind": String("prompt"), .. } => Ok(Steer(kind=Prompt, text~))
    { "kind": String("command"), .. } => Ok(Steer(kind=Command, text~))
    { "kind": String(other), .. } => Err("unknown steer kind: \{other}")
    { "kind": _, .. } => Err("expected a string \"kind\" field")
    // A steer with no kind at all is a prompt steer: see the rule above.
    _ => Ok(Steer(kind=Prompt, text~))
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
