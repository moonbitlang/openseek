# Transcript minimal mode

Status: implemented.

Minimal mode is a presentation of the shared transcript component, selected by
one application-wide preference. The projection from provider events to
transcript items is the same in both modes; only the component decides what to
show. The behavior itself is specified by the tests in
`desktop/frontend/transcript/component/minimal_wbtest.mbt` and
`desktop/e2e/tests/transcript_minimal.spec.js`, and the vocabulary lives in
`CONTEXT.md`.

## Decisions that are not visible in the code

- Minimal mode is the default for a new profile. An explicit opt-out is stored
  with the other local appearance preferences, so it survives restarts but does
  not roam between devices.
- The switch lives in Settings, under Interface, as "Transcript details". It
  was first placed in the conversation title bar and moved back: a display
  preference that applies to every conversation is not a per-conversation
  runtime fact, which is what the title bar shows.
- Reasoning is hidden in minimal mode for this version. Assistant progress
  messages stay visible while a turn runs.
- Activity summaries name the kinds of work, never counts of files or calls.
  The one number shown is the count of failed tool calls, because a failure is
  what a reader needs to notice.
- Categories come only from tool names. Arguments, script contents, and output
  are never inspected to classify a call, so a description cannot reclassify
  what a script did.
- Elapsed-time display was dropped from scope. It would need a persisted
  turn-start marker that no entry point currently records reliably: idle shell
  context and in-turn steering are also persisted as user records, and a
  submission id is absent for legitimate starts from other entry points.
- OpenSeek can finish a turn successfully without final text (the finish tool
  accepts an empty answer). Such a turn is a boundary, not an answer: its
  process stays unfolded and a later answer cannot fold it.

## Out of scope

- Raw tool parameters and output within minimal mode, editor widgets, and
  side-by-side diff layouts. Edit previews are static HTML.
- Reasoning display within minimal mode.

These are reversible presentation choices; no ADR is warranted.
