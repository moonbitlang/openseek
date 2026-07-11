///|
/// Lifecycle status of one plan step. Named after the update_plan vocabulary
/// (`pending`/`in_progress`/`completed`) that coding models already know;
/// deliberately distinct from any goal-level lifecycle status.
pub enum PlanStatus {
  Pending
  InProgress
  Completed
} derive(Debug, Eq)

///|
/// The wire spelling of a status — the exact strings `decode` accepts, so a
/// decoded plan round-trips identically. Consumers also use it as a stable
/// machine-readable tag (the plan reminder's `[status]` brackets, the
/// viewer's CSS classes).
pub fn PlanStatus::label(self : PlanStatus) -> String {
  match self {
    Pending => "pending"
    InProgress => "in_progress"
    Completed => "completed"
  }
}

///|
test "labels spell statuses exactly as the decoder accepts them" {
  for status in [PlanStatus::Pending, InProgress, Completed] {
    let decoded = decode({
      "steps": [{ "title": "t", "status": status.label() }],
    })
    assert_true(decoded.steps[0].status == status)
  }
}

///|
/// One step of the agent's plan: a short imperative title plus its status.
pub struct PlanStep {
  title : String
  status : PlanStatus
} derive(Debug)

///|
/// Decoded arguments of the `plan` tool: the complete, ordered list of steps.
/// Every call replaces the previous plan, so the array is the whole plan; an
/// empty array clears it.
pub struct PlanInput {
  steps : Array[PlanStep]
} derive(Debug)

///|
/// Upper bound on plan length. More steps than this is a sign the model is
/// planning at the wrong granularity, so decoding rejects it instead of
/// letting the plan crowd out real work.
pub const MAX_STEPS : Int = 20

///|
/// Upper bound on a step title, in Unicode characters (code points), counted
/// after trimming. Titles are rendered into the UI brief and replayed with
/// the tool-call arguments on every request, so oversized titles crowd out
/// context.
pub const MAX_TITLE_CHARS : Int = 120

///|
/// Decode `plan` tool-call arguments.
///
/// Strict by design, unlike `finish`: a malformed plan is fed back to the
/// model as an error naming the first offending field so the next call can
/// correct it. Rules: `steps` is a required array of at most `MAX_STEPS`
/// objects (empty clears the plan) and no other argument fields exist; each
/// step carries exactly a `status` of `"pending"`, `"in_progress"`, or
/// `"completed"` (at most one step in progress) and a `title` that is
/// non-blank, a single line, and at most `MAX_TITLE_CHARS` characters after
/// trimming.
///
/// Error messages never echo model-supplied text: `failure_message` recovers
/// the message by splitting on a marker, so interpolating a crafted value
/// could truncate the very error meant to correct it.
pub fn decode(arguments : Json) -> PlanInput raise {
  guard arguments is Object(fields) else {
    fail("arguments to be an object with a steps array")
  }
  for key, _ in fields {
    if key != "steps" {
      fail("arguments to have only the steps field")
    }
  }
  guard fields is { "steps": Array(items), .. } else {
    fail("arguments.steps to be an array of steps")
  }
  if items.length() > MAX_STEPS {
    fail(
      "arguments.steps to have at most \{MAX_STEPS} steps, got \{items.length()}",
    )
  }
  let steps : Array[PlanStep] = []
  let mut in_progress_count = 0
  for index, item in items {
    let step = decode_step(index, item)
    if step.status is InProgress {
      in_progress_count += 1
      if in_progress_count > 1 {
        fail("arguments.steps to contain at most one in_progress step")
      }
    }
    steps.push(step)
  }
  { steps, }
}

///|
fn decode_step(index : Int, item : Json) -> PlanStep raise {
  guard item is Object(fields) else {
    fail("arguments.steps[\{index}] to be an object")
  }
  for key, _ in fields {
    if key != "title" && key != "status" {
      fail("arguments.steps[\{index}] to have only title and status fields")
    }
  }
  let raw_title = match fields {
    { "title": String(value), .. } => value
    { "title": _, .. } => fail("arguments.steps[\{index}].title to be a string")
    _ => fail("arguments.steps[\{index}].title to be present")
  }
  let title = normalize_title(index, raw_title)
  let status = match fields {
    { "status": String("pending"), .. } => PlanStatus::Pending
    { "status": String("in_progress"), .. } => InProgress
    { "status": String("completed"), .. } => Completed
    { "status": String(_), .. } =>
      fail(
        "arguments.steps[\{index}].status to be one of pending|in_progress|completed",
      )
    { "status": _, .. } =>
      fail("arguments.steps[\{index}].status to be a string")
    _ => fail("arguments.steps[\{index}].status to be present")
  }
  { title, status }
}

///|
/// Trims surrounding whitespace and enforces the non-blank, single-line, and
/// length rules. The trimmed title is what gets rendered, so a title that
/// only differs by surrounding whitespace round-trips identically. Blankness
/// uses the Unicode White_Space property, not just ASCII: a title of
/// no-break or ideographic spaces would otherwise render as an empty row.
/// Length counts code points, matching the `maxLength` the advertised JSON
/// Schema promises, so a schema-valid title is never rejected over its
/// encoding.
fn normalize_title(index : Int, raw_title : String) -> String raise {
  let title = raw_title.trim().to_owned()
  if title.contains("\n") || title.contains("\r") {
    fail("arguments.steps[\{index}].title to be a single line")
  }
  if title.all(ch => ch.is_whitespace()) {
    fail("arguments.steps[\{index}].title to be non-blank")
  }
  let chars = title.char_length()
  if chars > MAX_TITLE_CHARS {
    fail(
      "arguments.steps[\{index}].title to be at most \{MAX_TITLE_CHARS} chars, got \{chars}",
    )
  }
  title
}
