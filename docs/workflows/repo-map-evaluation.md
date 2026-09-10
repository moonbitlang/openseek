# Repo-map live evaluation — 2026-09-09–10

The revised workflow can produce useful first-pass onboarding on OpenSeek,
with exact validation recipes and source-backed examples. Completion and
semantic accuracy remain variable; it deliberately leaves much of a large
repository uninspected. [Latest live output](repo-map-sample.md).
The earlier root-package-only output is retained [here](repo-map-sample-initial.md).

## Method

Compiled the actual bundled `share/workflow/repo-map.mbtx` as Wasm, then ran it
with `moonrun` and a test `WORKFLOW_HOST` handoff pointing to this checkout's
native `openseek subrun explore` binary. Children used the default
`deepseek-v4-flash` model and high thinking, real provider credentials, isolated
session storage, and a host journal/event stream. This exercises the script and
real child contract, not a simulated model and not the outer `mbtx` tool's UI or
approval path. No model was changed between compared runs.

The comparison is exploratory, on one repository, not a statistical benchmark.
The revised task is intentionally narrower, and validation no longer uses a
model. Token totals include repeated/cached prompt tokens; they are not unique
context sizes or dollar costs. Wall times include variable provider latency.

| Version | Submitted reports | Child steps | Accounted tokens | Wall time |
| --- | --- | --- | --- | --- |
| Original three-scout baseline | 1 / 3 | 16 / 16 / 16 | 1,035,558 | 200.6 s |
| Two scouts, shared entry context | 2 / 2 | 3 / 6 | 150,148 | 145.5 s |
| Root-package filenames included | 2 / 2 | 3 / 4 | 114,004 | 117.7 s |
| Nested discovery + citation checks + additive example | 2 / 2 | 3 / 5 | 189,643 | 158.7 s |

Baseline and final runs both completed before their host deadlines (240 and
600 seconds respectively), so deadline truncation does not explain their
reported results. Additional diagnostic iterations were run while tuning;
cancelled/superseded runs are excluded from this table. A proxy connectivity
probe failed while direct access worked, but later transcripts showed actual
model usage even in the initial proxy-enabled run. Connectivity alone did not
explain the workflow's failures.

## What the live runs revealed and changed

- Broad questions led scouts into repeated repository discovery and invalid
  ad hoc MoonBit traversal scripts; two original scouts exhausted 16 steps.
- Shared, numbered entry documents reduced repeated setup. A bounded inventory
  of real root-package filenames removed the need to guess implementation paths.
- A validation scout repeatedly returned plain text instead of calling
  `submit_answer`, leaving no contract-valid report. MoonBit now prints the
  root `justfile` directly and explicitly marks its recipes as not executed.
- An intermediate submission exceeded the 20-citation contract limit. The
  revised task requests at most eight citations and a small, explicit scope.
- The final scouts used only targeted reads and submission, inspecting one
  execution trace and one extension point. Read/word/citation limits in the
  prompt remain guidance; the 12-step limit is enforced by the engine.
- Output preserves citations and unresolved areas as readable Markdown. Missing
  or empty answers and failed scouts still make the run fail visibly.

## Assessment of the first successful output

All 16 citation paths exist and every cited line is in range. Manual checks
confirmed the cited executable declaration, `inspect` main function and
`/api/sessions` route, `viz_export` listing encoder, skill discovery/merge/prompt
functions, and the discovery regression test. The validation block matches the
root `justfile` exactly. These checks support the central claims; they do not
prove every sentence in the generated map.

The strongest improvement is the extension report: it now points to
`agent_skill/skill.mbt` and `agent_skill/skill_test.mbt`, rather than guessing
filenames and relying only on README examples. A newcomer has concrete places
to start reading and a test showing the behavior.

Limitations of that earlier version:

- The inventory covers root-level package directories, not the entire nested
  package tree. The final report explicitly leaves `cmd/openseek` and other
  nested-package implementations uninspected.
- Some architecture statements remain sourced from the README, not independently
  verified against implementation. This is an orientation aid with visible gaps.
- Adding a playbook accepted by existing discovery code does not itself require
  changing the engine's discovery test. The generated suggestion to extend that
  test is useful when changing the discovery/frontmatter contract, and should
  not be followed mechanically for every new skill file.
- The requested 350-word answer limit is not enforced, and the final answers
  exceed it. They are still bounded by the engine report contract.
- Model submission behavior and provider latency varied. Two successful final
  iterations are encouraging evidence, not a reliability guarantee across repos.

## Follow-up: nested discovery and automatic citation validation

The current script inventories package files through depth three, visiting at
most 160 directories and keeping at most 16,000 inventory characters. Hidden,
`_build`, `node_modules`, and `vendor` directories and directory symlinks are
skipped. Omitted areas are marked. The latest report now reads the actual
`cmd/openseek/main.mbt`, `cmd/openseek/README.md`, and `agent/agent.mbt`, rather
than missing the CLI because it is nested below `cmd/`.

Each returned citation is checked in MoonBit: repository-relative path,
positive integer line number, real-path containment (including symlinks), file
readability, and actual line count. A missing citation list or any bad location
makes the workflow incomplete; successful reports remain visible. `CHECKED`
means a valid location, never semantic proof.

That distinction mattered in a diagnostic run: the model proposed sorting
`Map.values()` because it claimed Map iteration was unstable. Every referenced
location existed, yet the recommendation was wrong. The installed API docs
(`moon ide doc '@moonbitlang/core/builtin.Map'`) explicitly describe insertion
ordering. The extension question now asks for a hypothetical additive feature,
forbids inventing a defect to justify it, and reserves a read for an actual test.
This reduces a failure mode; it is not an automated proof of correctness.

In that live run, both scouts finished and all 16 citation locations
passed the script's checks. The extension example uses the real
`AgentToolDefinition`/`ToolExecutor` boundary and the inspected
`agent_tool/web_search/web_search_test.mbt` localhost mock-server test. Manual
inspection confirmed those constructor/executor and test-shape claims. The
hypothetical `fetch_url` example is clearly additive and does not repeat the
Map-ordering error. No proposed feature was implemented by the scouts.

The architecture report now distinguishes its verified CLI dispatch/session
setup from an unverified final hop into the loop, and calls out contradictory
target-support wording in README files instead of pretending to resolve it.
The inventory still does not map symbols to definitions or enumerate every
non-package document. Word/read-count limits remain prompt guidance. These are
onboarding reports with explicit gaps, not exhaustive architecture verification.

This iteration trades tokens for broader coverage: 189,643 versus 114,004 in the
previous successful run. Runtime was 158.7 versus 117.7 seconds; provider latency
and model decisions vary, so neither is a stable performance estimate.

## Follow-up: read package contracts before implementation

The user suggested inspecting `moon.pkg` and `pkg.generated.mbti` before
implementation details. Scouts now follow this order for selected packages,
using imports/target settings and exported signatures to focus source reads.
The suggested read budget is six (still a hard 12-step child ceiling).
Interfaces may be stale or omit private behavior; the scout must not regenerate
them or treat them as proof of caller behavior.

A fresh run of the previous prompt completed 2/2 reports in 16.9 seconds using
115,155 accounted tokens. The first package-first run completed 2/2 in 99.3
seconds using 155,881 tokens (4 and 4 child steps). Both scouts actually read
`moon.pkg` and `pkg.generated.mbti` before source, and 15 citation locations
passed. The architecture report gained a manifest-backed executable/target
check. However, the extension report inferred that consumers needed no changes
from an opaque event API and used a sibling steering test as its example.
Those claims were not supported. The prompt now explicitly disallows that
inference and reminds scouts that directly relevant tests may be embedded in
implementation `.mbt` files. This comparison supports better navigation, not a
claim of lower cost or consistently better reports.

The final prompt run completed one report and failed the other after 417.6
seconds (106,568 accounted tokens). The extension scout read its package
manifest/interface before implementation, including the embedded event tests,
but its subsequent provider call exhausted five connection attempts
(`Tcp::connect(): Operation timed out`, 386,303 ms). The workflow preserved the
architecture report, checked its eight citation locations, and exited nonzero.
The architecture scout did not follow the interface-first instruction and
reported that omission. Its phrase that the root manifest "declares no
package" is also imprecise: `moon.pkg` defines a package boundary even without
an executable declaration. These are unedited model outputs, not authoritative
documentation. The new guidance is retained as a navigation aid, not a proven
reliability improvement. No further live retries were made in that iteration.

All September 10 live comparisons above inspected commit `3aea46ca1` plus the
workflow changes, before rebasing onto the newly fetched origin/main. The
samples are historical evidence; line references may move after that rebase.
`change-review.mbtx` was exercised offline, not evaluated with real review scouts.

## Verification on the rebased PR

A fresh run on PR commit `6b9968968` used the rebuilt native binary and the
unchanged bundled script. Both scouts submitted (3 steps each) in 24.5 seconds,
using 114,414 accounted tokens. All 16 citation locations passed. Transcripts
confirm that each scout read its selected `moon.pkg` and `pkg.generated.mbti`
before implementation. The latest sample is this successful, unedited output.

Manual source review confirmed the executable declaration, session-startup
MCP config read/decode/build path, open `AgentEvent` contract, and the embedded
emit/drain and event-flood tests. The extension report now uses the directly
relevant event tests and does not claim production consumers need no changes.
One wording problem remains: it labels the traced resolver as `openseek mcp` /
session startup, but `run_mcp_command` has a separate fail-fast path; the
resolver's log-and-return-empty behavior applies to session startup. The
proposed bgjobs implementation location is hypothetical and was not read.
Location validation does not establish those claims. This successful run does
not erase the earlier connection failure or prove stable cost/reliability.

Verification also found that CI calls Moon directly and would skip the new
`just test-workflows` recipe. The native CI job now invokes the same offline
Python suite explicitly, before the full workspace check. All 17 scenarios
passed again locally. This verifies the script/child contract; the live run
still does not exercise the outer mbtx UI/approval path.

## Validation

`just test-workflows`: 17 offline scenarios passed, including partial failure,
missing/insufficient handoff, empty answers, absent recipes, excerpt truncation,
nested-package filenames in shared context, empty citation lists, missing files,
unreadable directory citations, fractional/out-of-range lines, traversal, and
escaping symlinks. Both scripts compile for Wasm
with warnings denied. `just build`, `moon info`, formatting, prompt consistency,
and whitespace checks passed; no generated public interfaces changed. After
rebasing, `moon test agent_tool/mbtx --target native` passed all 85 tests.

Repository-wide `just check` and `just test` remain blocked by pre-existing
tuple-pattern loop syntax errors in existing tests (including
`deepseek/client/openrouter_wbtest.mbt` after rebasing,
`desktop/internal/uri/uri_test.mbt` and
`editor/viewer/diff_provider/moondiff/*test.mbt`). No such files were changed.
