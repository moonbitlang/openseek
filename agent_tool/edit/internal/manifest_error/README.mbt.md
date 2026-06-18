# Edit Manifest Error

`bobzhang/openseek/agent_tool/edit/internal/manifest_error` keeps the manifest
safety checks used before the `edit` tool writes replacement content.

This package is internal to `agent_tool/edit`. It does not edit files itself;
it inspects the target path and proposed file content, then returns an optional
error message for manifest rewrites that look like common agent mistakes.
`moon.mod`, `moon.pkg`, and `moon.work` writes are also parsed with
`moonbitlang/moon_config` so malformed current-syntax manifests are rejected at
the edit boundary.

## API Shape

- `write_error(path, content)`: returns `Some(message)` when the proposed write
  should be rejected, otherwise `None`.

## Checks

The guard is intentionally narrow and only handles MoonBit manifest paths:

- New `moon.mod.json` files are rejected because that manifest is legacy.
- `moon.mod` is rejected when it is empty, JSON-shaped, missing `name =`, or
  rejected by the `moon_config` parser.
- `moon.pkg` is rejected when it is suspiciously tiny, JSON-shaped, or rejected
  by the `moon_config` parser.
- `moon.work` is rejected when it is JSON-shaped or rejected by the
  `moon_config` parser.
- Other paths are allowed.

Existing `moon.mod.json` files are allowed so `edit` can still update legacy
projects deliberately; the guard only blocks creating new legacy manifests.

## Example

```moonbit check
///|
async test "manifest error rejects JSON moon.mod content" {
  let error = @manifest_error.write_error("moon.mod", "{\"name\":\"demo\"}")
  guard error is Some(message) else { fail("expected manifest error") }
  assert_eq(message, "moon.mod uses current text syntax, not JSON")
  assert_true(@manifest_error.write_error("notes.json", "{}") is None)
}
```
