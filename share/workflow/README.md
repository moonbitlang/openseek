# Bundled workflows

These OpenSeek scripts ship in the application's `share/workflow/`,
alongside the official documentation in `share/doc/moonbit/`.
`Bundled resources` points to `share/`; the engine's environment prompt gives
this resource root's absolute path.

- `read.mbtx` reads text files with numbered lines and per-file ranges (see below).
- `rg.mbtx` searches text with ripgrep: its arguments go to `rg` unchanged
  (ripgrep flags and Rust regex, not POSIX grep), output is `path:line:text`
  bounded to 40000 bytes, and no match exits zero with a note.
- `check.mbtx` runs `moon check`.
- `test.mbtx` runs `moon test` without updating snapshots.
- `check-test.mbtx` runs check then test, stopping on the first failure.
- `info-fmt.mbtx` runs info then fmt, modifying generated interfaces and formatting.
- `check-json.mbtx` relays `moon check --output-json` diagnostics without filtering.
- `fix-deprecations.mbtx` (needs `ptc=true`) fixes deprecation warnings whose
  message names a bare replacement (`use \`len\` instead`), one guarded `edit`
  per site, and lists what it left to a human; `--dry-run` plans only,
  `--limit N` stops after N fixes.

See [Checking, testing, and formatting](../../tests/cram/validation-workflows.md)
for executable examples of these validation scripts against a small project.

Call `mbtx(description="Check the workspace", filename="@builtin/check.mbtx")` (or another bundled name) and omit `source`. No file
creation is needed. `cwd` selects the module to check or test, defaulting to
the workspace. The commands use project/toolchain target defaults, stream
output, and fail when the underlying command fails. Follow repository-specific
validation commands when they differ from these defaults.

Scripts use the ordinary mbtx sandbox and approval path. Read them with the
read workflow to inspect their behavior; save a customized copy in the workspace
when needed. The bundled copies are installation resources and should not be
edited. `@builtin/` runs the copy embedded in the OpenSeek binary at build
time; these files are its source and a readable reference. Ordinary names such as `check.mbtx` resolve from the workspace.
Missing bundled names do not fall back to workspace files. Other `@namespace/`
prefixes are reserved and currently rejected. To customize a script, save the
modified source with an ordinary workspace filename; never send source with
`@builtin/`.

## Reading files

See [Reading files with `read.mbtx`](../../tests/cram/read-workflow.md) for
executable examples of ranges, errors, literal filenames, and output limits.

```json
{"filename":"@builtin/read.mbtx","args":["src/main.mbt:120:200","moon.mod","README.md:50"]}
```

Selectors are `path`, `path:start`, and `path:start:end`. Lines start at 1;
both ends are included. A range beyond EOF returns an empty range footer.
Each file has a JSON-quoted filename heading, numbered content, and the same
`start_line`, `shown_lines`, `total_lines`, and `truncated` footer as the former
read tool. Empty files explicitly report `total_lines=0 note=empty file`.
Trailing newlines still count as a final blank line. Directory, missing-file,
and invalid UTF-8 errors remain distinct; a failed file does not prevent later
files from being read. Any file/argument error gives a nonzero exit; a
successfully truncated read exits zero.

The default body budget is 12000 UTF-8 bytes per file (including gutters).
`--max-output-bytes N` adjusts it for all files, capped at 50000. The whole
batch, headings and footers included, is bounded to 40000 bytes, so multiple
files cannot trip mbtx's 48000-byte stop limit.
`truncated=true` marks incomplete bodies; `skipped_files=N` marks files not
attempted when the batch budget runs out. Request smaller ranges/batches to
continue. The workflow uses the normal compiled mbtx execution path.

Use `--literal PATH` for literal filenames ending in `:number` (including any
such path with a range-like suffix), and `--` before paths starting with `--`.
Range parsing proceeds from the right, preserving Windows drive letters and
other colons. Paths with spaces are single args without shell quoting.
`args=["--help"]` prints usage. Relative file paths use cwd (default workspace).

## Agent workflows

- `review.mbtx` audits the current worktree against the standing goal the
  engine supplies and/or the criteria given in `args` (see below).
- `change-review.mbtx` examines staged, unstaged, and untracked source changes
  from correctness, compatibility, and regression-test perspectives. Its scope
  is the working tree against HEAD, not committed branch history.
- `repo-map.mbtx` surveys architecture and data flow, validation commands, and
  extension points for a new contributor.

Run these in a session that can start subagents; they start them through the
host with `@tools.call("subagent", ...)`:

```json
{"description":"Audit the parser","filename":"@builtin/review.mbtx","args":["Check the CSV parser's CRLF and escaped-quote handling."]}
```

```json
{"description":"Review working-tree changes","filename":"@builtin/change-review.mbtx"}
```

```json
{"description":"Map repository architecture","filename":"@builtin/repo-map.mbtx","cwd":"/path/to/repository"}
```

`review.mbtx` launches one `review` child (100-step ceiling). With no
arguments it audits the standing goal and the baseline it recorded, which the
script reads from the host's `audit_context` tool (`goal`, optional `sha` and
`dirty`) when one stands; arguments, joined
with spaces, narrow that goal as an audit focus, or are the whole criteria
when no goal stands. It prints the full report JSON, then a
`findings=N blockers=M tokens=T` line, and exits unsuccessfully when any finding is a
blocker so the caller cannot read past it. `--sha COMMIT` (with `--dirty`
when the worktree was already dirty at that commit) overrides the engine's
baseline; `--help` prints usage.

Swarm mode runs several reviewers in parallel instead of one, each from its
own angle (a *lens*). `--swarm` picks `correctness`, `architecture` and
`tests`; `--lens NAME`, repeatable, picks lenses instead (`compatibility`
and `security` are also available). Each lens reviewer gets the same
criteria and baseline, narrowed to its lens, and 100 steps. Their findings
are merged: two findings are one claim only when they come from different
lenses, sit in the same file within 3 lines, and share at least half their
title words. Then each blocker or high finding, at most `--verify N` of them
(default 6, at most 8, `0` for none), goes to a fresh reviewer (40 steps)
that is given the original criteria and the allegation and tries to refute
it. The first line of its summary must be `VERDICT: CONFIRMED`, `REFUTED`
or `INCONCLUSIVE` alone; a refuted finding is dropped and printed on a `Refuted:`
line, and anything that isn't a clean confirmation or refutation leaves the
finding `[unverified]`. Verification never changes a severity, so an
unverified blocker still fails the run. `--max-tokens N` skips verification
once the lenses have spent N tokens.

Swarm mode prints the merged report in the same JSON shape, one line per
lens, the refuted findings, and
`findings=N blockers=M tokens=T lenses=R/L verified=V refuted=X unverified=U`.
It fails on a remaining blocker, and when any lens was refused or did not
report: an incomplete swarm is never a clean result. The design is in
[docs/plans/review-swarm.md](../../docs/plans/review-swarm.md).

The other two start read-only `explore` children together, wait for all of
them, and read each report. Change review runs three scouts, allowing 16 steps each.
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
The host launches, records and accounts for each child. Without a host, or
when the session cannot start another child, the script fails with the
reason. These workflows use model tokens.

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
limit. The children are OpenSeek's own subagents, so they are accounted for
and shown in the desktop. Compile them with `moon run --build-only --target
wasm share/workflow/repo-map.mbtx`; execute them through OpenSeek.

Maintainers: `just test-workflows` exercises all three scripts against an
offline fake host that speaks the PTC protocol, including partial failure, a
missing host and a full session.

## GitHub CI monitor

`ci-watch.mbtx` uses authenticated `gh` to monitor the current-branch PR, or an
explicit PR number/URL. It is deterministic, read-only, and uses no subagents
or model tokens. CLI parsing and generated help use `moonbitlang/core/argparse`.
It never reruns jobs, changes branches, or merges a PR.

```json
{"description":"Check PR CI status","filename":"@builtin/ci-watch.mbtx","args":["1427","--repo","moonbitlang/openseek","--once"]}
```

Omit `--once` to watch for up to 300 seconds, polling every 15 seconds. Override
with `--timeout-seconds` (1–3600) and `--interval-seconds` (1–60). Without an
explicit PR, `cwd` must select the repository containing the current branch.
`--repo` accepts `OWNER/REPO` or `HOST/OWNER/REPO`. Use `--help` for usage. The
host's own execution deadline can end the script sooner; with an OpenSeek job
runtime, long runs use its normal automatic background handoff. No scheduled
automation is needed.

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

## Validation

Run `just check-workflows` (`scripts/check-workflows.mbtx`) to type-check every
`.mbtx` under `share/workflow` against its declared imports with
`moon check --target wasm --deny-warn`.
This does not execute the scripts. `just check` includes this gate, and CI
runs it in the independent `bundled workflow checks` job. Newly added scripts
are discovered automatically.

`just test-workflows` separately compiles and executes the review,
repository mapping, change review, and CI watch scripts with offline fixtures.
