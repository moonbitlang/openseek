# De-slop at repository scale — 2026-09-12

This is a new two-round evaluation on OpenSeek and core, not a reinterpretation
of the earlier runs. It combines four whole-repository audits, three focused
negative/no-change controls, two control rechecks, two actual PR deliveries,
and targeted recovery/review follow-ups. All model runs use
`deepseek-v4-flash`; offline fixture results are counted separately.

OpenSeek was rebased onto `origin/main` (`af0ddd7fc`; already current); its audit
baseline was workflow branch `2d53f5450`. Core was freshly fetched and separate
clean worktrees started at `a0f0fb87c`. The user's existing core branch was not
rewritten. The second OpenSeek round uses a clean worktree at the same baseline;
core's audit worktree stays unchanged while deliveries use separate worktrees.

## Breadth and actual reading

| Repository | Source files | Scanned lines | Retained leads | Round 1 reviews | Round 2 reviews, before recovery |
| --- | ---: | ---: | ---: | --- | --- |
| OpenSeek | 1,582 | 463,397 | 1,040 | 8/8 | 7/8 |
| core | 950 | 233,144 | 877 | 7/8 | 8/8 |

All four inventories enumerate every configured source exactly once. Source
counts, lead contents and shard file assignments match across rounds. This is
**2,532 distinct files**, not 5,064 different files because they were scanned
twice. The four sweeps started 63 scouts: one failed discovery prevented its
challenger from starting.

Numbered source-read output from scout transcripts spans 191 OpenSeek files
(15,247 distinct lines) and 161 core files (17,904 lines) across the two rounds,
excluding recovery and focused runs. Round two adds 53 and 71 previously unread
source files respectively, and introduces 259 and 76 previously unsuggested
lead locations. These are observed read-window counts, not a claim of complete
semantic review of those files; searches and IDE output are not included. The
models and prompts also vary between rounds, so this is not an isolated causal
benchmark of the sampler, or a measured recall/precision score.

## Corrections driven by observed failures

- **Repeated sampling:** the old sampler always chose the same first four
  distinct files and never suggested later hits in a file. `--round N` now
  rotates four-hit windows through file-interleaved leads. Version-4 inventories
  persist the round and exact suggestions without changing shard membership.
  All hits remain available; suggestions eventually wrap. The offline fixture
  requires three rounds to reach every hit, including later same-file lines,
  and checks `--round` with `--shard` and invalid arguments.
- **Misclassified API work:** first-round OpenSeek accepted exposing private
  markdown geometry helpers as an “interface movement.” Such sketches now
  explicitly require DEFER, not ACCEPT-with-a-caveat. Round two correctly
  deferred that sharing and cross-package modifier helpers. An out-of-shard
  repeated-body peer remains allowed as verification context; its location does
  not by itself imply a new dependency or permission to expand the edit scope.
- **Right rejection, wrong explanation:** the ArrayView shrinker deletion was
  rejected, but the scout claimed it would not compile. On current core, the
  exact deletion passes `moon check --target js --deny-warn`; the existing
  `shrink array view` test then exceeds a 30-second bound. Emitted JS contains
  an unconditional loop that repeatedly copies and re-wraps the view. Baseline
  and restored source both pass the same test (1/1). The recheck now identifies
  expected-result inference and possible self-dispatch, and does not claim a
  compiler result it never ran. The preserved map performs a real conversion.
- **Ambiguous outcomes and invented allocation counts:** the no-change trim
  fixture emitted `ACCEPT (keep)`; the recheck uses REJECT for the proposed
  deletions and keeps both non-default and custom-receiver sets. ACCEPT is now
  reserved for an edit. The criteria also reject unsupported claims that an
  empty-string literal allocates or a record necessarily lives on the stack.
- **Citation failure:** core round 1 shard 3 supplied `builtin/moon.pkg` without
  a line. The strict validator rejected the entire shard and preserved its raw
  report; it was not counted as completed just because the CLI exited zero.
  Prompts now explicitly include manifests/instructions in the line requirement.
  Core round 2 completed all eight reports. The ASCII candidate went through a
  fresh focused audit before editing, rather than using the invalid report as
  an implementation handoff.
- **Repeated review gates:** the ASCII reviewer reran tests in scratch despite
  the caller's inspection-only instruction. Its system prompt explicitly told
  it to rerun gates, and its task unconditionally encouraged a scratch project.
  Both now honor inspection-only requests with supplied validation: inspect
  evidence and return a concrete missing check to the caller. This is aligned
  model guidance, not a new executable sandbox restriction.

The receiver-type control also rejected replacing `UInt16` string indexing with
`Char::is_ascii_alphabetic`. It correctly distinguished that method mismatch
from a colon literal that can typecheck in a UInt16 context. Whole-sweep
challenge rejected deleting result tests whose error-path assertion was absent
from the superficially matching doc example. These controls are selected known
risks, not a representative random sample of the repositories.

## Real PR delivery

| Batch | Verified published head | Diff | Natural completion |
| --- | --- | --- | --- |
| [core #4234](https://github.com/moonbitlang/core/pull/4234), Deque separator view | `8a8e6367ba842875f9728dd3f4789cb2d89a1e8e` | `deque/deque.mbt`, +1/−2 | 359.7 s |
| [core #4235](https://github.com/moonbitlang/core/pull/4235), shared ASCII scalar decoder | `cb404dfd5a38348897a549e40463a6b21d1b4076` | `encoding/ascii/decode.mbt`, +1/−13 | 486.4 s |

Both callers waited for a successful discovery/challenge handoff before editing,
ran baseline and post-edit package tests on all four targets, full `moon test`
(7,609 pass), all-target deny-warning checks, `moon bundle --all`, and
`moon info`/`moon fmt` with unchanged interfaces/snapshots. Deque passed
258/258 on wasm, wasm-gc and JS, and 248/248 native. ASCII passed 15/15 on wasm,
wasm-gc and native, and 12/12 JS. Each final review reported no blocker.

The agents performed edits, gates, review, commit, push, creation, head/file/base
readback and one CI snapshot themselves, then naturally returned **only a PR
link**. Neither was interrupted or finished by the outer host. The host prepared
worktrees and independently verified receipts afterward. Pending CI was recorded
as pending; no CI loop or merge occurred. Deque used a previously known candidate;
ASCII came from this new full-repository run. The ASCII review's redundant
experiments remain a failure of validation scope despite successful publication.
PR bodies also remain longer than the recipe's one/two-paragraph guidance; these
samples establish delivery and termination, not universal prompt compliance.

## Recovery, review recheck and regression gates

The failed OpenSeek round-2 discovery was rerun with
`--round 2 --shard 4`, the preserved workflow source and unchanged source tree.
Only that discovery/challenge pair ran; both submitted valid reports, completing
round 2's outstanding shard. Successful shards were not rerun. This recovery
remains separate from the original 7/8 result.

The same published ASCII diff was reviewed again after rebuilding with the
aligned system/task prompts. The child submitted a valid report, no blocker,
and one optional wording nit about limiting a single-owner claim to the raising
decoder. Its trace contains source/diff reads and comparison scripts, **no**
moon gate execution and **no** scratch project. It explicitly kept the caller's
validation as supplied evidence. It still spent time reconciling test counts;
this sample proves scope compliance, not a general latency improvement.

The trim recheck first returned nine citations, exceeding the eight-citation
cap. Its caller autonomously reran the pair once; the second attempt passed.
That extra pair is counted, not hidden as a single successful invocation. The
calling recipe now bounds recoverable format/submission retries to one targeted
attempt and requires preserving its failed predecessor. This is caller guidance;
the workflow script itself still performs no automatic retry.

Together these are **84 real child runs** (63 full-sweep scouts, twelve focused
control scouts, six delivery audit/review children, two recovery scouts, and
one review recheck). Three failed original reports remain visible in that
count. They are not retrospectively converted into successful first attempts.

`just check`, `just test` (3,087 native and 3,204 JS tests, all 38 cram cases and
CLI/workflow integration suites), and `just build` passed. After aligning the
review prompts, checks/build passed again and `agent_review` passed 12/12 native
tests. The final offline workflow suite passes **55 de-slop modes** (38 focused,
17 whole-repository), including combined round/shard recovery. `moon info` and
`moon fmt` leave public interfaces unchanged. Generated review prompt source is
updated from its Markdown owner.

## Reproduction and remaining limits

Ignored artifacts under `.moonagent/de-slop-scale/` retain exact prompts,
transcripts, job states, journals, full reports, inventories, numbered read
windows, metrics and remote PR receipts. `workflow-round2.mbtx` preserves the
exact workflow used for the round-2 retry. The dispatch counterexample retains
before/check/timeout/restored command results and emitted JS. Generated token
counts in journals include repeated context; they are not unique-source counts
or a billing estimate.

A bounded scout can still omit its submission, and a complete heading cannot
prove its semantic claims. There is no automatic retry that silently multiplies
spend, no PR quota, and no claim that two rounds exhausted these repositories.
Independent caller verification and existing behavior tests remain required.
