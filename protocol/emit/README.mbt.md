# OpenSeek Protocol Writer

`bobzhang/openseek_protocol/emit` writes an `Event` to the process log, which is
the engine's stdout JSONL stream. It is the effectful half of
`bobzhang/openseek_protocol`, the way `deepseek/client` is the effectful half of
`deepseek`: the parent package is pure and portable, this one is native-only and
does the I/O.

```mbt nocheck
@emit.emit(AssistantDelta(content=delta))
@emit.emit(AgentAborted(reason="interrupted"))
@emit.emit(MaxStepsExhausted)
```

That is the whole API. There is no level argument — see below.

## Why it is a separate package

`@xlog` is `supported_targets = "native"`. Keeping it here is what lets the
parent package build for js, wasm and wasm-gc, and that is not hypothetical:
`desktop/frontend` compiles to js and decodes this stream. A reader must not
have to link a logger to read what it is sent.

So the split runs along the effect, not along the data:

| | package | targets |
| --- | --- | --- |
| `Event`, `Usage`, `to_json`, `parse` | `bobzhang/openseek_protocol` | js, wasm, wasm-gc, native |
| `emit` | `bobzhang/openseek_protocol/emit` (here) | native |

## What this package owns

Exactly one thing the parent cannot: **the level**.

`level` maps each `Event` to an `@xlog.Level`. It lives here only because
`@xlog.Level` is native-only — conceptually it belongs beside the variant, and
it behaves as if it does: a call site cannot choose it. That is the point.
`compaction_failed` was once logged at `warn` from one place and `error` from
two, which no reader could see and no test could catch, because severity was
whatever the author typed that day.

The shape is *not* owned here. `emit` serializes through `Event::to_json` in the
parent package, so this is not a second encoder that can drift from the first.
The desktop host is a real second writer — it forwards a synthesized
`compaction_failed` when a compaction's engine dies — and it goes through the
same `to_json`. It did not always: it hand-wrote the JSON with a different key,
under a comment claiming otherwise, and only one decoder's leniency hid it.

## What `emit` does

```mbt nocheck
guard @xlog.event(level(event), loc~) is Some(entry) else { return }
guard event.to_json() is Object(fields) else { return }
entry.write_object_begin()
for key, value in fields {
  entry.write_object_field(key, value)
}
entry.write_object_end()
```

Three properties are load-bearing:

- **`loc` is the caller's.** `emit` carries `#callsite(autofill(loc))` and
  forwards `loc` to `@xlog`, which stamps every line with a `source`. Drop the
  forward and all ~60 events report `emit.mbt` instead of the code that reported
  them. `@xlog`'s own level helpers do exactly this internally.
- **The level is checked before serializing.** `@xlog.event` returns `None` when
  the level is disabled, so a filtered event costs nothing beyond the enum it was
  handed.
- **Fields are hoisted, not nested.** `@xlog`'s handler lifts an entry's
  structured fields to the top of the line, which is why `to_json` is flat and
  `parse` reads from the top level. A line looks like:

```json
{"timestamp":"…","level":"INFO","source":"agent/turn_loop.mbt:392:9","event":"assistant_delta","content":"Hel"}
```

The envelope (`timestamp`, `level`, `source`) is `@xlog`'s; everything from
`event` on is the protocol's.

## Tests

`emit_test.mbt` holds the round-trip — `parse(emit(e)) == e` for a sample of
every variant — because it needs both halves and this package is where they
meet. It also pins the serialized bytes per shape, which is what proved the
encoder unification faithful: the snapshots were written against the old
hand-rolled literals and still pass, field order included.

Decoder tests that need no writer live in the parent package, where they run on
every backend.

## A caveat worth knowing

This package writes to the process-wide `@xlog` logger, whose root level comes
from `MOON_XLOG`. Every protocol event is info/warn/error, so a `MOON_XLOG=warn`
would silence the entire stream — a client would render nothing, with no error to
explain it. `cmd/openseek` pins the level for that reason, and a cram case holds
it.

That is a guard on the caller's side, not a property of this package. The real
issue is that the stream has no identity apart from the log: it is also why
`reasoning_delta` was once dropped for log noise and silently took the clients'
live-thinking view with it. The typed event and its clients have since been
restored, but giving the protocol its own sink is still the structural fix.
