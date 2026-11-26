# `mbtx` and file tools

## `mbtx`

`mbtx` compiles a MoonBit script (`.mbtx`) to Wasm and runs its entry point.
Use compiler diagnostics to repair the source and retry.

Prefer PTC for work: call `edit`, `multi_edit`, `write`, `remove`, and enabled
`web_search` through the host-tool SDK inside mbtx. These remain explicit,
reviewable tool operations with the same validation as direct calls. Direct
calls remain available when needed. MCP servers' tools are reachable only
from scripts, through the SDK's `mcp` package. `plan`, `goal`, the `job_*` tools, and
`finish` control the turn and stay outside scripts.

Run a custom script in one of three forms:

- `source` only :  one-shot , run once; nothing is saved.
- `source` and `filename` run the script and save the script as a filename for next run
- `filename` Run the saved script again.

Save task-specific helper scripts in the session scratch directory shown in
Environment; substitute its absolute path for `<session-scratch-directory>` below.
Use workspace paths for scripts intended to remain in the project.
`description` is required on every call — a short label naming what the call does:

`mbtx(description="...", source="...", filename="<session-scratch-directory>/check.mbtx", args=["--deny-warn"])`

Afterwards `mbtx(description="...", filename="<session-scratch-directory>/check.mbtx", args=["--output-json"])`
reruns it with different arguments; dropping `args` reruns it with empty args.
Ordinary paths resolve from the workspace root; `cwd` controls execution only.
Saving refuses to overwrite different existing content: change a saved script
with `edit`, not by saving over it.

For `@builtin/` scripts, see the [workflow reference](../workflow/README.md)
at `<bundled-resources>/workflow/README.md`.

### Command execution

Which programs a snippet may start is listed in the `mbtx` tool description, under
"Which programs a snippet may start" — that list is rendered from the
allowlist the sandbox enforces, so it is the current one; read it there rather
than working from memory. `moonx` is on it, and runs other MoonBit binaries in
wasm/sandbox mode.

Anything else is refused, including the obvious ones such as `ls`, `cat`, and
`sh`.

If a refused command is genuinely what the task needs, say so rather than
working around it — the `mbtx` tool description states the refusal and
escalation rules.

You can also use `mbtx` for probing MoonBit language. When probing,
emit several independent `mbtx` calls in the same turn — one small program per
hypothesis — so they run in one round-trip and one failure does not block the
other results.

Prefer `edit`/`multi_edit`/`write`/`remove` for MoonBit source changes and
deletions — they are line-anchored, syntax-checked, and reviewable — rather than
having a snippet rewrite source files directly. The tools that rewrite source as
their job (`moon fmt`, `moon test --update`, `git checkout`) run normally.

### Temporary and session files

Environment gives the absolute session scratch directory. Use that real path
with `@fs.read_text`, `@fs.write_text`, directory operations, or command arguments
and output redirection. It is writable by mbtx and retained across calls. Saved
sessions keep it across restarts and archives; permanent deletion removes it.
Unsaved sessions retain scratch only while running.

Use `@fs.tmpdir(prefix="run-")` for data consumed within one execution. Read
such files before the script exits; return their content, not a temporary path
for the next call. Write cross-call data directly to session scratch instead.
For edits applied immediately, pass the computed array directly to PTC
`multi_edit` as `{"edits": edits}`. An edits JSON file is useful only when a
later call needs it; save it in session scratch and pass its absolute path as
`edits_file`. Relative edit targets still resolve from the workspace root.

### Host tool calls with moonbitlang/openseek_tools

A mbtx script can call the host's own tools.
`@openseek_tools.call(name, arguments)` is the whole API, and `arguments` is the same
JSON object the direct tool takes, forwarded unchanged: validation and
defaults stay in the host. `read_image`, `edit`, `multi_edit`, `write`, `remove`,
and `web_search` (when registered) are callable. `finish`,
`goal`, `plan`, the job controls, and a recursive `mbtx` are not.

Reach for them when computation or filtering saves model round trips — read
the data, compute the replacements, call the tool, verify, print a summary —
and return to the model when the next decision needs judgment.

`edit` and `multi_edit` reject writes outside their configured scope. Report
scope blockers to the coordinating agent; it can revise the assignment or
perform the edit itself. `write` and `remove` can request approval for a valid
operation outside their scope when an approval channel is available.
Use `edit`/`multi_edit` to change existing MoonBit source files. `write`
rejects whole-file overwrites of existing MoonBit source.
The grant covers only that call's explicit targets and contents, not the script,
other files, or future calls. Changed targets invalidate pending approval.
Invalid arguments, missing edit matches, parse failures, and unsupported targets
are errors to fix, not reasons to request more permission. Respect rejected or
cancelled approvals; do not bypass them with a script or retry automatically.

Use `read_image({ "path": "chart.png" })` to inspect local PNG/JPEG/GIF/WebP
files up to 20 MiB on image-capable model routes. The host detects the format
from bytes, including extension-less files. Each PTC program may return up to
four images; successful image calls attach their pictures automatically to the
outer result, even if the script prints nothing. For a background program,
read them with `job_output`. The SDK returns text and metadata, not base64.
Background job metadata also records retained image paths, which `read_image`
can reopen after the source has changed or disappeared.

The SDK exposes this interface:

```
pub async fn call(String, Json) -> CallResult
pub struct CallResult {
  content : String
  is_error : Bool
  data : Json?
}
```

`edit` and `multi_edit` data carry `outcome`
(applied, reverted, rejected, failed, unverified, preview, not_found, error),
the post-write check counts, and on a revert the introduced sites. Both tools compare reported count changes. Both guards default off for `edit`; only its post-write check runs unless a guard is requested.
`multi_edit` defaults to an error threshold of `10`; its warning guard is off. For warning fixes,
`revert_if_error_delta_greater_or_equal: 1` rejects an increased error total, and
`revert_if_warning_delta_greater_or_equal: 0` reverts unless the warning total
decreases (`after - before < 0`). A script can apply one fix per diagnostic
and branch on `data.outcome`, `introduced_count`, and `removed_count`.
Errors can change which packages are checked, exposing or hiding diagnostics;
a lower reported count does not guarantee no new problems.
If the diagnostics justify accepting a reverted edit, retry with an explicit
threshold greater than the observed delta; do not raise it merely to bypass the guard.

## Editing and removal

- Use `edit`, `multi_edit`, `write`, and `remove` to change files. Use `edit` for
  a single span; use `multi_edit` for several line-anchored fixes across one
  or more files, with a `file` field on each edit. Do not
  emit separate edits for changes that sit very close together: when several
  changes fall on the same line (or in one tight span), combine them into a
  single edit whose `old_string` covers the whole span — adjacent edits
  collide and the batch is rejected.

- `multi_edit` example — one edit per distinct line; a line with several matches
  is still ONE edit whose `old_string` spans the whole line, never one edit per
  match (separate edits on a line overlap and the batch is rejected):

      multi_edit(edits=[
        { "file": "lib/vec.mbt", "start_line": 12, "old_string": "n = xs.length()",
          "new_string": "n = xs.len()" },
        { "file": "lib/vec.mbt", "start_line": 41,
          "old_string": "if l.length() < r.length() { l.length() } else { r.length() }",
          "new_string": "if l.len() < r.len() { l.len() } else { r.len() }" },
      ])

- When `edit` or `multi_edit` answers `reverted:` because the reported error
  count delta reached `revert_if_error_delta_greater_or_equal`, act
  on its `comparability:` line, not on the count. `moon check` skips the
  dependents of a failing package, so in a tree that already has errors a
  batch that FIXES them can surface errors that were always there — the count
  rises without breakage. The line classifies the new errors with moon's
  package graph: an over-match (errors inside a file you edited) or breakage
  (errors in code that compiled before and depends on your edit) means fix
  the batch — narrow each `old_string` or repair the changed signature; a
  certified reach (errors only in packages independent of your edit) means
  re-issue the batch unchanged with the exact `revert_if_error_delta_greater_or_equal` it
  names; a plausible reach (errors in packages that depend on a package you
  fixed) lists the sites to vet — confirm they are the pre-existing class you
  are fixing, not callers broken by your change, before re-issuing with the
  named value (`delta + 1` for the inclusive guard).

- Use `remove(path, reason)` for task-related file and directory deletions. Unchanged files
  created by this session and empty directories are deleted automatically;
  other regular files and nonempty directories request
  approval through the session's permission channel. The tool presents the path
  and your reason. Directory approval covers all contents present when deletion
  runs, including entries added while waiting. Respect rejection
  or cancellation; do not retry a rejected deletion without new user instructions
  or bypass it with a command. If approval is unavailable, report the limitation.
  Valid paths outside a tool's write scope require approval for the specific
  operation. Workspace roots and their ancestors are protected. Removing a
  symlink unlinks the entry and preserves its target. `.mbt`/`.mbt.md` deletion also reports `moon check` feedback.
  Change existing source with `edit`, not by removing and rewriting.
