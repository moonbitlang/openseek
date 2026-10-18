# Background job lifecycle

Included in `just test` and native CI. Run it separately with
`just test-turn-finish`, or directly against the native CLI:

```sh
moon build . --target native
moon run tests/integration/turn_finish.mbtx \
  _build/native/debug/build/moonbitlang/openseek/openseek.exe
```

The local scripted provider checks the actual request messages through a real
`mbtx` background execution, plain-text finish reminder, `job_wait`, completion
notice, `job_output`, and explicit `finish`. A file gate controls completion.
The test does not call an external model service. It uses MoonBit's async HTTP
and subprocess APIs and the same runtime dependencies as `mbtx`.

The agent and runtime MoonBit tests cover input, cancellation, invalid calls,
multi-job selection, and notification ordering separately.

A second real `serve` scenario clears the goal through stdin while `job_wait`
observes a gated job. The next model request must report `user_input` before the
job is released, proving that the command dispatcher wakes the active turn.

# Subagents

`just test-subagents` runs `tests/integration/subagents.mbtx` against the native
CLI: a `run` with a durable session starts two explore subagents with the
`subagent` tool, waits, reads both reports with `job_output`, and finishes. One
local scripted server answers the parent and the two real child processes,
which reach it through the forwarded `--api-url`; a child is recognized by its
`submit_answer` tool and routed by a marker in its query. Afterwards each
child's session holds its transcript and `report.json`, and no claim file is
left. No model credentials or network are needed.

# Bundled workflows

`just test-workflows` runs the native MoonBit fixture package at
`tests/integration/workflows`. It compiles the actual bundled scripts as Wasm
and exercises them with local child processes. The runner itself doubles as the
hosted-child fixture and the fake `gh` executable; no Python, shell scripts,
network access, or model credentials are needed. Builds and fixture files live
in a temporary directory, keeping the bundled resource tree clean.

The hosted tests cover success, partial failure, missing handoff, insufficient
capacity, empty answers, bounded context, nested-package discovery, and citation
validation (including escaping symlinks and invalid line numbers); the review
script's criteria resolution (arguments, the engine's standing goal, or both),
baseline forwarding and override, the failing exit on blockers, and usage
errors. The CI tests
cover stable completion, PR-head replacement, failure/cancellation states,
registration gaps, errors, timeouts, and diagnostic argument lists.

Run the same suite directly with:

```sh
moon run tests/integration/workflows
```

The native CI job runs that command too, since its target matrix does not invoke
`just test`. These subprocess/symlink fixtures run on Linux and macOS. The
pre-existing background lifecycle suite above is separate.
