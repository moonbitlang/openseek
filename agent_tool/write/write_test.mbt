///|
/// Run the `write` tool from a built definition — the shape every test that
/// drives the registered executor uses.
async fn run_write(
  tool : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match tool.execute {
    Async(run) => run(arguments)
    Sync(_) => fail("write tool should be async")
  }
}

///|
/// Run `write` with the default workspace and a fresh file-state map, through
/// the public definition.
async fn execute(arguments : Json) -> @agent_tool.ToolAction {
  run_write(@write.definition(), arguments)
}

///|
async test "write resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-write-workspace-", dir => {
    let result = run_write(@write.definition(workspace_root=dir), {
      "path": "note.txt",
      "content": "workspace",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    let path = "\{dir}/note.txt"
    assert_false(output.is_error)
    assert_eq(output.content, "ok: wrote 1 line (9 chars) to \{path}")
    assert_eq(@fs.read_file(path).text(), "workspace")
  })
}

///|
async test "write fails on a dangling symlink instead of creating its target" {
  @vfs.with_tmpdir(dir => {
    // alias.txt -> lib/new.mbt where the target does not exist: `exists`
    // follows the link (false), so an O_CREAT write would create ungated
    // source THROUGH the link. CreateNew on the not-existed probe makes the
    // write fail instead.
    @fs.mkdir("\{dir}/lib", recursive=true)
    let link = "\{dir}/alias.txt"
    @fs.symlink(target="lib/new.mbt", link)
    let result = execute_via_boundary({
      "path": link,
      "content": "not moonbit (",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("write failed"))
    assert_false(@fs.exists("\{dir}/lib/new.mbt"))
  })
}

///|
/// Execute through the registry so filesystem faults — which raise out of the
/// executor — are converted by the dispatch boundary in
/// `@agent_tool.execute_tool_call`, the same path production takes.
async fn execute_via_boundary(arguments : Json) -> @agent_tool.ToolAction {
  let tools = @agent_tool.Tools([@write.definition()])
  let call = @agent_tool.AgentToolCall(
    ToolCall(id="call_1", name="write", arguments=Json::stringify(arguments)),
  )
  @agent_tool.execute_tool_call(call, tools)
}

///|
async test "write surfaces filesystem errors through the dispatch boundary" {
  @vfs.with_tmpdir(dir => {
    // A parent component that is a regular file cannot be created or written
    // through, so the write fails (missing parent *directories* are created).
    @fs.write_file("\{dir}/afile", "x", create_mode=CreateOrTruncate)
    let result = execute_via_boundary({
      "path": "\{dir}/afile/child.txt",
      "content": "x",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("write failed"))
    assert_true(output.is_error)
  })
}

///|
async test "write records a new file as Created and keeps it on overwrite" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let tool = @write.definition(file_state=state)
    let path = "\{dir}/note.txt"
    // A brand-new file the agent wrote is recorded as its own creation.
    let _ = run_write(tool, { "path": path, "content": "v1" })
    assert_true(state.get(path) is Some(Created))
    // Overwriting that same non-source file keeps the stronger Created state.
    let _ = run_write(tool, { "path": path, "content": "v2" })
    assert_true(state.get(path) is Some(Created))
  })
}

///|
async test "write records an overwrite of a pre-existing file as Modified" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let path = "\{dir}/pre.txt"
    // The file exists before the agent touches it this session.
    @vfs.FileSystem({ "pre.txt": "old" }).write_to(dir)
    let _ = run_write(@write.definition(file_state=state), {
      "path": path,
      "content": "new",
    })
    assert_true(state.get(path) is Some(Modified))
  })
}

///|
async test "a write scope confines write to its allowed paths" {
  @vfs.with_tmpdir(prefix="openseek-write-scope-", dir => {
    @vfs.FileSystem({ "lib/keep.txt": "k\n" }).write_to(dir)
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["lib"])
      is Ok(scope) else {
      fail("expected the scope to build")
    }
    let tool = @write.definition(workspace_root=dir, write_scope=scope)
    guard run_write(tool, { "path": "lib/new.txt", "content": "n\n" })
      is Respond(admitted) else {
      fail("expected Respond")
    }
    assert_false(admitted.is_error)
    assert_eq(@fs.read_file("\{dir}/lib/new.txt").text(), "n\n")
    // Out of scope: blocked before parent directories are even created.
    guard run_write(tool, { "path": "other/new.txt", "content": "n\n" })
      is Respond(blocked) else {
      fail("expected Respond")
    }
    assert_true(blocked.is_error)
    assert_true(blocked.content.contains("write blocked"))
    assert_false(@fs.exists("\{dir}/other"))
  })
}

///|
async test "write creates missing parent directories" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/pkg/sub/moon.pkg"
    let result = execute({ "path": path, "content": "import {}\n" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(output.content, "ok: wrote 2 lines (10 chars) to \{path}")
    assert_eq(@fs.read_file(path).text(), "import {}\n")
  })
}

///|
async test "write creates a file with the given content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/test.txt"
    let result = execute({ "path": path, "content": "hello write" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: wrote 1 line (11 chars) to \{path}")
    assert_false(output.is_error)
    let read_back = @fs.read_file(path).text()
    assert_eq(read_back, "hello write")
  })
}

///|
async test "write truncates existing files" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/truncate.txt"
    @vfs.FileSystem({ "truncate.txt": "long original content" }).write_to(dir)
    let result = execute({ "path": path, "content": "short" })
    guard result is Respond(output) else { fail("expected Respond") }
    // The path already existed, so the result flags the overwrite.
    assert_eq(
      output.content,
      "ok: wrote 1 line (5 chars) to \{path} (overwrote existing file)",
    )
    assert_false(output.is_error)
    let read_back = @fs.read_file(path).text()
    assert_eq(read_back, "short")
  })
}

///|
async test "write reports whether it created or overwrote a file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/note.txt"
    // First write to a fresh path: a plain "created" result, no overwrite note.
    let created = execute({ "path": path, "content": "v1" })
    guard created is Respond(first) else { fail("expected Respond") }
    assert_eq(first.content, "ok: wrote 1 line (2 chars) to \{path}")
    // Writing again clobbers the existing file, which the result now calls out.
    let overwritten = execute({ "path": path, "content": "v2!" })
    guard overwritten is Respond(second) else { fail("expected Respond") }
    assert_eq(
      second.content,
      "ok: wrote 1 line (3 chars) to \{path} (overwrote existing file)",
    )
  })
}

///|
async test "write accepts empty content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.txt"
    @vfs.FileSystem({ "empty.txt": "previous" }).write_to(dir)
    let result = execute({ "path": path, "content": "" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: wrote 0 lines (0 chars) to \{path} (overwrote existing file)",
    )
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
    @vfs.FileSystem({ "pkg.generated.mbti": "old interface" }).write_to(dir)
    let result = execute({ "path": path, "content": "new interface" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("run moon info"))
    assert_eq(@fs.read_file(path).text(), "old interface")
  })
}

///|
async test "write rejects overwriting an existing .mbt source file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/lib.mbt"
    @vfs.FileSystem({ "lib.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(dir)
    let result = execute({
      "path": path,
      "content": "pub fn f() -> Int { 2 }\n",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("use edit or multi_edit"))
    // unchanged on disk
    assert_eq(@fs.read_file(path).text(), "pub fn f() -> Int { 1 }\n")
  })
}

///|
async test "write still creates a NEW .mbt source file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/new.mbt"
    let result = execute({
      "path": path,
      "content": "pub fn g() -> Int { 0 }\n",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "pub fn g() -> Int { 0 }\n")
  })
}

///|
async test "write rejects overwriting an existing .mbt.md doc file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/doc.mbt.md"
    @vfs.FileSystem({ "doc.mbt.md": "# old\n" }).write_to(dir)
    let result = execute({ "path": path, "content": "# new\n" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("use edit or multi_edit"))
  })
}

///|
async test "write rejects overwriting source through a symlink" {
  @vfs.with_tmpdir(dir => {
    let src = "\{dir}/lib.mbt"
    @vfs.FileSystem({ "lib.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(dir)
    // link.txt -> lib.mbt: the .txt name must not let the write slip past the
    // guard and truncate the real source.
    let link = "\{dir}/link.txt"
    @fs.symlink(target="lib.mbt", link)
    let result = execute({ "path": link, "content": "clobbered\n" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("use edit or multi_edit"))
    assert_eq(@fs.read_file(src).text(), "pub fn f() -> Int { 1 }\n")
  })
}

///|
/// Writing through a link whose own name is not a syncheck input still gates by
/// the target's kind: `alias.txt -> moon.pkg` must not let malformed manifest
/// content land in the real `moon.pkg` (the write would otherwise follow the
/// link and truncate it). The existing manifest is left untouched.
async test "write parse-gates manifest content written through a symlink" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-link-", dir => {
    let manifest = "\{dir}/moon.pkg"
    let original = "import {}\n"
    @fs.write_file(manifest, original, create_mode=CreateOrTruncate)
    let link = "\{dir}/alias.txt"
    @fs.symlink(target="moon.pkg", link)
    let result = execute({ "path": link, "content": "x" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    // The malformed content never reached the manifest.
    assert_eq(@fs.read_file(manifest).text(), original)
  })
}

///|
/// `moon.pkg` now flows through the syntax gate too, so malformed config is
/// rejected before anything lands. Tininess alone is not the trigger — the
/// manifest guard's commented-out "suspiciously small" heuristic stays off, and
/// a valid dummy (`import {}`) still writes (see the parent-directories test) —
/// invalid syntax is. A bare `x` is not a valid package statement.
async test "write parse-gates a malformed moon.pkg" {
  @vfs.with_tmpdir(prefix="openseek-write-manifest-", dir => {
    let path = "\{dir}/moon.pkg"
    let result = execute({ "path": path, "content": "x" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(@fs.exists(path))
  })
}

///|
/// End-to-end through real moonc: the gate needs no moon project, so a plain
/// tmpdir exercises the reject, the opt-out, and the `.mbt.md` doc path (whose
/// checked fenced blocks are now gated too).
async test "write gates .mbt content through moonc before writing" {
  @vfs.with_tmpdir(prefix="openseek-write-gate-", dir => {
    // Broken .mbt: rejected, nothing on disk (not even parent dirs).
    let broken = execute({
      "path": "\{dir}/lib/broken.mbt",
      "content": (
        #|///|
        #|pub fn f() -> Int {
        #|  let x =
        #|}
        #|
      ),
    })
    guard broken is Respond(out) else { fail("expected Respond") }
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the content for"))
    assert_true(out.content.contains("nothing was written"))
    assert_false(@fs.exists("\{dir}/lib/broken.mbt"))
    assert_false(@fs.exists("\{dir}/lib"))
    // Clean .mbt: written.
    let clean = execute({
      "path": "\{dir}/lib/clean.mbt",
      "content": (
        #|///|
        #|pub fn g() -> Int {
        #|  42
        #|}
        #|
      ),
    })
    guard clean is Respond(ok) else { fail("expected Respond") }
    assert_false(ok.is_error)
    assert_true(@fs.exists("\{dir}/lib/clean.mbt"))
    // Opt-out: broken fixture is written as-is.
    let fixture = execute({
      "path": "\{dir}/lib/fixture.mbt",
      "content": "not moonbit (",
      "revert_on_parse_errors": false,
    })
    guard fixture is Respond(fx) else { fail("expected Respond") }
    assert_false(fx.is_error)
    assert_true(@fs.exists("\{dir}/lib/fixture.mbt"))
    // .mbt.md prose (no checked block): parses clean, written untouched.
    let doc = execute({
      "path": "\{dir}/lib/doc.mbt.md",
      "content": (
        #|# Doc
        #|
        #|prose only
        #|
      ),
    })
    guard doc is Respond(md) else { fail("expected Respond") }
    assert_false(md.is_error)
    assert_true(@fs.exists("\{dir}/lib/doc.mbt.md"))
    // .mbt.md with a broken ```mbt check block: gated like source, rejected.
    let broken_doc = execute({
      "path": "\{dir}/lib/broken.mbt.md",
      "content": (
        #|# Doc
        #|
        #|```mbt check
        #|///|
        #|pub fn h() -> Int {
        #|  let x =
        #|}
        #|```
        #|
      ),
    })
    guard broken_doc is Respond(bad) else { fail("expected Respond") }
    assert_true(bad.is_error)
    assert_false(@fs.exists("\{dir}/lib/broken.mbt.md"))
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
