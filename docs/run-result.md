# `run` requests and results (v1)

`openseek run --result-file PATH TASK` writes one JSON object to `PATH` saying
how the run ended. It is the one authoritative result of a run: stdout is the
answer as text for a human, stderr is progress, and neither is meant to be
parsed. A parent that needs live progress reads the run's session log instead.

The type and its decoder are `RunResult` and `parse_run_result` in
`moonbitlang/openseek_protocol` (`protocol/run_result.mbt`); the fixtures in
`protocol/run_result_test.mbt` pin every shape below byte for byte.

`run` can also read what to do as a JSON request on stdin, run a preset
instead of the general agent, and be launched and cancelled by a parent; see
[Requests](#requests). The types are `RunRequest` and `parse_run_request`
(`protocol/run_request.mbt`).

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

## Requests

By default the task is the command line's words. `--input-format json` reads
one request from stdin instead:

```json
{"version":1,"request_id":"parser-fix-1","input":{"task":"Fix the parser and run its tests"},"limits":{"max_steps":100}}
{"version":1,"kind":"explore","input":{"query":"Explain the parser","hints":"Focus on recovery"}}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | integer | Always `1`. |
| `request_id` | string, optional | The caller's name for the request, echoed in the result. |
| `kind` | string, optional | A preset (`explore`, `review`, `worker`, `pattern-repair`, `echo`) or `general`. Absent means `general`. |
| `input` | any JSON | `{"task": string}` for a general run; the preset's own input otherwise (the `moonbitlang/workflow` child contract lists each preset's input and report). |
| `limits.max_steps` | integer ≥ 1, optional | The step ceiling for this request. |

Unknown fields are ignored. A request is refused, before any workspace,
session or model call exists, when it has another `version`, a malformed
field, or a `schema` (this engine cannot hold a report to a caller's schema,
and does not pretend to). An unknown `kind` is refused too; it never falls
back to the general agent.

`--kind NAME` selects a preset from the command line; when the request also
names one, the two must agree. `--kind` needs `--input-format json`, and a
task on the command line cannot be combined with it.

The step ceiling is, in order: an explicit `--max-steps`, else the request's
`limits.max_steps`, else `OPENSEEK_MAX_STEPS`, else the preset's default (a
general run has none).

A preset always starts a new session: `--session` must name one that does not
exist yet. Its report is the result's `output`; a preset that finishes without
one ends `no_report`.

### Batch and managed input

- **Batch** (`--input-format json`): stdin is read through EOF, so a request
  in a file works (`run --input-format json < request.json`). EOF only ends
  the input.
- **Managed** (`--input-format json --cancel-on-stdin-eof`): for a parent that
  launches the run. The request is one line; the parent keeps stdin open, and
  closing it cancels the run, which then ends `interrupted` and still writes
  its result. Closing stdin before a request arrives is a `failed` run. A
  pipe writer the parent passed to other processes can keep stdin open after
  the parent closes its own end, so EOF is not a way to stop a process tree.

A managed run is a delegated run, and it delegates no further: its `mbtx`
snippets get no workflow handoff (they see an empty `WORKFLOW_HOST`), and
`--review-gate` is refused. It also refuses every escalation: an inherited
`OPENSEEK_APPROVAL` does not apply, and `--approval` other than `never` is
refused. One launched from a hosted workflow must carry
its reserved `--session`.

Only one managed general run may work in a workspace at a time. It holds a
lock on `<workspace>/.openseek/general-child.lock` for as long as it runs; a
second is refused with a `failed` result. The lock is released with its
process, even when that process crashes. A parallel writer should be a
`worker` preset, which gets its own git worktree.

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
| `request_id` | string, optional | The request's `request_id`, echoed. |
| `kind` | string, optional | The preset that ran. Absent for a general run. |
| `status` | string | How the run ended; see below. |
| `output` | any JSON | Only when `status` is `completed`: what the run produced. For a general run it is `{"answer": string}`, the model's final answer, the same text `run` prints on stdout. For a preset, its typed report. |
| `reason` | string | When `status` is `context_yield`, `aborted`, `interrupted` or `failed`: why. For humans; do not match on it. |
| `session` | string, optional | The durable session the run recorded to. Absent with `--no-session`, and when the run failed before its session was opened. |
| `usage` | object, optional | Token usage the run recorded; see below. Absent when the run never reached its turn. |
| `steps` | integer, optional | How many model responses this run's turn recorded. Present exactly when `usage` is. |

A writer includes `output` and `reason` only for the statuses listed; a reader
ignores them elsewhere.

### Status

| `status` | Session terminal | Meaning |
| --- | --- | --- |
| `completed` | `finished` | The model finished. The only success. |
| `no_report` | `finished` | A preset finished its turn without submitting its report. Not a failure of the engine, but no result either. A general run never ends this way. |
| `context_yield` | `context_yield` | The turn filled the model's context window and was checkpointed. The work is not necessarily done; continue it with `--session`. |
| `max_steps_exhausted` | `max_steps_exhausted` | `--max-steps` ran out before the model finished. |
| `aborted` | `aborted` | The agent stopped on purpose, e.g. a tool asked it to abort. |
| `interrupted` | `interrupted` | The run was cancelled: its parent closed stdin in managed mode, or a failure elsewhere in its task group cancelled the turn. |
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
- Expected additive fields: machine-readable failure codes and cost.
