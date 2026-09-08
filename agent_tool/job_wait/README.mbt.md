# job_wait

`job_wait({"job_ids":["bg-1","bg-2"]})` waits for any selected job to
finish, or for user steering/command context. It has no timeout and does not
read logs. Read results with `job_output` after waiting. Call it alone in a tool
batch; unknown/blank ids and an empty selection are errors. Repeated ids are
deduplicated.

The tool returns a `WaitJobs` control action. The agent loop owns the async
wait, preserves input in its lossless queue, and continues the same turn.
Cancellation interrupts the turn; cancelling a losing wait branch does not
stop the job. This control is not eligible for context-ceiling salvage.

Plain-text completion with pending jobs prompts a decision. Explicit `finish`
still completes the work; it is not held hostage by a long-lived background
process. See [turn_finish.md](../../docs/turn_finish.md).
