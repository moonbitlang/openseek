// The `plan` tool's checklist, read back out of the transcript. Every call
// carries the whole plan and replaces the previous one, so the standing plan
// is simply the last call the tool accepted — there is no plan state to hold,
// subscribe to, or reconcile here, only recorded arguments to decode.

///|
/// One step of a recorded plan. The title is already trimmed for display.
pub struct Step {
  title : String
  status : Status
} derive(Eq, @debug.Debug)

///|
/// A step's status. `Other` keeps a status word this build does not know
/// (a newer engine's, say) rather than folding it into `Pending`: showing a
/// blocked step as an untouched circle would misreport it.
pub enum Status {
  Pending
  InProgress
  Completed
  Other(String)
} derive(Eq, @debug.Debug)

///|
/// Ceilings on what is worth decoding, in UTF-16 code units and in steps.
///
/// The transcript records a call's arguments whether or not the tool accepted
/// them, so a degenerate payload — a model looping, or anything past the
/// tool's own caps — reaches this package, and every render decodes it: the
/// card builds one DOM row per step even while its `details` sits collapsed
/// (as the generic arguments path notes, a collapsed node is still built).
/// Past these bounds the call keeps the generic rendering, which clamps
/// before parsing.
///
/// Deliberately far above the tool's own limits (20 steps, 120-character
/// titles) rather than mirroring them: this is a resource bound, not a second
/// copy of the validation, and it must not start rejecting real plans if
/// those limits are ever raised.
const MAX_PAYLOAD_CHARS = 128_000

///|
const MAX_RENDERED_STEPS = 200

///|
/// The steps of a recorded `plan` call, or `None` when `arguments` is not a
/// plan payload this build can read. An accepted call carrying an empty array
/// cleared the plan and decodes as `Some([])`.
///
/// Deliberately more permissive than the tool's own decoder — it does not
/// re-check title length, single-line titles, or the at-most-one-`in_progress`
/// rule. Whether a call was actually applied is the paired result's
/// `is_error`, not a rule re-implemented here, and a second copy of the
/// validation would only drift from the one that matters. The one thing it
/// does reject is a step missing its title or status: inventing a row for it
/// would show a plan that never existed.
///
/// It does refuse a payload too large to be a plan at all — see
/// `MAX_PAYLOAD_CHARS` — because that is a cost question rather than a
/// validation one.
pub fn decode(arguments : String) -> Array[Step]? {
  if arguments.length() > MAX_PAYLOAD_CHARS {
    return None
  }
  let json = @json.parse(arguments) catch { _ => return None }
  guard json is Object(fields) && fields.get("steps") is Some(Array(entries)) else {
    return None
  }
  if entries.length() > MAX_RENDERED_STEPS {
    return None
  }
  let steps = []
  for entry in entries {
    guard entry is Object(fields) &&
      fields.get("title") is Some(String(title)) &&
      fields.get("status") is Some(String(status)) else {
      return None
    }
    steps.push({ title: title.trim().to_owned(), status: parse_status(status), })
  }
  Some(steps)
}

///|
fn parse_status(word : String) -> Status {
  match word {
    "pending" => Pending
    "in_progress" => InProgress
    "completed" => Completed
    _ => Other(word)
  }
}

///|
/// What a recorded `plan` call amounts to.
///
/// The store commits a call and its result as two separate durable events, so
/// every reader necessarily observes calls between the two — briefly during a
/// healthy run, and forever for a run interrupted in that window. The states
/// are named here, once, rather than left for each caller to reconstruct out
/// of `has_result` and `is_error`: a caller then has to say which ones it
/// accepts, and a state it fails to consider is a missing match arm rather
/// than a missing `&&`.
pub enum Call {
  /// The tool ran and accepted it, so this call is what the model's plan
  /// became. An empty step list is the model clearing the plan.
  Applied(Array[Step])
  /// Recorded, with no result yet — the model asked for this plan, and
  /// whether it took effect is not yet known.
  Pending(Array[Step])
  /// A plan call whose payload this build cannot produce steps from: past the
  /// decode bounds, shaped in a way it does not recognize (a newer engine
  /// raising the tool's caps, say), or a result the loader could not pair
  /// back to its call, which leaves no arguments at all.
  ///
  /// `applied` carries the same distinction `Applied` and `Pending` do, and
  /// it is the whole weight of this state: an applied one is evidence the
  /// plan changed to something unknown, while a pending one is evidence of
  /// nothing yet.
  Unreadable(applied~ : Bool)
  /// The tool refused the payload, so it never became a plan at all.
  Rejected
}

///|
/// Classify a tool call as a `plan` call, or `None` when it is another tool.
///
/// A plan call this build cannot read is `Unreadable`, never `None`. The
/// difference matters to `latest`: "this call is not a plan call" is something
/// to scan past, while "a plan call landed here and its content is not
/// available" may be a wall.
pub fn classify(call : @transcript.ToolCall) -> Call? {
  guard call.name == "plan" else { return None }
  let applied = match call.outcome {
    @transcript.ToolOutcome::Done(is_error=true, ..) => return Some(Rejected)
    @transcript.ToolOutcome::Done(..) => true
    @transcript.ToolOutcome::Pending(..) => false
  }
  // Absent arguments are a call whose source recorded no payload. The payload
  // is gone, but the recorded call is still evidence it ran.
  guard call.arguments is Some(arguments) && decode(arguments) is Some(steps) else {
    return Some(Unreadable(applied~))
  }
  Some(if applied { Applied(steps) } else { Pending(steps) })
}

///|
/// The steps of the last applied `plan` call in `calls`, or `None` when there
/// is none — including when the last one cleared the plan, which is the
/// model saying the checklist no longer applies.
///
/// Only `Applied` counts. A rejected call never became the model's plan; a
/// pending one is not known to have, and a run interrupted in that window
/// leaves it pending for good, so honouring it would let arguments that never
/// executed stand as the plan for the rest of the session — or, if they
/// cleared it, hide the last plan that really did apply.
///
/// An *applied* `Unreadable` call ends the search with no plan rather than
/// being scanned past. The tool accepted it, so the plan *was* replaced; this
/// build just cannot say with what. Walking past it would answer with the
/// plan before it — a stale answer stated as a current one, and silently,
/// which is worse than showing nothing. A pending one is no such evidence and
/// is skipped, exactly as a pending readable call is; a malformed call is
/// unresolved for the moment before its rejection lands, and blanking the
/// meter there would flicker on every one of them.
///
/// Over one run of activity this is the plan as that run left it.
pub fn latest(calls : Array[@transcript.ToolCall]) -> Array[Step]? {
  for call in calls.rev_iter() {
    match classify(call) {
      Some(Applied(steps)) =>
        return if steps.is_empty() { None } else { Some(steps) }
      Some(Unreadable(applied=true)) => return None
      Some(Pending(_))
      | Some(Unreadable(applied=false))
      | Some(Rejected)
      | None => continue
    }
  }
  None
}

///|
/// How many of these steps are completed.
fn completed_count(steps : Array[Step]) -> Int {
  steps.count_if(step => step.status is Completed)
}

///|
/// The step the model says it is on, if any. The tool admits at most one, so
/// the first match is the only one.
fn active_step(steps : Array[Step]) -> Step? {
  steps.iter().find_first(step => step.status is InProgress)
}

///|
/// The one-line reading of a plan, in the same shape the tool's own brief
/// uses (`plan 3/5 · fix the parser`). The progress meter carries it as a
/// tooltip, so a collapsed run names its active step on hover.
fn summary_line(steps : Array[Step]) -> String {
  let completed = completed_count(steps)
  let total = steps.length()
  if active_step(steps) is Some(step) {
    "plan \{completed}/\{total} · \{step.title}"
  } else if completed == total {
    "plan \{completed}/\{total} · all steps done"
  } else {
    "plan \{completed}/\{total}"
  }
}

///|
pub extend Status with Debug::{to_repr}

///|
pub extend Status with Eq::{equal, not_equal}

///|
pub extend Step with Debug::{to_repr}

///|
pub extend Step with Eq::{equal, not_equal}
