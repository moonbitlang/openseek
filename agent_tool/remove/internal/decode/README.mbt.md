# agent_tool/remove/internal/decode

Argument decoding for the `remove` tool, which deletes a file. This package is
internal to `agent_tool/remove` and owns only argument-shape decoding —
resolving the path, checking it exists, and performing the delete stay in the
parent package.

## Arguments

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `path` | string | yes | Missing or non-string raises `arguments.path`. |
| `reason` | string | yes | Missing or non-string raises `arguments.reason`; blank raises `arguments.reason to be a non-empty explanation`. |

Extra fields are ignored. Non-object JSON raises `object arguments`.

```mbt check
///|
test "a well-formed removal decodes to path and reason" {
  debug_inspect(
    @decode.decode({
      "path": "scratch/old_notes.md",
      "reason": "superseded by the new design doc",
    }),
    content=(
      #|{
      #|  path: "scratch/old_notes.md",
      #|  reason: "superseded by the new design doc",
      #|}
    ),
  )
}
```

## Why `reason` is required, and why blank is not enough

`remove` is the only destructive file tool: unlike `write` and `edit`, there is
no previous content to recover from the result. `reason` is what makes that
auditable after the fact, so it is required rather than optional — and requiring
a field the model can satisfy with `" "` would buy nothing. A whitespace-only
reason is rejected.

The blank check is Unicode-aware, which is the reason it is not written as
`reason.trim() != ""`: `String::trim` strips only ASCII whitespace, so a reason
made of non-breaking or ideographic spaces would pass and then render as a
visually empty audit entry.

```mbt check
///|
/// True when decoding `arguments` fails with a message containing `expected`.
/// The raw error also carries `fail`'s source location, which is why the test
/// matches on a substring rather than snapshotting the whole string.
fn decode_error_says(arguments : Json, expected : String) -> Bool {
  try {
    ignore(@decode.decode(arguments))
    false
  } catch {
    err => "\{err}".contains(expected)
  }
}

///|
test "a blank reason is rejected, ASCII or not" {
  inspect(
    decode_error_says(
      { "path": "a.txt", "reason": "   " },
      "arguments.reason to be a non-empty explanation",
    ),
    content="true",
  )
  // U+00A0 no-break space and U+3000 ideographic space: invisible, and not
  // ASCII whitespace.
  inspect(
    decode_error_says(
      { "path": "a.txt", "reason": "\u{00A0}\u{3000}" },
      "arguments.reason to be a non-empty explanation",
    ),
    content="true",
  )
}
```

## Which field the error names

The decoder reports the *first* problem in a fixed order, so the message always
points at one specific argument to fix rather than describing the payload as a
whole.

```mbt check
///|
test "rejections name one field, outermost problem first" {
  // Not an object at all.
  inspect(decode_error_says(Json::null(), "object arguments"), content="true")
  inspect(decode_error_says(["a.txt"], "object arguments"), content="true")
  // An object whose `path` is missing or the wrong type.
  inspect(
    decode_error_says({ "reason": "no longer used" }, "arguments.path"),
    content="true",
  )
  inspect(
    decode_error_says(
      { "path": 7, "reason": "no longer used" },
      "arguments.path",
    ),
    content="true",
  )
  // A valid `path`, so the next problem reported is `reason`.
  inspect(
    decode_error_says({ "path": "a.txt" }, "arguments.reason"),
    content="true",
  )
  inspect(
    decode_error_says({ "path": "a.txt", "reason": 7 }, "arguments.reason"),
    content="true",
  )
}
```

Note the ordering consequence: a payload with *both* fields wrong reports
`arguments.path`, never `arguments.reason`. The model fixes one field per
retry.

Unlike the read workflow, an empty-string `path` is not rejected here — the pattern only
requires a string. A path that is empty, absent from disk, or outside the
workspace is the parent package's problem, because answering those questions
needs the filesystem.

```mbt check
///|
test "an empty path decodes; existence is not this package's question" {
  debug_inspect(
    @decode.decode({ "path": "", "reason": "cleanup" }),
    content=(
      #|{ path: "", reason: "cleanup" }
    ),
  )
}
```
