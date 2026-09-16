# Edit Tool

`edit` replaces exact text in `arguments.path`. It is intended for targeted
code changes where overwriting the whole file would be unnecessarily broad.

## Design Rationale

`edit` uses exact `old_string` replacement instead of a patch language because
the host can validate the change with simple, deterministic rules. `start_line`
anchors the edit near the caller's intended location, then the first matching
`old_string` at or after that line is replaced. Optional `end_line` narrows the
search when the caller wants a tighter inclusive 1-based line range. Because
the line anchor carries the location, `old_string` can be the small exact span
to replace instead of a large surrounding block.

An empty `old_string` switches the tool to insertion: `new_string` is inserted
at the start of `start_line` (use `start_line` = last line + 1 to append at end
of file). Rejecting empty-and-empty (both `old_string` and `new_string` empty)
and identical replacements protects against no-op edits. The tool is designed
for small surgical changes; if a file needs a complete rewrite, `write` is the
clearer API.

MoonBit manifests get the same safety check as `write`: edits that would create
legacy `moon.mod.json`, JSON-style `moon.mod` or `moon.pkg`, or `moon.pkg` with
`#` comments are rejected before the original file is overwritten.

Edits to syncheck inputs (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`) get a
pre-write syntax gate: the edited result is parsed standalone (`moonc syncheck`
in a scratch file, no project context needed), and an edit that would introduce
new lex/parse errors is rejected with the file left untouched — the call fails
with the errors and numbered excerpts synthesized from the would-be content.
"Introduced" compares parse-error *counts* against the original content parsed
the same way (not diagnostic identities, because an edit shifts the line numbers
of every pre-existing error below it), so a file that already fails to parse
still accepts edits, including partial fixes. Type errors never trigger the
gate; in `.mbt.md` only the checked (`mbt check` / `moonbit check`) fenced blocks
are parsed. `revert_on_parse_errors=false` opts out.

## API Style

Use a focused exact string near the starting line:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "Use moon check before moon test.",
  "new_string": "Use moon check before moon test, and inspect failures before editing.",
  "start_line": 42
}
```

Use `end_line` when the same text appears shortly after the intended location
and the edit should stay inside a tighter range:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "moon check",
  "new_string": "moon check --diagnostic-limit 1",
  "start_line": 120,
  "end_line": 140
}
```

## Arguments

| Name          | Type    | Required | Notes |
| ------------- | ------- | -------- | ----- |
| `path`        | string  | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `old_string`  | string  | yes | Exact text to replace. Empty string switches to insertion at `start_line`. |
| `new_string`  | string  | yes | Replacement (or inserted) text. For replacement it must differ from `old_string`; empty-and-empty is rejected. |
| `start_line`  | integer | yes | 1-based first line of the search/replace range. The first match at or after this line is replaced. |
| `end_line`    | integer | no  | 1-based last line of the search/replace range. Defaults to the file end. |
| `revert_on_parse_errors` | boolean | no (default `true`) | Reject an edit whose result would introduce new lex/parse errors into a syncheck input (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`), leaving the file untouched and returning the errors with excerpts. In `.mbt.md` only the checked fenced blocks are parsed. Set `false` only to intentionally produce non-parsing content. |
| `revert_when_errors_above` | integer | no (off) | Post-write guard. `moon check` runs from the file's module before and after the write; if the edit introduced more than this many errors the tree did not have (counted by diagnostic identity: path, code, message, so line shifts never count; `0` = any) the file is restored and the call returns `is_error` with the introduced sites. If the check cannot run, a guarded edit is not written. |
| `revert_when_warnings_above` | integer | no (off) | The same guard for warnings. One guarded edit per diagnostic at `0` is the unit of a mechanical warning-fix script (see `share/workflow/fix-deprecations.mbtx`). |
| `replace_all_preview` | boolean | no (default `false`) | Preview mode: the file is **not** modified. Every match of `old_string` in the range is listed with surrounding context lines, plus a ready-to-review `multi_edit` edits array (capped at 40 sites; several matches on one line collapse into a single whole-line entry). |

Legacy calls with `replace_all=false` are tolerated, but `replace_all=true` is
rejected. Use `multi_edit` when a compiler diagnostic suggests several known
locations in one file should be fixed efficiently.

## Preview → select → apply → verify

`replace_all_preview=true` exists for the edits the compiler cannot vet:
comments, doc prose, `.mbt.md` text, string literals. The pipeline is
complementary, not overlapping — the **preview** shows every textual match so
the agent can filter the sites the type checker will never flag; the selected
subset is applied with **`multi_edit`** (line numbers refer to the file as
previewed); and `multi_edit`'s own gates — the pre-write parse gate and the
post-write `moon check` auto-revert — **verify** what the compiler *can* see.
Neither step substitutes for the other.

For typed-code renames the compiler loop stays the better tool (add the new
name, deprecate the old, fix what `moon check` flags): text matches cannot see
types. A useful secondary effect of the preview is exactly that signal — a
match list that turns out to be code-heavy or type-ambiguous is the cue to
switch to the compiler loop *before* any damage.

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for edit or argument failures. The string body
has one of these shapes:

- `"ok: replaced <n> occurrence(s) at line <line> in <path>"` on success.
  If the target is `moon.mod`, `moon.pkg`, `.mbt`, or `.mbt.md` inside a
  MoonBit module, a check line follows: `moon check: ok — 0 errors, <w>
  warning(s)` plus the first warning, or `moon check: <e> error(s), <w>
  warning(s)` plus the first error sites; a check that could not run says so
  (`moon check: timed out`).
- `"reverted: the edit introduced <what> the tree did not have, so <path> was
  restored to its pre-edit content."` with `is_error=true` — a post-write
  guard fired; the body lists the introduced sites and, when the baseline
  already had errors, the reach caveat.
- `"not applied: a revert_when_*_above guard was requested, but moon check
  could not verify the tree (<reason>); <path> was NOT modified"` with
  `is_error=true`.
- `"rejected: the edit would introduce <n> new parse error(s) in <path>, ..."`
  with `is_error=true` — the pre-write syntax gate refused the edit and the
  file is untouched; the body excerpts the would-be content at each error and
  says how to retry.
- `"error editing <path>: old_string not found"` — no exact match was found in the selected range.
- `"preview: <n> match(es) at <k> site(s) for old_string in <path> (file NOT modified)"` — `replace_all_preview=true`; the body lists each site with context and ends with the reviewable `multi_edit` edits array.
- `"error editing <path>: replace_all=true is no longer supported; use replace_all_preview=true to review every match as a multi_edit edits array, or multi_edit with explicit line-anchored edits"` — the call requested a blind global replacement.
- `"error editing <path>: moon.pkg use // for comment syntax, not #"` or similar
  manifest-guard messages — the replacement would likely break MoonBit package
  discovery.
- `"error editing <path>: <error>"` — reading or writing failed.
- `"error: edit requires arguments.<field>"` — payload was an object but missed a required field.
- `"error: edit requires object arguments"` — payload was not a JSON object.

Every response also carries `data` (never shown to the model; returned to
PTC scripts and kept in the transcript): `outcome` is one of `applied`,
`reverted`, `rejected`, `unverified`, `preview`, `not_found`, `error`, with
`path` and, for writes, `lines` (`start`/`end`). A kept edit in a MoonBit
project adds `check` (`error_count`, `warning_count`, `truncated`, first
`errors`); a guarded edit adds `baseline` counts, `introduced_count` and
`removed_count` per severity (on kept and reverted outcomes; an `unverified`
outcome has none of them), and `reach_caveat`; a
reverted one adds `reason` (`introduced_errors`, `introduced_warnings`,
`unverified`), `introduced` (`errors`, `warnings`, `complete`), and
`restore_failed` (also set when the file no longer held the edit at restore
time, so another writer's content was left alone; the comparison and the
restore are two operations, so a save landing in the instant between them is
still overwritten — the window is a file read, not the whole check);
`introduced` lists at most 20 sites per severity and says how many it left
out in `errors_omitted` / `warnings_omitted`, while its `complete` refers to
the comparison itself; a rejected one adds `parse_errors`. Guards refuse an
overflowed check capture (`unverified`), since its lists are windows, not the
whole. A filesystem failure inside the edit (a missing or unreadable file)
is `error editing <path>: edit failed: <error>` with `outcome: error`; a
response with no `data` at all can only come from the dispatcher, before the
tool ran. Guarded writes and restores go to the file's resolved target,
pinned before the baseline check, so a link retargeted during a check cannot
redirect them.

## Example

```moonbit check
///|
test "edit tool advertises the expected schema" {
  let tool = @edit.definition()
  assert_eq(tool.name, "edit")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"path\""))
  assert_true(text.contains("\"old_string\""))
  assert_true(text.contains("\"new_string\""))
  assert_false(text.contains("\"replace_all\""))
  assert_true(text.contains("\"start_line\""))
  assert_true(text.contains("\"end_line\""))
  assert_true(text.contains("\"required\""))
}
```

```moonbit check
///|
async test "edit tool applies a focused code change through the registry" {
  @vfs.with_tmpdir(tmpdir => {
    let path = "\{tmpdir}/openseek-edit-readme-example.mbt"
    @vfs.FileSystem({
      "openseek-edit-readme-example.mbt": "fn greet() -> String {\n  \"hello\"\n}\n",
    }).write_to(tmpdir)

    let tools = @agent_tool.Tools([@edit.definition()])
    let arguments : Json = {
      "path": "\{tmpdir}/openseek-edit-readme-example.mbt",
      "old_string": "  \"hello\"",
      "new_string": "  \"hello, MoonBit\"",
      "start_line": 2,
    }

    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_edit_greeting",
        name="edit",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 2 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "fn greet() -> String {\n  \"hello, MoonBit\"\n}\n",
    )
  })
}
```
