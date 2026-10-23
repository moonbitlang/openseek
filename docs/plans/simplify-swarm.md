# Simplify swarm

Status: implemented in `share/workflow/simplify.mbtx`, after a Codex (high)
design review and an implementation review (see Review), and checked by a
live run (see Live run).

`@builtin/simplify.mbtx` sweeps a MoonBit project for safe, obvious
simplifications and turns each surviving change into its own pull request. It
automates what we have done by hand in past simplify sweeps: scouts look for
candidates, one worker per package makes the change, an independent reviewer
checks each change, and each one that holds up becomes a small PR. Desktop gets
a Claude-style `/simplify [focus]` command that runs it.

The engine, the subagent kinds and their report contracts stay as they are.
The feature is one bundled script with its MoonBit guidance, plus a Desktop
prompt command.

## Why a script

Fanning out, queueing workers, matching candidates to packages, and pushing
branches are deterministic steps. A script does them the same way every time,
for no model tokens, and its output says exactly what ran. The model is used
only where judgment is needed: finding candidates, making the change, and
reviewing it. The host already provides everything the script needs:

- `subagent` starts `explore` and `worker` children; `job_wait` returns when
  any of the given jobs ends, and `job_output` reads a child's report. The
  start, wait and outcome helpers are the ones in
  [review swarm](review-swarm.md).
- A `worker` child runs in its own git worktree forked from HEAD and may change
  only its `allowed_paths` (component-wise prefixes, disjoint from every other
  live worker's). When it ends, whatever its outcome, the engine checks its
  scope from git and commits its change on its own branch, with the pinned
  base as parent. `job_output` reports `subagent.workspace.worktree` with
  `branch`, `base` and a `state` of `committed {commit}`, `no_changes`,
  `unmergeable {defects}` or `capture_failed {reasons}`, plus the worker's own
  report (`status` `done`, `partial` or `failed`, `summary`,
  `verification`). See [subagents](subagents.md), "As built", PR 7.
- At most 16 children run at once per session, 8 of them workers (raised from
  4 by this change, so a sweep's workers and their reviewers fit together),
  and a script may start at most 64. A start past a limit is refused with a reason, never
  queued.
- The mbtx policy admits every command the script runs: `git rev-parse`,
  `git status`, `git ls-files`, `git merge-base`, `git push`, `gh repo view`,
  `gh auth status` and `gh pr`. Spawned processes keep network access.

## Interface

```
@builtin/simplify.mbtx [--path DIR ...] [--scouts N] [--max-prs N]
                       [--no-pr] [--] [FOCUS...]
```

- `--path DIR` (repeatable): sweep only packages under these directories.
  Default: the whole repository.
- `--scouts N`: how many scouts run in parallel (default 8, at most 16).
- `--max-prs N`: at most this many packages are changed, one PR each (default
  8, at most 16).
- `--no-pr`: stop after review; accepted changes stay on their local branches
  and are listed. Nothing is pushed.
- `FOCUS`: free text joined with spaces, e.g. `pattern matching in parsers`.
  Scouts and workers get it as an extra emphasis, never as a license to break
  the safety rules.

## Pipeline

### 0. Preflight

Everything here runs before any child starts, so a run that cannot finish
spends no tokens.

- **Repository root.** `git rev-parse --show-prefix` must be empty. Worker
  worktrees are provisioned from the session's workspace, and the engine
  refuses a workspace below the repository root, so the session must be
  opened at the root.
- **Clean tracked files.** `git status --porcelain --untracked-files=no` must
  be empty. Scouts read the checkout, while workers fork HEAD's commit; with
  local edits the two would see different code.
- **Pinned HEAD.** `git rev-parse HEAD` is recorded. A worker whose `base` is
  not that commit (HEAD moved during the run) is rejected.
- **PR target** (unless `--no-pr`):
  - `default_ref` = `git rev-parse --abbrev-ref origin/HEAD` (e.g.
    `origin/main`), and `base_branch` is that minus `origin/` (`main`). `gh pr
    create --base` takes the branch name, not the remote-tracking ref.
  - HEAD must be an ancestor of `default_ref` (`git merge-base --is-ancestor`).
    Otherwise each PR would also carry unrelated local commits.
  - `repo` = `gh repo view <origin's URL> --json nameWithOwner`, passed to
    every `gh` call as `--repo`. It is resolved from `origin` itself, the
    remote branches are pushed to, so `gh`'s own default repository (`gh repo
    set-default`) cannot send a PR elsewhere. A fork workflow (push to a fork,
    PR to upstream) is out of scope.
  - `gh auth status` must succeed.

### 1. Inventory

- Packages are the directories of tracked `moon.pkg` / `moon.pkg.json` files
  (`git ls-files`), limited by `--path`. `git ls-files` does not list
  submodule contents, so vendored code is excluded for free; `.mooncakes/` and
  `_build/` are untracked.
- A package's files are its tracked `*.mbt` files directly in its directory,
  not in a nested package. Generated files are skipped: names starting with
  `generated_`, and `pkg.generated.mbti`.
- Packages with no remaining `.mbt` file are dropped.

### 2. Scout

Packages are sorted by path and dealt into `--scouts` slices of roughly equal
total size, keeping each package whole. Each slice goes to one `explore` child
(label `simplify:scout-<n>`, 80 steps), whose query carries:

1. the MoonBit guidance (below);
2. the slice's package directories and their files;
3. the focus, if any;
4. the instruction: report at most 12 candidates in these files, only obvious,
   behavior-preserving wins, each as one citation `{file, line, note}` whose
   note (at most 200 characters, the kind's cap) is `<idiom>: <the rewrite>`.

`explore` is the right kind because it is read-only outside its scratch lab,
and its report (`answer`, `citations`) already carries one location and a note
per item. It may still run experiments in its lab, so its cost is not
build-free.

### 3. Select

- Each citation is mapped to the package whose file list contains its file.
  Citations naming any other file (outside the slice, generated, untracked,
  missing) are dropped, and duplicates (same file and line) collapse.
- Packages are ranked by candidate count (descending, ties by path), and the
  top `--max-prs` are chosen. Each chosen package becomes one unit of work:
  one worker, one review, one PR.

### 4. Work

One `worker` child per chosen package (label `simplify:<package>`, the kind's
default step budget), with:

- `worktree.name`: `simp-<8 hex of the package path's hash>-<slug>`, where
  `<slug>` is the package path lowercased with every run of other characters
  turned into `-`, trimmed to fit 40 characters (the engine's limit is
  `[a-z0-9][a-z0-9-]{0,39}`); the root package is `root`. The hash keeps two
  long paths that trim to the same slug apart.
- `worktree.allowed_paths`: the package's files. Listing files, not the
  directory, keeps the sets disjoint when one package is nested in another,
  and keeps the worker out of the nested one. It also leaves out
  `pkg.generated.mbti`: a change that would alter the public interface makes
  the capture `unmergeable`.
- `task`: the guidance, the candidate list, the focus, and these rules:
  - Apply only the candidates that are clearly safe and strictly simpler, and
    say in the report which were skipped and why.
  - Change only the allowed files, and add no new file.
  - First read the repository's `AGENTS.md` files on the path from the root to
    the package, and the guidance they link, and run the validation they
    require for this package. That always includes `moon check` and
    `moon test` for the package in its module or workspace, and the target
    that package needs. Run `moon info` and `moon fmt` with the package path:
    run over the whole module, a toolchain newer than the project's can
    rewrite other packages' files, and any change outside the allowed files
    makes the capture `unmergeable`.
  - Report `done` only when every required check passed, and name each
    command and its result in `verification`.

At most 8 workers run at once. The script starts up to 8, then starts the next
whenever one ends (`job_wait` returns when any ends). A refused start is
recorded for that package, and the queue continues.

The host reports a worker ended as soon as its outcome is recorded, and
captures its worktree only after that, so `job_output` can still show the
worktree `working`. Such a worker is not done: it stays in the wait set (and
keeps its slot, as it does on the host) until a later read shows the capture.

A change moves on to review only when all of these hold. Otherwise it stops
here, and the reason is printed:

- the capture is `committed`;
- its `base` is the pinned HEAD;
- the worker reported, and its status is `done`.

`partial` or `failed` changes are never published. The engine commits them
anyway, so their branches stay local for inspection.

### 5. Review

A `review` child audits the current checkout. It cannot be pointed at another
commit, and it would test the unchanged code. So the reviewer is a second
`explore` child (label `simplify:review-<n>`, 60 steps), which reads the change
as git objects:

- **Input**, in clearly separated parts:
  1. the package, the base and the commit, and how to read them: `git diff
     <base> <commit>`, `git show <commit>:<file>` (both admitted, and the
     read-only sandbox allows object reads). To build or test it, the reviewer
     may check it out with `git worktree add --detach` into its scratch lab.
     The lab is deleted when the reviewer ends, and the script runs `git
     worktree prune` once every child has ended to drop the stale records;
  2. the worker's summary, labeled as the author's claim, not as evidence;
  3. the criteria:
     - behavior is unchanged, including error paths, side-effect order and
       timing;
     - each rewrite is strictly simpler, not just different;
     - no invariant is loosened: no added `mut`, no widened visibility, no
       merged builder and result types, no deleted check;
     - no test is made stricter or order-sensitive as a side effect;
  4. the instruction: try to find a reason to reject first, using the scratch
     lab for any language experiment. Then answer with a first line of exactly
     `VERDICT: ACCEPT` or `VERDICT: REJECT` (trailing periods aside),
     followed by the reasoning. Cite each problem as `{file, line, note}`.
- **The verdict is read strictly**, as the review swarm's verifiers are:
  - **accepted**: `VERDICT: ACCEPT`;
  - **rejected**: `VERDICT: REJECT`, which prints the citations and the
    reasoning;
  - **unreviewed**: anything else, such as a missing, hedged or unknown verdict
    line, or a reviewer that was refused or ended without a report. The change
    is not published.
- Reviews start as their worker passes the gate in step 4, so they overlap
  with the remaining workers.
- **Who checks what.** The reviewer reads code, and does not run the project's
  tests on the commit. The tests were run by the worker in its worktree (its
  `done` status and `verification`), and again by the PR's CI. The review is a
  second opinion on semantics, not a second test run.

### 6. Pull requests

Unless `--no-pr`, each accepted change is pushed and opened as a PR:

- `git push origin <commit>:refs/heads/simplify/<worktree name>-<first 8 of
  the commit>`: the commit keeps a later sweep of the same package off this
  branch;
- `gh pr create --repo <repo> --base <base_branch> --head <that branch>
  --title "refactor(<package>): simplify" --body <body>`. The body has the
  worker's summary and verification, the candidates with their lines, the
  reviewer's reasoning, and a line saying it was generated by
  `@builtin/simplify.mbtx`.

A PR is never merged by the script. Once a PR is open, the worker's local
branch is deleted, since the change lives on `origin`. A change that is not
published keeps its local branch, and the output prints the `git branch -D`
line for it. If a push or `gh pr create` fails (a nonzero exit, a timeout or a
process that cannot start), that package is reported, the others continue,
and the run ends nonzero.

## MoonBit guidance

The guidance is a constant in the script, given to scouts and workers. It holds
what past sweeps learned:

**Bar.** A rewrite must be strictly simpler, with identical behavior and
performance; "different" is not "simpler". Leave code that is already clear.
Never trade an invariant for fewer lines.

**Worth doing:**

- **Patterns that bind what a check guarded:** `guard parts is [name, value]`,
  `if xs is [.., last] && …`, `argv is ["env", ..]`, `[..s.split("=")] is
  [k, _, ..]`, and string patterns such as `s is [.. "prefix", .. rest]`. Only
  do this where the body then indexes the same container; a bare
  `xs.is_empty()` stays.
- **Range loops** for C-style index loops with step ±1 and no reassignment of
  the loop variable: `for i in 0..<n`, `for i, x in xs`. Descending forms bind
  the start and include the end: `n>=..m`, `n>..m`.
- **Comprehensions** for a fresh array filled by exactly one push loop:
  `[for x in xs => f(x)]`, `[for x in xs if p(x) => f(x)]`,
  `[for i, x in xs => …]`. Two generators in one literal do not parse.
- **Slices** for prefixes and suffixes: `xs[:n]`, `s[i:]`.
- **Direct container methods:** `xs.any(p)`, not `xs.iter().any(p)`;
  `xs.length()`, not `xs.iter().count()`.
- **String helpers:** `split_once`, `rev_split_once` and `strip_prefix` instead
  of index arithmetic around `find`.
- **Interpolation** `"\{a}/\{b}"` over `+` chains of strings, when the result
  fits on one line of about 100 columns. `moon fmt` never wraps a string
  literal, so a chain that splits a long string across lines stays.
- **Functional `for` with state** (`for v = view; ; { match v { … continue
  rest … } }`) instead of the deprecated `loop`.
- **Inlining** a private function with exactly one caller, when its body reads
  as well at the call site.
- **Deleting** dead code and exact-duplicate tests.

**Do not:**

- add `mut`, widen visibility, merge a builder into its result, or change a
  public signature (`pkg.generated.mbti` must not change);
- reorder side effects or change their timing;
- replace subscripting a `String` with a pattern: indexing is by UTF-16 code
  unit, while a pattern binds a `Char`;
- replace an index that documents an upstream constant, or one guarded by a
  non-empty invariant (the pattern would force an impossible branch);
- convert multi-branch accumulators, real tokenizers, or prefix checks against
  shared named constants;
- collapse match arms that name variants into a wildcard or catch-all (`C(_)`,
  `_`): a variant added later would silently take that arm instead of failing
  to compile;
- turn a `String` stored in a long-lived structure into a `StringView`: a
  stored view pins its whole string. Own at storage, view in transit;
- touch generated files or vendored code, or add files.

**Verify.** Run `moon check` and `moon test` for the package, plus `moon fmt`
and `moon info` with its path, and confirm the `.mbti` is unchanged.
`moon ide hover` confirms that a method resolves on the receiver's type.

## Budget

- **Children:** at most 16 scouts, 16 workers and 16 reviewers, so 48 starts,
  inside the 64-start quota. Live at once: at most 16 scouts (the whole
  session's allowance, so the default is 8), then at most 8 workers plus their
  reviewers, which also fits in 16.
- **Steps:** scouts 80, workers the kind's default (300), reviewers 60.
- **Tokens:** each child's usage is summed and printed. There is no token
  budget flag in the first version; `--max-prs` and `--scouts` are the cost
  knobs.

## Output and exit

The script prints:

1. One line per scout: `scout <n>: packages=P candidates=C tokens=T`, or why
   it has no report.
2. One line per chosen package: `<package>: candidates=C worker=<state>
   review=<accepted|rejected|unreviewed: reason> pr=<url|branch|reason>`,
   followed by a rejected change's reasons.
3. A totals line: `packages=N chosen=K prs=P accepted=A rejected=R
   skipped=S tokens=T`, where `skipped` counts changes that stopped at the
   step 4 gate.

The script fails (nonzero exit) when preflight fails, when no scout reported,
when any start was refused or any child ended without a result, or when a push
or `gh pr create` failed. The lines above are printed first either way. A sweep that finds nothing worth changing,
or whose changes were all rejected, exits 0.

## Desktop

`/simplify` is a prompt command, like `/ultrareview`: the composer keeps
`/simplify [focus]`, and sending expands it into a prompt. The prompt asks the
agent to call `mbtx` with `filename: "@builtin/simplify.mbtx"` and `args:
["--", <focus>]` (no args when the focus is empty), to wait with `job_wait`,
read with `job_output`, and report the PRs it opened and the changes it
rejected. The menu detail says it opens pull requests and uses many tokens.

## Tests

Offline, in `tests/integration/workflows/hosted.mbt`. They run against its fake
PTC host, in a temporary git repository with a few packages, with a local bare
repository as `origin` and a stub `gh` (the same executable trick the
`ci-watch` tests use):

- Preflight: a dirty tracked file, a run below the root, and HEAD not an
  ancestor of `origin/HEAD` each fail before any start.
- Scouts get the right slices, labels, step budgets and guidance.
- Citations map to packages; citations naming other files, and duplicates,
  are dropped; the top `--max-prs` packages are chosen in rank order.
- Workers get valid, distinct names and disjoint file lists, and never more
  than 8 run at once: nine packages queue past the cap, and the fake host
  refuses a ninth live worker, as the real one does. A refused worker is
  reported, and the rest continue.
- Only a `committed` capture on the pinned base with a `done` report reaches
  review. `partial`, `no_changes`, `unmergeable`, a moved base and a worker
  without a report do not.
- A worker reported ended while its worktree is still `working` is waited for
  again, and its change still reaches review.
- `ACCEPT` publishes. `REJECT`, a hedged verdict, a refused reviewer and a
  reviewer without a report do not; the last two fail the run.
- An accepted change is pushed to the bare `origin` under
  `simplify/<name>-<commit>`; the stub `gh` is asked for `origin`'s
  repository and receives `pr create --repo <repo> --base main --head
  <that branch>`. A failing `gh pr create` still prints the report and fails
  the run. `--no-pr` pushes nothing.
- The output lines and exit status above.

`just check-workflows` type-checks the script. Whether real children follow
the briefs is checked by a live run on a real repository before merge.

## Out of scope

- Merging PRs, or watching their CI.
- Fork workflows, sweeps across repositories, or non-MoonBit code.
- Splitting one package across several workers.
- A token budget flag.

## Review

| Codex finding | Resolution |
|---|---|
| HIGH: `committed` does not mean done or verified; capture runs for every outcome | Step 4 gate: a `done` report is required as well |
| HIGH: a `review` child audits the checkout, not the worker's commit | The reviewer is an `explore` child reading git objects, with a strict verdict line; tests are the worker's and CI's |
| MEDIUM: `origin/main` vs `main` for `gh --base`; unbound repository | `default_ref` and `base_branch` kept apart; `--repo` from `gh repo view`; PR mode tested offline |
| MEDIUM: scouts read the checkout, workers fork HEAD | Clean tracked files required; HEAD pinned and each worker's base checked |
| MEDIUM: worktree names are limited to 40 characters of `[a-z0-9-]` | `simp-<hash>-<slug>` |
| MEDIUM: the launcher refuses a workspace below the repository root | Preflight requires the root |
| MEDIUM: children do not see `AGENTS.md` | Workers read the `AGENTS.md` chain and run what it requires |
| LOW: explore children can build in their lab | Described as read-only, not build-free |

Implementation review (Codex, high, whole branch):

| Codex finding | Resolution |
|---|---|
| HIGH: a worker can read as ended before its capture finishes, so a valid change is skipped and a slot freed early | A worker still `working` stays in the wait set; the fake host now races capture the same way |
| MEDIUM: `gh repo view` may name a repository other than `origin` | `--repo` is resolved from `origin`'s URL |
| MEDIUM: remote branch names collide across sweeps | The branch carries the commit's first 8 characters |
| MEDIUM: a push or `gh` timeout aborts the remaining packages | Caught per package; the run still prints its report |

## Live run

A headless `openseek run --model deepseek-flash` session on a scratch
repository (three packages, a few planted wins, `--no-pr --scouts 2`):
2 scouts, 3 workers and 2 reviewers ran, about 1.36M tokens in all. The
workers turned an index loop into `xs.map`, dropped an `.iter()` hop, turned a
`+` chain into interpolation, bound `parts is [key, value]` instead of
checking the length, and inlined a single-use helper as
`xs.last().unwrap_or(0)`. Both reviewers accepted. The worker for the package
with no real win changed nothing.

A real sweep of `moonbitlang/core` (PR mode, defaults: 4 scouts, at most 4
PRs, deepseek-flash, from a clean worktree at `origin/main`):
- **Coverage:** 77 packages and 37 candidates.
- **Result:** 4 workers ran, 4 changes were reviewed and accepted, and 4 PRs were
  opened (moonbitlang/core#4432 to #4435: `bigint`, `string/internal/regex_engine`,
  `argparse`, `list`).
- **Tokens:** about 23M in all, of which the scouts used about 13M.
- **Change quality:** every change was checked by hand:
  - each descending range matches the C-style loop it replaced;
  - each pattern binds what its check guarded;
  - `argparse`'s length-checked positional loop keeps its bound.
  The weakest change merged two named match arms into `OptionInfo(_)`. That is
  correct today, since `OptionAction` has only `Set` and `Append`, but it gives
  up the exhaustiveness check; the guidance now rules it out.
- **Reviewers:** they built each change in a worktree inside their lab and ran
  its tests.

The run surfaced three fixes:
- the stale worktree records those labs left (now pruned at the end);
- the published workers' local branches (now deleted);
- review text whose line breaks were collapsed into one paragraph in the PR body
  (now kept).

A sweep of this repository (`--no-pr`, defaults: 8 scouts, at most 8
changes, deepseek-flash, from a clean worktree at `origin/main`):
- **Coverage:** 350 packages and 85 cited candidates, after many earlier
  manual sweeps. The scouts finished in about 3 minutes.
- **Result:** 8 workers ran and 8 changes were reviewed and accepted
  (`desktop/frontend`, `desktop/frontend/fileeditor`, `desktop/protocol`,
  `desktop/backend/host`, `desktop/backend/internal/console_proxy`,
  `editor/internal/shell/workbench`, `editor/internal/viewer/markdown`,
  `editor/internal/viewer/contrib/hover/browser`).
- **Tokens:** about 30M in all, of which the scouts used about 14M.
- **Change quality:** every hunk keeps behavior, and the 8 commits apply
  together cleanly and pass `moon fmt --check` and `moon check --deny-warn`.
  Most are small: interpolation, direct container methods, comprehensions,
  plus a few patterns that bind guarded indexes and a `while xs.pop() is Some(x)`
  drain.
- **Cleanup:** no worktree records were left behind.

The run surfaced one fix: three interpolations joined a `+` chain that had
been split across lines into one line of up to 123 columns. The guidance now
keeps interpolation to results that fit on one line.
