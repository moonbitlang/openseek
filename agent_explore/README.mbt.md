# agent_explore

The `explore` sub-run kind: a read-only scout that answers one self-contained
question about the workspace or the MoonBit APIs it can use, and submits a
bounded, cited answer. The scout runs as an `openseek subrun explore` child
process; this package is the child half (`run_child` decodes the input line
and runs the kind in-process on `@agent_kind.execute_kind`). Who launches it:

- a parent agent's `mbtx` snippet running a `moonbitlang/workflow` workflow
  with `subrun: true` — `wf.agent(prompt=..., kind="explore")` is one scout,
  and the library sends the child `{"query": prompt, "hints"?: ...}` (the
  `agent_workflow` adapter spawns and reaps it);
- a standalone workflow script, or anything else that speaks the subrun
  child contract with the same input line.

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
  the report stays far below the loop's tool-result clamp.
- Failure is graceful: a scout that never submits, times out, or dies at its
  step ceiling is a failed `wf.agent` call — `@workflow.attempt` turns it
  into an `Err` and `collect_ok` keeps the answers that did arrive.

## Evaluating Parent Delegation

Prompt wording is effective only if the parent model fans out scouts at the
right time. A unit test that checks whether the prompt contains a phrase cannot
measure that behavior. Compare the baseline and candidate prompts with the same
model, thinking mode, repository revision, user tasks, and step budget. Run each
case at least ten times because delegation is nondeterministic.

Use a balanced case set:

- **Parallel-positive:** one read-only architecture question with two or three
  independent tracks, such as tracing subrun budgeting, workflow child launch,
  and desktop result presentation. The desired first action is one `mbtx` call
  with `subrun: true` whose workflow runs two or three non-overlapping scouts.
- **Single-positive:** one broad cross-package flow question. The desired
  behavior is one early scout followed by targeted spot-checks.
- **Negative control:** an exact symbol or known-file question answerable with
  one `moon ide doc` query or one focused read. The desired behavior is no
  scout.

Record positive delegation rate, first-step fan-out rate, negative-control
over-delegation, duplicate/overlapping scout questions, citations that survive
spot-checking, snippet compile failures, total model steps, tokens, and wall
time. Promote a prompt change only when delegation and useful fan-out improve
without materially raising negative-control delegation, errors, or end-to-end
cost. Run the normal `eval/prompt_task` suite as a regression check after this
focused A/B; its implementation tasks measure overall task quality but are
not, by themselves, a sensitive test of scout delegation.
