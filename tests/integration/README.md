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

`just test-workflows` runs the native MoonBit fixture package at
`tests/integration/workflows`. It compiles the actual bundled scripts as Wasm
and exercises them with local child processes. The runner itself doubles as the
hosted-child fixture and the fake `gh` executable; no Python, shell scripts,
network access, or model credentials are needed. Builds and fixture files live
in a temporary directory, keeping the bundled resource tree clean.

The hosted tests cover success, partial failure, missing handoff, insufficient
capacity, empty answers, bounded context, nested-package discovery, and citation
validation (including escaping symlinks and invalid line numbers). The CI tests
cover stable completion, PR-head replacement, failure/cancellation states,
registration gaps, errors, timeouts, and diagnostic argument lists.

Run the same suite directly with:

```sh
moon run tests/integration/workflows
```

The native CI job runs that command too, since its target matrix does not invoke
`just test`. These subprocess/symlink fixtures run on Linux and macOS. The
pre-existing background lifecycle suite above is separate.
