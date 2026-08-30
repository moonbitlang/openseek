# agent_explore

The `explore` tool: delegate one self-contained question to a read-only scout
subagent (a dedicated `openseek subrun explore` child process on the `@agent_subrun` substrate) and get back a bounded, cited answer.

Why it exists: long autonomous runs burn their context on fan-out reading,
and MoonBit is young enough that model priors about its APIs are unreliable.
The scout answers workspace questions ("where is X handled") and MoonBit API
questions (what a package offers, exact signatures) with `moon ide doc` as
its primary instrument, returning `file:line` citations the parent can
spot-check — conclusions enter the parent's context, never file dumps.

Contract highlights:

- Child toolset: `read` + `mbtx` + `submit_answer` — no edit tools, no
  nested subagent tools. Commands run from a `mbtx` snippet through the
  shell-free `moonbitlang/async/shell` API, and the source-write sandbox denies
  writes to the workspace's own sources. A per-child scratch lab (temp dir) is
  the one writable place: the scout may scaffold throwaway projects and run any
  moon command there to verify claims empirically.
- Every report field is capped at submission (`ExploreReport::validate`), so
  the rendered result stays far below the loop's tool-result clamp.
- Launching takes one slot of the shared per-turn `SubrunBudget` call
  allowance BEFORE the child exists; an exhausted allowance refuses without
  spending anything, and a granted child always runs at its full ceiling.
- Failure is graceful: no report / timeout / budget exhaustion all return an
  is_error result telling the parent to fall back to reading directly.

## Evaluating Parent Tool Selection

Prompt wording is effective only if the parent model chooses `explore` at the
right time. A unit test that checks whether the prompt contains a phrase cannot
measure that behavior. Compare the baseline and candidate prompts with the same
model, thinking mode, repository revision, user tasks, and step budget. Run each
case at least ten times because tool selection is nondeterministic.

Use a balanced case set:

- **Parallel-positive:** one read-only architecture question with two or three
  independent tracks, such as tracing subrun budgeting, explore child launch,
  and desktop result presentation. The desired first action is one batched
  assistant step containing two or three non-overlapping `explore` calls.
- **Single-positive:** one broad cross-package flow question. The desired
  behavior is one early `explore` call followed by targeted spot-checks.
- **Negative control:** an exact symbol or known-file question answerable with
  one `moon ide doc` query or one focused read. The desired behavior is no
  `explore` call.

Record positive selection rate, first-step parallel batch rate, negative-control
over-delegation, duplicate/overlapping scout questions, citations that survive
spot-checking, tool errors, total model steps, tokens, and wall time. Promote a
prompt change only when selection and useful batching improve without materially
raising negative-control delegation, errors, or end-to-end cost. Run the normal
`eval/prompt_task` suite as a regression check after this focused selection A/B;
its implementation tasks measure overall task quality but are not, by
themselves, a sensitive test of `explore` selection.
