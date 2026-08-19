# Job Stop Tool

`job_stop` cancels a running background job by its `job_id` — the id
`run_moonbit` returns when called with `run_in_background=true`.

Stopping is a request against the job's shared execution: the child process is
cancelled and the job lands on the `Stopped` status, which `job_output`
reports as a tool error thereafter. Stopping an already-finished job is a
*successful* no-op — the id is known, there is just nothing left to cancel —
so `job_stop` is idempotent; only an unknown id is a tool error
(`no background job with id …`).

## Design Rationale

- **A requested stop produces no completion notice.** The push-completion
  watcher only announces jobs that end on their own (natural exit, or the
  output-limit watchdog); the model that called `job_stop` already has the
  acknowledgment in the tool result, so a notice would be noise.
- **Cancellation reaches the direct child only.** The process library exposes
  no process-group kill, and the direct child here is the snippet's `moon run`,
  so processes it spawned in turn can outlive a stop — the same limitation as
  foreground cancellation, documented rather than hidden.
- Session teardown stops all jobs the same way: every job's direct child is
  spawned on the session task group, so it is cancelled when the session ends —
  with the same direct-child-only limitation as above: daemonized descendants
  can outlive the session.
