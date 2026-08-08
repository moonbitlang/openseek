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
pub fn decode(arguments : String) -> Array[Step]? {
  let json = @json.parse(arguments) catch { _ => return None }
  guard json is Object(fields) && fields.get("steps") is Some(Array(entries)) else {
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
/// `(call id, steps)` when `item` is a `plan` call the tool applied.
///
/// A call the tool rejected (`is_error`) never became the model's plan, so it
/// is not one here either — it keeps the generic failed-call rendering. A call
/// still waiting for its result does count: `plan` executes synchronously, so
/// the unresolved window is a frame, and holding the checklist back for it
/// would make the panel lag the run.
fn applied_call(item : @transcript.TranscriptItem) -> (String, Array[Step])? {
  guard item.kind
    is Tool(
      name="plan",
      call_id~,
      arguments=Some(arguments),
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
/// A call with an empty id (a streaming glitch), or an id shared by several
/// plan calls, gets no entry either: a per-id lookup cannot say which call it
/// belongs to, and a wrong baseline fabricates plan history.
pub fn baselines(
  items : Array[@transcript.TranscriptItem],
) -> Map[String, Array[Step]] {
  let counts : Map[String, Int] = Map([])
  for item in items {
    guard applied_call(item) is Some((id, _)) else { continue }
    counts.set(id, counts.get(id).unwrap_or(0) + 1)
  }
  let baselines : Map[String, Array[Step]] = Map([])
  let mut previous : Array[Step]? = None
  for item in items {
    guard applied_call(item) is Some((id, steps)) else { continue }
    if id != "" && counts.get(id) == Some(1) && previous is Some(prev) {
      baselines.set(id, prev)
    }
    previous = Some(steps)
  }
  baselines
}

///|
/// Whether this plan reads as an evolution of `baseline` — at least half the
/// steps of the smaller of the two carried over by title — rather than a
/// wholesale rewrite. Measuring against the smaller plan keeps a pure
/// extension (every old step kept, new ones appended) an evolution instead of
/// branding an intact plan "rewritten". Only an evolution gets per-step change
/// markers; diffing a rewrite against the old plan would chip every row.
fn evolves(steps : Array[Step], baseline : Array[Step]?) -> Bool {
  guard baseline is Some(previous) && !previous.is_empty() else { return false }
  let carried = steps.count_if(step => {
    previous.any(old => old.title == step.title)
  })
  let smaller = if steps.length() < previous.length() {
    steps.length()
  } else {
    previous.length()
  }
  carried * 2 >= smaller
}

///|
/// What changed for `step` against the previous plan call, as marker text that
/// doubles as a CSS class suffix; `None` when nothing changed or there is no
/// usable baseline. Leaving a completed step is checked first, so finished
/// work coming back reads "reopened" rather than a benign "started".
fn delta(step : Step, baseline : Array[Step]?) -> String? {
  guard baseline is Some(previous) && !previous.is_empty() else { return None }
  for old in previous {
    if old.title == step.title {
      return match (old.status, step.status) {
        (before, after) if before == after => None
        (Completed, _) => Some("reopened")
        (_, Completed) => Some("done")
        (_, InProgress) => Some("started")
        // in_progress -> pending: the step was set aside, not reopened.
        (_, _) => Some("paused")
      }
    }
  }
  Some("new")
}

///|
/// Steps present in the baseline plan but absent (by title) from this one — a
/// silently cut step is exactly what a reader wants to notice.
fn dropped(steps : Array[Step], baseline : Array[Step]?) -> Array[Step] {
  guard baseline is Some(previous) else { return [] }
  previous.filter(old => !steps.any(step => step.title == old.title))
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
