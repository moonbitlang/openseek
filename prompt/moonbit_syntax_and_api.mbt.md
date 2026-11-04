# MoonBit Syntax And Library APIs

Each language section states its rules and links a verified example: a script under
`share/examples/` that CI type-checks under deny-warn and runs, shown inline.

## Writing mbtx programs

A script is a whole program: front matter holding its imports, then vanilla
MoonBit.

- The file opens with the front matter: a `---` line, the `import { ... }`
  block in `moon.pkg` syntax, and a closing `---` line. Nothing, not even a
  comment, comes before the opening `---`.
- Import every package it uses separately, core packages included and by
  their real path: `moonbitlang/core/encoding/base64`, not
  `moonbitlang/core/base64` — `moon ide doc "@base64"` prints the path.
- Keep `async fn main` for async IO.
- Helpers that run an async command/IO are `async fn` too;
  a plain `fn` cannot call them. (so async is contagious)
- There is no `await`: async calls are written normally, and async functions
  and tests are marked `async`.
- Use `println` (no `print`).

A minimal `moon check` script:

[share/workflow/check.mbtx](../share/workflow/check.mbtx)

`mbtx` is powerful since it can reuse the whole MoonBit ecosystem

## CLI Parsing with moonbitlang/core/argparse and env

- Read `@env.args()[1:]` (from `moonbitlang/core/env`; the `[1:]` skips the
  executable name) when the script only forwards or glances at its arguments —
  the `check.mbtx` above passes them straight through to `moon check`.

Below is a complete example of CLI parsing using argparse:

[share/examples/cli_count_input.mbtx](../share/examples/cli_count_input.mbtx)

For a nonzero exit,import `"moonbitlang/x/sys"`, and call `@sys.exit(1)`.

## Shell EDSL with moonbitlang/core/async/shell

Use `@shell.Cmd` to run an external program and capture its output.

Shell utilities can be expressed in MoonBit, including on Windows:

| Command     | Alternatives     |
|-------------|------------------|
| ls          | @fs.readdir(dir) |
| find        | @shell.glob(pattern), spread into args as `[..files]` |
| cat         | @fs.read_text(p) |
| head/tail   | slice the split text; wc -l → count it |
| grep        | `@builtin/rg.mbtx` (ripgrep flags and regex, not POSIX grep), or .split("\n").filter(...) on captured output |
| sort/uniq   | .sort(), a Set, or a Map |
| pwd         | @env.current_dir(); printenv → @env.get_env_var(name) — both `String?` |
| mkdir -p    | @fs.mkdir(d, recursive=true) |
| test -f     | @fs.exists(p); test -d → @fs.kind(p) is Directory |
| echo/printf | println |
| rm/mv/cp    | the `remove` and `write` tools; `remove` requests approval when automatic deletion is not allowed; do not bypass a refusal |
| sh -c, xargs, make | write the logic as MoonBit statements |

`@fs.kind(p)` returns a `FileKind` enum — `Directory`, `Regular`, `SymLink`,
`BlockDevice`, `CharDevice`, `Pipe`, `Socket`, `Unknown` — which does **not**
implement `Show`, so never interpolate or `println` it directly:
`"\{@fs.kind(p)}"` is a type error. Test it with `is`
(`@fs.kind(p) is Directory`, `@fs.kind(p) is Regular`); `match` it only when
you need the full set. To print one for debugging, use `"\{Repr(k)}"`

An example of using rg in `mbtx`:

[share/examples/command_output.mbtx](../share/examples/command_output.mbtx)

Use `moon ide doc @moonbitlang/core/async/shell` for the full API.

For compiler feedback, stream the line-delimited JSON from one `moon check`
rather than collecting it and parsing it afterward:

[share/examples/check_diagnostics.mbtx](../share/examples/check_diagnostics.mbtx)

## Guarded edits through PTC

A script may run `moon check --output-json` itself to find its targets:

[share/examples/ptc_guarded_edit.mbtx](../share/examples/ptc_guarded_edit.mbtx)

## Delegating from a script

The following example starts child agents through the host-tool SDK:

[share/examples/subagent_scouts.mbtx](../share/examples/subagent_scouts.mbtx)

## CI monitoring program

This bounded monitor discovers the current branch's PR, watches registered
checks, then gives late workflows one settle interval to appear:

```mbtx
---
import {
  "moonbitlang/core/async",
  "moonbitlang/core/async/shell",
}
---

async fn main {
  @shell.Cmd("gh", ["pr", "view", "--json", "number"]).output().check()
  for pass in 0..<12; previous = None {
    ignore(
      @shell.Cmd("gh", ["pr", "checks", "--watch"]).output(),
    )
    let snapshot = @shell.Cmd("gh", ["pr", "checks"]).output()
    let stdout = snapshot.stdout()
    let count = [..stdout.split("\n")]
      .filter(line => !line.is_blank())
      .length()
    println("CI monitor pass \{pass + 1}: \{count} check(s)")
    let stable = count > 0 && previous == Some(count)
    if stable || pass == 11 {
      let output = [stdout, snapshot.stderr()]
        .filter(text => !text.is_blank())
        .join("\n")
      if !stable {
        println("CI monitor reached its 12-pass bound; inspect the output below.")
      }
      println <| (
        $|\{output}
        $|gh pr checks exit=\{snapshot.exit_code()}
      )
      return
    }
    @async.sleep(10_000)
    continue Some(count)
  }
}
```

The single `mbtx` call hands itself off after five seconds; do not poll it.

## Method resolution

Do not find edit sites with `regex` or by syntax/AST-based reasoning — `expr.method()`
resolves by the *type* of `expr`, so text matching hits the wrong occurrences,
comments, strings, and other types, and misses spacing variants; only the type
checker knows which uses are real.

## Test annotations

To keep a test but not run it, annotate it `#skip("reason")`: still
type-checked, but run only with `--include-skipped` (or `-i <index>`, which
implies it) — plain `moon test --filter` will not run it. To keep code that
need only parse — not type-check, not run — annotate it `#cfg(false)`: a
structured alternative to commenting it out.

## Packages, imports, and visibility

Files inside one package share a flat namespace; file names do not create modules.

- Declare executable packages with `pkgtype(kind: "executable")`. The legacy
  `"is-main"` option is deprecated; use `pkgtype` instead.
- Treat files like Go package files: splitting a package into small focused
  `.mbt` files does not affect visibility, and is preferred when it avoids
  large fragile edits.
- Import local packages by their full package path from `moon.mod` plus the
  package directory. For module `name = "user/toml"` and package `lib/moon.pkg`,
  import `"user/toml/lib"` and call it as `@lib.parse(...)`; import
  `"user/toml/src"` and call `@src.name(...)` for a `src` package.
- Configure imports in `moon.pkg`, not in `.mbt` files. Use `@alias.name` in
  code to call imported package APIs.
- Do not import `moonbitlang/core` as a package. Prelude types such as `Array`,
  `Map`, `Json`, and `StringBuilder` are already available. Import specific
  core subpackages only when needed, for example
  `moonbitlang/core/string` for typed `@string.from_str` parsing,
  `moonbitlang/core/argparse` for CLI parsing, or `moonbitlang/core/json` for
  `@json.parse`.
- Use `pub fn` for APIs called from another package. Plain `fn` is private.
- Types are abstract by default: a plain `struct X { ... }` (no `pub`) leaves
  only the type *name* visible to other packages — they can call its `pub`
  methods but cannot construct it or read its fields. Prefer that over
  `pub struct X { priv ... }` when every field is internal: the per-field
  `priv` markers are redundant and `pub` (readonly) exposes nothing when no
  field is readable. Reserve `pub` for types with readable fields, and
  `priv struct X` for a type whose name itself must not leave the package.

## Top-level declarations

- Top-level MoonBit items are separated by `///|`.

To add NEW top-level code (functions, tests, types) to an existing file,
append at end of file: `edit` with an empty `old_string` and any
`start_line` past the last line (e.g. 999999) — top-level order does not
matter in MoonBit, and an append cannot mismatch an anchor. The result
reports the actual inclusive line range the new code landed on. Insert
mid-file only when grouping related code.

## Manifest examples

Example module skeleton:

```moon.mod
name = "username/project"
version = "0.1.0"
preferred_target = "native"

import {
  "moonbitlang/x@0.5.5", // import registry modules(`username/modulename`) with version
}
warnings = "+test_unqualified_package" // `moon explain --diagnostic test_unqualified_package` to learn more
```

Example native CLI package:

```moon.pkg
import {
  "moonbitlang/core/async",
  "moonbitlang/core/async/fs", // package
  "moonbitlang/core/async/stdio",
  "moonbitlang/core/argparse",
}

supported_targets = "+native"

pkgtype(kind: "executable")
```

## Syntax And API Discipline

- Prefer `Int32` over `Int` for 32-bit integers. They are aliases today, but
  the current toolchain names the type and its APIs `Int32`; use `Int32` in
  new annotations and when parsing integers.
- Syntax the compiler rejects, each shown working in the verified example
  below: parameters and `self` are never `mut`, a mutable local is
  `let mut` (there is no `var`), and only a struct field you assign is
  declared `mut field : T`; keywords such as `test`, `type`, `method`,
  and `ref` cannot name a binding; negation is the `!` prefix, not `.not()`;
  a bare `{}` is ambiguous and an error under deny-warn, so an empty map is
  `Map([])` and the no-op expression is `()`; match arms are separated by
  newlines, never `|`; lambdas are arrows (`x => ...`, `(a, b) => { ... }`),
  and an async lambda is `async fn(x) { ... }`.

[share/examples/syntax_basics.mbtx](../share/examples/syntax_basics.mbtx)

## Checked Error Handling

Errors are a checked effect on the function, not a value it returns: a parser
returns `Json` on success and its failures travel in `raise`. Call raising
functions directly from functions marked `raise` and handle errors only at a
real boundary, such as a CLI path that needs its own stderr text. Use
`fail("message")` for a one-off internal failure and a small `suberror` for
user-facing errors; never encode failure as `null`, `()`, or another
success sentinel. `async fn` raises by default; mark an async helper `noraise`
when it must not. In tests, call raising functions directly and let a raise
fail the test. The verified example, compiled and run by CI:

[share/examples/checked_errors.mbtx](../share/examples/checked_errors.mbtx)

## Strings, Maps, JSON, And Tests

- String interpolation is `\{expr}` and works for any `Show` value; `\(expr)`
  is not MoonBit. Build strings with interpolation rather than `+`, which
  needs a `String` on both sides. Multi-line raw strings use `#|` lines and
  interpolated ones `$|` lines.
- `s[i]` is a UTF-16 code unit, not a `Char`; literals adapt to the expected
  type, so never write casts such as `UInt16(92)`. To compare a `Char`
  variable, write `s.get_char(i) is Some(c) && c == ch`, not `is Some(ch)`:
  a lowercase name in a pattern binds a new variable.
- `String` compares in SHORTLEX order (length first, then code units), so the
  default sort is deterministic but not dictionary order; sort with an
  explicit comparator when a reader expects dictionary order. `sort` and
  `sort_by` work in place and return `Unit`; `rev` returns a new value; for a
  sorted directory listing pass `@fs.readdir(dir, sort=true)`.
- Slices are zero-copy `StringView`s whose offsets clamp instead of
  panicking; `map[key]` panics when the key is missing, `map.get(key)`
  returns `T?`. Parse with `@string.from_str` and an annotation on the
  binding, `let n : Int32 = @string.from_str(text)` (import
  `moonbitlang/core/string`); it raises on bad input. Do not write
  `@string.from_str[:Int32](text)` or `@string.from_str[Int32](text)`.

The verified example, compiled and run by CI:

[share/examples/strings_and_views.mbtx](../share/examples/strings_and_views.mbtx)

- Build JSON values with the `Json(value)` constructor — it accepts any value
  whose type implements `ToJson`. Use `null` for a JSON null and
  `Json::empty_object()` for an empty object. Do not create JSON with
  `Json::Object(...)`, `Json::String(...)`, or `Json::True`; use variants
  mainly for pattern matching.
- For integer JSON numbers, use `Json::number(n.to_double(), repr=text.to_owned())`
  when you need output to preserve integer spelling.
- For JSON CLI stdout and tests, use `json.stringify()` or inspect
  `json.stringify()`; do not rely on `println(json)` or Debug/Show snapshots.
- In black-box tests for a library returning `Json`, match `Json::Object(...)`,
  not `@library.Json::Object(...)`.
