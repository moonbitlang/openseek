# Desktop UX guidelines

This document defines interaction principles that should remain true as the
Desktop product grows. It complements [`DESIGN.md`](DESIGN.md): that document
defines the visual language, while this one defines how the interface behaves,
communicates, and protects the user's attention. CSS implementation rules remain
in [`styles/README.md`](styles/README.md). Detailed feedback, motion, timing,
recovery, and accessibility defaults live in
[`UX_GUARDRAILS.md`](UX_GUARDRAILS.md) and should be loaded when that detail is
relevant.

> **Let people entrust real software work to agents without losing context,
> evidence, or control.**

These guidelines deliberately avoid application-specific state machines and
component APIs. A feature specification may add more detail, but should not
weaken these principles. In this document, **must** is a product requirement;
**must not**, **never**, and **do not** are product prohibitions; **should** and
**prefer** are defaults that need a clear reason to override; and **avoid** means
**should not**.

## Experience values

Values are the highest-level test for product decisions. They describe the
experience we want to create, not a component catalog or a checklist of UI
states. The four value names below are adapted from [Ant Design's Design
Values](https://ant.design/docs/spec/values/); their definitions and the
principles derived from them are specific to Desktop. The functional and
emotional framing is influenced by [Fluent Design
Principles](https://fluent2.microsoft.design/design-principles). See [sources
and attribution](UX_GUARDRAILS.md#sources-and-attribution) for provenance and
license details.

### Natural

**Promise:** the workspace behaves the way sustained software work teaches the
user to expect.

Functionally, the interface builds on what the user already understands about
their platform and their work. Intent, action, and effect form a coherent whole
instead of making the user translate between the task and the interface.

Emotionally, Desktop should feel familiar, calm, and direct. The agent may do
complex work, but using it should not feel like managing a performance.

### Certain

**Promise:** the user can tell what the system is doing, what it affected, what
is known, and what remains uncertain.

Functionally, the interface gives an honest and legible account of its state,
effects, evidence, and limits. It reduces ambiguity without manufacturing
confidence that the underlying work cannot support.

Emotionally, Desktop should feel dependable without pretending to be infallible.
Confidence comes from legible state, honest uncertainty, and recoverable
outcomes.

### Meaningful

**Promise:** every visible signal and interruption helps the user understand or
advance the work.

Functionally, each part of the experience serves the user's intent and helps
them understand or advance the work. Detail, emphasis, and interruption are
proportional to their value in the moment.

Emotionally, Desktop should feel focused and purposeful. A quiet interface is
not an inactive one; it is an interface that spends attention carefully.

### Growing

**Promise:** the workspace can become more capable without making the user
relearn it or confront all of its complexity at once.

Functionally, deeper capability builds on familiar ideas and becomes available
in proportion to the user's need and understanding. Growth adds fluency rather
than continually resetting it.

Emotionally, Desktop should reward learning with increasing fluency and agency,
not increasing caution.

## Derived interaction principles

These principles turn the values into reusable product judgments. A feature
specification may define its own states and transitions, but it must preserve
these relationships.

| Value | Principles it primarily governs |
| --- | --- |
| Natural | The user's flow outranks system chatter |
| Certain | State follows work, not focus; Evidence, not theater, earns trust |
| Meaningful | Attention follows agency, not activity |
| Growing | Autonomy follows reversibility; Hide complexity, never consequence |

### State follows work, not focus

A consequential state belongs to the work it describes. Selection may change
its detail or emphasis, but must not determine whether it is discoverable.
Event streams are history, not the sole representation of current state. An
active operation remains glanceable at its owning surface and, when work can
continue in multiple contexts, from a selection-independent overview. Its
outcome and supporting evidence remain available for as long as they can affect
the user's decisions, trust, or recovery; they do not disappear merely because
an event or animation ended.

This principle catches a whole class of defects: a working conversation that
looks idle until another event arrives, a background conversation whose
activity disappears when focus moves elsewhere, or a completed operation that
has no durable result. These are not separate exceptions; each confuses view
state with work state.

### Attention follows agency, not activity

Activity should be observable without automatically becoming an interruption.
Escalate attention when the user can make a useful decision, when work is at
risk, or when an outcome changes what the user can safely do next. Routine
background work should remain quiet even when it is busy.

### Evidence, not theater, earns trust

Feedback must describe what the system can support as true. Distinguish an
accepted request from running work, a produced result from a verified result,
and confidence from evidence whenever the difference matters. Animation,
confident language, and a generic “working” state must never substitute for an
inspectable result or an honest limitation.

### Autonomy follows reversibility

Within the goal and scope the user has authorized, the easier an action is to
stop, inspect, undo, or repair, the more freely the system may perform it.
Reversibility does not create permission. As consequences become broader, less
predictable, or harder to reverse, the interface must make scope clearer and
give the user more opportunity to preview, constrain, or confirm the action.

### The user's flow outranks system chatter

Background updates should preserve focus, selection, scroll position, open
context, and unfinished input. They must not move controls or steal focus merely
to announce progress or routine success. If the user leaves a live-following
position, the system must respect that choice instead of pulling the viewport
back.

### Hide complexity, never consequence

Progressive disclosure may simplify machinery, diagnostics, or advanced
controls. It must not conceal what will change, what did change, whether the
result is trustworthy, what failed, or how the user can recover. Simplicity is
the removal of unnecessary decisions, not the removal of necessary truth.

## Operational companion

Concrete defaults for feedback, wait thresholds, motion, reduced motion,
control and recovery, and perceivable state live in
[`UX_GUARDRAILS.md`](UX_GUARDRAILS.md). Feature specifications may tighten
those defaults but must not weaken the values or principles above.

## Review with the values

Use the values before checking individual pixels or component conventions:

- **Natural:** Does the interaction fit the user's existing mental model and
  preserve continuity while work changes?
- **Certain:** Can the user discover the state of relevant work regardless of
  focus or whether a new event just arrived? Does the UI distinguish claims
  from evidence and uncertainty from failure?
- **Meaningful:** Does every signal change understanding or enable an action?
  Is interruption proportional to the user's agency, and does motion explain
  something that would otherwise be lost?
- **Growing:** Can capability expand without destabilizing familiar workflows?
  Are complexity and advanced controls disclosed progressively while
  consequences remain explicit?

Then verify the [non-negotiable operational
guardrails](UX_GUARDRAILS.md): readable content never flashes or moves while it
must be read; ongoing work remains observable while active and its consequential
outcome remains available; progress is honest; recovery preserves unrelated
work; and the complete workflow remains understandable with motion disabled.
