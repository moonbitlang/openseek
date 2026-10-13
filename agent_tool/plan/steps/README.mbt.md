# agent_tool/plan/steps

The plan vocabulary and its decoder: `PlanStatus`, `PlanStep`, `PlanInput`, and
the `decode` that turns `plan` tool-call arguments into them.

`agent_tool/plan` decodes calls with it; `viz` renders stored plans with it. The
types live here rather than in `agent_tool/plan` so the renderer does not have
to depend on the tool.

## A plan call replaces the whole plan

`steps` is not a delta. Every call carries the complete, ordered list, and an
empty array is the documented way to clear the plan. That is why `decode` has no
notion of adding, removing, or reordering — there is only one operation.

```mbt check
///|
test "a plan is the whole ordered list, and empty clears it" {
  debug_inspect(
    @steps.decode({
      "steps": [
        { "title": "reproduce the failing test", "status": "completed" },
        { "title": "fix the decoder", "status": "in_progress" },
        { "title": "run moon test", "status": "pending" },
      ],
    }),
    content=(
      #|{
      #|  steps: [
      #|    { title: "reproduce the failing test", status: Completed },
      #|    { title: "fix the decoder", status: InProgress },
      #|    { title: "run moon test", status: Pending },
      #|  ],
      #|}
    ),
  )
  debug_inspect(
    @steps.decode({ "steps": [] }),
    content=(
      #|{ steps: [] }
    ),
  )
}
```

## `label` is the wire spelling

`PlanStatus::label` produces exactly the strings `decode` accepts, so a decoded
plan round-trips. Consumers also use it as a stable machine-readable tag — the
plan reminder's `[status]` brackets, the viewer's CSS classes — which is why it
is a method on the enum rather than a formatting detail of either consumer.

```mbt check
///|
test "every label decodes back to the status it came from" {
  let decoded = @steps.decode({
    "steps": [
      { "title": "a", "status": "pending" },
      { "title": "b", "status": "in_progress" },
      { "title": "c", "status": "completed" },
    ],
  })
  debug_inspect(
    decoded.steps.map(step => step.status),
    content="[Pending, InProgress, Completed]",
  )
  // Each decoded status spells itself back as the wire form it came from.
  inspect(
    decoded.steps.map(step => step.status.label()).join(" "),
    content="pending in_progress completed",
  )
}
```

The variants are readable but not constructible from outside the package: a
plan reaches consumers by being decoded, never by being assembled field by
field.

## Strict by design

`agent_tool/finish/internal/decode` is deliberately lenient because a bad
`finish` should still end the run. `plan` is the opposite: a malformed plan is
worth one round-trip to correct, since the plan is shown to the user and
replayed into context on every subsequent request. Every rule below rejects
rather than repairs.

```mbt check
///|
/// True when decoding `arguments` fails with a message containing `expected`.
/// The raw error also carries `fail`'s source location, which is why the test
/// matches on a substring rather than snapshotting the whole string.
fn rejects(arguments : Json, expected : String) -> Bool {
  try {
    ignore(@steps.decode(arguments))
    false
  } catch {
    err => "\{err}".contains(expected)
  }
}

///|
test "the payload must be an object with exactly a steps array" {
  inspect(
    rejects(Json::null(), "arguments to be an object with a steps array"),
    content="true",
  )
  inspect(
    rejects(Json::empty_object(), "arguments.steps to be an array of steps"),
    content="true",
  )
  // Unknown top-level fields are rejected, not ignored.
  inspect(
    rejects(
      { "steps": [], "note": "extra" },
      "arguments to have only the steps field",
    ),
    content="true",
  )
}

///|
test "a step carries exactly a title and a status" {
  inspect(
    rejects(
      { "steps": ["just a string"] },
      "arguments.steps[0] to be an object",
    ),
    content="true",
  )
  // Unknown step fields too: models invent `id` and `notes`, and silently
  // dropping them would lose information the model believed it had recorded.
  inspect(
    rejects(
      { "steps": [{ "title": "a", "status": "pending", "id": 1 }] },
      "arguments.steps[0] to have only title and status fields",
    ),
    content="true",
  )
  inspect(
    rejects(
      { "steps": [{ "status": "pending" }] },
      "arguments.steps[0].title to be present",
    ),
    content="true",
  )
  inspect(
    rejects(
      { "steps": [{ "title": "a" }] },
      "arguments.steps[0].status to be present",
    ),
    content="true",
  )
  inspect(
    rejects(
      { "steps": [{ "title": "a", "status": "done" }] },
      "arguments.steps[0].status to be one of pending|in_progress|completed",
    ),
    content="true",
  )
}
```

## At most one step in progress

The plan answers "what is the agent doing *now*", and two simultaneous answers
make it useless as a progress display. Zero in-progress steps is fine — that is
what a finished plan looks like.

```mbt check
///|
test "one in_progress step at most; zero is allowed" {
  inspect(
    rejects(
      {
        "steps": [
          { "title": "a", "status": "in_progress" },
          { "title": "b", "status": "in_progress" },
        ],
      },
      "arguments.steps to contain at most one in_progress step",
    ),
    content="true",
  )
  debug_inspect(
    @steps.decode({
      "steps": [
        { "title": "a", "status": "completed" },
        { "title": "b", "status": "completed" },
      ],
    }),
    content=(
      #|{ steps: [{ title: "a", status: Completed }, { title: "b", status: Completed }] }
    ),
  )
}
```

## Titles are trimmed, then bounded

Titles are rendered into the UI brief and replayed with the tool-call arguments
on every request, so both limits exist to protect context rather than to enforce
style. The trimmed form is what gets stored, so two titles differing only in
surrounding whitespace are the same title.

```mbt check
///|
test "surrounding whitespace is trimmed before anything else" {
  debug_inspect(
    @steps.decode({
      "steps": [{ "title": "  fix parser\t", "status": "pending" }],
    }),
    content=(
      #|{ steps: [{ title: "fix parser", status: Pending }] }
    ),
  )
}

///|
test "the bounds, and the units they are counted in" {
  inspect(@steps.MAX_STEPS, content="20")
  inspect(@steps.MAX_TITLE_CHARS, content="120")
  let too_many : Array[Json] = [
    for i in 0..<(@steps.MAX_STEPS + 1) => {
      { "title": "step \{i}", "status": "pending" }
    }
  ]
  inspect(
    rejects({ "steps": Json(too_many) }, "at most 20 steps, got 21"),
    content="true",
  )
  // Length counts code points, matching the `maxLength` the advertised JSON
  // Schema promises — so a schema-valid title is never rejected over its
  // encoding. 121 astral characters is 242 UTF-16 code units, and still 121.
  let long_title = "😀".repeat(@steps.MAX_TITLE_CHARS + 1)
  inspect(
    rejects(
      { "steps": [{ "title": long_title, "status": "pending" }] },
      "title to be at most 120 chars, got 121",
    ),
    content="true",
  )
}
```

A title must be non-blank and a single line. Blankness uses the Unicode
White_Space property rather than ASCII trimming, because a title of no-break or
ideographic spaces would otherwise render as an empty row. Newlines are refused
because a title is rendered into a line-oriented brief, where an embedded
newline could forge extra plan rows.

```mbt check
///|
test "blank and multi-line titles are refused" {
  inspect(
    rejects(
      { "steps": [{ "title": "   ", "status": "pending" }] },
      "arguments.steps[0].title to be non-blank",
    ),
    content="true",
  )
  // U+00A0 no-break space, U+3000 ideographic space: invisible, not ASCII.
  inspect(
    rejects(
      { "steps": [{ "title": "\u{00A0}\u{3000}", "status": "pending" }] },
      "arguments.steps[0].title to be non-blank",
    ),
    content="true",
  )
  inspect(
    rejects(
      { "steps": [{ "title": "fix\nparser", "status": "pending" }] },
      "arguments.steps[0].title to be a single line",
    ),
    content="true",
  )
}
```

## Errors never echo model text

Every message above names a *field path* and never interpolates the offending
value. That is deliberate: `agent_tool/internal/error` recovers the message by
splitting on a ` FAILED: ` marker, so a crafted title containing that marker
could truncate the very error meant to correct it.
