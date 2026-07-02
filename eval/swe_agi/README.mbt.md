# SWE-AGI eval (native)

Vendored [SWE-AGI](https://swe-agi.com) task suites for running the OpenSeek
agent directly — no Docker, no bespoke harness. You point the agent at a task
directory, it implements the frozen API against the tests, and you grade with a
plain `moon test`.

## Running

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

- **`--concurrency 1` writes in place.** A single run mutates `--dir` directly
  (the agent writes its implementation there), dirtying the vendored task. For a
  one-off, copy the task first (`cp -r eval/swe_agi/tasks/csv /tmp/csv && …
  --dir /tmp/csv`). `--concurrency ≥ 2` needs no copy.
- **For a strict grade**, restore the shipped tests before `moon test` — the
  agent works in a copy where the tests are writable and may add or edit
  `*_test.mbt`. Drop the run's `*_test.mbt` and copy the task's originals back.

## The private tests are visible in this workflow

There is no held-out split here. `*_priv_test.mbt` are ordinary files in the
task directory, so `--concurrency` copies them into every run and the agent
**can read them** — scores measure "can implement with the tests in view," not
generalization to hidden tests. OpenSeek has no read sandbox, so the only way to
hold them out is to physically `rm` the `*_priv_test.mbt` before the run and copy
them back to grade.

## Layout

- `tasks/csv/` — first vendored task (RFC 4180 CSV; 10 public / 88 private tests).

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
