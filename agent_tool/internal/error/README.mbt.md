# agent_tool/internal/error

One function, `failure_message`, that takes MoonBit's rendering of a raised
`fail(...)` and gives back just the message the code meant to say.

Ten packages depend on it — `edit`, `goal`, `multi_edit`, `plan`, `read`,
`remove`, `mbtx`, `shell`, `write`, and `goal/internal/decode` — because
argument validation lives in internal decode packages that signal problems with
`fail("arguments.path")`. The string a tool would otherwise hand back to the
model looks like this:

```text
Failure(agent_tool/read/internal/decode/decode.mbt:41:7-41:29@decode FAILED: arguments.path)
```

That leaks a source location into a message whose whole job is to tell the model
which argument to fix. `failure_message` strips the wrapper so the tool result
reads `arguments.path` and stays stable when the raising code moves to another
line or another file.

## Behavior

The wrapper comes off; anything that is not wrapped passes through unchanged.
There is no error case — this is a formatting normalizer, not a parser.

```mbt check
///|
test "the wrapper comes off, and unwrapped text is left alone" {
  inspect(
    @error.failure_message(
      "Failure(agent_tool/read/internal/decode/decode.mbt:41:7-41:29@decode FAILED: arguments.path)",
    ),
    content="arguments.path",
  )
  // A message that was never wrapped is already the answer, so applying this
  // twice is safe.
  inspect(@error.failure_message("arguments.path"), content="arguments.path")
  inspect(@error.failure_message(""), content="")
}
```

The point of the package is that this works on a *real* raised error, not just
on a hand-written string. The location in the raw text depends on where `fail`
is called, so only the extracted message is stable enough to pin:

```mbt check
///|
/// Stands in for the argument validation a decode package performs.
fn reject_argument() -> String raise {
  fail("arguments.max_output_chars to be a positive number")
}

///|
test "a real raised failure round-trips to just its message" {
  let extracted = try reject_argument() catch {
    err => @error.failure_message("\{err}")
  } noraise {
    _ => "no error was raised"
  }
  inspect(
    extracted,
    content="arguments.max_output_chars to be a positive number",
  )
}
```

## Edges worth knowing

A message containing a literal `)` survives, because exactly one trailing
parenthesis — the wrapper's own — is removed:

```mbt check
///|
test "one closing paren is removed, not every one" {
  inspect(
    @error.failure_message("Failure(decode.mbt:1:1-1:2@d FAILED: expected (a))"),
    content="expected (a)",
  )
}
```

The scan is greedy to the **last** ` FAILED: ` marker, so a failure message that
itself contains that exact marker is cut at the wrong place. No message in this
repository does, and the alternative — matching the first marker — would break
on nested renderings instead. It is a documented limit, not a bug to route
around:

```mbt check
///|
test "a message containing ` FAILED: ` is cut at the last marker" {
  inspect(
    @error.failure_message(
      "Failure(d.mbt:1:1-1:2@d FAILED: step FAILED: badly)",
    ),
    content="badly",
  )
}
```
