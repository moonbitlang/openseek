# bobzhang/jsonl

A tiny async reader for [JSON Lines](https://jsonlines.org/) (newline-delimited
JSON, also called NDJSON). Each line is one independent JSON value; this package
turns such a stream into MoonBit `Json` values using the built-in
`moonbitlang/core/json` parser.

It is native-only because it reads from `moonbitlang/async/io` streams.

## API

- `parse(text : String) -> Array[Json] raise` — pure helper that decodes
  already-buffered text. Blank lines are skipped; the first malformed line
  raises.
- `each(reader, visit) -> Unit raise` (async) — stream values from any
  `@io.Reader`, invoking `visit` on each parsed value in order.
- `read_all(reader) -> Array[Json] raise` (async) — collect every value from a
  reader into an array.
- `read_stdin() -> Array[Json] raise` (async) — collect every value from
  standard input, so the caller need not import `moonbitlang/async/stdio`.

## Buffered Input

The pure `parse` helper needs no IO, so it is handy for testing and for input
you already hold as a string:

```moonbit nocheck
///|
test "parse buffered JSON Lines" {
  let values = @jsonl.parse(
    (
      #|{"event": "agent_step", "step": 1}
      #|{"event": "agent_finished", "answer": "DONE"}
    ),
  )
  assert_eq(values.length(), 2)
  assert_true(values[1] == { "event": "agent_finished", "answer": "DONE" })
}
```

## Streaming From A Reader

`each` and `read_all` consume any `moonbitlang/async/io` reader — a pipe, a
socket, `@stdio.stdin`, and so on — one line at a time:

```moonbit nocheck
///|
async test "stream JSON Lines from a pipe" {
  @async.with_task_group(group => {
    let (rd, wr) = @io.pipe()
    group.spawn_bg(() => {
      wr.write("{\"n\": 1}\n{\"n\": 2}\n")
      wr.close()
    })
    let values = @jsonl.read_all(rd)
    assert_eq(values.length(), 2)
  })
}
```

A common use is to consume a program's JSONL log over a pipe and assert on it
with the typed `Json` values instead of an external tool such as `jq`.

## License

Apache-2.0.
