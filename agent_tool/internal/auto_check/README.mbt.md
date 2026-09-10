# agent_tool/internal/auto_check

The guardrails that run around a write. `write`, `edit`, `multi_edit`, and
`remove` all use this package to answer three questions about a change to
MoonBit source:

1. **Does the candidate content even parse?** — `gate_paths` and
   `content_parse_errors`, checked *before* the write lands.
2. **Did the change break the build?** — `count_errors`, whose tally drives the
   caller's revert decision.
3. **What should the model be told?** — `append_summary` and
   `format_parse_gate_errors`.

Compiler processes (`moon` and `moonc`) run directly with literal argument
arrays. The private collector bounds merged stdout/stderr by Unicode character
count, closes stdin immediately, and cancels the child on output overflow or
when the caller's timeout expires.

## Everything here fails open

Each entry point returns `None` (or the content unchanged) when it cannot do its
job — the path is not MoonBit, there is no project, `moonc` is missing, the
scratch directory is unwritable, the check timed out. A guard that could not run
never blocks a write.

That is a deliberate trade: an agent that cannot write files because a tool is
missing is useless, while an agent that writes a file the build then rejects has
merely produced a normal, recoverable error. The one thing the gate must never
do is *certify* content it did not actually parse to completion.

```mbt check
///|
async test "a non-MoonBit path is not gated, checked, or annotated" {
  inspect(
    @auto_check.content_parse_errors("notes.md", "# hi") is None,
    content="true",
  )
  inspect(@auto_check.count_errors("notes.md") is None, content="true")
  // `append_summary` returns the tool result untouched rather than None.
  inspect(
    @auto_check.append_summary("notes.md", "ok: wrote 4 chars"),
    content="ok: wrote 4 chars",
  )
}
```

## The parse gate

The gate runs `moonc syncheck` — moonc's parse-only front end — over candidate
content in a **scratch file**, before the content reaches its destination. A
rejection therefore leaves no broken file to delete or restore, which is what
makes it safe to run on every write.

Only lexer and parser diagnostics gate. Type and resolution errors do not: they
are a legitimate transient state mid-edit, and refusing them would stop an agent
from making a change in two steps.

```mbt check
///|
async test "the gate parses candidate content that never touches disk" {
  // `path` selects the input KIND only. Nothing reads or writes src/main.mbt.
  let clean = @auto_check.content_parse_errors(
    "src/main.mbt", "pub fn hi() -> Int { 1 }\n",
  )
  guard clean is Some(gate) else { fail("gate could not run") }
  inspect(gate.errors.is_empty(), content="true")
  inspect(gate.truncated, content="false")

  // An unterminated block is a parse error, so the gate flags it.
  let broken = @auto_check.content_parse_errors(
    "src/main.mbt", "pub fn hi() -> Int {\n",
  )
  guard broken is Some(gate) else { fail("gate could not run") }
  inspect(gate.errors.is_empty(), content="false")

  // A type error is NOT a parse error, so it passes the gate untouched.
  let unresolved = @auto_check.content_parse_errors(
    "src/main.mbt", "pub fn hi() -> Int { missing_name }\n",
  )
  guard unresolved is Some(gate) else { fail("gate could not run") }
  inspect(gate.errors.is_empty(), content="true")
}
```

`truncated` marks `errors` a **lower bound**, not a tally. Callers that compare
error counts before and after a change have to account for that, which is why it
is on the struct rather than folded into the error list.

### `gate_paths` — which input kinds to check

`syncheck` recognizes its input by *name*: `.mbt`, `.mbt.md` (where it parses
only ` ```mbt check ` fences), and an exact `moon.mod` or `moon.pkg`. `gate_paths`
returns the distinct kinds named by a path and its resolved symlink target, as
representative paths to hand to `content_parse_errors`.

Usually that is one entry. It is two only when a symlink **crosses kinds**:

```mbt check
///|
test "one entry per distinct syncheck input kind" {
  // A regular file: pass the same value twice.
  debug_inspect(
    @auto_check.gate_paths("src/main.mbt", "src/main.mbt"),
    content=(
      #|["src/main.mbt"]
    ),
  )
  // A symlink whose target shares its kind collapses to one check.
  debug_inspect(
    @auto_check.gate_paths("link.mbt", "real.mbt"),
    content=(
      #|["link.mbt"]
    ),
  )
  // A symlink that CROSSES kinds is checked both ways: moon may classify it by
  // the directory entry it globs OR by the file it resolves to, so a caller
  // rejects if either kind flags the content. The caller's own spelling is
  // listed first.
  debug_inspect(
    @auto_check.gate_paths("link.mbt", "doc.mbt.md"),
    content=(
      #|["link.mbt", "doc.mbt.md"]
    ),
  )
  // Only one side is a syncheck input.
  debug_inspect(
    @auto_check.gate_paths("link.mbt", "notes.md"),
    content=(
      #|["link.mbt"]
    ),
  )
}
```

An empty result means the gate does not apply — the caller writes without it.
Note which manifests are *not* syncheck inputs:

```mbt check
///|
test "manifests must be an exact basename, and moon.work is never gated" {
  debug_inspect(
    @auto_check.gate_paths("moon.pkg", "moon.pkg"),
    content=(
      #|["moon.pkg"]
    ),
  )
  debug_inspect(
    @auto_check.gate_paths("pkg/moon.mod", "pkg/moon.mod"),
    content=(
      #|["pkg/moon.mod"]
    ),
  )
  // `moon.work` and the legacy JSON manifests are not syncheck inputs.
  debug_inspect(@auto_check.gate_paths("moon.work", "moon.work"), content="[]")
  debug_inspect(
    @auto_check.gate_paths("moon.pkg.json", "moon.pkg.json"),
    content="[]",
  )
  // Not an exact basename.
  debug_inspect(
    @auto_check.gate_paths("foo.moon.pkg", "foo.moon.pkg"),
    content="[]",
  )
  debug_inspect(@auto_check.gate_paths("notes.md", "notes.md"), content="[]")
}
```

### `format_parse_gate_errors` — the model's only view of the breakage

Because rejected content never lands anywhere, the model cannot go read the
broken file. The excerpt in the report is all it gets, so each error renders as
`path:loc: message` followed by numbered source lines.

The compiler's own `context` excerpt is preferred when present; it is indented
two spaces and its trailing blank line dropped.

```mbt check
///|
test "the compiler's own excerpt is indented and reused" {
  debug_inspect(
    @auto_check.format_parse_gate_errors("src/main.mbt", "unused\n", [
      {
        loc: "5:2-5:2",
        message: "Parse error, unexpected token `end of file`.",
        context: "4 |  match x {\n5 |}\n",
      },
    ]),
    content=(
      #|["src/main.mbt:5:2-5:2: Parse error, unexpected token `end of file`.\n  4 |  match x {\n  5 |}"]
    ),
  )
}
```

When `context` is empty the excerpt is synthesized from the in-memory content
using the diagnostic's `loc` — one line of leading context plus the error span,
in the compiler's own `N |text` shape:

```mbt check
///|
test "a missing excerpt is synthesized from the candidate content" {
  let content = "fn main {\n  let x = 1\nlet y\n"
  debug_inspect(
    @auto_check.format_parse_gate_errors("src/main.mbt", content, [
      { loc: "3:1-3:6", message: "Parse error", context: "", },
    ]),
    content=(
      #|["src/main.mbt:3:1-3:6: Parse error\n  2 |  let x = 1\n  3 |let y"]
    ),
  )
}

///|
test "a diagnostic with no location renders as a bare header" {
  debug_inspect(
    @auto_check.format_parse_gate_errors("moon.pkg", "", [
      { loc: "", message: "Invalid configuration", context: "", },
    ]),
    content=(
      #|["moon.pkg: Invalid configuration"]
    ),
  )
}
```

At most five errors are rendered. Parse errors cascade, so a handful shows the
shape of the breakage without dumping pages of noise:

```mbt check
///|
test "the report is capped at five errors" {
  let errors : Array[@auto_check.ParseGateError] = [
    for i in 0..<8 => { loc: "", message: "e\{i}", context: "", }
  ]
  debug_inspect(
    @auto_check.format_parse_gate_errors("a.mbt", "", errors).length(),
    content="5",
  )
}
```

## `count_errors` — the tally behind a revert

After a write lands, `count_errors` runs `moon check --output-json` from the
containing module and tallies diagnostics by level. JSON Lines is used rather
than the human summary so `level == "error"` can be counted exactly instead of
inferred from warning-heavy prose.

```mbt check
///|
async test "a real check tallies errors separately from warnings" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-readme-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_readme\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/main.mbt",
      "pub fn bad() -> Int { missing_name }\n",
      create_mode=CreateOrTruncate,
    )
    let tally = @auto_check.count_errors("\{dir}/main.mbt")
    guard tally is Some(errors) else { fail("check did not run") }
    inspect(errors.error_count >= 1, content="true")
    inspect(errors.truncated, content="false")
    // `first_errors` renders as `path:loc: message`, the same shape the human
    // `moon check` output uses, so a reverted batch points straight at the site.
    inspect(errors.first_errors.length() >= 1, content="true")
  })
}
```

`first_errors` holds at most ten entries while `error_count` stays exact, so a
revert report can show the shape of an over-match without dumping a broken
build. When the capture budget overflows, `truncated` is set and both counts
become lower bounds — which only ever makes a caller's guard fire more readily,
never less.

## `append_summary` — the human-facing tail

The last step: run the bounded `moon check` from
`agent_tool/internal/moon_check` and append its rendered output to the tool
result. This is raw compiler output, deliberately not summarized.

```mbt check
///|
async test "a check summary is appended after the tool's own result line" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-readme-summary-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/auto_check_readme_summary\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/main.mbt",
      "pub fn bad() -> Int { missing_name }\n",
      create_mode=CreateOrTruncate,
    )
    let result = @auto_check.append_summary(
      "\{dir}/main.mbt",
      "ok: wrote 37 chars",
    )
    inspect(
      result.has_prefix("ok: wrote 37 chars\nmoon check:\n"),
      content="true",
    )
    inspect(result.contains("Error:"), content="true")
  })
}
```

The check runs from the module or workspace root rather than the file's own
directory, so an edit in one package surfaces breakage it caused in another.
