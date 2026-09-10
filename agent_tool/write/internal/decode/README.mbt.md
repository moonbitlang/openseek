# agent_tool/write/internal/decode

Argument decoding for the `write` tool, which creates or overwrites a file with
exactly the content given. This package is internal to `agent_tool/write` and
owns only argument-shape decoding; path resolution, the manifest guards, and the
post-write syntax gate stay in the parent package.

## Arguments

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `path` | string | yes | Missing or non-string raises `arguments.path`. |
| `content` | string | yes | Missing or non-string raises `arguments.content`. Empty is valid. |
| `revert_on_parse_errors` | boolean | no | Defaults to `true`. `null` also means `true`. A non-boolean raises. |

Extra fields are ignored. Non-object JSON raises `object arguments`.

```mbt check
///|
test "a well-formed write decodes, with the syntax gate on by default" {
  debug_inspect(
    @decode.decode({
      "path": "agent_tool/write/notes.md",
      "content": "# Notes\n",
    }),
    content=(
      #|{
      #|  path: "agent_tool/write/notes.md",
      #|  content: "# Notes\n",
      #|  revert_on_parse_errors: true,
      #|}
    ),
  )
}
```

## `revert_on_parse_errors` defaults to on

The parent tool lexes and parses new `.mbt` content before committing the write,
and reverts when it does not parse. That gate defaults **on**, so a model that
omits the field gets the safe behavior; opting out has to be deliberate and
explicit.

`null` is treated as absent rather than as an error, because a client that
serializes unset optional fields as `null` should behave the same as one that
omits them. Any other type is a mistake worth reporting.

```mbt check
///|
test "absent, null, and explicit true all mean the gate is on" {
  let absent = @decode.decode({ "path": "a.mbt", "content": "" })
  let null_valued = @decode.decode({
    "path": "a.mbt",
    "content": "",
    "revert_on_parse_errors": Json::null(),
  })
  let explicit = @decode.decode({
    "path": "a.mbt",
    "content": "",
    "revert_on_parse_errors": true,
  })
  inspect(absent.revert_on_parse_errors, content="true")
  inspect(null_valued.revert_on_parse_errors, content="true")
  inspect(explicit.revert_on_parse_errors, content="true")
  // Opting out is explicit.
  inspect(
    @decode.decode({
      "path": "a.mbt",
      "content": "",
      "revert_on_parse_errors": false,
    }).revert_on_parse_errors,
    content="false",
  )
}
```

## Empty content is a valid write

Truncating a file to nothing is a legitimate request, so `content: ""` decodes
rather than raising. Contrast a file selector in the read workflow, where
an empty string *is* rejected — there it names a file to open, and no file is
named by the empty string.

```mbt check
///|
test "an empty content field truncates rather than failing" {
  debug_inspect(
    @decode.decode({ "path": "scratch/log.txt", "content": "" }),
    content=(
      #|{ path: "scratch/log.txt", content: "", revert_on_parse_errors: true }
    ),
  )
}
```

## Which field the error names

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
test "rejections name one field, outermost problem first" {
  inspect(decode_error_says(Json::null(), "object arguments"), content="true")
  inspect(
    decode_error_says({ "content": "hi" }, "arguments.path"),
    content="true",
  )
  // A valid `path`, so the next problem reported is `content`.
  inspect(
    decode_error_says({ "path": "a.mbt" }, "arguments.content"),
    content="true",
  )
  inspect(
    decode_error_says({ "path": "a.mbt", "content": 7 }, "arguments.content"),
    content="true",
  )
  // The flag is checked only once path and content are both valid.
  inspect(
    decode_error_says(
      { "path": "a.mbt", "content": "", "revert_on_parse_errors": "yes" },
      "arguments.revert_on_parse_errors to be a boolean",
    ),
    content="true",
  )
}
```
