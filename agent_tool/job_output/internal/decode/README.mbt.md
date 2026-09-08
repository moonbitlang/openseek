# agent_tool/job_output/internal/decode

Argument decoding for the `job_output` tool, which reads a background job's
output and status by id. This package is internal to `agent_tool/job_output`
and owns only argument-shape decoding: validating `job_id` and turning the
`wait_ms`/`offset` selectors into typed optionals. Waiting on the job, reading
its retained output, and rendering the `<system>` footer stay in the parent
package.

## Arguments

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `job_id` | string | yes | Missing or non-string raises `job_output requires a string job_id`. |
| `wait_ms` | number | no | Absent/`null` means no waiting (`None`). Must be positive; an oversized value is capped to `max_wait_ms` (`120000`) rather than rejected. Non-number raises `job_output wait_ms must be a number`. |
| `offset` | number | no | Absent/`null` means the recent tail (`None`). Must be zero or positive. Non-number raises `job_output offset must be a number`. |

Extra fields are ignored.

## Defaults and Explicit Selectors

```mbt check
///|
test "decode defaults wait_ms and offset when only job_id is given" {
  debug_inspect(
    @decode.decode({ "job_id": "bg-3" }),
    content="{ job_id: \"bg-3\", wait_ms: None, offset: None }",
  )
}

///|
test "decode reads explicit wait_ms and offset selectors" {
  debug_inspect(
    @decode.decode({ "job_id": "bg-3", "wait_ms": 30000, "offset": 12000 }),
    content="{ job_id: \"bg-3\", wait_ms: Some(30000), offset: Some(12000) }",
  )
}
```

## `wait_ms` is capped, not trusted

`wait_ms` bounds how long one call blocks awaiting the job's exit. A caller may
ask for any positive wait, but not more than `max_wait_ms`: the ceiling exists
so one `job_output` call cannot hold the turn indefinitely — a deadline expiry
is not an error, and the model can always call again.

```mbt check
///|
test "an oversized wait_ms clamps silently to max_wait_ms" {
  inspect(@decode.max_wait_ms, content="120000")
  debug_inspect(
    @decode.decode({ "job_id": "bg-3", "wait_ms": 999999 }).wait_ms,
    content="Some(120000)",
  )
}
```

Zero and negative values are rejected rather than clamped, because they express
an intent the tool cannot satisfy — no waiting is already spelled by omitting
the argument.

```mbt check
///|
/// True when decoding `arguments` fails with a message containing `expected`.
fn decode_error_says(arguments : Json, expected : String) -> Bool {
  try {
    ignore(@decode.decode(arguments))
    false
  } catch {
    err => "\{err}".contains(expected)
  }
}

///|
test "malformed selectors are errors that name the argument to fix" {
  inspect(
    decode_error_says(
      { "job_id": "bg-3", "wait_ms": 0 },
      "wait_ms must be a positive number",
    ),
    content="true",
  )
  inspect(
    decode_error_says(
      { "job_id": "bg-3", "wait_ms": "30000" },
      "wait_ms must be a number",
    ),
    content="true",
  )
  inspect(
    decode_error_says(
      { "job_id": "bg-3", "offset": -1 },
      "offset must be zero or a positive number",
    ),
    content="true",
  )
  inspect(
    decode_error_says(
      { "job_id": "bg-3", "offset": "0" },
      "offset must be a number",
    ),
    content="true",
  )
  // A missing or wrong-typed job_id is caught before the selectors.
  inspect(
    decode_error_says({ "wait_ms": 500 }, "requires a string job_id"),
    content="true",
  )
}
```
