# MoonBit development

The following workflow applies when the task is MoonBit code.

## Compiler-Driven Work

Refactor and fix by compiler guidance, not by text. MoonBit is soundly typed and
`moon check` is fast, so let the compiler tell you *what* to change and *where*.

Loop: `moon check` (use `--output-json` or `--diagnostic-limit <N>` to group repeats, sync mode) →
fix the reported `path:line`s with `edit`/`multi_edit` →
re-check until clean.

To rename an API, add the new name, make the old one a deprecated alias,
and fix the deprecations the compiler then flags — far more reliable than a regex sweep.

Run `moon check` through `mbtx` (for example, `filename="@builtin/check.mbtx"`) as the primary fast feedback loop;
add `--diagnostic-limit 5` for focused diagnostics. It skips code
generation, so it is way faster than `moon build` or `moon test`. Use
`moon build` or `moon test` only when you need artifacts or test results.
After `edit` or `write` changes `moon.mod`, `moon.pkg`, `moon.work`, `.mbt`,
or `.mbt.md` inside a MoonBit module, the tool result may append bounded raw
feedback from module-root `moon check --diagnostic-limit 1`, starting with
`moon check:`; failures include `exit=<code>` or `exit=cancelled`. Treat it as
immediate/synchronous compiler feedback, and run an explicit `moon check --output-json` when you need
full diagnostics.

## Common `moon` subcommands

- `moon check`: type-check for compiler feedback; supports
  `--target` and `--diagnostic-limit <N>`. A successful check also updates
  `.mbti` files for checked packages whose preferred backend is covered.
- `moon test`: targeted or full tests; run plain `moon test` before
  `moon test --update`. Example: `moon test parser --filter "Parser::*"
  --diagnostic-limit 5`. Filters support glob syntax. This is THE way to
  exercise local package code: write a black-box `_test.mbt` test and run it
  with `--filter` — never probe local packages through `moon run -e`.
- `moon run`: executable package and CLI probes; package path goes before
  `--`, program arguments go after `--`. Example:
  `moon run --target native cmd/tomljson -- input.toml` (a file the `write` tool
  put in the workspace).
- `moon cram test`: durable CLI transcript tests under `tests/cram`;
  use `mooncram` blocks for stable help, examples, stdout/stderr, and exits.
  Example: `moon cram test tests/cram`.
- `moon fmt`: format MoonBit sources before finishing. Example:
  `moon fmt --check parser`.
- `moon build`: check build artifacts or backend-specific builds. Example:
  `moon build --target native cmd/tool --diagnostic-limit 5`.
- `moon doc` and `moon explain`: documentation and diagnostic help.
- `moon ide doc`, `moon ide outline`, `moon ide peek-def`,
  `moon ide find-references`, and `moon ide hover`: semantic navigation.
  Verified examples: `moon ide doc "@json.parse"`,
  `moon ide outline parser`, `moon ide peek-def parse --loc
  src/parser.mbt:42:9`, `moon ide find-references parse --loc
  src/parser.mbt:42:9`, and `moon ide hover parse --loc src/parser.mbt:42:9`.
- `moon add`, `moon remove`, `moon update`, and `moon tree`:
  dependencies and package registry/dependency inspection. Examples:
  `moon add moonbitlang/x`, `moon remove moonbitlang/x`,
  `moon update`, `moon tree`.
- `moon search`: search the package registry for modules by keyword when
  the exact module name is not known yet; then add the chosen module with
  `moon add`. Examples: `moon search base64`,
  `moon search json --limit 5 --json` (`--json` prints one result set as
  JSON for parsing).
- `moon clean`: clear `_build` when stale build output is suspected.
  Example: `moon clean`.
- `moon bench`: run benchmarks, e.g. `moon bench lib/parser`.
- `moon coverage analyze`: inspect test coverage when coverage matters.
  Example: `moon coverage analyze --package user/project/parser`.

## Ast based search with `moongrep`

```text
moonx moonbit-community/moongrep scan lib/parser --pattern 'match $(v:exp) { Some($(x:id)) => $(a:exp); None => $(b:exp) }' --json
```

The positional argument is the scan root (a directory or one `.mbt` file;
the default `.` is the whole repository), `$(name:kind)` marks a
metavariable, and `--json` writes one finding per line on stdout with
diagnostics on stderr. Pass each argument as its own element of
`@shell.Cmd("moonx", [...])` — there is no shell to split them, and no `--`
separator is needed before moongrep's own flags. The pattern language, output
fields, scan-root exclusions, and exit codes are in
the `moongrep` guide; read it before going beyond this
example rather than guessing the flags.

## MoonBit Project Setup

- Current MoonBit modules use `moon.mod`.
- Create `moon.mod` before running `moon check`; otherwise `moon` may walk up to
  an unrelated parent module.
- `moon.mod` is the module manifest: keep module `name`, `version`,
  module-level dependency versions, `warnings`, and module options there.
- Packages are directories with `moon.pkg`.
- `moon.pkg` is the package manifest: keep package imports, import aliases,
  test/wbtest imports, `supported_targets`, and package declarations there.
  Do not put package imports or aliases in `moon.mod`; do not put module
  dependency versions in `moon.pkg`.
- `_test.mbt` files are black-box tests. Use `_wbtest.mbt` only when tests must
  inspect private helpers.

Async IO is part of the standard library. Import the packages you use, such
as `moonbitlang/core/async/fs`, in `moon.pkg`. They need no registry dependency.
When adding registry dependencies, prefer `moon add moonbitlang/x` from the
module root so MoonBit writes a valid current version. Do not guess dependency
versions by hand.

After adding new module dependencies, run `moon update` from the module root if
`moon check` cannot find them.

## API Lookup And Probes

- Use `moon ide doc` before guessing unfamiliar APIs. Query symbols,
  methods, types, or imported package aliases, not broad English terms:
  `moon ide doc "StringView::split"` for methods,
  `moon ide doc "@json.parse"` for package functions, and
  `moon ide doc "@json"` for package exploration.
- `moon ide doc` accepts several queries per call and `*` globs in any
  position (`"String::*rev*"`, `"@string.*parse*"`, `"*parse*"`). When
  unsure of a name, batch candidates with a bare glob in one call —
  `moon ide doc "parse_float" "*parse*" "@string"` — misses report
  `No results found` inline while the others return. Globs can omit
  deprecated symbols, so an empty package glob does not prove absence:
  widen to a bare glob across packages. On a miss, never retry
  near-identical spellings or compile-probe blindly: re-query once with a
  bare glob or list the package and read the real names. Use
  `moon ide outline <dir-or-file>` for package symbols,
  `moon ide peek-def Symbol --loc file.mbt:line:col` for definitions,
  `moon ide find-references Symbol`, and `moon ide hover Symbol --loc
  file.mbt:line:col` for types.
- Use the `mbtx` tool for quick core-language probes and MoonBit
  automation; there is no `python`/`node` to fall back to.

## Validation Before Finish

Before finishing code work:

1. Run `moon check` through `mbtx` and confirm it is clean or the
   remaining diagnostics are understood.
2. Run targeted `moon test`.
3. Run `moon fmt` when formatting may have changed.
4. Run task-specific acceptance probes with `moon run`.

Use exact `moon` subcommands for final validation: `moon check` for fast
type-checking, `moon test` for tests, `moon run` for CLI probes, `moon cram
test tests/cram` for durable CLI transcript fixtures, `moon fmt` for formatting,
and `moon build` for build artifacts.

For CLI work, run probes that cover:

- file arguments;
- stdin mode;
- invalid input and exit/error behavior;
- stdout shape for successful output.

When CLI behavior should become a lasting fixture, add `tests/cram/*.md`
coverage with `mooncram` blocks and run `moon cram test tests/cram`. Keep
live or networked CLI tests opt-in, for example under `tests/live`.

Report the commands actually run and any remaining caveats.
