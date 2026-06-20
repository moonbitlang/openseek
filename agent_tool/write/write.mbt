///|
/// Tool definition for `write`: overwrites `arguments.path` with
/// `arguments.content`. Existing files are truncated; missing parent
/// directories are created (so `dir/moon.pkg` works without a separate mkdir).
///
/// ## Arguments
/// - `path` (string, required): filesystem path to write.
/// - `content` (string, required): text to write. The file is truncated
///   before writing.
///
/// ## Result
/// - `Respond(ToolOutput("ok: wrote <n> chars to <path>"))` on success.
/// - `Respond(ToolOutput("error writing <path>: <error>", is_error=true))`
///   if the write fails.
/// - `Respond(ToolOutput("error: write requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="write",
    description="Overwrite arguments.path with arguments.content.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "content": { "type": "string" },
      },
      "required": ["path", "content"],
    }),
    execute=Async(arguments => execute_with_workspace(workspace_root, arguments)),
  )
}

///|
async fn execute(arguments : Json) -> @agent_tool.ToolAction {
  execute_with_workspace(".", arguments)
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: write requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  write_file(input, path~)
}

///|
async fn write_file(
  input : @decode.WriteInput,
  path~ : String,
) -> @agent_tool.ToolAction {
  try {
    match manifest_write_error(path, input.content) {
      Some(message) =>
        return @agent_tool.ToolAction::respond(
          "error writing \{path}: \{message}",
          is_error=true,
          brief="write \{@agent_tool.brief_basename(path)}",
        )
      None => ()
    }
    create_parent_dirs(path)
    @fs.write_file(path, input.content, create_mode=CreateOrTruncate)
    let content = @auto_check.append_summary(
      path,
      "ok: wrote \{input.content.length()} chars to \{path}",
    )
    @agent_tool.ToolAction::respond(
      content,
      brief=@agent_tool.brief_line(
        "wrote \{input.content.length()} chars to \{input.path}",
      ),
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @agent_tool.ToolAction::respond(
        "error writing \{path}: \{error}",
        is_error=true,
        brief="write \{@agent_tool.brief_basename(path)}",
      )
  }
}

///|
/// Create the parent directory of `path` (recursively) when it is missing, so a
/// write to `dir/moon.pkg` works without a separate `mkdir`. The path is already
/// resolved under the workspace root, so this stays inside the workspace. A
/// mkdir failure propagates to the caller's `error writing` path rather than
/// being swallowed — the write would fail anyway, so the real cause is useful.
async fn create_parent_dirs(path : String) -> Unit {
  let parent = parent_dir(path)
  if parent != "" && !@fs.exists(parent) {
    @fs.mkdir(parent, recursive=true)
  }
}

///|
/// The directory portion of `path` (before the last `/` or `\`), or `""` when
/// the path has no directory component or is at the filesystem root.
fn parent_dir(path : String) -> String {
  let cut = match (path.rev_find("/"), path.rev_find("\\")) {
    (Some(a), Some(b)) => if a > b { a } else { b }
    (Some(a), None) => a
    (None, Some(b)) => b
    (None, None) => -1
  }
  if cut <= 0 {
    ""
  } else {
    path[:cut].to_owned()
  }
}

///|
async fn manifest_write_error(path : String, content : String) -> String? {
  let trimmed = content.trim()
  if is_generated_mbti_path(path) {
    return Some(
      "*.generated.mbti files are generated; run moon info instead of editing them",
    )
  }
  if is_moon_mod_json_path(path) && !@fs.exists(path) {
    return Some(
      "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
    )
  }
  if is_moon_mod_path(path) {
    if trimmed == "" {
      return Some("moon.mod must not be empty")
    }
    if trimmed.has_prefix("{") || trimmed.contains("\"name\"") {
      return Some("moon.mod uses current text syntax, not JSON")
    }
    if !trimmed.contains("name =") {
      return Some("moon.mod should include a module `name = ...` entry")
    }
  }
  if is_moon_pkg_path(path) {
    // This is normal when we create a moon.pkg dummy file
    // another mistake is AI is trying to write 
    // # as a comment
    // if trimmed.length() < 8 {    
    //   return Some("moon.pkg content is suspiciously small")
    // }
    if trimmed.has_prefix("#") {
      return Some("moon.pkg use // for comment syntax, not #")
    }
    if trimmed.has_prefix("{") {
      return Some("moon.pkg uses current text syntax, not JSON")
    }
  }
  None
}

///|
fn is_moon_mod_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path == "moon.mod" || path.has_suffix("/moon.mod")
}

///|
fn is_moon_mod_json_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path == "moon.mod.json" || path.has_suffix("/moon.mod.json")
}

///|
fn is_moon_pkg_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path == "moon.pkg" || path.has_suffix("/moon.pkg")
}

///|
fn is_generated_mbti_path(path : String) -> Bool {
  let path = path.replace_all(old="\\", new="/")
  path.has_suffix(".generated.mbti")
}

///|
async test "write creates missing parent directories" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/pkg/sub/moon.pkg"
    let result = execute({ "path": path, "content": "import {}\n" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(output.content, "ok: wrote 10 chars to \{path}")
    assert_eq(@fs.read_file(path).text(), "import {}\n")
  })
}

///|
test "parent_dir returns the directory portion" {
  assert_eq(parent_dir("/a/b/c.txt"), "/a/b")
  assert_eq(parent_dir("a/b.txt"), "a")
  assert_eq(parent_dir("file.txt"), "")
  assert_eq(parent_dir("C:\\ws\\x.txt"), "C:\\ws")
}

///|
async test "write creates a file with the given content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/test.txt"
    let result = execute({ "path": path, "content": "hello write" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: wrote 11 chars to \{path}")
    assert_false(output.is_error)
    let read_back = @fs.read_file(path).text()
    assert_eq(read_back, "hello write")
  })
}

///|
async test "write resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-write-workspace-", dir => {
    let tool = definition(workspace_root=dir)
    let result = match tool.execute {
      Async(execute) => execute({ "path": "note.txt", "content": "workspace" })
      Sync(_) => fail("write tool should be async")
    }
    guard result is Respond(output) else { fail("expected Respond") }
    let path = "\{dir}/note.txt"
    assert_false(output.is_error)
    assert_eq(output.content, "ok: wrote 9 chars to \{path}")
    assert_eq(@fs.read_file(path).text(), "workspace")
  })
}

///|
async test "write manifest guards accept Windows path separators" {
  guard manifest_write_error("C:\\workspace\\pkg.generated.mbti", "package x")
    is Some(generated_mbti) else {
    fail("expected generated mbti guard")
  }
  assert_true(generated_mbti.contains("run moon info"))
  guard manifest_write_error("C:\\workspace\\moon.mod", "{\"name\":\"bad\"}")
    is Some(moon_mod) else {
    fail("expected moon.mod guard")
  }
  assert_eq(moon_mod, "moon.mod uses current text syntax, not JSON")
  // guard manifest_write_error("C:\\workspace\\moon.pkg", "x") is Some(moon_pkg) else {
  //   fail("expected moon.pkg guard")
  // }
  // assert_eq(moon_pkg, "moon.pkg content is suspiciously small")
  guard manifest_write_error("C:\\workspace\\moon.mod.json", "{}")
    is Some(moon_mod_json) else {
    fail("expected moon.mod.json guard")
  }
  assert_eq(
    moon_mod_json, "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
  )
}

///|
async test "write truncates existing files" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/truncate.txt"
    @fs.write_file(path, "long original content", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "content": "short" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: wrote 5 chars to \{path}")
    assert_false(output.is_error)
    let read_back = @fs.read_file(path).text()
    assert_eq(read_back, "short")
  })
}

///|
async test "write accepts empty content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.txt"
    @fs.write_file(path, "previous", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "content": "" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: wrote 0 chars to \{path}")
    assert_false(output.is_error)
    let read_back = @fs.read_file(path).text()
    assert_eq(read_back, "")
  })
}

///|
async test "write rejects new legacy moon.mod.json" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-", dir => {
    let path = "\{dir}/moon.mod.json"
    let result = execute({ "path": path, "content": "{\"name\":\"legacy\"}" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("moon.mod.json is legacy"))
  })
}

///|
async test "write rejects json style moon.mod" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-", dir => {
    let path = "\{dir}/moon.mod"
    let result = execute({ "path": path, "content": "{\"name\":\"bad\"}" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("moon.mod uses current text syntax"))
  })
}

///|
async test "write rejects generated mbti files" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-", dir => {
    let path = "\{dir}/pkg.generated.mbti"
    @fs.write_file(path, "old interface", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "content": "new interface" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("run moon info"))
    assert_eq(@fs.read_file(path).text(), "old interface")
  })
}

///|
async test "write rejects suspiciously tiny moon.pkg" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-", dir => {
    let path = "\{dir}/moon.pkg"
    let result = execute({ "path": path, "content": "x" })
    guard result is Respond(output) else { fail("expected Respond") }
    debug_inspect(
      output.is_error,
      content=(
        #|false
      ),
    )
  })
}

///|
async test "write surfaces filesystem errors" {
  @vfs.with_tmpdir(dir => {
    // A parent component that is a regular file cannot be created or written
    // through, so the write fails (missing parent *directories* are created).
    @fs.write_file("\{dir}/afile", "x", create_mode=CreateOrTruncate)
    let result = execute({ "path": "\{dir}/afile/child.txt", "content": "x" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("error writing"))
    assert_true(output.is_error)
  })
}

///|
async test "write rejects missing content" {
  @vfs.with_tmpdir(dir => {
    let result = execute({ "path": "\{dir}/noop.txt" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: write requires arguments.content")
    assert_true(output.is_error)
  })
}

///|
async test "write rejects missing path" {
  let result = execute({ "content": "stuff" })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "error: write requires arguments.path")
  assert_true(output.is_error)
}

///|
async test "write rejects non-object arguments" {
  let result = execute(Json::null())
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "error: write requires object arguments")
  assert_true(output.is_error)
}
