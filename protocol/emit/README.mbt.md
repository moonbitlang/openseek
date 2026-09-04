# OpenSeek Protocol Writer

`bobzhang/openseek_protocol/emit` writes an `Event` to the engine's stdout JSONL
stream — the events the desktop host, the TUI, and any script driving `run` or
`serve` decode. It is the effectful half of `bobzhang/openseek_protocol`, the
way `deepseek/client` is the effectful half of `deepseek`: the parent package
is pure and portable, this one is native-only and does the I/O.

```mbt nocheck
@emit.emit(AssistantDelta(content=delta))
@emit.emit(AgentAborted(reason="interrupted"))
@emit.emit(MaxStepsExhausted)
```

That is the whole reporting API. There is no level argument — see below. The
other public functions are plumbing the stdout sink: `open` starts accepting
events, `drain_stdout` is the one task that writes the queue to fd 1, `close`
ends the stream at run teardown, and `poll_line` is the in-process read side
for a test that owns no fd 1. Until `open`, and again after `close`, `emit`
drops every event — see below.

## Why it is a separate package

Writing a stream line is I/O, not encoding: the line must reach fd 1 whole and
in order, which means an asynchronous writer (`@stdio.stdout`) that only a
native process can run. Keeping that here is what lets the parent package build
for js, wasm and wasm-gc, and that is not hypothetical: `desktop/frontend`
compiles to js and decodes this stream. A reader must not have to link a writer
to read what it is sent.

So the split runs along the effect, not along the data:

| | package | targets |
| --- | --- | --- |
| `Event`, `Usage`, `to_json`, `parse` | `bobzhang/openseek_protocol` | js, wasm, wasm-gc, native |
| `emit`, the stdout sink | `bobzhang/openseek_protocol/emit` (here) | native |

## What this package owns

Exactly one thing the parent cannot: **the severity label and the sink**.

`level` maps each `Event` to the label its line carries. It lives here only
because the writer is native-only — conceptually it belongs beside the variant,
and it behaves as if it does: a call site cannot choose it. That is the point.
`compaction_failed` was once logged at `warn` from one place and `error` from
two, which no reader could see and no test could catch, because severity was
whatever the author typed that day.

The shape is *not* owned here. `emit` serializes through `Event::to_json` in the
parent package, so this is not a second encoder that can drift from the first.
The desktop host is a real second writer — it forwards a synthesized
`compaction_failed` when a compaction's engine dies — and it goes through the
same `to_json`. It did not always: it hand-wrote the JSON with a different key,
under a comment claiming otherwise, and only one decoder's leniency hid it.

`emit` is not a logger. Events used to travel through the process-wide `@xlog`
logger — the stream doubled as the process log — so every line carried the
envelope its handler added (`timestamp`, `level`, `source`), and a logging
environment variable could silence the whole stream. None of that is true
anymore: the line is exactly the `level` label plus the event's own fields,
written straight to stdout, and genuine log content stays in `@xlog` in the CLI
where it belongs.

## What `emit` does

`emit` serializes `event` and hands the line to the open sink's queue; one drain
task, spawned by the CLI for the run, owns every write to stdout:

```mbt nocheck
///|
fn emit(event : Event) -> Unit {
  guard sink.val is Some(queue) else { return }
  guard event.to_json() is Object(fields) else { return }
  let object : Map[String, Json] = { "level": Json::string(level(event)) }
  for key, value in fields {
    object[key] = value
  }
  ignore(queue.try_put(Json::object(object).stringify()))
}
```

Four properties are load-bearing:

- **The line is the protocol's, with no log envelope.** It is the event's
  severity label plus its flat `to_json` fields. `timestamp`, `source`, and
  `category` were the `@xlog` handler's; events no longer go through the logger,
  so none of them appear.
- **Nothing can filter or silence an open stream.** There is no level check and
  no environment variable between a call site and the queue (`MOON_XLOG`
  configures only `@xlog`, which the CLI pins to discard). Every event emitted
  while the sink is open reaches stdout.
- **Order and line integrity come from the single drain task.** `emit` is
  synchronous (agent internals call it) while `@stdio.stdout` writes are
  asynchronous; concurrent emitters could interleave writes, so the drain is the
  only task that touches fd 1. The queue is unbounded and drained in order.
- **The sink drops by default.** The queue is process-global, and a process
  that never drains — a CLI command whose stdout is a report or human text, a
  test binary, anything that links the agent without owning fd 1 — must not
  accumulate lines forever in a queue nobody reads. So there is no queue until
  `open` installs one, and `close` uninstalls it before closing it. The one
  place that opens is the one place that spawns the drain
  (`with_jsonl_stdout` in the CLI); nothing else has to remember to close.
  `open` is synchronous and precedes the spawn, because `spawn_bg` does not
  promise the drain runs before the body's first `emit`.

```json
{"level":"INFO","event":"assistant_delta","content":"Hel"}
```

`parse` in the parent package reads the top level, so the `level` label is
ignored by every client that decodes events.

## Tests

`emit_test.mbt` holds the round-trip — `parse(emit(e)) == e` for a sample of
every variant — because it needs both halves and this package is where they
meet. Its `wire` helper reads each line back through `emit` and `poll_line`,
the real path, rather than a serializer the drain might not share. It also pins
the serialized bytes per shape, which is what proved the encoder unification
faithful: the snapshots were written against the old hand-rolled literals and
still pass, field order included.

Decoder tests that need no writer live in the parent package, where they run on
every backend.

## The protocol has its own sink

The stream's identity is no longer borrowed from a logger: `emit` writes
directly to stdout, and `@xlog` in the CLI is left with content that is truly a
log. `MOON_XLOG` cannot silence an event, and a reader never has to strip a log
envelope — every line on the stream is an event.

The desktop host opts into presenting `reasoning_delta` while other consumers
ignore it; the writer does not care, because it does not log — it streams.
