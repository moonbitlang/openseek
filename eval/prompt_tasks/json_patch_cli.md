You are running a MoonBit coding-agent benchmark.

Workspace: {{WORKSPACE}}

Build a small MoonBit JSON Pointer / JSON Patch library and native CLI in that
workspace. This measures long-horizon adherence to a specification with many
independent rules.

Requirements:

- Create a current MoonBit project using `moon.mod`, not `moon.mod.json`.
- Implement, over `Json` values, a subset of:
  - RFC 6901 JSON Pointer resolution, including the escapes `~1` → `/` and
    `~0` → `~`, unescaped in that order.
  - RFC 6902 JSON Patch application supporting the ops `add`, `remove`,
    `replace`, `move`, `copy`, and `test`.
  - A structural `diff` that produces a JSON Patch (an array of ops)
    transforming one document into another.
- For array paths, `-` as the final reference token means "append" for `add`.
- Add black-box tests for successful operations and for malformed input, and a
  round-trip test that applying `diff(a, b)` to `a` yields `b`.
- Add a native CLI at `cmd/jsonpatch`. The primary JSON **document is read from
  stdin**. The first argument selects the mode:
  - `pointer <ptr>` — resolve the pointer against the stdin document and print
    the referenced value as compact JSON.
  - `patch <patchfile>` — apply the JSON Patch array read from `<patchfile>` to
    the stdin document and print the resulting document as compact JSON.
  - `diff <otherfile>` — print a JSON Patch array transforming the stdin
    document into the document read from `<otherfile>`.
- Successful CLI stdout must be valid JSON only.
- On any invalid input — an unresolved pointer, a failed `test` op, an
  out-of-range array index, or a malformed patch/JSON document — the CLI must
  print a clean, single-line error to stderr containing the word `error`, then
  exit non-zero. A MoonBit panic, abort, or debug stack must never reach the
  output.

Validation expectations before finishing:

- Run `moon check --target native`.
- Run `moon test --target native`.
- Run `moon fmt`.
- Run at least these CLI probes:
  - `pointer /a~1b/c~0d` on the document `{"a/b":{"c~d":5}}` (escaping).
  - a `replace` patch and an array `add` with the `-` append token.
  - a failing `test` op (must error, not panic).
  - `diff` between two documents (stdout must be a valid JSON array).
- Finish only after reporting the validation commands you ran and any remaining
  caveats.
