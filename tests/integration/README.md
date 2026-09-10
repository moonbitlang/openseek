# Background job lifecycle

Included in `just test` and native CI. Run it separately with
`just test-turn-finish`, or directly against the native CLI:

```sh
moon build cmd/openseek --target native
python3 tests/integration/turn_finish.py \
  _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe
```

The local scripted provider checks the actual request messages through a real
`mbtx` background execution, plain-text finish reminder, `job_wait`, completion
notice, `job_output`, and explicit `finish`. A file gate controls completion.
The test does not call an external model service. It requires Python 3 and the
same MoonBit runtime dependencies as `mbtx`.

The agent and runtime MoonBit tests cover input, cancellation, invalid calls,
multi-job selection, and notification ordering separately.

A second real `serve` scenario clears the goal through stdin while `job_wait`
observes a gated job. The next model request must report `user_input` before the
job is released, proving that the command dispatcher wakes the active turn.

# Bundled workflows

`just test-workflows` compiles the bundled agent scripts for Wasm and runs them
with a local Python child-contract fixture. It checks success, partial failure,
missing handoff, insufficient capacity, empty answers, and bounded shared
repository context, nested-package discovery, and citation validation (including
escaping symlinks and invalid line numbers), without calling a model service.
It is also included in `just test`. Builds live in a temporary directory so the
bundled resource tree stays clean.

The native CI job also runs `python3 tests/integration/workflows.py` directly,
since its target matrix does not invoke the root `just test` recipe.

`ci_watch.py` compiles the bundled CI monitor as Wasm and substitutes a scoped
`gh` executable with controlled JSON snapshots. It verifies stable completion,
PR-head replacement, failure/cancellation states, registration gaps, errors,
timeouts, and diagnostic argument lists without network or model credentials.
Run it directly with `python3 tests/integration/ci_watch.py`; the root workflow
test recipe and native CI job include it.
