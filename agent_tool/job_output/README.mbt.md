# Job Output Tool

`job_output` reads a background job's recent output and status by its
`job_id` — the id `mbtx` returns when a run is still active after its
five-second foreground grace period and moves to the background automatically.

The primary consumption path for job results is the **pushed completion
notice** (a job announces itself when it finishes); `job_output` is for
checking progress on a still-running job, and for reading the output once the
notice arrives. The tool description and system prompts steer the model away
from calling it in a polling loop.

## Result Shape

Output first, one `<system>` footer line last (the `read` tool convention):

```text
<recent output…>
<system>job=bg-3 running truncated=true total_chars=48210 shown_chars=12000</system>
```

- The body is a **bounded tail window** (most recent output), never the full
  log — a poll must not flood the conversation. `truncated=true` appears
  whenever what is shown is less than what the job produced, with
  `total_chars`/`shown_chars` naming the gap; `output_dropped_at_cap=true`
  marks output lost at the hard cap, and a watchdog-killed job reports
  `stopped killed_at_output_cap=true` (or `killed_at_time_cap=true` for the
  wall-clock reaper) so the model does not read it as a
  requested stop.
- Output beyond the window is **retained** (the spill file for a large job),
  and `offset` reads the window that starts at that character offset from
  the start instead of the tail; the footer then carries `window_offset=N`.
  A reader pages through all of `total_chars` with offsets 0, 12000, 24000,
  … — the case is a workflow snippet that prints several scouts' reports,
  which do not fit one window.
- Status is `running`, `exit=<code>`, or `stopped`; non-zero exits and stops
  are tool errors, matching what the same snippet would report in the
  foreground.

## Design Rationale

Two invariants drove the implementation:

1. **Never present a partial view as complete.** The truncation check compares
   what is *shown* against what the job *produced* — covering the tail window,
   a memory-only runtime that dropped output past its budget, and hard-cap
   drops. The footer metadata is sampled *after* the awaited read, so a job
   that appends or exits while the read yields cannot produce a stale footer.
2. **Foreground error-semantics parity.** A background job read later behaves
   exactly like the same snippet run in the foreground: binary (non-UTF-8)
   output is a tool error even at exit 0 (`binary_output=true`). While the job
   is running, denial detection checks only the bounded recent tail; once the
   job is terminal, the *full* retained output is scanned once and that
   classification is cached. This catches a denial line earlier than the final
   displayed tail, with the same guidance appended and the footer still last.
