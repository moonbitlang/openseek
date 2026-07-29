# SWE-AGI eval (native)

Vendored [SWE-AGI](https://swe-agi.com) task suites for running the OpenSeek
agent directly — no Docker, no bespoke harness. You point the agent at a task
directory, it implements the frozen API, and the runner grades it with the
task's pristine SWE-AGI evaluator.

## Benchmark runner

The checked-in runner drives `openseek serve` as a persistent JSONL process. It
sets a short durable goal with automatic continuation, waits for the engine to
confirm it, then sends the complete `TASK.md` as the first prompt. The process
stdin stays open until the goal is met, blocked, fails, or reaches the
agent-work deadline. Benchmark runs set the goal continuation count to
unlimited; the wall deadline remains the final bound. A `ConnectionClosed`
turn resumes in the same serve session with 5, 10, 20, 40, then 60 second
backoff, up to ten consecutive failures. A completed provider response resets
that consecutive-failure count. If the serve process itself exits
unexpectedly, the runner reconnects the same durable session up to three
consecutive times.
Retries, restarts, and their waits all consume the same wall deadline. Bounded
process cleanup follows and is reported in the engine duration.

Run one formal CSV trial. The defaults shown here are 48 hours of agent work, a
three-hour suite deadline, no fixed per-turn step count, and an unlimited goal
continuation count:

```bash
export DEEPSEEK=sk-...
moon run --target native eval/swe_agi/cmd/main -- \
  --task-dir eval/swe_agi/tasks/csv \
  --model deepseek-v4-pro \
  --timeout-seconds 172800 \
  --grade-timeout-seconds 10800 \
  --out .moonagent/eval_runs/swe_agi_csv
```

For a short harness smoke test, explicitly pass a smaller deadline and, if
desired, `--max-steps 160`. Such a constrained run is not a formal performance
result.

The runner currently requires a POSIX host with `rsync`, `find`, Python 3, and
process-group signals. It creates an isolated trial workspace under `--out`
without copying `*_priv_test.mbt` files or `*_priv_test/` fixture directories,
initializes that trial as an independent Git repository, and commits the public
task as its initial state. It preserves the raw engine JSONL and stderr. Only
after `openseek serve` exits, it creates an inspectable sibling `<trial>.grade`
workspace: the agent implementation is copied without tests, specs, evaluators,
Git data, or caches, then pristine protected inputs are overlaid from the
vendored source. The agent's trial remains private-test-free.

Agent-authored test files and test blocks embedded in implementation files
therefore do not change the score. Source-tree build outputs and dependency
caches are excluded from both the grading workspace and test selection, so
their own tests cannot enter the grade. The runner pins the complete vendored
task digest before materializing the trial and rejects source drift throughout
preparation and grading. Changed or new agent manifests may add imports,
dependencies, and subpackages, but executable build hooks are rejected; the
root task target remains the pristine value (`js` for Pug and `native` for the
other current tasks).

Before building, the runner compares the exact `moon test --outline` identities
from the pristine source and grading workspace under that fixed target. Both
build and suite commands receive only the pristine test-file paths. Tasks that
ship `try.py` run the pristine evaluator copied into the grading workspace
under Python isolated mode, with a ten-second deadline for each case, and every
JSONL result identity must match the verified outline. Other tasks require the
final Moon summary total to equal the same outline count. Compilation has its
own 120-second deadline, matching the upstream evaluator.

A `setsid()` supervisor terminates ordinary descendant commands left by the
engine or grader. The trusted evaluator wrapper also tracks child process groups
created with Python's `start_new_session` and kills them when the suite deadline
expires. Grader output is drained through bounded logs instead of accumulating
in runner memory or limiting files created by the tests. `try.py` stdout and
stderr are kept separately and each stream is capped at 64 MiB; only stdout is
parsed as evaluator JSONL. `--grade-timeout-seconds` independently bounds the
suite phase and reports exit status 124.

Reports are written as Markdown, JSON, and HTML. The pristine evaluator result
is the benchmark verdict; the model's `goal(met)` claim is recorded only as
diagnostic state.

`--out` must not already exist. Pass `--engine /path/to/openseek` to skip the
nested `moon run` launcher and benchmark a prebuilt binary.

## One-shot best-of-N

Use the agent's own fleet mode — `openseek run --dir <task> --concurrency N`:

```bash
export DEEPSEEK=sk-...
moon run --target native cmd/openseek -- run \
  --dir eval/swe_agi/tasks/csv --concurrency 5 \
  --model deepseek-v4-pro --max-steps 160 \
  "$(cat eval/swe_agi/tasks/csv/TASK.md)"
```

`--concurrency N` copies `--dir` into `N` sibling run directories
(`csv_run_1 … csv_run_N`, next to the task), runs them concurrently, and
**never writes to `--dir` itself** — so the vendored task stays pristine and one
crashed attempt never aborts the others. `TASK.md` is the prompt, fed verbatim.

Grade each run, then clean up the run directories:

```bash
for d in eval/swe_agi/tasks/csv_run_*; do
  echo "== $d =="; (cd "$d" && moon test 2>&1 | grep -E 'Total tests')
done
rm -rf eval/swe_agi/tasks/csv_run_*
```

A run is a pass only when all tests pass (`failed: 0`, `total > 0`) — SWE-AGI's
binary gate. The `passed/total` count is a useful partial-credit signal. A bare
`moon test` honors the task's `preferred_target` (see Vendoring).

Notes:

- **`--concurrency 1` also copies.** Any explicit `--concurrency` — including
  1 — runs in `<task>_run_<i>` copies and never writes to `--dir` itself. Only
  a flagless `openseek run --dir <task>` mutates the task directory in place.
- **For a strict grade**, restore the shipped tests before `moon test` — the
  agent works in a copy where the tests are writable and may add or edit
  `*_test.mbt`. Drop the run's `*_test.mbt` and copy the task's originals back.

## Private-test visibility

The serve benchmark runner never copies `*_priv_test.mbt` files or
`*_priv_test/` fixture directories into its trial workspace. After
`openseek serve` has exited, it creates a separate sibling grading workspace
containing the agent implementation and pristine tests. The trial's own Git
repository also prevents Git commands in goal review from walking into the
surrounding OpenSeek repository and discovering the vendored source task.

The one-shot `openseek run --concurrency N` workflow above still copies private
tests into every run, so those scores measure "can implement with the tests in
view," not generalization to hidden tests.

This is not a filesystem read boundary or hostile-process sandbox. An agent
that already knows or guesses an absolute source path can still read outside
the trial workspace, and a deliberately detached process can escape a POSIX
process group. Use a container or a process-level read sandbox when that
stronger isolation is required.

## Layout

| Task | Scope | Public tests | Private tests |
| --- | --- | ---: | ---: |
| `c99` | C99 subset parser and AST encoder | 12 | 99 |
| `capnp` | Cap'n Proto wire codec | 11 | 100 |
| `cdcl` | DIMACS parser and SAT solver | 430 | 3882 |
| `csv` | RFC 4180 CSV parser | 10 | 88 |
| `ecma262` | ECMAScript expression evaluator | 62 | 556 |
| `git_object` | Git loose-object parser | 105 | 895 |
| `hpack` | RFC 7541 HPACK codec | 13 | 116 |
| `html5` | HTML5 parser | 822 | 7390 |
| `ini` | INI parser | 10 | 88 |
| `jq` | jq query interpreter | 22 | 196 |
| `lua` | Lua 5.4 interpreter | 8 | 75 |
| `protobuf` | Streaming Protocol Buffers codec | 14 | 127 |
| `pug` | Pug template engine | 33 | 218 |
| `python` | Python interpreter | 66 | 587 |
| `r6rs` | R6RS Scheme interpreter | 152 | 1305 |
| `toml` | TOML parser | 73 | 660 |
| `uri` | RFC 3986 URI parser and resolver | 14 | 124 |
| `url` | WHATWG URL parser | 127 | 1093 |
| `wasm` | WebAssembly decoder and validator | 81 | 721 |
| `xml` | Streaming XML parser and writer | 73 | 662 |
| `yaml` | YAML 1.2.2 parser | 39 | 306 |
| `zip` | ZIP archive parser | 109 | 980 |

## Vendoring a task

SWE-AGI tasks ship legacy `moon.mod.json` / `moon.pkg.json` manifests, but the
OpenSeek agent prompt expects the current `moon.mod` / `moon.pkg` format — left
as-is, the agent burns steps migrating the manifest, which is toolchain
housekeeping, not the benchmark. So normalize each vendored task once with the
toolchain's own migration:

```bash
rsync -a --exclude target --exclude _build --exclude .mooncakes \
  ~/Workspace/moonbit/SWE-AGI/tasks/<name>/ eval/swe_agi/tasks/<name>/
cd eval/swe_agi/tasks/<name> && moon fmt   # migrates *.json manifests -> moon.mod/moon.pkg
```

`moon fmt` faithfully preserves every field (`deps`, `source`, `preferred-target`,
package `import`/`targets`) — do not hand-convert. Tasks with `deps` may need
`moon install` before `moon fmt` can resolve them.

Ensure the task's `moon.mod` declares its target with `preferred_target`
(`"native"`, `"js"`, etc.). The runner treats that value as the trusted target
and passes an explicit `--target` to outline, build, and suite commands. This
avoids grading the wrong backend or accepting a bogus zero-test result after an
agent retargets package manifests.

Then normalize `TASK.md` — it is fed to the agent **verbatim**, so it must be
self-consistent with running in place. Remove anything that assumes otherwise:

- the SWE-AGI submission flow (`swe-agi-submit` / "evaluation server" section) —
  there is none here; replace it with "make the tests pass, then finish"
- `cd <name>` and any "create a MoonBit project" phrasing — the agent already
  sits in the task directory; it must work in place
- stale `moon.mod.json` / `moon.pkg.json` mentions (e.g. example dir trees)

Finally, audit the private tests for oracles that contradict the task's spec —
the grade is only as good as the tests it runs. Vendored suites occasionally ship
a test whose expected value doesn't match the spec (often a string-escaping or
encoding slip in how the input or expectation was written), which rewards a wrong
implementation and fails a correct one. Skim for these before trusting a score,
and fix the test rather than let it distort the benchmark.
