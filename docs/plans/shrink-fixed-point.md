# Shrink to a fixed point

Status: implemented in `share/workflow/shrink.mbtx`, after a Codex (xhigh)
design review (see Review).

`@builtin/shrink.mbtx` shrinks the public API of a MoonBit workspace until
`moon ide analyze` finds nothing left to shrink. It automates the method in
[shrink_package.md](../../shrink_package.md). Each round becomes one pull
request, stacked on the previous round's. Desktop gets a `/shrink [focus]`
prompt command that runs it, as `/simplify` runs
[simplify swarm](simplify-swarm.md).

## The fixed point

`moon ide analyze` (no paths: every package of the workspace, about 25 s here)
prints each package's exported items with `// usage: N (M in test)`, where N
counts uses from OTHER packages and M how many of those are in tests. It
appends `, in exports.mbt` to items defined in a package's `exports.mbt`, and
`(all) or (open) can be removed` to types whose visibility can narrow.

A **candidate** is a top-level row (not indented) without `in exports.mbt`
that is one of:

- an exported item whose usage line has `N == M`: no use from another
  package (`N == 0`), or only tests use it (`N == M > 0`);
- a type with the `(all) or (open) can be removed` hint.

Not candidates:

- **rows without a usage count**, such as derive-generated methods or
  `type Model derive(Eq)`: a missing count is not a zero;
- **`pub impl` rows**: the manual demotes some, but a conformance used
  through a trait object cannot be, and the counts don't tell which. They are
  left out of this version, so its fixed point covers the other rows only;
- **re-exports**: the analyzer does not count uses through a `pub using`,
  so a re-exported item reads `usage: 0` while other packages use it (found
  in the live run: `CloudOrigin`, `Failure`, `RequestError` of
  `desktop/frontend/cloud`). A re-exported type is a `pub using` row, but a
  re-exported value is listed as a plain declaration (`pub const
  CloudOrigin …`), so the script reads the package's `pub using` blocks and
  leaves out every row that declares a re-exported name, or a method of
  one;
- **fields, variants and trait methods** (indented rows): a field of a plain
  `pub struct` cannot be made private, so they shrink only through their
  type's narrowing hint;
- **a test kit's test-only items**: a package that other packages import
  only `for "test"` (in `moon.pkg`, or `test-import` in `moon.pkg.json`)
  exists for those tests (shrink_package.md's test-kit exemption). Its
  unused items are still candidates.

The repository convention makes every candidate resolvable inside its own
package: drop `pub` (only its package uses it), delete it (vestigial), narrow
`pub(all)`/`pub(open)`, or move it to `exports.mbt` with a comment naming why
it is exported without a consumer. So the end state needs no state outside the
repository:

> **Fixed point**: the analyzer reports no candidate.

It takes rounds because changes cascade. Deleting a vestigial function drops
its uses of other packages' items, which may then have no production use.
Narrowing or demoting may surface `unused_*` warnings that show more dead
code. Cascades can raise the candidate count, so progress is judged per
package (see Progress), not by the total.

Moving an item to `exports.mbt` clears it without shrinking anything, so the
reviewer checks each such move against a fixed list of reasons, and each round
reports its interface change: lines removed from and added to
`pkg.generated.mbti`, and lines added to `exports.mbt`.

Today: 125 packages carry 308 unused items, 229 test-only items and 140
narrowable types.

**The yardstick is usage inside the repository**, as in the manual sweeps
(the owner's call in #522). The analyzer only sees the workspace, so the
worker `git grep`s the whole repository before any visibility change (`.mbtx`
scripts use `moonbitlang/openseek_tools`, and `desktop/app` is a separate
module that imports backend APIs). A module published for outside users is
left alone with `--exclude` (for this repository: `tools_sdk`, `protocol`,
and `editor`, a Monaco mirror published as its own module).

## Interface

```
@builtin/shrink.mbtx [--path DIR ...] [--exclude DIR ...] [--skip DIR ...]
                     [--max-packages N] [--rounds N] [--check-target T ...]
                     [--check-in DIR ...] [--stack-on BRANCH] [--no-pr]
                     [--] [FOCUS...]
```

- `--path DIR` (repeatable): only packages under these directories.
- `--exclude DIR` (repeatable): leave every package under these directories
  alone.
- `--skip DIR` (repeatable): leave the one package in each directory alone
  (what a continuation passes for given-up packages).
- `--max-packages N`: at most N packages per round (default 8, at most 16).
  Each round is one PR, so this keeps a PR reviewable.
- `--rounds N`: stop after N rounds (default: until the fixed point or the
  start quota).
- `--check-target T` (repeatable): check each combined round with
  `moon check --deny-warn --no-mbti --target T`; by default once, with no
  `--target`. This repository passes `native` and `js`.
- `--check-in DIR` (repeatable): also run that check in DIR, a separate
  workspace that imports this one. This repository passes `desktop/app`.
- `--stack-on BRANCH`: the first round's PR targets BRANCH, and HEAD must be
  exactly `origin/BRANCH`'s tip. This continues a published stack.
- `--no-pr`: keep each round on a local branch; push nothing.
- `FOCUS`: an emphasis for workers, never a license to break the rules.

## Pipeline

### 0. Preflight

As in simplify: the session is at the repository root and tracked files are
clean. Unless `--no-pr`, the PR target is resolved: the repository comes from
`origin`'s URL, `gh auth status` must succeed, and HEAD must be an ancestor
of `origin/HEAD` (or equal `origin/<--stack-on>`). Then:

- the package manifests are read once (test kits);
- the starting HEAD is recorded: its branch name if attached, else its
  commit.

The script prints that recovery point first.

### 1. Rounds

Each round, from its base commit B (round 1: the starting HEAD; HEAD is B):

1. **Analyze.** Run `moon ide analyze`, then require tracked files to still
   be clean (its check could rewrite a stale `pkg.generated.mbti`). Parse the
   candidates and map each package name to its directory as Moon resolves
   it: `moon check --dry-run` prints one `moonc check` per package, naming
   its source files and `-pkg <name>`, from Moon's workspace root: the
   nearest `moon.work` at or above the checkout root that lists the
   checkout, as Moon finds it. A
   package whose files are outside the checkout
   (a `moon.work` member beside it) is reported as not in this checkout and
   keeps the run from a plain fixed point. Keep
   packages under `--path`, not under `--exclude`, not named by `--skip`, and
   not given up earlier in this run (see Progress). With none left, the run has reached the fixed
   point: "fixed point" when the analyzer reports nothing in scope, else
   "fixed point except <packages>", which is incomplete scope, not a global
   fixed point.
2. **Select.** Rank packages by candidate count (descending, ties by path)
   and take the first `--max-packages`, fewer if the start quota is short.
3. **Work.** One `worker` child per package, at most 8 live (the engine's
   cap). Each runs in its own worktree forked from HEAD, which is B, and is
   labeled `shrink:<dir>`. Its `allowed_paths` are:
   - the package's tracked `.mbt` files;
   - its `moon.pkg`/`moon.pkg.json` (an import only a deleted item used);
   - its `pkg.generated.mbti`;
   - `<dir>/exports.mbt`;
   - `<dir>/<last segment>_wbtest.mbt`, for tests that move in.

   They stay disjoint across packages. The brief carries the candidate rows
   verbatim, the method, and these rules:
   - Resolve EVERY candidate: demote, delete, narrow, or move to
     `exports.mbt` with a reason from this list: a test seam that tests of
     other packages use; protocol or round-trip surface; a documented tunable
     or one member of a symmetric family; a consumer the analyzer cannot see,
     named with its file and line. "Might be useful" is not a reason. The
     last reason includes the analyzer's own misses: a `{ ..x, f }` record
     update of a `pub(all)` type in another package, which its narrowing
     hint ignores (plain struct literals are counted). Nothing is left in place, since a
     left item would be listed again forever; the one exception is an item
     defined in a generated file.
   - Workers cannot delete files (the remove tool needs an approval they
     have no channel for), so they empty a file whose code all moved; the
     combine step removes it.
   - Before any visibility change, `git grep -n -w <name>` the whole
     repository.
   - Test use alone never justifies an export. Tests of this package move to
     its whitebox file when its own code also uses the item. When only tests
     use it, a whitebox file is not enough: `--deny-warn` does not count
     whitebox tests as uses (`unused_value`), so the item is deleted with its
     tests, or its tests become inline `test` blocks in its source file. For
     tests of other packages, it is a seam, or the
     worker leaves the item and says so; it never edits another package.
   - Validate the whole workspace, since a shrink breaks consumers, not the
     package. Run `moon check --deny-warn --no-mbti` from the root for each
     target the repository builds, since without `--no-mbti` a workspace
     check rewrites other packages' interfaces. Check consumers outside the
     workspace that `git grep` found. Then `moon test` for the package, and
     `moon check` (which regenerates its interface) and `moon fmt` with the
     package path.
   - Report `done` only when all of that passed; list every candidate and
     what was done to it.
4. **Gate** (as simplify): the capture is `committed`, its base is B, and the
   worker reported `done`. A worker read as ended while its capture is still
   `working` stays in the wait set.
5. **Review.** One `explore` child per gated change (`shrink:review-<dir>`,
   60 steps). It reads the change as git objects, gets the candidate rows,
   and must open with a strict `VERDICT: ACCEPT` or `VERDICT: REJECT` line.
   Criteria:
   - every item made private, deleted **or narrowed** has no production use
     the change breaks: it `git grep -w`s other packages, `.mbtx` scripts,
     js-only packages and modules outside the workspace, and looks for struct
     literals of a narrowed type;
   - every `exports.mbt` addition names a true reason from the list;
     blessing items just to clear the list is a REJECT;
   - deletions are vestigial code, not one half of an API;
   - no behavior change; tests moved or converted, not lost;
   - only the package's files changed, and its interface only lost lines (or
     `pub(all)` became `pub`).
6. **Combine.** If nothing was accepted, the round publishes nothing and the
   next round starts from the same B. Otherwise:
   - `git checkout --detach B`, then `git cherry-pick` the accepted commits
     one at a time, in package order. The files are disjoint, so this should
     not conflict; the result is one commit per package. After each pick,
     the package's files that the commit left with nothing but comments are
     `git rm`ed, and the commit is amended into
     `refactor(<dir>): shrink public API` with the worker's summary as its
     body (the engine names a worker's commit after its worktree). On any
     failure (a nonzero exit, or an
     error such as a timeout) the pick is aborted and the run stops.
   - The tip is kept on the local branch `shrink/r<k>-<8 of the tip>`.
   - The accepted workers' branches are deleted.
   - The combination is checked with `moon check --deny-warn --no-mbti` per
     `--check-target`, then in each `--check-in` directory. Two packages' changes, each valid alone, meet here
     for the first time (A starts using a helper B demotes). A failure stops
     the run and leaves the round on its local branch. Tests are not rerun
     on the combination: each package's tests ran in its worker, and a
     visibility change or a deletion of unused code cannot change another
     package's behavior.
7. **Publish.** Unless `--no-pr`:
   - push the tip to that branch on `origin`;
   - open a PR whose base is the previous round's branch (round 1: the
     default branch or `--stack-on`), titled
     `refactor: shrink public API (round k)`.

   The body has the interface change, and per package the worker's
   per-candidate summary and verification and the review. Nothing is merged.
8. **Advance.** The tip is the next round's B, and it is checked out. A
   package whose change was not accepted (refused, failed, `no_changes`,
   unmergeable, rejected, unreviewed) is given up for the rest of the run.

### 2. Progress

Every round either gives a package up or changes it. An accepted change
records the rows its package was given. If the next analysis still lists any
of those rows (compared by declaration), the change did not resolve them: the
package is printed as `unresolved after its change: …` and given up. New
rows from cascades don't count against it. So each package can be offered at
most once more than it makes progress, and a run always ends.

### 3. Checkout

Workers fork from the session's HEAD; there is no host argument for another
base. So each round checks out its base, and at the end the script checks out
the starting branch (or commit) again, success or failure.

If the run is killed (the session ends, the job is stopped), the
script cannot clean up: the checkout may be detached, or in the middle of a
cherry-pick. The first line it prints names the starting point to go back
to. Run it in a checkout of its own: a worktree at the default branch.

### 4. Budget and continuation

- A script may start at most 128 children (`ScriptQuota`): a round of k
  packages costs at most 2k starts. A round starts only if a package fits,
  so a run does at least eight rounds of 8.
- The host retains every tool call's arguments and result, up to 4 MiB per
  script (`MaxTraceBytes`), and serves at most 1,024 calls
  (`MaxCallsPerProgram`; a wait that times out counts). The second live run
  retained 37.5 KB and 7.4 calls per package (two briefs of about 9 KB, two
  reports of about 8 KB, and the waits), so the 512 KiB budget it had would
  have run out in a default run's second round. The script meters both,
  counting each result JSON-escaped as the host does, and sizes each round
  to what fits beyond a reserve (512 KiB, 128 calls): each package costs a
  quarter over the measured average, and at least 48 KB and 16 calls. A run
  that cannot fit one more package stops with `stopped: the host's call or
  trace budget is spent`. A round that runs over anyway meets a refusal; the
  run abandons that round, neither giving nor skipping its packages, and
  stops with `stopped: the host refused a call in round <k>` and its
  continuation.
- Live: at most 8 workers plus their reviewers (16 children).
- A run that stops short (`--rounds`, the start quota, the trace budget) or
  gives packages up prints
  `continue from <branch>: <arguments>`: check out that branch and run again
  with them. The arguments keep `--path`, `--max-packages`,
  `--check-target`, `--check-in`, `--rounds`, `--no-pr` or `--stack-on <branch>`,
  `--exclude`, every skipped package (given and given-up, as exact
  `--skip`) and the focus. Desktop shows the line; it never continues by
  itself, so the person decides each further run.

## Output and exit

- `round k: packages=P chosen=K`;
- one line per chosen package (`<dir>: candidates=C worker=… review=…`),
  with a rejected change's reasons;
- `round k: accepted=A tip=<commit> api: pkg.generated.mbti -R +A,
  exports.mbt +E pr=<url|branch>`;
- at the end, one `stack:` line per round;
- the ending (`fixed point`, `fixed point except …`, `stopped: …`), followed
  by `rounds=… starts=… tokens=…`;
- the continuation line.

The run exits nonzero when:
- preflight fails;
- a start was refused, or a child ended without a result;
- the round does not combine, or fails its check;
- a push or PR failed.

## Desktop

`/shrink [focus]` is a prompt command like `/simplify`. It asks the agent to:
- run `@builtin/shrink.mbtx`, passing `--check-target` for the targets the
  repository's AGENTS.md names;
- wait for it;
- report the stack in order: each round's interface change, the rejected
  changes, the packages given up, and the continuation line, which it does
  not run.

## Tests

Offline, in `tests/integration/workflows/shrink.mbt`, against the fake PTC
host. The repository is a temporary one with:
- a nested module in `moon.mod.json` format;
- a test kit;
- a local bare `origin`;
- a stub `gh`;
- a stub `moon` that serves canned `ide analyze` text per call, records each
  call with the commit it ran at, and fails `check` on demand.

Committers are pinned, so the test predicts each round's cherry-picked tip
and the scripted workers report commits on it. The modes cover:

- **publish:** a nested module whose package lives under its `source`
  directory, as the fake `moon check --dry-run` places it; two
  stacked PRs; round 1 combining two packages' commits,
  with the test file one worker emptied removed in its own commit;
  `--check-in`;
  round 2 analyzed and checked at round 1's tip; `--exclude`; base branches; the interface line; the parser (padded rows, `//`
  inside a value, blessed, used, member, unannotated, impl and derive rows,
  an unmapped package, the test kit); allowed paths; the capture race; a
  rejected change; `no_changes`; the unresolved package; and the
  continuation line;
- **check-fails**; **conflict** (the pick is aborted, nothing left half
  done); **rounds**, then **continue**, which runs the exact arguments the
  bounded run printed from its branch (given-up packages stay out, the limit
  holds); **none** (nothing accepted); **skip** (`--skip` of a package
  leaves the package nested in it eligible);
- **fixed point**;
- **preflight:** bad number, subdirectory, dirty, ahead of origin, and a
  `--stack-on` mismatch.

After every mode, HEAD is back where it started, the tree is clean and no
cherry-pick is in progress. `just check-workflows` type-checks
the script. Desktop: the frontend whitebox tests list the command, and the
e2e specs send `/shrink` locally and in Cloud.

## Out of scope

- Editing other packages' tests.
- `pub impl` rows.
- Merging PRs, or continuing automatically.

## Live run, round 1

A first live run on this repository (`--check-target native --check-target
js --exclude editor --exclude tools_sdk --exclude protocol --max-packages 4
--rounds 3`, deepseek-flash, from a clean worktree at `origin/main`) chose
`desktop/frontend/fileeditor` (40 candidates), `desktop/protocol` (26),
`desktop/frontend/cloud` (17) and `desktop/frontend/composer` (17). Each
worker took about 10 minutes. They checked the whole workspace and, on their
own, the separate `desktop/app` workspace too, and reported every candidate
with evidence:

- `fileeditor`: 2 deleted, 7 demoted, 26 narrowed, 3 test seams.
- `protocol`: 2 deleted, 2 demoted, 13 narrowed. The `desktop/app` check
  caught 2 bad narrowings, which were reverted.
- `cloud`: 12 narrowed.
- `composer`: 20 interface lines removed, including two types made private.

The reviewers built each change in their lab, and one proved its key claim
with an experiment: a `pub` enum stays matchable from another package.

The run surfaced six fixes, now in the script:

- **`pub using` re-exports were false candidates.** The analyzer doesn't
  count uses through them, so they are now left out.
- **Workers left items in place** that other packages build with `{ ..x }`
  record updates, or that the separate `desktop/app` workspace builds. The
  narrowing hint misses both, and a left item would be listed forever. Such
  items now go to `exports.mbt` with the consumer named, and nothing is
  left in place.
- **Workers cannot delete files**, so two left a stub test file holding only
  a comment. They now empty the file, and the combine step removes it.
- **The combined check now covers separate workspaces** (`--check-in`).
  The workers' own `desktop/app` checks were what caught the bad
  narrowings.
- **Commit names.** Round 1's PR carried the engine's commit names
  (`subtask shrink-6e675f1b-desktop-frontend-compose: worker changes`), so
  each pick is now reworded as `refactor(<dir>): shrink public API` with
  the worker's summary as its body.
- **Two traps are now in the guidance:** a `pub` type stays matchable and
  readable from other packages, and a `pub extend T with Eq` keeps a type in
  the interface.

## Review

Design review (Codex, xhigh):

| Codex finding | Resolution |
|---|---|
| HIGH: the gate misses consumers outside the workspace (`.mbtx` scripts via `openseek_tools`, `desktop/app`), and narrowing was not audited | Worker and reviewer `git grep` the whole repository before any visibility change, narrowing included; published modules are skipped by `--skip` |
| HIGH: restoring HEAD does not cover a killed run, an interrupted cherry-pick, or obstructing files | Picks are aborted on failure; each round's tip is a named local branch; the recovery point is printed first; run in a checkout of its own. No promise after process death |
| HIGH: no enforced progress; continuation removes the overall bound; blessing conflates shrinking with classification | Per-package progress check; Desktop never continues automatically; each round reports interface lines removed vs. kept in `exports.mbt` |
| MEDIUM: impl rationale wrong; unannotated rows; test-kit exemption | Impls left out as a stated v1 boundary; unannotated rows never count; test kits detected from manifests |
| MEDIUM: allowed files and validation contradict the work; `moon check` rewrites other packages' `.mbti` | Manifest and one wbtest file allowed; every workspace check uses `--no-mbti` |
| MEDIUM: empty rounds, `--stack-on` equality, continuation arguments, `--no-pr` continuation | Empty rounds publish nothing; `--stack-on` requires the exact tip; the continuation line keeps every option, local in `--no-pr` mode |
| LOW: failing checks, real analyzer rows, the capture race in tests | All in the offline modes above |

Implementation review (Codex, xhigh, whole branch):

| Codex finding | Resolution |
|---|---|
| MEDIUM: the continuation turns given-up packages into subtree skips (`--skip .` skips everything) | `--skip` names one package; `--exclude` is the subtree form |
| MEDIUM: the continuation drops `--rounds` | Kept; the continue mode runs the printed arguments and checks the limit holds |
| MEDIUM: a cherry-pick that raises (a timeout) skips the abort | Raised errors and nonzero exits share one abort path, whose own failure is reported |
| Tests never combine two commits, nor execute a continuation | A second accepted package in round 1 (a negative control that picks only the first commit fails), a conflict mode, and the continue mode |

Second pass (Codex, xhigh, whole branch): the three fixes above confirmed.

| Codex finding | Resolution |
|---|---|
| MEDIUM: packages of a module with `source = "src"` map to the wrong directory and drop out silently, faking a fixed point | The module's `source` directory is resolved; the fixture's nested module uses one (a negative control without the fix fails) |
| LOW: no test of a skipped package with an eligible descendant | The skip mode |
| LOW: no test of a cherry-pick that raises rather than exits nonzero | Not injected: the test host cannot make `git` time out. Both outcomes go through the one `abort_pick`, which the conflict mode exercises |

Third pass (Codex, xhigh, whole branch): the earlier fixes confirmed.

| Codex finding | Resolution |
|---|---|
| MEDIUM: a re-exported value is listed as a plain `pub const`, so excluding `pub using` rows misses the live run's own case | Rows declaring a name the package's `pub using` blocks re-export (or a method of one) are left out; the fixture re-exports a value, a type and a renamed function |

Fifth pass (Codex, xhigh, whole branch after the second live run): four
P1 findings, each confirmed before it was fixed. Its P2 findings are left
for follow-ups.

| Codex finding | Resolution |
|---|---|
| P1: `--exclude --no-pr` takes `--no-pr` as the directory, so a local run publishes; unknown options become focus text | A flag's value may not start with `-`, and an unknown option before `--` is refused; the option-value and unknown-option modes |
| P1: a merge whose result is HEAD leaves `git status --porcelain` empty, and the final checkout discards it | Preflight refuses a pending merge, cherry-pick, revert, rebase or bisect; the merging mode checks `MERGE_HEAD` survives |
| P1: `name = "x" // comment` is not parsed, so the module's packages drop out and the run reports a fixed point | The value is the first quoted string; a package with candidates in no known module is reported and keeps the run from a plain fixed point. The fixture's root manifest has a trailing comment (the old script reports `fixed point except sub/src/delta`) and the unmapped mode |
| P1: the host retains every call against a 512 KiB budget, and a refused call ends the run without its continuation | Measured on the second live run: 450,674 bytes for 12 packages. The host budget is 4 MiB (job records 8 MiB) and a script may start 128 children; the script meters its calls and sizes rounds to fit, stopping with its continuation. The 40-character fake host cannot reach 4 MiB, so the stop was checked by hand with the budget set to 120,000 bytes |

Sixth pass (Codex, xhigh, the fifth pass's fixes):

| Codex finding | Resolution |
|---|---|
| P1: round sizing uses an average, results are counted unescaped, and a refused wait still ends the run without its continuation | Results are counted as the host stores them; a refused call raises `HostLimit`, which abandons the round and stops with the continuation (the host-limit mode, whose fake host refuses a wait as agent_tool/ptc does) |
| P1: the 1,024-call limit is not tracked | Calls are metered beside bytes and rounds sized by both |
| P1: a cherry-pick sequence between two picks passes preflight | `sequencer/` is a marker too (the sequencing mode) |
| P2: a `name` inside a `rule(...)` before the module's own wins; compact `moon.mod.json` has no matching line | A `moon.mod.json` is parsed as JSON; a `moon.mod` field must start its line (revised in the seventh pass). The fixture's root manifest has such a rule |
| P2: a `moon.work` member outside the checkout aborts even a scoped run | Reported as not in this checkout, and the run ends `fixed point except` it rather than failing |
| P2: a branch named `MERGE_HEAD` reads as a merge | Every marker is a file looked up with `git rev-parse --git-path` |
| P2: `--exclude ./-vendor` continues as `--exclude -vendor`, which is refused | Continuation arguments keep `./` before a leading `-` (the rounds mode's continuation, which the continue mode replays) |
| P2: 100 records with 4 MiB traces pass an SSH host's 128 MiB reply | A history page also stopped once its records' data reached 32 MiB (replaced in the seventh pass) |

Seventh pass (Codex, xhigh, both fix commits):

| Codex finding | Resolution |
|---|---|
| P1: requiring a `moon.mod` field at column 0 drops a valid indented one (`  source = "src"`), faking a fixed point | Fields are told apart by syntax: a top-level field is an assignment, `key = "x"`, at any indentation, while a `rule(...)` argument is `key: "x"`. The fixture's root `name` is indented, after a rule with a `name:` |
| P2: a legacy `moon.mod.json` with comments or a trailing comma fails strict JSON | Such a file is read by its `"key": "x"` lines; the fixture's nested manifest has both |
| P2: a refusal after a child failed suppresses the continuation | A host refusal prints the continuation whatever the round recorded |
| P2: an abandoned round's starts and tokens are lost | Counted as they happen; the host-limit mode checks its whole stop line (`starts=5`) and continuation |
| P2: a test kit's test-only rows are reported as unmapped | The kit filter runs first; a package left with no candidates is neither |
| P2: size-bounded history pages break the desktop's paging cursor, miss the first page's running jobs, and count UTF-16 units | Replaced: listed jobs leave out their `data` (the trace), so a page stays small at 100 rows; `selected`, which every desktop list request asks for, carries it |
| P2: an external module whose name extends a local module's maps to a local directory | Not fixed: needs the analyzer's package locations. A follow-up |

Eighth pass (Codex, xhigh, the three fix commits):

| Codex finding | Resolution |
|---|---|
| P1: on a first-page reply the desktop ordered the list rows after merging `selected`, so the selected job lost its trace | `selected` is merged last (a frontend test with both copies; it fails without the fix) |
| P2: a `moon.mod.json` that opens with a comment reads as a `moon.mod` | The format is the file's name; the fixture's nested manifest opens with a comment |
| P2: a proactive budget stop after a failure prints no continuation | Both host-limit stops print it |
| P2: a first round too large for the budget is retried at the same size | Not fixed: a follow-up |
| P2: usage read from a child's earlier report chunks is lost at a refusal | Not fixed: the stop line's token count only. A follow-up |

Ninth pass (Codex, xhigh, P1 findings only, the four fix commits):

| Codex finding | Resolution |
|---|---|
| P1: `moon.mod` sets `source` in an `options(...)` block (`source: "custom"`), which the assignment-only reader missed, faking a fixed point | A `moon.mod` field is a top-level assignment or an `options(...)` argument; other blocks' arguments are not. The fixture's nested module is a `moon.mod` with a rule, an indented `name =` and `options(source: ...)`, and its root a legacy `moon.mod.json` that opens with a comment (the previous reader loses `sub/src/delta`) |

Tenth pass (Codex, xhigh, P1 findings only, the five fix commits):

| Codex finding | Resolution |
|---|---|
| P1: a quoted `"source":` key in `options(...)` is missed, faking a fixed point | Superseded: the script no longer reads module manifests. Each pass found another way a `moon.mod` can set a name or `source` (comments, indentation, `rule(...)` arguments, `options(...)`, quoted keys, parentheses in comments), so packages are mapped to directories from `moon check --dry-run`, Moon's own resolution, which the analyzer shares. On this repository it maps all 333 analyzed packages |
| P1: a `)` in a comment ends the `options(...)` block early | Superseded likewise |

Eleventh pass (Codex, xhigh, P1 findings only, the six fix commits):

| Codex finding | Resolution |
|---|---|
| P1: with `moon.work` above the checkout, Moon prints `./repo/src/x.mbt`, which matches no tracked file, so the package drops out | The checkout's prefix in Moon's paths was inferred from which printed files are tracked (replaced in the twelfth pass); the workspace-above mode (the previous script fails it) |
| P1: an open browser on the old frontend loses the selected job's trace from a host that lists jobs without it, at the same protocol revision | `HostProtocolRevision` is 16, and the E2E harness's `hostProtocol` with it |

Twelfth pass (Codex, xhigh, P1 findings only, the seven fix commits):

| Codex finding | Resolution |
|---|---|
| P1: the inferred prefix fails when a package's first listed file is generated and untracked, and a sibling with the same layout can outvote the checkout | The prefix is no longer inferred: Moon's workspace root is the nearest `moon.work` at or above the checkout root, found as Moon finds it (scripts may read any path). The workspace-above mode writes a real `moon.work` above the fixture, and alpha's first listed file is untracked |

Thirteenth pass (Codex, xhigh, P1 findings only, the eight fix commits):

| Codex finding | Resolution |
|---|---|
| P1: an ancestor `moon.work` that does not list the checkout is used, though Moon ignores it, so the checkout's own paths lose a real prefix | An ancestor `moon.work` counts only when its `members` hold the checkout (or a module in it); the workspace-sibling mode (the previous script fails it) |
