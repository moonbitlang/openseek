# De-slop delivery evaluation — 2026-09-12

This iteration follows the OpenSeek/core sweep and the missed explicit trim
arguments. It tests a small delivery batch rather than repeating the full
repository model scan. The previous inventory/semantic coverage figures remain
historical observations in [the cross-repository evaluation](de-slop-cross-repo.md).

## Changes driven by feedback

- Compare explicit defaults with the resolved declaration. Character-set
  equality ignores order: `"\r\n \t"` equals the current trim default
  `"\t\n\r "`. Non-default sets, custom receivers and documented protocol
  choices need separate evidence.
- Seed repeated nontrivial MoonBit function bodies, linking a matching sibling
  even across packages. These are lexical leads; similar spelling cannot prove
  compatible ownership, dispatch, mutation, cfg or panic behavior. Keep all
  hits in the inventory; prioritize implementation defaults/bodies over tests
  and comments. Short wrappers and test bodies are not duplicate-body seeds.
- Require evidence for KEEP/REJECT too: resolve constants at their declarations,
  inspect actual backend behavior and count allocations branch by branch.
- Add `--deliver` and a [calling-agent delivery recipe](de-slop-deliver.md): one
  coherent accepted batch, baseline tests, edits, required gates, actual diff
  review, scoped commit, PR publication and remote head/file/CI verification.
  There is no worker-controller dependency. The hosted script remains read-only;
  the calling agent owns mutation and publication.

## Deterministic regression tests

`just test-workflows` compiles the actual script and exercises **44 de-slop
modes** (33 focused, 11 whole-repository), alongside the existing workflow suites.
The fixture checks default and non-default trim leads; exact repeated bodies,
near matches and excluded test copies; complete/disjoint inventory; source/test
pairing; invalid reports; and successful, no-change and incomplete delivery.

A challenger fixture also changes an untracked source while returning a valid
complete report. `--deliver` rejects the handoff because the contents changed,
although Git status still marks the same file untracked. Whole-repository
fixtures include deleted tracked files and symlinks. Snapshot comparison covers
Git-visible configured source in the selected scope, not every dependency or
environment variable; it is a before/after check, not a filesystem lock.

## Real delivery attempt and corrections

The first real run used `deepseek-v4-flash`, a clean dedicated branch
`codex/drop-default-trim-arguments`, and OpenSeek base
`44f58fefa03a00ee3e8ee030a34c598ac4480b99`. The batch removes only the three
redundant trim arguments in desktop subrun, workflow-tail and session-record
readers. Existing non-default sets and owned results are preserved.

This was **not an autonomous end-to-end pass**:

1. The calling model edited before the discovery/challenge job completed. The
   original handoff prompt did not prevent that. The recipe now states an
   explicit phase barrier, and the script refuses delivery if scoped source
   differs from its pre-audit snapshot. The regression above validates the new
   guard; it was not present during the first real run.
2. The inner mbtx process policy refused `just` and `python3`. Individual MoonBit
   commands did not cover the whole required gate. The recipe now checks
   environment capabilities and hands a blocked step, branch and artifacts to
   the authorized outer host without changing or evading the inner policy.
3. The evaluation launcher injected `OPENSEEK_REFERENCES`, adding a line to two
   existing CLI environment snapshots. The failure output established the
   cause. The host runs the required gates in the normal test environment,
   without that launcher-only override; snapshots stay unchanged.

The first model was stopped after preserving its audit and validation output;
the outer host resumed the same three-file diff. Focused native tests passed
**29/29 before and after** the edit. The host also independently read the
installed core implementation: String trim delegates to StringView trim, whose
ASCII bit-set construction makes the argument order immaterial. A separate
bundled `review.mbtx` run checks the final diff against the recorded base.

Raw evaluation artifacts live under `.moonagent/de-slop-delivery/`: launcher
prompts/events, workflow job reports, the first-attempt script, isolated worktree
and negative-control fixture. They are ignored local artifacts, not a runtime
dependency or evidence that every future model run will follow the recipe.

## Independent controls and final validation

A separate real discovery/challenge run completed successfully on a tiny MoonBit
fixture. It ACCEPTed removing the explicit four-character default, and kept
both `trim(chars=" ")` and a custom receiver whose own default is `" "`.
It also kept required `.to_owned()` calls and rejected helper extraction for
these one-line expressions. The fixture's existing behavior test passed on
wasm, wasm-gc, JS and native before the edit; the accepted edit is checked with
the same test afterward, also passing on all four targets. This is one controlled observation, not a recall or
false-positive benchmark for arbitrary repositories.

The final review reported no blocker and one informational nit about a
hypothetical future change to core defaults. Independent triage found no
current difference or documented requirement to pin these defaults. The small
PR therefore retains the simplification without adding three redundant
call-site tests. The recipe now explicitly separates such hypothetical drift
from a demonstrated current contract violation.

Both the workflow-development checkout and the isolated cleanup passed
`moon info && moon fmt`, `just check`, `just test`, and `just build`. Public
interfaces are unchanged. The cleanup gate passed 3086 native tests, 3204 JS
tests, all 38 cram cases, and the CLI lifecycle/bundled-workflow integration
fixtures. The development checkout additionally passed the 44 de-slop fixture
modes. Passing host gates and a published PR establish this delivery; they do
not turn the first model attempt into an autonomous success.

## Published batch

[PR #1485](https://github.com/moonbitlang/openseek/pull/1485) publishes commit
`8ba268a8b796977d557f21b6f0a0a76b0cbb2071` against `main`: exactly three files,
three added lines and five removed lines. The PR was read back to verify its
head SHA, base, open/non-draft state and changed-file list against the tested
commit. At the initial verification, the seven build/test/E2E jobs were pending;
GitGuardian had passed. The PR was unmerged at that verification. A third-party review status
marked success while explicitly skipping review, so it is not review evidence.

## PR-only continuation

The next iteration makes the end-to-end calling task's final response only a
verified PR link. Test details and CI state belong in the PR body; discovery
and rejected candidates stay in local artifacts. There is no user handoff
between the audit, edit, validation, review and publication phases.

A first core attempt exposed a missing input: passing just a filename lost the
specific candidate supplied by the user, and the scouts explored unrelated
changes. That run was stopped and its own partial edit preserved then restored.
`--focus TEXT` now carries one hypothesis to both scouts, with explicit-path,
nonblank and length checks. All **48 de-slop fixture modes** pass, including
candidate forwarding to both phases and invalid focus arguments.

The tool vocabulary now admits `moon bundle` (required by core's contribution
guide) and the named `just check`, `test`, `build`, `editor-test`, and
`editor-test-browser` recipes. These execute the actual repository gates;
individual MoonBit commands are not substituted for integration steps. The
normal argument-prefix policy is retained. Tests cover the admitted vocabulary,
its rendered tool description, actual `moon bundle --help` execution and
continued refusal of unlisted command forms.

The fresh core run used `deepseek-v4-flash` and an isolated branch based on
`e6fdab5ba198349b80049cc0766ac863f25058c0`. With `--focus`, both scouts reviewed
only the `symmetric_difference` first-phase delegation to `difference`. The
calling agent observed successful audit completion before editing. Existing
hashset tests passed 77/77 on all four targets before and after, and in release
mode afterward. Full post-edit tests passed 7609 (wasm), 7636 (wasm-gc), 7569
(JS), and 7524 (native); all-target deny-warning checks and `moon bundle --all`
also passed. No tests or public interfaces changed.
