# The `run` result file (v1)

`openseek run --result-file PATH TASK` writes one JSON object to `PATH` saying
how the run ended. It is the one authoritative result of a run: stdout is the
answer as text for a human, stderr is progress, and neither is meant to be
parsed. A parent that needs live progress reads the run's session log instead.

The type and its decoder are `RunResult` and `parse_run_result` in
`moonbitlang/openseek_protocol` (`protocol/run_result.mbt`); the fixtures in
`protocol/run_result_test.mbt` pin every shape below byte for byte.

This is step 1 of #1767. Structured input, `--kind` and a managed cancel mode
come later, as additive fields or options; this file format is what they will
report through.

## When the file is written

1. When `run` starts, it removes `PATH` if it exists.
2. The file is written once, when the run is over, after its answer and
   progress have been written to stdout and stderr: first to a new, uniquely
   named sibling (`PATH.<random>.tmp`), then renamed onto `PATH`. A reader sees
   either no file or a whole result. The rename makes the file appear
   atomically; it is not synced to disk, so it may not survive a power loss.
3. It is written on every ending the process controls, successful or not,
   including a run that fails before its turn starts (no API key, an invalid
   `run` option). If writing it fails, `run` exits nonzero.
4. **No file means the run did not finish.** It never means success. `openseek`
   installs no signal handlers, so a run stopped by Ctrl-C or `SIGTERM` is
   killed and leaves no file, like a crash.

Give every run attempt a fresh `PATH` that nothing else writes. Step 1 cannot
protect a reused path: errors that stop `openseek` before `run` starts (an
unknown flag, `--result-file` without a value, an invalid `--retry-attempts`)
leave the path untouched, so a stale file from an earlier attempt would still
be there. Two runs given the same path each write their own temporary file,
and whichever finishes last owns `PATH`.

`PATH` is relative to the process's working directory, not to `--dir`. A
parent still has to drain the child's stdout and stderr and wait for it to
exit; after the file appears, `openseek` may still print a final error line to
stderr before exiting.

## Format

One JSON object on one line, UTF-8, ending in a newline:

```json
{"version":1,"status":"completed","output":{"answer":"Fixed the parser; tests pass."},"session":"s-1","usage":{"prompt_tokens":120,"completion_tokens":30,"total_tokens":150,"prompt_cache_hit_tokens":100,"prompt_cache_miss_tokens":20}}
```

```json
{"version":1,"status":"failed","reason":"an API key is required for deepseek-flash: pass --api-key"}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | integer | Always `1` for this format. |
| `status` | string | How the run ended; see below. |
| `output` | any JSON | Only when `status` is `completed`: what the run produced. For a general run it is `{"answer": string}`, the model's final answer, the same text `run` prints on stdout. Later, `--kind` presets will put their typed reports here. |
| `reason` | string | When `status` is `context_yield`, `aborted`, `interrupted` or `failed`: why. For humans; do not match on it. |
| `session` | string, optional | The durable session the run recorded to. Absent with `--no-session`, and when the run failed before its session was opened. |
| `usage` | object, optional | Token usage the run recorded; see below. Absent when the run never reached its turn. |

A writer includes `output` and `reason` only for the statuses listed; a reader
ignores them elsewhere.

### Status

| `status` | Session terminal | Meaning |
| --- | --- | --- |
| `completed` | `finished` | The model finished. The only success. |
| `context_yield` | `context_yield` | The turn filled the model's context window and was checkpointed. The work is not necessarily done; continue it with `--session`. |
| `max_steps_exhausted` | `max_steps_exhausted` | `--max-steps` ran out before the model finished. |
| `aborted` | `aborted` | The agent stopped on purpose, e.g. a tool asked it to abort. |
| `interrupted` | `interrupted` | The turn was cancelled, e.g. by a failure elsewhere in its task group. |
| `failed` | `failed`, or none | An error ended the run: the provider failed, the turn recorded no terminal, or the run failed before its turn started. |

A run whose turn finished but which then failed anyway (for example, writing
its output) is `failed`, never `completed`: the status and the exit code
always agree.

The status says whether the run finished its task, not whether the task's
outcome was good: a completed review can report blocking findings.

### Usage

`usage` has the same five non-negative integer counters as the `usage` event
(`prompt_tokens`, `completion_tokens`, `total_tokens`,
`prompt_cache_hit_tokens`, `prompt_cache_miss_tokens`). It is the sum over the
model responses recorded in this run's turn of the session log, so for a
resumed session (`--session ID`) it counts only this run. It is a total, not
an increment to add to usage a parent already observed.

It is **recorded** usage, not necessarily everything the run spent. It does
not include:

- child runs the turn started (a review gate, `mbtx` sub-runs), which have
  their own sessions;
- the model requests that write a context checkpoint summary, which the
  session log does not record today;
- a response that never made it into the log, e.g. one cut off by a failure
  or cancellation, or one whose append failed.

So `usage` with zero counters means nothing was recorded, not that the run was
free.

## Exit status

Unchanged by `--result-file`: `run` exits 0 only when the status is
`completed`, and nonzero otherwise, after the file is written. A caller should
still read the status from the file: a nonzero exit without a file is a crash
or an invocation error, and a zero exit without a file should not happen.

## Compatibility

- Readers ignore fields they do not know, so new optional fields do not change
  `version`.
- A new `status` value, or a change to an existing field, does change
  `version`. `parse_run_result` refuses any other version
  (`UnsupportedVersion`) and any unknown status (`Malformed`), rather than
  guessing whether an unknown run succeeded. A caller may treat either as an
  unsuccessful run, but should report it as a protocol error, not as a failure
  of the task.
- Expected additive fields: the request id and kind once structured input
  lands, machine-readable failure codes, and step counts or cost.
