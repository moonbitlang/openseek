# OpenSeek Protocol

`bobzhang/openseek_protocol` owns **both directions** of the serve protocol: the
stdout event stream the engine reports (`Event`), and the stdin command stream it
is told (`Command`). Between them they are the whole wire contract with the TUI,
the desktop host, the desktop frontend, and any script driving `run` or `serve`.

It is a **leaf module with no openseek dependencies**, split so the decoder is
portable:

| Package | Contents | Targets | Deps |
| --- | --- | --- | --- |
| `bobzhang/openseek_protocol` | `Event`, `Usage`, `Command`, `SteerKind`, `to_json`, `parse` | js, wasm, wasm-gc, native | `core/json` |
| `bobzhang/openseek_protocol/emit` | `emit` (level + `to_json` + log) | native | `xlog`, above |

Only the *writer* needs `@xlog`, which is native-only. Keeping it in its own
package means a client that reads the stream does not have to be a native
binary — `desktop/frontend` compiles to js, and its decoder can now be the same
`match` the engine's encoder is checked against.

Being a module rather than a package is what lets a *different* module consume
it: `desktop/moon.work` can list `"../protocol"` as a member and bind the
working tree (a `moon.work` member wins over the registry, so there is no stale
mooncakes snapshot).

The stream doubles as the process log. `emit` routes through `@xlog`, whose
handler writes one `Entry` per line and **hoists** structured fields to the top
level, so a line looks like:

```json
{"timestamp":"…","level":"INFO","source":"agent/turn_loop.mbt:392:9","event":"assistant_delta","content":"Hel"}
```

The envelope (`timestamp`, `level`, `source`) is `@xlog`'s; everything from
`event` on is this package's.

## Why it exists

The contract used to live as anonymous JSON literals at ~55 `@xlog.info() <? {…}`
call sites, with a hand-written decoder per client. Nothing tied the two
directions together, and they had drifted:

- `tool_result` was emitted with `brief` from one site and without it from two.
- `mcp_connect_failed` was emitted with `error` from one site and without it
  from another.
- `compaction_failed` was reported at `warn` from one site and `error` from two.

`Event` closes that by construction: one variant per event, owning its payload
**and its level**, with `to_json` the only author of the shape and `parse` its
inverse. Every reader — the TUI, the desktop host, the desktop frontend —
matches on the same enum, so adding a variant is a compile error at each one:
ignoring an event is a decision someone wrote down, not a `_ => None` nobody
noticed.

What that caught, once the readers were made exhaustive:

- **`reasoning_delta`** had not been emitted since 2026-06-21 (a85d5682), yet the
  TUI and the desktop both still decoded it and rendered a live "thinking" view
  from it — under tests that passed on fabricated lines. It was later restored
  as a typed transient event, with both clients covered from the shared decoder.
- **`runtime_update`** had not been emitted since 2026-07-05 (4b1ec831), yet the
  desktop host still decoded it, likewise under a passing test.
- The desktop host **synthesized `compaction_failed` with `reason`** while the
  engine writes `error`, under a comment claiming "the same wire shape the engine
  emits". One decoder happened to accept both spellings, so nothing noticed.

## API

```mbt nocheck
// Report an event. The level comes from the variant, never the call site.
@emit.emit(AssistantDelta(content="Hel"))
@emit.emit(AgentAborted(reason="interrupted"))

// Or build the line without logging it — what the desktop host forwards for a
// compaction whose engine died before reporting one itself.
let line = CompactionFailed(error="engine exited").to_json()

// Read one back. `None` means "not an event this engine emits" — an unknown
// name or a malformed payload — so a client stays tolerant of a newer engine.
match @protocol.parse(line) {
  Some(AssistantDelta(content~)) => render(content)
  Some(_) | None => ()
}
```

`emit` carries `#callsite(autofill(loc))` and forwards `loc` to `@xlog`, so each
line's `source` still points at the reporting code rather than at `emit.mbt`.

## When a field may be absent

**The rule and the fields it covers live in `parse`'s doc comment** (events) and
`Command::parse`'s (commands) — beside the code that enforces them, and nowhere
else. This file used to restate the rule and the list, and within a month it was
wrong on both: it still said "exactly one field qualifies" after the count went
to three, and stated an "iff" after a second case was found. A rule copied is a
rule that drifts, which is the failure this package exists to prevent — so the
copy is gone rather than corrected.

What is worth knowing here: a field is defaulted only for a reason the git
history can settle, never because no reader happens to use it. Run `git log -S`
for the field against its event's introducing commit before adding another; the
doc comment says what to look for.

## The command direction

`Command` is the same shape for the opposite direction: one type, one encoder
(`to_json`/`to_jsonl`), one decoder (`Command::parse`), and every controller
encodes through it — `cmd/tui` and the desktop host both, where each used to
model the commands itself. They drifted exactly as the events had: the TUI sent
`steer` with a `kind` and the desktop sent it without one, working only because
the engine's decoder happened to default it.

```mbt nocheck
// A controller writes a line.
let line = (Prompt(text="do it") : @protocol.Command).to_jsonl()

// The engine reads one back. `Err` is a line it cannot read — and only that:
// whether a readable command is *acceptable* is the engine's to say, which is
// why `serve`, not `parse`, refuses a blank goal.
match @protocol.Command::parse(line) {
  Ok(Prompt(text~)) => start_turn(text)
  Ok(_) => ()
  Err(message) => report(message)
}
```

`Command::parse` returns `Result`, not `Option`, unlike `parse` for events. An
unreadable event is a line to ignore; an unreadable command is a request that
will never be answered, and silence is the one reply a controller cannot act on.
Its `Err` strings reach the controller as `command_error`, so they are wire
contract too.

## Invariants

- **`parse` is `emit`'s inverse** for every variant. `emit/emit_test.mbt` pins
  this per sample — it needs both halves, so it lives with the writer; it is the
  property the package exists to provide.
- **Optional string fields are written as the value or `null`, never omitted.**
  A field's own `ToJson` would encode `Some(v)` as the one-element array `[v]`,
  which every decoder's string lookup rejects — silently turning a present field
  into an absent one. `or_null` is why, and the round-trip test is what caught it.
- **`Usage` is owned here, not borrowed from the provider.** It is structurally
  identical to `@deepseek.Usage` — same fields, same order, same JSON — and
  deliberately a separate type. The wire format must not be whatever a vendor's
  response struct happens to be, and this module cannot depend on the engine's
  provider layer without a cycle. `agent`'s `wire_usage` is the single place the
  two meet.

## Known gaps

- **The stream still has no identity apart from the log.** `reasoning_delta` was
  once dropped for log noise (a85d5682) and silently took the clients'
  live-thinking view with it. The typed protocol made that coupling explicit and
  the event is emitted again, but there is still no way to send a reader a
  transient fragment without also writing it to the log file. The engine pins
  its own level so `MOON_XLOG` cannot silence the protocol; a real separation
  still needs a protocol sink distinct from diagnostic logging.
