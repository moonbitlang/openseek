# Manifest Error

`moonbitlang/openseek/agent_tool/internal/manifest_error` keeps the manifest safety
checks shared by `write`, `edit`, and `multi_edit`.

This package is shared internally by the write tools under `agent_tool`. It does
not edit files itself; it inspects the target path and proposed file content,
then returns an optional error message for manifest rewrites that look like
common agent mistakes.

## API Shape

- `write_error(path, content)`: returns `Some(message)` when the proposed write
  should be rejected, otherwise `None`.

## Checks

The guard handles current MoonBit manifests and generated interfaces:
- `moon.mod` is rejected when it is empty, JSON-shaped, or missing `name =`.
- `moon.pkg` is rejected when it is JSON-shaped or uses `#` comments.
- `*.generated.mbti` files are rejected because they are generated outputs.
- Other paths are allowed.

## Example

```moonbit check
///|
test "manifest error rejects JSON moon.mod content" {
  let error = @manifest_error.write_error("moon.mod", "{\"name\":\"demo\"}")
  guard error is Some(message) else { fail("expected manifest error") }
  assert_eq(message, "moon.mod uses current text syntax, not JSON")
  assert_true(@manifest_error.write_error("notes.json", "{}") is None)
}
```
