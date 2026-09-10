# Remove Tool

`remove` deletes a file the agent created earlier this session, gated on that
provenance and carrying a required rationale for the audit trail. It is the
delete verb of the tool-mediated file API: `write` and
`edit`/`multi_edit` already exist, but there was no in-workflow way to delete a
file — the shell sandbox blocks `rm` on source paths, and routing other
deletions through `shell` bypasses provenance entirely.

`remove` deletes a path **only** when the session's
[`FileStateMap`](../file_state.mbt) records it as `Created` — one the agent
itself created this session — so removing it merely undoes the agent's own
work. A pre-existing file (one the agent never created, or only modified) is
refused.

## Design Rationale

The gate is provenance, not file type. `remove` handles any file the agent
created: for a source file it is the *only* way to delete it (the sandbox
blocks `rm` on `.mbt`/`.mbt.md`/manifest paths), and for any other file it is
the *provenance-checked* path where a bare `shell rm` is not. Deleting a
`.mbt`/`.mbt.md` file runs module `moon check` and appends the feedback, so a
break the deletion causes surfaces in the result exactly as it does after
`write`/`edit`.

Because deletion is irreversible, every call carries a `reason`. The rationale
is recorded in the (durable) success message — `ok: removed <path> (reason:
…)` — so a destructive action can be audited after the fact.

## Safety Model

`Created` alone is not a delete capability (see the
[`FileStateMap`](../file_state.mbt) docs). Three guards gate a removal:

- **Content revalidation.** The gate is `created_and_unchanged`, which pairs the
  `Created` provenance with a content digest (SHA-256) of what the agent last
  wrote. `remove` reads the file back at delete time, hashes it, and refuses on a
  mismatch, so a path *rebound to different content* since the agent wrote it — a
  `git checkout -- x.mbt` restoring a tracked file the agent had recreated, or a
  `mv` onto the path — is not deleted. And a targeted `edit` cannot launder a
  rebind: `record_edited` downgrades a `Created` file whose pre-edit content is
  not what the agent last wrote. A read failure at delete time also refuses.
- **Forget on delete.** After a successful removal the provenance is dropped
  (`FileStateMap::forget`), so a path recreated after a removal reads as unknown
  and a second `remove` refuses it.
- **No symlink following.** The regular-file check uses `follow_symlink=false`,
  so a path replaced by a symlink is refused rather than followed to its target.

The digest is captured from the content the tools already hold in memory — so
identity capture never stats the filesystem and never races cancellation — and,
being a content *version*, it cannot collide the way coarse-resolution or
`mv`-preserved mtimes can. A different file with byte-identical content passes,
which is harmless (deleting identical bytes deletes the agent's own content).
Keys are the exact resolved path `write` used, so an unrecognized spelling reads
as unknown and is conservatively refused rather than risking a wrong-file
deletion.

## Arguments

| Name     | Type   | Required | Notes |
| -------- | ------ | -------- | ----- |
| `path`   | string | yes | Filesystem path. Relative paths resolve against the workspace root. Must name an existing regular file the agent created this session. |
| `reason` | string | yes | A short, **non-empty** explanation of why the file is being deleted, recorded with the result for auditing. A blank (whitespace-only) reason is rejected. |

## Action

The action is always `Respond(ToolOutput(...))`; the agent loop forwards
`ToolOutput.content` to the model. `is_error` is `false` on success and `true`
otherwise. The body has one of these shapes:

- `"ok: removed <path> (reason: <reason>)"` — the file was deleted. When the
  target is a `.mbt`/`.mbt.md` file inside a MoonBit module, bounded module-root
  `moon check` feedback is appended after the success line, starting with
  `"moon check:"`.
- `"error removing <path>: not created by the agent this session — ..."` — the
  gate refused: the file is pre-existing, or the agent only modified it.
- `"error removing <path>: no such file"` / `"... not a regular file; remove
  deletes regular files"` — the path is missing, a directory, or a symlink.
- `"error removing <path>: <error>"` — the unlink itself failed (e.g. permission
  denied).
- `"error: remove requires arguments.path"` / `"... arguments.reason"` /
  `"... arguments.reason to be a non-empty explanation"` / `"... object
  arguments"` — invalid payload.

## Examples

```moonbit check
///|
test "remove tool advertises the expected schema" {
  let tool = @remove.definition()
  assert_eq(tool.name, "remove")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"path\""))
  assert_true(text.contains("\"reason\""))
  assert_true(text.contains("\"required\""))
}
```

```moonbit check
///|
async test "remove deletes an agent-created file through the registry" {
  @vfs.with_tmpdir(prefix="openseek-remove-readme-", dir => {
    let path = "\{dir}/scratch.mbt"
    @vfs.FileSystem({ "scratch.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(
      dir,
    )
    // The session recorded that the agent created this file, as `write` would,
    // capturing its content digest so the delete gate can revalidate it.
    let file_state = @agent_tool.FileStateMap::FileStateMap()
    file_state.record_created(
      path,
      @agent_tool.content_digest(@fs.read_file(path).text()),
    )
    let tools = @agent_tool.Tools([@remove.definition(file_state~)])
    // Build the arguments as JSON and stringify: a Windows temp path would
    // otherwise form an invalid escape inside a JSON string literal.
    let arguments : Json = {
      "path": path,
      "reason": "scratch no longer needed",
    }
    let call = @agent_tool.AgentToolCall(
      ToolCall(id="call_remove", name="remove", arguments=arguments.stringify()),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: removed \{path} (reason: scratch no longer needed)",
    )
    assert_false(@fs.exists(path))
  })
}
```

```moonbit check
///|
async test "remove refuses a file the agent did not create" {
  @vfs.with_tmpdir(prefix="openseek-remove-readme-refuse-", dir => {
    let path = "\{dir}/lib.mbt"
    @vfs.FileSystem({ "lib.mbt": "pub fn g() -> Int { 0 }\n" }).write_to(dir)
    // An empty file-state map: the agent never created this file this session.
    let tools = @agent_tool.Tools([@remove.definition()])
    let arguments : Json = { "path": path, "reason": "cleanup" }
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_remove_refuse",
        name="remove",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(
      output.content.contains("not created by the agent this session"),
    )
    // The file is untouched.
    assert_true(@fs.exists(path))
  })
}
```
