# Structural search with `moongrep`

`moonx` runs `moongrep`, a structural (AST-based) search and lint tool for
MoonBit. Use it when a text grep cannot express the shape you need ("all
`inspect` calls whose `content` is a literal", "every `match` over
`Some`/`None`", "every call of one function nested inside another"). No `--`
separator is needed: the arguments after the coordinate are moongrep's own.

```mbtx
///|
import {
  "moonbitlang/async",
  "moonbitlang/async/shell",
}

///|
async fn main {
  let out = @shell.Cmd("moonx", [
    "moonbit-community/moongrep", "scan",
    "--pattern",
    "match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }",
    "--output-json",
  ]).output()
  println("exit=\{out.exit_code()}")
  // Whole-repo scans can match many nodes; keep the printed excerpt bounded.
  // Slicing clamps, so a shorter output needs no length guard.
  println(out.stdout()[:2000])
}
```

## Scan roots and exclusions

`scan` (and `lint`, which prepends the embedded builtin rules) scans
recursively from the scan root — a directory or a single `.mbt` file; the
default root `.` means the whole repository, which is the typical use.
Hidden entries — any child name beginning with `.` (case-independent) —
plus `_build`, `node_modules`, and `target` are skipped by default;
`--exclude <name-or-path>` skips more entries. These exclusions apply to
child entries during traversal: an explicitly selected scan root is still
inspected even when its final path component matches one of the rules.

Non-hidden tool/eval/worktree directories are NOT in the default exclusions:
a whole-repo scan descends into them and duplicates findings across nested
checkouts, or aborts on a dangling symlink inside one. Hidden ones
(`.claude`, `.worktrees`, `.moonagent`, `.repos`) are already covered by the
leading-dot rule; exclude the rest up front — in this checkout:
`--exclude editor/codemirror/demo`.

## Output

Use `--output-json` for agent-friendly output: one JSON object per finding
with `file` (relative to the scan root, often `./`-prefixed), `rule_id`,
`description`, `range` (1-based `line`/`column`), `matched_source`, and
`source_context`; a scan with zero findings writes nothing and still exits 0.
When parsing records with `@json.parse`, integer fields such as
`range.start.line` pattern-match as `Number(value)` (a `Double`; call
`.to_int()` on it), not `Int`.

A whole-repo scan can match many nodes — `@shell.Cmd(...).output()` cannot
capture unbounded output, so a large scan hits the shell's output-limit error
— stream with `.each_line()` (one record per callback line) to count or
aggregate findings, and redirect stderr with `stderr=ToFile(...)` so skip
warnings do not flood the merged output.

`--rules <dir>` and `--rule <file>` load YAML rule files, `--disable
<rule-id>` drops a loaded rule, and `--verbose` traces traversal on stderr.

## Patterns

A `--pattern` is a MoonBit *expression* containing `$(name:kind)`
metavariables — `exp`, `id`, `const`, `arg`, `pat`, `type` — plus `$_` to
match anything without capturing. Matching is on the untyped CST: whitespace
and comments do not matter, but syntax shape does (`Some(1)` does not match
`Some($(some:id))`; `Ok`/`Err` branches do not match a `Some`/`None`
pattern). A metavariable used twice must capture equal structure. `--guard
'{$name: "regex"}'` filters `id` and `const` captures (substring match unless
anchored with `^...$`).

When a pattern surprises you,
`moonx moonbit-community/moongrep dump --expr '...'` or
`moonx moonbit-community/moongrep dump --impl 'fn f { ... }'` prints the CST
of a snippet. `moonx moonbit-community/moongrep docs RuleSpec` and
`moonx moonbit-community/moongrep docs CLISpec` print the full specs.

## Lint rules

The builtin `lint` rules are advisory style checks — `catch_all`, for
instance, flags deliberate `catch { _ => () }` swallows. Treat rule counts as
signal, not a bug list, and read `matched_source` before acting on a finding.

## Exit codes

0 for help, dump, findings, no-findings, and parse warnings (no-match is NOT
grep's 1); 2 usage; 3 invalid dump input; 4 rule-source failure; 5 invalid
rule content (including a `--pattern` that is not a valid MoonBit
expression); 6 missing/unreadable scan input; 7 output failure.

The scanner follows symlinks, so a broken symlink anywhere under the scan
root aborts the whole scan with 6. Source blocks whose syntax the bundled
parser does not know yet (e.g. nested record-spread `is` patterns) are
skipped with a stderr warning while exit stays 0 — treat skipped blocks as a
blind spot.
