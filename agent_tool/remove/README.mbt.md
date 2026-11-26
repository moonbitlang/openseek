# Remove Tool

`remove(path, reason)` deletes a regular file, unlinks a symbolic link, or
recursively deletes a directory.

- Files recorded as created by this session whose contents still match the
  recorded digest are deleted automatically.
- A nonempty directory tree is also deleted automatically when every directory
  was created by this session and every contained file still matches its
  recorded digest.
- Existing files, files made by external commands, and files changed since the
  agent last wrote them require one-shot approval through `ApprovalChannel`.
  The question shows the path, the agent's reason, and why approval is needed.
- Empty directories are deleted automatically using non-recursive `rmdir`;
  if an entry appears before removal, it fails without deleting that entry.
- Other nonempty directories require approval, showing the recursive file and
  subdirectory counts. Hidden files and empty subdirectories are included.
- Symbolic links, including dangling links, require approval. A link inside a
  directory is a leaf in the approved tree. Unlinking it preserves its target.
  A trailing slash on the link still unlinks the entry. Intermediate links
  resolve normally when addressing an entry below them.
- Missing entries, workspace roots and their ancestors, and special files are
  rejected without requesting approval.
- Valid targets outside a configured write scope require one-shot approval.
  Each grant applies to the requested operation only.

## Approval and concurrency

The channel uses the existing session permission policy: `ask` waits for the
controller, `always` grants automatically, and `never` provides no channel.
Rejection, cancellation, or an absent/unavailable channel leaves the target intact.
Workers currently have no approval channel; they report the blocked deletion
to their parent instead of bypassing confinement.

Approving a directory authorizes recursive removal of the named directory and
its contents at execution time. The counts in the prompt are a preview. Files
added, edited, or renamed while the prompt is open are included. The tool
checks that the path still names a directory at the approved location, then
calls the filesystem's recursive removal operation. A filesystem failure can
leave a partially removed tree.

A standalone file approval covers its location and raw-byte SHA-256. A
standalone symlink approval covers its name in the resolved parent directory
and its stored link target. Both are rechecked after the approval wait.

The definition owns its locking through `FileStateMap::with_access`: the initial
check and automatic deletion share one locked phase; approval waits outside
the lock; the recheck and approved deletion share another. Do not wrap this
definition in `FileStateMap::serialize`, which would hold the lock during the
human interaction and deadlock other file tools.

A successful deletion clears provenance and records the nonblank `reason` in
the response. Deleting `.mbt`/`.mbt.md` files also appends bounded `moon check`
feedback. Errors return `is_error=true` and distinguish rejected, cancelled,
unavailable, changed-file, and filesystem failures. This tool does not create
recovery backups.

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
      @agent_tool.content_digest(@fs.read_text(path)),
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
async test "remove refuses an existing file without an approval channel" {
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
      output.content.contains(
        "not recorded as created by the agent this session",
      ),
    )
    // The file is untouched.
    assert_true(@fs.exists(path))
  })
}
```
