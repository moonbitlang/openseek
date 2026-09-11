# Improvement Checklist

Observations collected while working on streaming, sessions, and documentation
(June 2026). Each item is small enough to land as its own PR; none blocks
current functionality. Check items off as they land, and add new ones at the
bottom of the matching section.

## TUI

The TUI now lives in its own repository,
[`moonbitlang/openseek_tui`](https://github.com/moonbitlang/openseek_tui); its
checklist moved with it.

## Engine / agent

Findings from a real 156-step session log (seek-toml, 2026-06-11: "Write a
toml parser in MoonBit with high quality tests" — succeeded, but the log
shows where steps and tokens went to waste):

- [x] **One watcher per directory, not per option set.** The `moon_check`
  registry keys watchers by the full option set, so toggling `deny_warn`
  stacked three concurrent watchers on one cwd. They competed for moon's
  build lock with each other and with the model's own `moon test` runs,
  produced stale results, and the model ended up running `pkill -9 -f
  "moon check"` mid-task to recover. Same cwd + new options should replace
  (stop) the old watcher. *(Done: the registry keys by cwd; a running
  watcher is reused when the incoming command matches and stopped+replaced
  (`watcher=replaced`) when the options changed, with the tool description
  telling the model so.)*
- [x] **Stop resending historical `reasoning_content`.** The request encoder
  sends stored reasoning back on every historical assistant message — 11%
  of a 141K-token final context was old reasoning the model never needs
  again (DeepSeek's own docs say not to pass it back). Drop it when
  projecting session history to API messages. *(Done: the wire encoder
  never emits `reasoning_content` — the right chokepoint, since the 11%
  accrued within a single 156-step turn via the agent's incremental
  pushes, not only across turns. Sessions still store reasoning for the
  TUI transcript and the visualizer.)*
- [x] **Remove stale watcher notices.** 61 moon_check runtime
  notices (11% of final context) were appended, mostly identical
  re-reports from the duplicate watchers. The first mitigation coalesced
  notices per watcher; the follow-up removed the unused runtime-notice
  producer/API entirely. `moon_check` now returns watcher snapshots only from
  direct tool calls.)*
- [ ] **First-class API-lookup tool (or document the probe recipe).**
  *A/B result (2026-06-12, 5 flash trials per arm): a prompt addendum
  teaching query forms, the no-results fallback ladder, multi-query
  batching, and the probe recipe did NOT help — pass rate 3/5 → 2/5,
  failed doc queries 11 → 18, zero multi-query adoption. Prompt-tail
  instruction alone is insufficient for flash; next candidates are a
  dedicated lookup tool with query rewriting, or folding examples into
  the base prompt's tool docs rather than an addendum.* The
  model spent ~25 steps probing stdlib APIs: repeated `moon ide doc`
  queries that returned "No results found" (7KB of failed lookups in one
  result), 8 consecutive failed one-liner compile experiments against
  `@strconv`, and one `moon ide` OCaml assertion crash. Better query
  ergonomics (or a documented snippet-eval recipe) converts that tail of
  failures into one or two steps.
  *Second A/B (2026-06-12, 5 pro trials per arm, TOML task): verified
  glob/multi-query/miss-recovery guidance folded into the prompts' tool
  docs (the placement the first result pointed at) — successes 1/5 →
  5/5, no 160-step cap overruns (was 2), doc calls 25 → 37 while misses
  fell 23 → 17 (miss rate 0.92 → 0.46), package-listing exploration up
  17 → 25. Promoted: every statement is CLI-verified and the trace
  improved across the board. Attribution caveats recorded: n=5; the
  taught glob (1 use) and multi-query (0 uses) forms themselves were
  barely adopted — the absorbed lesson looks like "trust doc lookups,
  recover by listing the package"; baseline's failures were step-cap
  finish discipline and project misplacement, not lookup tails. A
  dedicated lookup tool with query rewriting stays open as the
  zero-adoption-risk endgame; schema-level cues beat prose (see the
  multi-path read tool).*
- [x] **Ground the model in its environment.** The system prompt never
  states the working directory, so models guess on step 1: in a 5-run
  batch, one agent passed `cwd="/workspace"` (rejected: does not exist),
  then explored the *parent* directory, found a concurrent sibling run's
  files, and adopted that workspace wholesale — two agents silently
  co-editing one project. Another opened with `read /home/user`. Inject
  the engine's cwd (and a "stay inside the workspace; siblings/parents
  are other projects" line) into the prompt at run start. *(Done: an
  `## Environment` section names the realpath cwd on every prompt source;
  judged by a concurrency-5 experiment — hallucinated step-1 paths 2/5 →
  0/5, sibling-workspace hijack eliminated, 5/5 artifacts in their own
  directories. Eval harnesses now run trial engines inside their staged
  workspaces so grounding and isolation agree.)*
- [x] **Remove watcher notice payload path.** The trimming idea is obsolete:
  `moon_check` no longer emits runtime notices, and diagnostics are returned
  from direct tool calls instead.
- [ ] **Encourage batching independent tool calls.** 154 of 156 steps made
  exactly one tool call; the model proved it can batch (it opened with two
  parallel reads). A system-prompt nudge for batching independent
  reads/checks would cut round trips — at ~7s a step, real minutes.
- [x] **Timestamps on session events.** `events.jsonl` lines carry no
  timestamps, so per-step latency and where wall-clock went cannot be
  reconstructed from the log (this analysis had to infer duration from
  file mtimes). One `ts` field per event line fixes it and feeds the viz.
  *(Done: the store stamps every appended event with `ts` (unix ms,
  required field — no external users, so old logs are simply re-created;
  in-memory appends without a clock carry the 0 sentinel).)*

- [x] **Expose thinking controls.** `run_with_runtime` hardcoded max-effort
  thinking; make it an engine flag (`--thinking no|high|max`) and a TUI
  pass-through. *(Done: `OPENSEEK_THINKING` is env-backed on both binaries and
  threaded through `@agent.run*` as an optional param with max as the default.)*
- [x] **Auto-compaction — deferred, reframed as a context-ceiling guard.**
  Compaction exists only as the manual `--session-compact-*` flow.
  Deliberately deferred (owner decision, 2026-06-12): compaction rewrites
  the model-facing history prefix, so every request after it is a DeepSeek
  prefix-cache miss until the new prefix re-warms — at cache-hit pricing a
  long append-only history is cheaper than periodically re-paying full
  price for a rewritten one, plus summary-generation cost and
  information-loss risk. When implemented, trigger only as the projected
  prompt approaches the model's context window (where the alternative is
  failure), not as a cost optimization. *(Done as exactly that guard: after
  every response the loop compares reported total_tokens against 80% of
  `Model::context_window`; over it, a checkpoint summary (thinking=No, the
  manual flow's prompt) is appended through the turn's append seam — prior
  turns first so the active task stays verbatim, then at most one
  full-range checkpoint per turn, disarming on failure (fail-open) — and
  the request buffer re-seeds from the compacted projection. Events
  `auto_compaction_started/finished/failed` are distinct from the manual
  `compaction_*` names, which the TUI treats as run-terminal; surfacing
  auto-compaction in the TUI status line is a possible follow-up.)*
- [x] **Richer `--session-list`.** Bare ids are hard to recognize; include
  last-activity time and the first user prompt as a label. *(Done:
  `SessionStore::listings` returns id + last-activity + first prompt, newest
  first with unreadable sessions kept visible for cleanup; the CLI prints
  tab-separated rows, so `| cut -f1` recovers the old bare-id output.)*
- [ ] **Stale `session.lock` recovery.** Verify what happens when an engine
  crashes while holding the lock, and document (or implement) the recovery
  path.
- [ ] **Flush the JSONL queue on hard crash.** The stdout drain trades
  crash-tail durability for purity (no C stub): lines queued but unwritten
  when the process aborts are lost. A panic hook that drains synchronously
  would close the gap.
- [ ] **Cheapen the engine probe.** `engine_launchable` spawns
  `<engine> --help` on every TUI launch; cache the result per engine path
  (mtime-keyed) or accept the first spawn failing fast instead.
- [x] **Skills: advertise markdown playbooks, load on demand.** *(Done:
  workspace `.openseek/skills` plus a user-level library — default
  `$HOME/.openseek/skills`, override `--global-skills-dir` /
  `OPENSEEK_GLOBAL_SKILLS_DIR`, workspace shadows global by name — are
  listed name/description/path in a `## Skills` prompt section; bodies load
  through the `@builtin/read.mbtx` workflow. Effectiveness A/B (2026-06-11, 5 flash
  trials per arm, marketplace `anthropics/skills` brand-guidelines skill,
  "branded landing page" task): skill arm read the skill unprompted 5/5 and
  shipped the exact brand palette 5/5 (7–36 hex occurrences); no-skill
  control hit the palette 0/5; negative control — skill advertised, haiku
  task — read it 0/5, so the listing does not pollute unrelated tasks.
  Listing cost ~1 line/skill; the matched read added one step. Eval
  harnesses pin `OPENSEEK_GLOBAL_SKILLS_DIR` into the trial workspace so a
  developer's personal library never leaks into trials.)* Follow-ups: TUI
  surfacing of available skills, multi-skill libraries under noisier tasks.

## DeepSeek client

- [ ] **Unify `chat` and `chat_stream`.** They share request encoding but
  duplicate response and error handling. Implementing `chat` as
  streaming-with-no-callbacks leaves one wire path to maintain.
- [ ] **Retry transient HTTP failures.** Both entry points are single-shot;
  a bounded retry with backoff on connect/5xx errors would remove the most
  common spurious turn failures.

## Testing / CI

- [ ] **More CI platforms.** CI is a single `check (nightly)` job; the TUI's
  pty handling and the engine's stdio behavior are platform-sensitive
  (macOS pty quirks surfaced during verification). Add macOS, then Windows.
- [x] **Make the live cram lifecycle test extension-proof.** It asserts an
  exact event-name set and broke when `*_delta` events were added (now
  filtered). Assert the stable lifecycle subset is *present* instead of
  asserting the full set. *(Done: the example whitelists the lifecycle
  events, so new payload event kinds cannot break it.)*
- [ ] **Checked-in TUI integration harness.** The pty driver used to verify
  streaming and session memory lives outside the repo. Pair a small pty
  driver with a recorded-stream replay engine (the TUI already accepts
  `--engine <replayer>`) for deterministic offline TUI tests.
- [ ] **Run `moon fmt --check` before push.** Two consecutive PRs hit
  CI-only formatting failures; a pre-push hook or documented `moon` alias
  would catch them locally.
- [ ] **CI does not exercise the JS packages.** `ci.yml` runs `moon check` /
  `moon test` on the default (native) target only, so the visualizer's
  js-only packages (`viz`, `cmd/viz_app`) are silently skipped — they
  compile and pass locally but a regression there would not fail CI today.
  Add a `--target js` check/test step (or a target matrix). Their logic is
  currently covered only by local unit tests + a headless-browser run.

## Docs / prompts

- [ ] **Doc-exemplary prompt examples.** `prompt/moon.pkg` opts the system
  prompt out of `missing_doc` because its example code blocks are
  model-facing text. Consider documenting those examples *as a prompt
  change* (with an eval run) so the model also learns the doc convention.
- [x] **Document the TUI session default.** The root README does not yet
  mention that every TUI launch converses in a durable session and how to
  resume one (`--session <id>` from the startup banner). *(Done: the README
  gains a Terminal UI section covering default sessions, `--continue`,
  `--session`, and the enriched `--session-list`, plus a `cmd/tui` row in
  the packages table.)*

## Visualizer (viz)

Follow-ups for the `events.jsonl` web viewer (`viz`, `inspect`,
`cmd/viz_app`, `web/`).

- [ ] **Smarter `--session-root` default discovery.** The default is the
  relative `.openseek`, resolved against the server's cwd; `moon run
  inspect` uses the module root as cwd (no `.openseek` there), so the
  no-arg case shows nothing. Walk up from cwd to the nearest `.openseek`
  (like git finds `.git`) so the default "just works" from a subdirectory.
- [ ] **Optional self-contained binary for distribution.** Today the server
  serves `web/index.html` from disk and auto-locates the built `viz_app.js`
  from `_build/`. If we ever want to *ship* the viewer as one binary, embed
  both via the `md_to_mbt_string`-style `rule` and accept the js→embed→native
  build order. Not worth it for a local dev tool; embedding only the HTML is
  a half-measure (the binary still needs the JS), so it is all-or-nothing.
- [ ] **UI polish.** Sidebar: show the last-active timestamp (the server
  already returns it; the frontend ignores it). Turn headers: show a per-turn
  summary (tool count, terminal status) on the collapsed `<details>` line.
  Tool cards: collapse long output by default with an expand toggle.
  Navigation: jump-to-errors, text search/filter, expand/collapse all.
- [ ] **Persist the theme choice.** The Light/Dark/System toggle resets to
  Light on reload; persist it (localStorage) so the choice sticks.

## MoonBit toolchain & DX

Observations from building the visualizer (native server + JS frontend in
one module). These are toolchain/language ergonomics — several are likely
upstream `moon`/MoonBit items rather than openseek changes — but they cost
real time and are worth tracking.

- [ ] **`moon info` does not generate `.mbti` for js-only packages.** In a
  module whose canonical backend is native, `moon info` writes no
  `pkg.generated.mbti` for `supported_targets = "js"` packages — it only
  prints a perpetual "requested interfaces different from canonical backend
  Native" diff. I had to hand-copy the generated interface out of `_build/`.
  A per-package canonical backend (or `moon info --target js` writing the
  files) would fix it.
- [ ] **No cross-target build dependency.** `moon build` is per-target, so
  there is no way to express "build the JS bundle, then embed it into the
  native binary" in one invocation — it forces a manual two-step. This is
  the root reason the viz bundle is served from disk rather than embedded.
- [ ] **Library aborts are invisible and uncontainable.** A second
  `send_response` on a connection hit a `guard … else`-less panic (abort) in
  `@async/http` that tore down `run_forever`; neither `catch` (handles
  `Error`, not panics) nor `allow_failure` contained it. Checked errors are
  tracked in signatures, but panics/aborts are not — so you cannot tell which
  library calls can kill the process. Surfacing "can abort", or a task
  boundary that contains aborts, would make robust server code tractable.
  *(Worked around in viz by computing each reply before a single send.)*
- [ ] **Default trait methods are not callable through a trait object.**
  `@fs.read_file` returns `&@io.Data`; the *required* `binary()`/`text()`
  dispatch fine, but the *default* `to_bytes()`/`to_bytesview()` fail with
  `[4039] Cannot use method … of abstract trait`. The required-vs-default
  rule through `&Trait` is non-obvious and cost compile cycles.
- [ ] **A `moon fix` autofixer for deprecations.** A lot of small edit cycles
  came from deprecation warnings with mechanical rewrites: `not(x)`→`!x`,
  `StringView::to_string`→`to_owned`, `String::substring`→view slicing,
  `@strconv.parse_int`→`@string.parse_int`, `derive(Show)`→`derive(Debug)`,
  plus `+unnecessary_annotation` cascading. An autofix (à la `moon fmt`)
  would erase most of these.
- [ ] **Lint a `..` cascade that discards a non-unit return.** `session..append(x)`
  on an immutable builder (where `append` returns a *new* `Session`) compiles
  and silently no-ops — it caused a real test bug. Warn when `..` drops a
  non-`Unit` result.
- [ ] **Surface dependency examples/APIs in `moon ide doc`.** Learning
  third-party APIs (rabbita's callable `Emit`, `@async/http.Server::Server`,
  `@utf8.decode_lossy`, `&Data::binary`) meant grepping `.mooncakes`/`.repos`.
  Examples like `http_file_server` were invaluable once found; surfacing dep
  docs/examples through `moon ide doc` would shortcut discovery.
