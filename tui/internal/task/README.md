# bobzhang/openseek/tui/internal/task

This is the **serialization point** for everything the TUI does to the screen.
Drawing a frame, handling a keystroke, and committing a transcript line all
mutate the same terminal, so they must never run concurrently. `Queue` is a
single-slot async queue that guarantees that: one long-lived worker runs
submitted jobs one at a time, in order.

The mental model is a worker thread with an inbox of size one — you `wait` a job
onto it from anywhere and get its result back, and the worker drains them
serially. It's a thin wrapper over `@async/aqueue` with no scheduling policy of
its own.

## Usage

Spawn the worker loop once, then `wait` jobs onto it; each runs to completion
before the next starts, and `wait` returns the job's result (or re-raises its
error).

```mbt
let queue = @task.Queue::Queue(kind=Blocking(1))

// Background: the worker drains the queue forever.
g.spawn_bg(no_wait=true, () => queue.run())

// Foreground: submit work and get its result back, serialized against redraws.
let frame = queue.wait(() => self.build_frame())
queue.wait(() => self.redraw(frame))
```

Internal to `tui/` — only importable within the module.
