# Code Review (`agent_review`)

`agent_review` is OpenSeek's **code-review engine**. It runs a read-only,
compiler-grounded review of a change set and returns a single structured
`ReviewReport`. The engine is deliberately front-end-agnostic: the headless
`openseek review` CLI is one caller today, and the same `ReviewReport` JSON is
the boundary other coding agents (e.g. Codex, Claude) spawn and consume when they
dispatch a review to OpenSeek.

## What it does

`run_review(base, …)` reviews the diff between `base` and `HEAD`:

1. drives a model over a **read-only** toolset (`read`, `mbtx`, and
   `submit_review`) — no `edit`/`multi_edit`/`write`, so it reports rather than
   rewrites;
2. instructs the model to ground every finding in the compiler — run
   `moon check`/`moon test` and cite real diagnostics, not opinion;
3. captures the model's `submit_review` call into a validated `ReviewReport` and
   returns it. If the model finishes without submitting, it raises `ReviewError`.

## The contract: `ReviewReport`

This stable, versioned, flat, string-typed JSON is the integration boundary —
what every front-end returns and every external consumer parses:

```json
{
  "schema_version": 1,
  "scope": { "base": "origin/main", "head": "HEAD", "files": ["a/b.mbt"] },
  "findings": [
    {
      "file": "a/b.mbt",
      "line": 42,
      "severity": "blocker | high | medium | low | nit",
      "category": "correctness | safety | perf | style",
      "title": "short summary",
      "detail": "what and why, with evidence",
      "suggestion": "optional concrete fix"
    }
  ],
  "summary": "one-paragraph overview",
  "stats": { "files_reviewed": 7, "findings": 3, "build": "pass", "tests": "pass" }
}
```

`line` and `suggestion` are optional; everything else is required.
`ReviewReport::validate` rejects malformed output (bad severity, empty
file/title/category/detail/summary, wrong `schema_version`) so a review never
returns a half-formed report — the `submit_review` tool re-prompts the model
instead of finishing.

## Design rationale

- **Engine over `run_turn_in_scope`, not `@agent.run`.** A review needs to
  *capture a typed result*, so the engine builds an ephemeral session, supplies a
  custom tool registry, and reads the report back out of a captured ref —
  `@agent.run` discards the session and returns `Unit`.
- **Structured output is forced, not parsed.** `submit_review`'s JSON schema *is*
  the contract, and the executor validates the arguments before ending the run.
  The agent loop will otherwise accept a bare-text finish; the tool makes "no
  structured report" a retryable error.
- **Compiler-grounded.** The prompt makes the reviewer execute the build/tests
  and report what they actually said — `stats.build` / `stats.tests` are observed
  facts. The MoonBit compiler is reliable; the model's intuition is not.
- **Strongest model.** Review is judgement-heavy, so it pins the Pro model;
  flash is too shallow for the call.

## Read-only stance (best-effort, not airtight)

The review has no edit/write tools, and the commands it runs through
`mbtx` inherit the source-write sandbox, which denies writes to the
workspace's sources — including the bulk source-rewriters (`moon fmt` /
`moon info` / `moon test --update`). It is **not** an airtight guarantee: the
profile is best-effort (a program can still smuggle sources via directory
renames), and where it cannot be enforced at all the run is unsandboxed. By
design, a review *reports* rather than *edits*.

## Using it

Headless, one JSON report on stdout (progress is suppressed so stdout stays
clean), exit code by severity:

```bash
# 0 = clean or non-blocking findings, 1 = the review produced no report,
# 2 = blocker findings present
openseek review --base origin/main
```

Because the report is a stable JSON document on stdout, any orchestrator that can
run a subprocess can use it:

```bash
openseek review --base origin/main | jq '.findings[] | select(.severity=="blocker")'
```

## Ensembling for confidence

A single review run undersamples and varies run-to-run. Because the model is
cheap to re-run, a useful pattern is to run the review **N times and rank
findings by agreement**: a finding several runs surface independently is
high-confidence, while singletons are usually noise. Voting across runs gives the
report a calibrated confidence signal that one pass cannot.

## Layout

| file | role |
| --- | --- |
| `types.mbt` | `ReviewReport` / `Finding` / `ReviewScope` / `ReviewStats`, JSON derive, `to_json_string` |
| `exports.mbt` | `ReviewReport::parse` and `ReviewReport::validate` |
| `submit.mbt` | the `submit_review` structured-output tool |
| `prompt.mbt` | the review system prompt and task |
| `engine.mbt` | `run_review` — the engine, and `ReviewError` |
