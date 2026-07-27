# SWE-AGI eval (native)

Vendored [SWE-AGI](https://swe-agi.com) task suites for running the OpenSeek
agent directly — no Docker, no bespoke harness. You point the agent at a task
directory, it implements the frozen API against the tests, and you grade with a
plain `moon test`.

## Benchmark runner

The checked-in runner drives `openseek serve` as a persistent JSONL process. It
sets a short durable goal with automatic continuation, waits for the engine to
confirm it, then sends the complete `TASK.md` as the first prompt. The process
stdin stays open until the goal is met, blocked, exhausts its continuation
budget, fails, or reaches the agent-work deadline. A `ConnectionClosed` turn
waits five seconds and resumes in the same serve session, up to ten times
within that unchanged deadline. Bounded process cleanup follows the work
deadline and is reported in the engine duration.

Run one CSV trial:

```bash
export DEEPSEEK=sk-...
moon run --target native eval/swe_agi/cmd/main -- \
  --task-dir eval/swe_agi/tasks/csv \
  --model deepseek-v4-pro \
  --max-steps 160 \
  --timeout-seconds 1800 \
  --grade-timeout-seconds 300 \
  --out .moonagent/eval_runs/swe_agi_csv
```

The runner currently requires a POSIX host with `rsync`, `find`, Python 3, and
process-group signals. It creates an isolated workspace under `--out` without
copying `*_priv_test.mbt` files or `*_priv_test/` fixture directories,
initializes that workspace as an independent Git repository, and commits the
public task as its initial state. It preserves the raw engine JSONL and stderr,
restores the shipped tests and fixtures after `openseek serve` exits, and
finally runs `moon test` against those restored test files explicitly.
Agent-authored test files and test blocks embedded in implementation files
therefore do not change the score. Source-tree build outputs and dependency
caches are excluded from both restoration and test selection, so their own
tests cannot enter the grade. A `setsid()` supervisor terminates ordinary
descendant commands left by the engine or grader before protected inputs are
restored. Grader output is drained through a 64 MiB-capped log instead of
accumulating in runner memory or limiting files created by the tests.
`--grade-timeout-seconds` independently bounds a hung restored-test run and
reports exit status 124.

Reports are written as Markdown, JSON, and HTML. The restored test result is the
benchmark verdict; the model's `goal(met)` claim is recorded only as diagnostic
state.

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

The serve benchmark runner holds out `*_priv_test.mbt` files and
`*_priv_test/` fixture directories from its trial workspace until
`openseek serve` has exited, then restores the pristine tests and fixtures for
grading. The trial's own Git repository also prevents Git commands in goal
review from walking into the surrounding OpenSeek repository and discovering
the vendored source task.

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
(`"native"`, `"js"`, etc.). Grading runs a bare `moon test`, which honors
`preferred_target`; without it `moon test` defaults to wasm-gc, and an agent that
pins `supported_targets = "+native"` in `moon.pkg` then produces "no test entry
found" — a bogus zero-test grade.

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
