# Shrink to a fixed point

Status: design, for review.

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

A **candidate** is one of:

- a top-level exported item (`pub fn`, method, `pub const`, `pub let`, type)
  whose usage line has `N == M` (no production use from another package) and
  no `in exports.mbt`. `pub impl` rows are left out: a trait implementation's
  count misses dynamic dispatch, and conformance cannot be demoted;
- a `(all) or (open) can be removed` hint without `in exports.mbt`.

Field and variant rows are not candidates on their own (a field of a plain
`pub struct` cannot be made private), only through their type's narrowing
hint.

The repository convention makes every candidate resolvable inside its own
package: drop `pub` (used only in its package), delete it (vestigial), narrow
`pub(all)`/`pub(open)`, or move it to `exports.mbt` with a comment saying why
it is exported without a consumer. So the end state needs no state outside
the repository:

> **Fixed point**: the analyzer reports no candidate.

It is reached in rounds because changes cascade. Deleting a vestigial
function drops its uses of other packages' items, which may then have no
production use. Narrowing or demoting may surface `unused_*` warnings that
show more dead code.

Today: 125 packages carry 308 unused items, 229 test-only items and 140
narrowable types.

## Interface

```
@builtin/shrink.mbtx [--path DIR ...] [--skip DIR ...] [--max-packages N]
                     [--rounds N] [--stack-on BRANCH] [--no-pr] [--] [FOCUS...]
```

- `--path DIR` (repeatable): only packages under these directories.
- `--skip DIR` (repeatable): leave these packages alone (carried from an
  earlier run that could not resolve them).
- `--max-packages N`: at most N packages per round (default 8, at most 16).
  Each round is one PR, so this keeps a PR reviewable.
- `--rounds N`: stop after N rounds (default: until the fixed point or the
  start quota).
- `--stack-on BRANCH`: the first round's PR targets this branch instead of
  the default branch; HEAD must be `origin/BRANCH`'s tip. This is how a later
  run continues a stack.
- `--no-pr`: keep each round on a local branch; push nothing.
- `FOCUS`: an emphasis for workers, never a license to break the rules.

## Pipeline

### 0. Preflight

As in simplify: the session is at the repository root; tracked files are
clean; unless `--no-pr`, the PR target is resolved (`origin/HEAD`, the
repository from `origin`'s URL, `gh auth status`) and HEAD is an ancestor of
the target (`origin/<default>` or `origin/<--stack-on>`). The starting HEAD
(its branch name if attached, else its commit) is recorded to restore.

### 1. Rounds

Each round, from the round's base commit B (round 1: the starting HEAD):

1. **Analyze.** Run `moon ide analyze` and parse it into packages and
   candidates. Map each package name to its directory with the tracked
   `moon.mod` files (`name` + the package's path inside the module). Drop
   packages outside `--path`, in `--skip`, or skipped earlier in this run.
   If none is left, the run has reached the fixed point (or the fixed point
   up to the skipped packages) and stops.
2. **Select.** Rank packages by candidate count (descending, ties by path)
   and take the first `--max-packages`.
3. **Work.** One `worker` child per package, at most 8 live (the engine's
   cap), each in its own worktree forked from HEAD (= B), label
   `shrink:<dir>`. `allowed_paths` = the package's tracked `.mbt` files, its
   `pkg.generated.mbti`, and `<dir>/exports.mbt` (which it may create). The
   brief carries the package's candidate rows verbatim, the method below, and
   the rules:
   - Resolve EVERY candidate: demote, delete, narrow, or move to
     `exports.mbt` with a one-line reason from this list: a test seam that
     several packages' tests use; protocol or round-trip surface (JSON
     codecs, wire types); a documented tunable or one member of a symmetric
     family; a consumer the analyzer cannot see (a `.mbtx` script, another
     workspace, a js-only app, an external user of a published module), named
     in the comment.
   - A test-only item whose tests live in this package: move or convert the
     test (it may not edit other packages' tests). A test-only item whose
     tests are in another package: an `exports.mbt` test seam, or leave it
     and say so.
   - Change only the allowed files; never generated files.
   - Validate the whole workspace, since a shrink breaks consumers rather
     than the package: `moon check --target native --deny-warn` and
     `moon check --target js --deny-warn` from the root, `moon test` for the
     package, then `moon info` and `moon fmt` with the package path. The
     `.mbti` diff may only shrink.
   - Report `done` only when all of that passed; list every candidate with
     what was done to it.
4. **Gate** (as simplify): the capture is `committed`, its base is B, and the
   worker reported `done`.
5. **Review.** One `explore` child per gated change (`shrink:review-<n>`),
   reading the change as git objects, strict first line `VERDICT: ACCEPT` or
   `VERDICT: REJECT`. Criteria:
   - every demoted or deleted item has no production use anywhere in the
     workspace (`git grep`, or `moon ide analyze` in a worktree of the
     commit), including `.mbtx` scripts and js-only packages;
   - every `exports.mbt` addition names a concrete reason from the list;
     "might be useful" is not one. Blessing everything to reach the fixed
     point is a REJECT;
   - deletions are vestigial code, not one half of a symmetric API;
   - no behavior change; tests moved or converted, not lost (unless they
     only tested deleted code).
6. **Combine.** `git checkout --detach B`, then `git cherry-pick` each
   accepted commit in package order. The packages' files are disjoint, so
   this cannot conflict; the result is one commit per package. Then
   `moon check --target native --deny-warn` and
   `moon check --target js --deny-warn` on the combination, since two
   packages' changes are each valid alone but checked together here for the
   first time. A failure stops the run (the round's commits stay on a local
   branch for inspection).
7. **Publish.** Unless `--no-pr`: push the round's tip to
   `shrink/r<k>-<8 of the tip>` and open a PR with base = the previous
   round's branch (round 1: the default branch or `--stack-on`). Title
   `refactor: shrink public API (round k)`. The body lists, per package, the
   worker's per-candidate summary, the review reasoning, and the `.mbti`
   line counts before and after. Nothing is merged.
8. **Advance.** The round's tip is HEAD (checked out detached) and the next
   round's B. Packages that ended without an accepted change this round
   (refused, failed, `no_changes`, unmergeable, rejected, unreviewed) are
   skipped for the rest of the run, so a run always terminates.

Workers fork from the session's HEAD, which is why each round checks out its
base. **At the end**, success or failure, the script checks out the starting
HEAD again; tracked files were clean, so nothing local is lost, and the
stack lives on its branches.

### 2. Budget

- A script may start at most 64 children: a round of k packages costs at most
  2k starts. A round starts only if its starts fit in what is left; otherwise
  the run stops with "quota" and prints the command that continues it
  (`--stack-on <last branch> --skip …`, after checking out that branch).
- Live: at most 8 workers plus their reviewers (16 children).

## Output and exit

Per round: one line per package (`<dir>: candidates=C worker=… review=…`),
then `round k: packages=P accepted=A tip=<commit> pr=<url|branch>`. At the
end: `fixed point` (no candidate left), `fixed point except <skipped>`, or
`stopped: <rounds|quota>` with the continuation command, and the token total.
The run exits nonzero when preflight fails, a start was refused, a child
ended without a result, a combined check failed, or a push or PR failed.

## Desktop

`/shrink [focus]`: a prompt command like `/simplify`, asking the agent to run
`@builtin/shrink.mbtx`, wait, and report the PR stack, what was blessed into
`exports.mbt`, and what was skipped. If the run stopped on the quota, the
prompt asks the agent to run the printed continuation.

## Tests

Offline, against the fake PTC host in `tests/integration/workflows/`, with a
temporary repository whose analyzer output is stubbed (a fake `moon` that
prints canned `ide analyze` text per round and succeeds on `check`): the
candidate parser (exports marker, impl rows, test-only, narrowing hints,
package-to-directory mapping), round sequencing with the base checked out,
the gate, cherry-pick combine, stacked PR bases, skip-on-failure
termination, the start-quota stop and its continuation line, and restoring
HEAD on success and on failure.

## Out of scope

- Editing other packages' tests.
- Shrinking published modules on behalf of outside users beyond what the
  worker can see; the reason list covers it.
- Merging PRs.
