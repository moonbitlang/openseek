# Bundled workflows

These OpenSeek scripts ship in the toolchain payload's `share/workflow/`,
alongside the official documentation in `share/doc/moonbit/`.
`OPENSEEK_REFERENCES` points to `share/`; the engine's environment prompt gives
this resource root's absolute path.

- `check.mbtx` runs `moon check`.
- `test.mbtx` runs `moon test` without updating snapshots.
- `check-test.mbtx` runs check then test, stopping on the first failure.
- `info-fmt.mbtx` runs info then fmt, modifying generated interfaces and formatting.
- `check-json.mbtx` relays `moon check --output-json` diagnostics without filtering.

Call `mbtx(filename="@builtin/check.mbtx")` (or another bundled name) and omit `source`. No file
creation is needed. `cwd` selects the module to check or test, defaulting to
the workspace. The commands use project/toolchain target defaults, stream
output, and fail when the underlying command fails. Follow repository-specific
validation commands when they differ from these defaults.

Scripts use the ordinary mbtx sandbox and approval path. Read them with the
file tools to inspect their behavior; save a customized copy in the workspace
when needed. The bundled copies are installation resources and should not be
edited. `@builtin/` resolves under `OPENSEEK_REFERENCES/workflow/` and refuses
escaping paths. Ordinary names such as `check.mbtx` resolve from the workspace.
Missing bundled names do not fall back to workspace files. Other `@namespace/`
prefixes are reserved and currently rejected. To customize a script, save the
modified source with an ordinary workspace filename; never send source with
`@builtin/`.

## Read-only agent workflows

- `change-review.mbtx` examines staged, unstaged, and untracked source changes
  from correctness, compatibility, and regression-test perspectives. Its scope
  is the working tree against HEAD, not committed branch history.
- `repo-map.mbtx` surveys architecture and data flow, validation commands, and
  extension points for a new contributor.

Run these with the hosted child-agent handoff:

```json
{"filename":"@builtin/change-review.mbtx","subrun":true}
```

```json
{"filename":"@builtin/repo-map.mbtx","subrun":true,"cwd":"/path/to/repository"}
```

Both use `moonbitlang/workflow`'s `fan_out` and `attempt` with read-only
`explore` children. Change review runs three scouts, allowing 16 steps each.
Repo-map runs two scouts, allowing 12 steps each, and displays the root
`justfile` recipes directly in MoonBit without asking a model to summarize
commands. Recipes are marked as not executed; a missing `justfile` is reported
explicitly. Long recipe files are visibly truncated.

For MoonBit, scouts start with the selected package’s `moon.pkg` and
`pkg.generated.mbti`, then use its dependencies and public API to choose
implementation and test reads. Interfaces are navigation aids: they can be
stale and omit private behavior, so behavioral claims still require source.

Repo-map asks for at most six targeted reads before submission. That read limit
is guidance to the scout; the 12-step ceiling is enforced by the engine.
The host supplies the runner, journal, event stream, credentials, and reserved
child IDs through `moonbitlang/workflow/hosted`. Missing handoff or insufficient
child capacity (three for change review, two for repo-map) fails before any
scout starts. These workflows use model tokens.

Change review prints JSON reports; repo-map prints readable Markdown answers,
supporting references, unverified areas, and usage counts. Repo-map shares one
bounded inventory of root entries and nested package source filenames, plus numbered
excerpts from root instructions, README, and MoonBit/build manifests across
the scouts. Discovery visits at most 160 directories through depth three,
skips hidden/generated/vendor directories and directory symlinks, and caps
the package listing at 16,000 characters. Omitted areas are marked explicitly.
It asks for one verified execution trace and one concrete extension
example, with answers under 350 words and at most eight citations, and rejects
a missing or empty answer. Every citation must contain a repository-relative
file and positive integer line number. The script resolves the path (including
symlinks), checks containment and readability, and verifies the line exists.
Missing/malformed references are marked `UNVERIFIED` and make the run fail;
`CHECKED` means only that the location exists, not that the claim is true.
The scout must submit through
`submit_answer`; ordinary final text does not satisfy the child contract.

Output contains one report per named perspective plus usage counts.
Successful reports remain visible if another perspective fails, and any failed
perspective makes the script exit unsuccessfully. Findings are agent-produced
leads with cited evidence, not a substitute for running project checks. The
calling agent can compare and consolidate the reports without another scout.
Run against a stable working tree so the scouts inspect the same state.

To customize, copy a script into the workspace and edit its questions or step
limit. Keep `ctx.run` so OpenSeek can account for and display its children.
The pinned imports make these scripts independent of the inspected project's
library dependencies. Compile them with `moon run --build-only --target wasm
share/workflow/repo-map.mbtx`; execute them through OpenSeek with `subrun=true`.

Maintainers: `just test-workflows` exercises both scripts with an offline child
contract fixture, including partial failure and missing/insufficient handoff.

## GitHub CI monitor

`ci-watch.mbtx` uses authenticated `gh` to monitor the current-branch PR, or an
explicit PR number/URL. It is deterministic, read-only, and uses no subagents
or model tokens. CLI parsing and generated help use `moonbitlang/core/argparse`.
It never reruns jobs, changes branches, or merges a PR.

```json
{"filename":"@builtin/ci-watch.mbtx","args":["1427","--repo","moonbitlang/openseek","--once"]}
```

Omit `--once` to watch for up to 300 seconds, polling every 15 seconds. Override
with `--timeout-seconds` (1–3600) and `--interval-seconds` (1–60). Without an
explicit PR, `cwd` must select the repository containing the current branch.
`--repo` accepts `OWNER/REPO` or `HOST/OWNER/REPO`. Use `--help` for usage. The
host's own execution deadline can end the script sooner; with an OpenSeek job
runtime, long runs use its normal automatic background handoff. No `subrun`
flag or scheduled automation is needed.

The first snapshot pins the PR URL and head commit. A changed head stops the
monitor as superseded, rather than mixing checks from different revisions.
Both Actions check runs and external commit statuses are included. Changed
snapshots print check names, workflows, raw states, and links as JSON rows;
missing links/workflows are `null`. Failed Actions checks also include
`failure_logs_argv`, an argument list for `gh run view --log-failed`. Logs are
not downloaded automatically; the caller can use that command or the check
URL, and a still-running workflow may not yet have downloadable failed logs.

A watch succeeds after two matching completed snapshots with at least one
successful check, no failed or pending checks, and any remaining checks
skipped/neutral. `--once` evaluates one snapshot. A failed/cancelled/action-required
check exits nonzero immediately, even if other checks remain pending. No checks,
only skipped/neutral checks, unknown states, API/authentication errors, and
expired deadlines never count as success. Pending `--once` snapshots exit
nonzero too; their output says `CI INCOMPLETE` rather than `CI FAILED`.

This reports **observed checks**, not branch-protection compliance or merge
readiness. It cannot know about workflows that have not registered, path-filtered
workflows that never run, or required checks missing from the returned snapshot.
Two stable polls reduce registration races but do not prove that all expected
checks exist. Each gh request has a 30-second timeout and a 1 MiB output bound.

`tests/integration/workflows` exercises the actual Wasm script using a local
native MoonBit `gh` fixture, including pending-to-success, delayed registration, late failure,
head replacement, external statuses, unknown states, and timeouts. It runs in
`just test-workflows` and the native CI job. The mbtx package also checks bundled
argument forwarding without requiring GitHub credentials.

All bundled-workflow fixtures run in MoonBit; they require no Python runtime.
