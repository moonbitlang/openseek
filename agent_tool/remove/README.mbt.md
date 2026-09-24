# Remove Tool

`remove(path, reason)` deletes a regular file or recursively deletes a directory. The arguments are unchanged;
the agent does not supply a hash or an approval flag.

- Files recorded as created by this session whose contents still match the
  recorded digest are deleted automatically.
- Existing files, files made by external commands, and files changed since the
  agent last wrote them require one-shot approval through `ApprovalChannel`.
  The question shows the path, the agent's reason, and why approval is needed.
- Directories always require approval, showing the recursive file and subdirectory
  counts. Hidden files and empty subdirectories are included.
- Missing files, workspace roots and their ancestors, symlinks (including inside
  a directory), special files, and targets outside a worker's write scope are
  rejected without requesting approval.

## Approval and concurrency

The channel uses the existing session permission policy: `ask` waits for the
controller, `always` grants automatically, and `never` provides no channel.
Rejection, cancellation, or an absent/unavailable channel leaves the target intact.
Workers currently have no approval channel; they report the blocked deletion
to their parent instead of bypassing confinement.

A grant is used only by this call for the file's captured canonical path and
raw-byte SHA-256. After approval, the tool rechecks the scope, kind, location,
and contents. A changed version is refused; a later request needs fresh
approval. Matching bytes identify a content version, not a filesystem object.
For directories, the captured version includes every entry's path, kind,
canonical location, and each regular file's raw-byte digest. Added, removed,
renamed, or changed entries invalidate the grant before deletion starts.

There is no atomic compare-and-unlink against external writers. After validating
all entries, directory deletion proceeds in postorder, checking each entry again
and using non-recursive directory removal. A concurrent change or filesystem
failure during deletion can leave a partially removed tree; it never expands
the approved list to include newly added files.

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
