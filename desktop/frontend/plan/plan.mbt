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
/// (as the generic arguments path notes, a collapsed node is still built),
/// and `baselines` decodes every plan call in the conversation. Past these
/// bounds the call keeps the generic rendering, which clamps before parsing.
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
    steps.push({ title: title.trim().to_owned(), status: parse_status(status) })
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
/// `(call id, steps)` when `item` is a `plan` call the tool applied — that is,
/// one that recorded a result, and a successful one.
///
/// A call the tool rejected (`is_error`) never became the model's plan, so it
/// is not one here either; it keeps the generic failed-call rendering. A call
/// with no result yet is the same story for a different reason: `plan` runs
/// synchronously, so the live gap is a frame, but a run interrupted between
/// the assistant event and its result leaves that call unresolved *forever* —
/// and arguments that were never executed would otherwise stand as the plan
/// for the rest of the session, or, if they cleared it, hide the last plan
/// that really did apply.
fn applied_call(item : @transcript.TranscriptItem) -> (String, Array[Step])? {
  guard item.kind
    is Tool(
      name="plan",
      call_id~,
      arguments=Some(arguments),
      has_result=true,
      is_error=false,
      ..
    ) else {
    return None
  }
  guard decode(arguments) is Some(steps) else { return None }
  Some((call_id, steps))
}

///|
/// The steps of the last applied `plan` call in `items`, or `None` when there
/// is none — including when the last one cleared the plan, which is the
/// model saying the checklist no longer applies.
///
/// Over a whole conversation this is the standing plan; over one folded run
/// of activity it is the plan as that run left it.
pub fn latest(items : Array[@transcript.TranscriptItem]) -> Array[Step]? {
  for item in items.rev_iter() {
    guard applied_call(item) is Some((_, steps)) else { continue }
    return if steps.is_empty() { None } else { Some(steps) }
  }
  None
}

///|
/// For each applied `plan` call, the steps of the previous applied call — the
/// baseline whose differences its card marks. A session's first plan has no
/// entry and renders without change markers.
///
/// Keyed by call id, which the view uses to look a card's baseline back up.
/// The engine's streaming assembly slots tool calls by their delta `index`
/// and copies each id through from the provider, so ids within a message are
/// as distinct as the provider made them.
pub fn baselines(
  items : Array[@transcript.TranscriptItem],
) -> Map[String, Array[Step]] {
  let baselines : Map[String, Array[Step]] = Map([])
  let mut previous : Array[Step]? = None
  for item in items {
    guard applied_call(item) is Some((id, steps)) else { continue }
    if previous is Some(prev) {
      baselines.set(id, prev)
    }
    previous = Some(steps)
  }
  baselines
}

///|
/// Whether this update reads as a wholesale rewrite rather than an evolution
/// of the plan it replaced: fewer than half the steps of the smaller of the
/// two carried over. A rewrite would mark nearly every row, which drowns the
/// checklist, so it gets a single note instead. Measuring against the smaller
/// plan keeps a pure extension — every old step kept, new ones appended — an
/// evolution instead of branding an intact plan "rewritten".
///
/// "Carried" is read off `markers`, the same one-to-one pairing the change
/// markers come from: a step that paired with a baseline step is anything but
/// `new`. Counting titles independently here would let the classifier and the
/// markers disagree about which steps carried over — a plan repeating a title
/// would look like an evolution to a by-title count while the pairing marked
/// nearly every row.
fn rewrites(
  steps : Array[Step],
  baseline : Array[Step]?,
  markers : Array[String?],
) -> Bool {
  guard baseline is Some(previous) && !previous.is_empty() else { return false }
  let carried = markers.count_if(marker => marker != Some("new"))
  let smaller = if steps.length() < previous.length() {
    steps.length()
  } else {
    previous.length()
  }
  carried * 2 < smaller
}

///|
/// What each step changed against the plan it replaced — marker text that
/// doubles as a CSS class suffix, `None` for a step that did not move — plus
/// the baseline steps this update dropped. With no baseline to diff against
/// (a session's first plan, or a rewrite) every marker is `None` and nothing
/// is dropped, so the checklist renders bare.
///
/// Both come out of pairing titles **one to one**, consuming each baseline
/// step at most once. A plan may legitimately repeat a title — nothing
/// constrains what the model writes — and matching every occurrence against
/// the first old step of that name invents changes (two `run tests` steps
/// would trade each other's statuses) while hiding the removal of a single
/// duplicate, since another occurrence still answers for the title.
///
/// Steps that did not move are paired first. Which of several same-titled
/// steps a survivor "is" has no answer, so the tie goes to the reading that
/// claims the least: pairing a completed `run tests` with a *pending* one
/// when an already-completed one was free would report work finishing that
/// may never have happened. Whatever ambiguity survives that rule is between
/// steps identical in both title and status — rows nobody can tell apart, so
/// no remaining choice is observably wrong.
fn changes(
  steps : Array[Step],
  baseline : Array[Step]?,
) -> (Array[String?], Array[Step]) {
  guard baseline is Some(previous) && !previous.is_empty() else {
    return ([ for _ in steps => None ], [])
  }
  let paired = Array::make(previous.length(), false)
  let carried = Array::make(steps.length(), false)
  // A step with no counterpart at all is one this update added.
  let markers : Array[String?] = Array::make(steps.length(), Some("new"))
  for index, step in steps {
    for old_index, old in previous {
      if !paired[old_index] &&
        old.title == step.title &&
        old.status == step.status {
        paired[old_index] = true
        carried[index] = true
        markers[index] = None
        break
      }
    }
  }
  for index, step in steps {
    if carried[index] {
      continue
    }
    for old_index, old in previous {
      if !paired[old_index] && old.title == step.title {
        paired[old_index] = true
        carried[index] = true
        markers[index] = status_delta(old.status, step.status)
        break
      }
    }
  }
  (markers, [ for index, old in previous if !paired[index] => old ])
}

///|
/// How a step's status moved. Leaving a completed step is checked first, so
/// finished work coming back reads "reopened" rather than a benign "started".
fn status_delta(before : Status, after : Status) -> String? {
  if before == after {
    return None
  }
  Some(
    match (before, after) {
      (Completed, _) => "reopened"
      (_, Completed) => "done"
      (_, InProgress) => "started"
      // in_progress -> pending: the step was set aside, not reopened.
      _ => "paused"
    },
  )
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
