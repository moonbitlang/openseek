# Review swarm

Status: implemented in `share/workflow/review.mbtx`; revised after a Codex
(high) design review.

`@builtin/review.mbtx` starts one `review` child to audit the worktree against
some criteria. This plan adds a swarm mode: several review children, each
reviewing from a different angle (a *lens*), run in parallel. The script then
merges their findings, has a fresh child try to disprove each serious one, and
prints one report.

The whole feature is a change to the bundled script. The engine, the `review`
kind and the report contract stay as they are.

## Why a script

Fanning out, waiting, merging and checking are deterministic steps. A script
does them the same way every time, for no model tokens, and its output says
exactly what ran. The host already provides everything the script needs:

- `subagent` starts a child and returns its `job_id`. `job_wait` takes up to 32
  ids, and `job_output` reads a report in chunks along with the child's token
  usage. `review.mbtx` already has `start`, `wait_all` and `outcome` built on
  these; `wait_all` already takes an array.
- Up to 16 children run at once per session (`MaxLive`), and a script may
  start at most 64 (`ScriptQuota`). A start past either limit is refused with a
  reason, never queued.
- A `review` child is read-only. It gets its own scratch lab, and on macOS a
  kernel profile that blocks source writes. Many children can share the
  checkout safely.

## Interface

```
@builtin/review.mbtx [--sha COMMIT [--dirty]] [--swarm | --lens NAME ...]
                     [--verify N] [--max-tokens N] [--] [CRITERIA...]
```

- No `--swarm` and no `--lens`: today's behavior, unchanged. One child, the
  same report, the same `findings=N blockers=M tokens=T` line, the same exit.
- `--swarm`: run the default lenses (`correctness`, `architecture`, `tests`).
- `--lens NAME` (repeatable): run exactly these lenses, which implies swarm
  mode. An unknown name is an error that lists the known ones.
- `--verify N`: verify at most N findings (default 6, 0 turns verification
  off).
- `--max-tokens N`: a soft budget, checked between phases (see Budget).
- `--verify` or `--max-tokens` without swarm mode is an error rather than
  being ignored.

Criteria resolution (`audit_context`, `--sha`, `--dirty`, the joined
arguments) is shared with single mode and unchanged.

## Lenses

A lens is a name plus one paragraph that narrows the reviewer's attention. The
built-in set:

| Name | Focus |
|---|---|
| `correctness` | Behavior that is wrong: boundary cases, state transitions, error propagation, resource lifetimes, concurrency and cancellation |
| `architecture` | Layering and ownership: whether the change sits in the right package, duplicated mechanisms, contracts that leak, designs that will not scale |
| `tests` | Behavior the change adds or alters that no test pins, and whether the build and tests pass |
| `compatibility` | Public API (`.mbti`), JSON and wire formats, CLI output, and how absence versus failure is represented |
| `security` | Sandbox and trust boundaries, untrusted input, paths, process spawning, secrets |

The default set is three lenses, to keep cost down. Each child's `goal` input
is the resolved criteria followed by:

```
Review lens: <name>
<focus paragraph>
Report only findings within this lens; other reviewers cover the rest.
```

The baseline (`sha`, `dirty`) is passed unchanged. The label is
`review:<name>`, and each lens gets an explicit 100-step budget (the `review`
kind's own ceiling is 120).

**Builds.** Every reviewer may run `moon check`/`moon test`: the audit system
prompt tells it to, and the script can't override that from the goal text.
Children share the checkout, so concurrent builds wait on moon's `_build`
lock. That costs wall time, not correctness. Experiments that need a writable
project use each child's own scratch lab, as today.

## Merge and dedupe

All lens reports are merged into one list. Merging is deliberately
conservative: wrongly merging two distinct bugs would hide one of them, while
failing to merge a duplicate only costs a reader a second look. Two findings
from **different** lenses are the same issue only when all three of these
hold:

1. **Same file**, after stripping a leading `./`.
2. **Close lines**: both have no line, or the lines differ by at most 3.
3. **Same claim**: their titles' word sets overlap at least half (Jaccard ≥
   0.5, over lowercase words of 3 or more letters or digits). A shared `category` alone
   is not enough; it's a free-form label, not an issue identifier.

Two findings from the same lens never merge: that reviewer already reported
them as separate issues.

A merged finding keeps the text, location and severity of its most severe
member (later findings are still matched against the first report's
location), and its `detail` gains a trailer naming the lenses that found it:
`[found by: correctness, tests]`. The merge is deterministic: findings are
taken lens by lens in the order given, and each finding joins the first
matching group.

Agreement between lenses is not independent evidence (they are the same
model), so it does not skip verification. It is shown so a reader can weigh it.

## Verify pass

Each finding of severity `blocker` or `high` (most severe first, at most
`--verify N`) goes to a fresh `review` child, which tries to disprove it.

- **Input.** Children don't see this conversation, so the `goal` text carries
  everything, in clearly separated parts:
  1. *The original criteria*, verbatim, labeled as what the work is held to.
  2. *The allegation*: the finding's file, line, severity, title and detail,
     labeled as one reviewer's claim, not as criteria.
  3. *The instruction*: try to refute the allegation first. Then submit with
     a summary that begins with exactly one of `VERDICT: CONFIRMED`,
     `VERDICT: REFUTED` or `VERDICT: INCONCLUSIVE`, followed by the evidence.
     The token must not run into a letter (`VERDICT: REFUTEDLY` is no
     verdict), but what separates it from the evidence isn't checked: in a
     live run, two verifiers wrote a literal `\n` there instead of a newline.
     For `CONFIRMED`, submit exactly one finding restating the claim, in the
     same file. Otherwise submit no findings. Say `INCONCLUSIVE` whenever the
     claim couldn't actually be tested.

  Same baseline. Label `review:verify-<n>`. Step budget 40.
- **The outcome is read strictly**, from the verdict line and the finding
  shape together:
  - **Confirmed**: `VERDICT: CONFIRMED` and exactly one finding in the
    claim's file. The verifier's detail is appended to the merged finding's
    detail.
  - **Refuted**: `VERDICT: REFUTED` and no findings. The finding is dropped
    from `findings` and listed, with the verifier's summary, under
    `Refuted:` in the printed output.
  - **Unverified**: everything else. That includes `INCONCLUSIVE`, a missing
    or unknown verdict line, a verdict whose findings don't fit it (for
    example `CONFIRMED` with an unrelated file or with two findings), and a
    verifier that was refused or ended without a report. The finding stays,
    with `[unverified: <reason>]` in its detail. A blocker nobody could check
    still blocks.
- **Severity never changes.** Verification only confirms or removes a
  claim. A verifier doesn't own the criteria's notion of `blocker` ("the goal
  is not met"), so letting it re-grade would let a confirmed blocker turn
  into a successful exit.

Verifiers start together, after every lens has ended, so their number
plus the lenses' never exceeds 16 at once.

Findings below `high`, and anything beyond `--verify N`, are reported as they
are, marked `[unverified]`.

## Budget

- **Children**: at most 5 lenses plus `--verify` verifiers (capped at 8).
  That's at most 13 starts, well inside the 64-start quota and the 16-child
  limit. The script can't see how many other children the session already
  has, so a refused start is handled, not prevented.
- **Steps**: lens children get an explicit 100 steps (as single mode does
  today; the kind's ceiling is 120), verifiers 40. Worst case:
  5 × 100 + 8 × 40 = 820 steps.
- **Tokens**: each child's usage is read from `job_output` and summed. With
  `--max-tokens N`, the verify pass is skipped when the lenses have already
  spent N or more; their findings are then reported unverified. A running
  child is never stopped for budget: the check sits between phases only.

## Output and exit

The script prints, in order:

1. The merged report as one JSON line, in the `ReviewReport` v1 shape
   (`schema_version`, `scope`, `findings`, `summary`, `stats`), so anything
   that parses today's report parses this one.
   - `scope`: `base` and `head` from the first lens that reported (a lens
     that reports different ones is noted in the summary), and `files` the
     union of every lens's files, in first-seen order.
   - `stats.findings`: the merged count. `stats.files_reviewed`: the most
     any one lens reviewed. The per-lens lines below give each count; the
     total isn't derivable, since lenses overlap.
   - `stats.build`/`stats.tests`: `"fail"` when any lens reported `"fail"`,
     else `"pass"` when any reported `"pass"`, else the first lens's value.
   - `summary`: each lens's one-line summary, prefixed with its name.
2. One line per lens: `lens <name>: reported, findings=N, files=F, tokens=T`,
   or why it has no report.
   When the token budget skipped verification, a
   `verify: skipped, the lenses spent T tokens of --max-tokens N` line
   follows.
3. `Refuted:` lines, one per dropped finding, when there are any.
4. A verdict line extending today's:
   `findings=N blockers=M tokens=T lenses=R/L verified=V refuted=X unverified=U`,
   where `R` of the `L` lenses reported.

The script fails (nonzero exit, so the caller can't read past it) when:

- any remaining finding is a `blocker`, confirmed or unverified, or
- any lens was refused or ended without a report: the run is incomplete,
  which is never a clean result. `change-review.mbtx` follows the same rule.

## Implementation notes

- One file: `share/workflow/review.mbtx`. The existing `start`, `wait_all` and
  `outcome` are reused as they are; single mode keeps its code path.
- The bundled copy (`agent_tool/mbtx/generated_bundled_workflows.mbt`) is
  regenerated by the `mbtx_bundle` rule; no new file is added to it.
- `share/workflow/README.md` documents swarm mode next to `review.mbtx`.

## Tests

Offline, in `tests/integration/workflows/hosted.mbt`, against its fake PTC
host, which records every start and serves scripted reports:

- `--swarm` starts the three default lenses with the right labels, lens text,
  baseline and step budgets.
- Two lenses report the same claim in nearby lines: one merged finding
  naming both lenses. Two different claims at nearby lines, and two findings
  from one lens, stay separate.
- A confirming verifier keeps a finding, at its original severity. An
  explicit refutation drops it and lists it under `Refuted:`. Each of these
  leaves it `[unverified]`: an `INCONCLUSIVE` verdict, an empty report with
  no verdict line, `CONFIRMED` with an unrelated file or two findings, and a
  verifier with no report.
- A confirmed or unverified blocker fails the run. An explicitly refuted one
  does not.
- A refused lens makes the run incomplete and fails it, while the other
  lenses' findings are still printed.
- `--verify 0` and `--max-tokens` skip verification.
- An unknown `--lens` name fails with the list of known names.
- Every existing single-mode case passes unchanged.

`just check-workflows` type-checks the script, and the mbtx package tests
check the bundle.

These tests check the script's logic against canned reports. Whether real
children follow the lens and verifier framing is checked by a live run on a
real branch before the change merges.

## Out of scope

- Reviewers that talk to each other mid-run (would need engine messaging).
- Lenses on other models through the `moonbitlang/workflow` shims.
- Splitting a large diff across children by file. This can be added later as
  another way to fan out.
- A code-review mode over `base...HEAD` (the `review` kind's `base` input
  takes no focus today, so lenses would need an engine change).
