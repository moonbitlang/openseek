# Plan v3: parallel worker subagents with worktree isolation ("subtask")

> Status (2026-09-06): the model-facing `subtask` tool described here was
> removed; the worker kind (`agent_worker`), the worktree/capture/integrate
> machinery (`agent_subtask`), and the sandboxes live on under
> `agent_workflow`'s worker runner (`worker`, `slices`, `integrate_slice`).

Date: 2026-07-31. Status: revised after subal xhigh round-2 (subal-round2.log,
NO-GO with 3 blockers + majors — all adopted below). v2: subtask-plan-v2.md.
Threat model unchanged from v2: cooperative (accident prevention + parallel
correctness), same trust tier as the parent; kernel layer macOS-only.

Follow-up (2026-08-06): the selected integration worktree may now be the main
worktree or a linked worktree. The shared registry remains repository-wide;
each entry is bound to its provisioning worktree by its canonical worker path,
and lifecycle actions from sibling worktrees are refused.

## Delta summary vs v2 (round-2 findings → resolutions)

- R2-B1 (profile wrong for linked-origin/external siblings; allow-default
  overclaim) → profile built from canonical `git rev-parse` outputs + the
  common Git directory + full `git worktree list` enumeration; lifecycle
  actions are bound to the selected integration worktree.
- R2-B2 (in-worktree marker poisons cleanliness) → controller-owned registry
  under the canonical common git dir; no marker in the worktree.
- R2-B3 (merge overwrites ignored files) → `--no-overwrite-ignore` + the
  dedicated git runner's full flag set.
- R2-MAJORs: scratch_dir launch-path gap (hotfix PR0'), static-guard
  quantifier flipped, WriteScope resolved-target + component-aware prefixes,
  mutex keyed by common git dir, reservations live until integrate/abort,
  reserve-before-provision + rollback, --untracked-files=all + separate -z
  parsers, submodules from ls-tree of base, staged-diff revalidation,
  engine-owned integrate_continue/abort, clean-tracked-origin gate,
  no unconditional prune, PR4 split, residuals restated.

## PR0' (immediate hotfix, independent of this plan): scratch-lab launch gap

`agent_tool/shell/shell.mbt`: `shell()` receives `scratch_dir` (used for its
own preblock) but omits it at both launch call sites —
`run_agent_shell_with_tree_precheck(...)` (foreground, ~line 364) and
`start_background(...)` (~line 307) — although BOTH callees accept
`scratch_dir?` and forward it to `agent_shell_launch`. Consequences today:
the K3 force-sandbox of trusted scaffolds (`moon new`) never applies on the
wired path (kernel backstop inert; lexical guard is sole defense again —
exactly the K3 blocker), and the second preblock inside each callee runs
with `scratch_dir=None` (background lab commands would be over-blocked if a
lab child ever had a bg runtime). Existing test calls `agent_shell_launch`
directly and cannot see this. Fix: pass `scratch_dir?` at both sites + an
end-to-end wbtest through `execute_with_workspace` asserting a trusted
scaffold launches SANDBOXED when a lab is present (and that the lab allow
reaches the profile). Ship first, alone.

## Provision preconditions (controller, engine-side)

1. Canonical geometry via `git rev-parse --git-common-dir --show-toplevel`
   (all realpath'd):
   - workspace_root must equal the selected worktree's toplevel. Main and
     linked worktrees are both supported integration targets.
2. Enumerate `git worktree list --porcelain` → every worktree root.
3. Reserve FIRST: worker slot (semaphore 4) + SubrunBudget slot; every later
   failure path rolls back provisioned state explicitly (postcondition
   inspection: branch? dir? admin entry? registry entry?) before the error
   result.
4. `base_oid` = rev-parse HEAD (recorded before add; add pins it).
5. Overlap check against REGISTRY entries in non-terminal states (not just
   live children): component-aware prefix intersection of `allowed_paths`.
6. Submodule check: `git ls-tree -r -z <base_oid>` mode-160000 paths vs
   `allowed_paths` (component-aware); intersection → reject.
7. info/exclude idempotent `.worktrees/` append.
8. Under the per-repo mutex (keyed by canonical COMMON git dir; process-local
   — cross-process is a documented residual):
   `git worktree add .worktrees/<name> -b openseek/<name>--<nonce>
   <base_oid>`; resolve the worktree's PRIVATE admin dir via
   `git -C <wt> rev-parse --absolute-git-dir` (never constructed from name;
   numeric suffixes exist).
9. Registry entry (controller-owned, OUTSIDE the worker-writable set):
   `<common-git-dir>/openseek/subtasks/<branch-nonce>.json` — schema v1:
   repo identity, name, branch, base_oid, worker root, admin dir,
   allowed_paths, lifecycle state (provisioned → running → captured|failed →
   committed → integrated|aborted|kept), parent session, created_at, and
   later the commit OID. This is the orphan-discovery + reservation record;
   lifecycle transitions rewrite it atomically (write temp + rename).
10. Prewarm: copy origin `.mooncakes` when present (immutable snapshot;
    measure size, skip over a threshold with a note). `_build` never copied.
11. Launch `run_subrun` (cwd=wt, `subrun worker --dir <wt>`, child_session?,
    deadline 45 min, steps 300 — resized 2026-08-04 after two sweeps
    truncated workers at the original 100). Child env additions:
    `GIT_OPTIONAL_LOCKS=0`.

## Worker sandbox profile (macOS kernel layer)

Composed per child from canonical paths (all realpath'd at provision):

- `(allow default)` — retained; scope statement is honest: the kernel layer
  confines against THIS repository and its sibling worktrees, not the wider
  filesystem (cooperative model; static guard + WriteScope cover the rest).
- `(deny file-write* (subpath <common-git-dir>))`
- `(deny file-write* (subpath <each enumerated worktree root>))` including
  the origin toplevel; enumeration happens at provision time (a sibling
  created afterwards is a documented residual).
- `(allow file-write* (subpath <worker root>))`
- `(allow file-write* (subpath <worker private admin dir>))` (resolved, not
  constructed)
- `(deny file-write* (literal <worker root>/.git))` — the gitfile pointer,
  last so it wins over the worker-root allow.

Result: moon writes wt/_build + ~/.moon (allowed; ~/.moon sharing is a
documented residual — moon's own cache locking is trusted); `git status`/
`diff` work (private index; plus GIT_OPTIONAL_LOCKS=0 keeps status from
optional index refreshes); `git commit`/ref/config/worktree mutations fail
(shared object/ref/config writes denied); sibling and origin writes fail.
Worker mode force-sandboxes EVERY class including Trusted* (K3 mechanism,
now actually propagated end-to-end per PR0'), foreground AND background.

Static guard (better messages + non-macOS floor): admit a mutating git/moon
command only when EVERY candidate cwd/target interpretation (cd chains, -C,
scaffold destinations) is inside the worker root; unknown or mixed →
blocked with a worker-scope message. Extend denial_output subjects with the
worker paths so kernel denials self-explain. mbtx: worker rooting +
absolute-cwd outside worker root rejected at decode + worker profile for
its sandbox. Auto-check stays on; residual stated plainly: auto-check/moon
prebuild is repository build code running unsandboxed in the child engine,
same as the parent — we trust repo build rules and accept concurrent
external writers per worktree (their _build dirs are disjoint).

## WriteScope (PR1 — independently landable)

Shared checker used by edit/multi_edit/write/remove (worker builds all four
around one instance + one shared FileStateMap, mirroring build_tools):

- Config: canonical root + `allowed_paths` (repo-relative component-wise
  prefixes; reject absolute, `..`, empty, `.`, NUL, `.git`/`.worktrees`
  prefixes at decode).
- Check at use, immediately before each write (and before each rollback
  write): normalize the REQUESTED path; resolve the nearest existing
  ancestor via realpath; reject when the resolved target escapes the root;
  reject when the final component is an existing symlink whose target
  escapes the root; THEN check BOTH the normalized requested path and the
  resolved path against `allowed_paths` component-wise (`src` never
  authorizes `src2`; an in-root symlink into out-of-scope territory fails).
- TOCTOU window documented; macOS kernel layer backstops it.
- Tests per subal: component boundaries, `..`, absolute, final/ancestor
  symlinks, in-root-but-out-of-scope symlink, nonexistent descendants,
  revalidation on rollback paths, four tools one FileStateMap.

## Capture → validate → commit (controller)

On child exit (any terminal), registry state advances; then:

- Validation (untruncated, byte-preserving): `git status --porcelain=v1 -z
  --untracked-files=all` and `git diff --name-status -z <base_oid>` with
  SEPARATE parsers (status reverses rename order vs diff). Every changed/
  untracked path (both sides of renames, deletes) must pass component-wise
  `allowed_paths`; wt HEAD must still equal base_oid (profile makes child
  commits impossible; violation → non-mergeable, kept, listed).
- Valid + non-empty → controller commits: `git add -A` then REVALIDATE the
  staged diff (`diff --cached --name-status -z` vs base_oid — background
  stragglers race the first pass), then commit via the dedicated runner,
  then verify the commit's tree diff matches. Commit OID → registry.
- is_error: terminal != Captured, report status "failed", scope violation,
  or HEAD moved. "partial" → success-with-warning. Evidence display ≤4K
  (validation never truncates; display does): branch, commit OID, diffstat,
  child report, provision warnings, cleanup commands for kept trees.

Dedicated git runner (NOT baseline's run_capture): argv-vector spawn,
per-phase timeouts, merged stdout+stderr diagnostics, NUL-safe capture,
sanitized env (strip GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE,
GIT_OBJECT_DIRECTORY, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_*,
GIT_CEILING_DIRECTORIES), postcondition inspection on failure,
cancellation reconciliation.

## Integrate (controller; actions on the subtask tool)

`subtask{integrate: <name>}`:
1. Registry entry must be in `committed`; branch OID must equal the recorded
   commit; must descend from base_oid.
2. Origin gate: NO staged changes and NO unstaged tracked changes
   (`--no-optional-locks status --porcelain=v1 -z`); sole carve-out:
   gitlink (mode 160000) dirt, which cannot collide (submodule slices were
   rejected at provision) — documented. Untracked files allowed;
   `--no-overwrite-ignore` protects ignored ones.
3. Merge BY EXACT OID: `git -c core.hooksPath=/dev/null merge --no-ff
   --no-edit --no-gpg-sign --no-autostash --no-rerere-autoupdate
   --no-overwrite-ignore -m "subtask <name>: <summary line>" <commit-oid>`
   via the runner, mutex-held.
4. Clean → post-merge `moon check` summary → targeted `git worktree remove
   <wt>` + `git branch -d` (no blanket prune) → registry `integrated`.
5. Conflict → registry `conflicted` + result lists conflicted files; the
   model edits markers via file tools (origin workspace, parent tools),
   then `subtask{integrate_continue: <name>}`: controller verifies
   MERGE_HEAD equals the subtask commit OID, no unresolved entries remain
   (`ls-files -u`), staged paths ⊆ allowed_paths ∪ conflict set, then
   commits through the runner. `subtask{integrate_abort: <name>}`: verify
   MERGE_HEAD belongs to this subtask FIRST, then `merge --abort`,
   registry back to `committed` (worktree/branch kept).

## Unchanged from v2 (still in force)

Naming (tool `subtask`, kind `worker`, pkg `agent_worker`, branch
`openseek/<name>--<nonce>`); schema {name, task ≤4000, allowed_paths,
context? ≤2000} concurrent_safe; child toolset (read unrestricted, worker
shell, WriteScope file tools, mbtx, versioned submit_result; no
subrun tools); substantial worker system prompt (.mbt.md + dev_build; "do
not run git commit/worktree — the harness commits; permission errors on
those are expected"); report v1 {status, summary, verification}; child
session persistence; viz gate + tests; TUI unchanged; about-text fix;
budget (SubrunBudget shared backstop + 4-slot semaphore, 45 min, 300
steps since 2026-08-04); prompt guidance incl. warning-sweep recipe (partitions =
allowed_paths; integrate one at a time re-checking after each); dogfood
eval with negative controls (seeded out-of-scope worker must yield a
scope-violation error; final verdict from the checker).

## PR sequence (revised)

- PR0' scratch_dir launch-gap hotfix (now).
- PR1 WriteScope + file-tool wiring (independently landable).
- PR2 worker sandbox mode: profile builder + force-sandbox propagation +
  static guard + mbtx rooting + denial subjects. Test matrix per
  subal: linked-origin lifecycle, suffixed admin dirs, external
  siblings denied, moon check ok, status/diff ok under GIT_OPTIONAL_LOCKS=0,
  commit/ref/config/worktree mutations fail, common state unchanged
  (before/after snapshot), fg/bg/trusted/untrusted/mbtx paths,
  no-sandbox platform fallback, e2e lab regression (through
  execute_with_workspace, not agent_shell_launch).
- PR3 agent_worker child kind (prompt, capture, dispatch, lifecycle tests).
- PR4a subtask controller package: geometry/preconditions, registry +
  lifecycle, mutex, scope parsing/validation, commit/integrate state
  machine, git runner — tested against real git temp repos including
  linked-origin, sibling, rename/delete, conflict, abort, rollback cases.
- PR4b subtask tool: registration ×2, slots, evidence presentation, viz
  gate + tests.
- PR5 prompt guidance + regenerate.
- PR6 dogfood warning-sweep eval.

## Residuals (explicit)

Cooperative-model accepted: direct `openseek` spawn / nesting
(prompt-forbidden), inherited credentials, no shell merge trust, non-macOS
= static-guard+WriteScope only (never described as hard confinement),
auto-check/prebuild = trusted repo build code + concurrent per-worktree
writers, shared `~/.moon` (moon's own locking trusted), allow-default
outside the repo on macOS, process-local mutex (single-engine-per-repo
assumption; two engines on one repo race — registry writes are
atomic-rename so they fail loudly, not silently), worktree enumeration is
provision-time (later external siblings undented), TOCTOU between
WriteScope check and write (kernel backstop on macOS).

## Round-3 outcome (2026-07-31, subal-round3.log)

GO for PR1+PR2; PR #615 confirmed sound; NO-GO only for PR4a as specified.
PR4a spec amendments to apply when building it (authoritative detail in the
round-3 log):
- Provision is ONE mutex-held transaction: registry reconcile → overlap
  check → create `provisioning` reservation → info/exclude → worktree add;
  reservation visible before mutex release.
- Record `origin_head_before` at merge; continue/abort require: registry
  state `conflicted` for THIS attempt + HEAD == origin_head_before +
  MERGE_HEAD == recorded worker OID + branch OID unchanged.
- Registry states: provisioning, running, captured, committing, committed,
  integrating, conflicted, merged/cleanup_pending; terminals integrated,
  discarded, no_changes. A `discard` action releases reservations;
  integrate_abort returns to `committed` WITHOUT releasing.
- Cross-process: atomic rename ≠ CAS; either add a common-dir lock file or
  state "cross-process races may be silent".
- Capture: stop controller-owned bg jobs first; pin validated staged tree
  OID; verify commit parent == base_oid, commit tree == pinned OID, branch+
  worktree HEAD == commit, final status snapshot clean; reject NEW
  mode-160000 entries (embedded repos staged by add -A).
- Integration gate: reject every staged change; gitlink carve-out only for
  worktree-only dirt of an existing gitlink whose index entry == HEAD;
  always `--ignore-submodules=none`.
- Classify merge outcome by postconditions (MERGE_HEAD, unmerged entries,
  HEAD), not exit code; crash-after-clean-merge must be recoverable.
- Merge env: also `-c rerere.enabled=false`; repo/global merge drivers are
  an accepted-and-stated trusted-repo residual.
- `git worktree list --porcelain -z`; `rev-parse --path-format=absolute`.
- WriteScope (PR1): checks cover recursive parent creation and every
  restore/rollback write; resolved absolute paths convert back to
  root-relative components before matching; dangling final/ancestor
  symlinks fail closed.
- Profile guarantee wording: shared objects/refs/config + origin + siblings
  protected; worker-private HEAD/index mutation is detected at capture.

## Empirical addendum (2026-07-31, discovered during PR #615 cleanup)

`git worktree remove` FAILS for ANY worktree of this repo — even clean,
even with the submodule deinit'd — because desktop/lepus is a tracked
gitlink: git refuses "working trees containing submodules cannot be moved
or removed" (git 2.5x needs `remove -f -f`, which our trust classifier
rightly fail-closes on). Consequences: (1) the controller's cleanup must
use engine-side rm -rf + `git worktree prune` (or -f -f) — never rely on
plain `worktree remove`; (2) the shipped prompt `.worktrees/` recipe's
cleanup step cannot complete in this repo under shell policy (remove fails;
rm -rf of source trees is sandbox-denied) — needs a prompt/policy
follow-up, tracked separately from this plan.
