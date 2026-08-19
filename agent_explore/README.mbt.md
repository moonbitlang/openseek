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

- Child toolset: `read` + `run_moonbit` + `submit_answer` — no edit tools, no
  nested subagent tools. Commands run from a `run_moonbit` snippet through the
  shell-free `bobzhang/myshell` EDSL, and the source-write sandbox denies
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
