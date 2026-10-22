# Review swarm

Status: design, for review before implementation.

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
`review:<name>`.

**Build ownership.** Children share the checkout, and concurrent
`moon check` runs serialize on moon's `_build` lock. So only the `tests` lens
is told to run the build and tests. The others are told to read code and run
targeted commands only. When the `tests` lens is not selected, the
`correctness` lens takes the build over; when neither is, nobody runs it.
Either way, the report's `stats.build`/`stats.tests` come from the lens that
ran them, or are `"skipped"`.

## Merge and dedupe

All lens reports are merged into one list. Two findings are the same issue
when all three of these hold:

1. **Same file**, after stripping a leading `./`.
2. **Close lines**: both have no line, or the lines differ by at most 3.
3. **Same issue**: the same `category`, or titles whose word sets overlap at
   least half (Jaccard ≥ 0.5, over lowercase words of 3 or more letters).

A merged finding keeps the text of its most severe member, and its `detail`
gains a trailer naming the lenses that found it:
`[found by: correctness, tests]`. The merge is deterministic: findings are
taken lens by lens in the order given, and each finding joins the first
matching group.

Agreement between lenses is not independent evidence (they are the same
model), so it does not skip verification. It is shown so a reader can weigh it.

## Verify pass

Each finding of severity `blocker` or `high` (most severe first, at most
`--verify N`) goes to a fresh `review` child, which tries to disprove it.

- Input: `goal` holds the claim (file, line, severity, title, detail) and the
  instruction:
  *"Verify this one claim. Try to refute it first. If it holds, submit exactly
  one finding restating it, with the severity you judge it deserves. If it
  does not hold, submit no findings and explain why in the summary."*
  Same baseline. Label `review:verify-<n>`. Step budget 40.
- **Confirmed**: the verifier's report has a finding. The verifier's severity
  replaces the original, so verification can downgrade but never adds a new
  issue. Its first finding's detail is appended to the merged finding's
  detail.
- **Refuted**: the report has no findings. The finding is dropped from
  `findings` and listed, with the verifier's summary, under
  `Refuted:` in the printed output.
- **Unverified**: the verifier was refused, or ended without a report. The
  finding stays at its severity, with `[unverified]` in its detail.
  Being conservative here is deliberate: a blocker nobody could check still
  blocks.

Verifiers start together, after every lens has ended, so their number
plus the lenses' never exceeds 16 at once.

Findings below `high`, and anything beyond `--verify N`, are reported as they
are, marked `[unverified]`.

## Budget

- **Children**: at most 5 lenses plus `--verify` verifiers (capped at 8).
  That's at most 13 starts, well inside the 64-start quota and the 16-child
  limit. The script can't see how many other children the session already
  has, so a refused start is handled, not prevented.
- **Steps**: lens children use the `review` kind's goal ceiling (100 steps),
  verifiers 40. Worst case: 5 × 100 + 8 × 40 = 820 steps.
- **Tokens**: each child's usage is read from `job_output` and summed. With
  `--max-tokens N`, the verify pass is skipped when the lenses have already
  spent N or more; their findings are then reported unverified. A running
  child is never stopped for budget: the check sits between phases only.

## Output and exit

The script prints, in order:

1. The merged report as one JSON line, in the `ReviewReport` v1 shape
   (`schema_version`, `scope`, `findings`, `summary`, `stats`), so anything
   that parses today's report parses this one.
   - `scope`: from the first lens that reported.
   - `stats.findings`: the merged count. `stats.files_reviewed`: the maximum
     over lenses. `stats.build`/`stats.tests`: from the build owner, else
     `"skipped"`.
   - `summary`: each lens's one-line summary, prefixed with its name.
2. One line per lens: `lens <name>: reported, findings=N, tokens=T`, or why
   it has no report.
3. `Refuted:` lines, one per dropped finding, when there are any.
4. A verdict line extending today's:
   `findings=N blockers=M tokens=T lenses=L verified=V refuted=R unverified=U`.

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
- Two lenses report the same issue in nearby lines: one merged finding naming
  both lenses.
- A high finding with a confirming verifier is kept, with the verifier's
  severity. One with a refuting verifier is dropped and listed under
  `Refuted:`. One whose verifier has no report stays, marked `[unverified]`.
- A confirmed blocker fails the run. A refuted blocker does not.
- A refused lens makes the run incomplete and fails it, while the other
  lenses' findings are still printed.
- `--verify 0` and `--max-tokens` skip verification.
- An unknown `--lens` name fails with the list of known names.
- Every existing single-mode case passes unchanged.

`just check-workflows` type-checks the script, and the mbtx package tests
check the bundle.

## Out of scope

- Reviewers that talk to each other mid-run (would need engine messaging).
- Lenses on other models through the `moonbitlang/workflow` shims.
- Splitting a large diff across children by file. This can be added later as
  another way to fan out.
- A code-review mode over `base...HEAD` (the `review` kind's `base` input
  takes no focus today, so lenses would need an engine change).
