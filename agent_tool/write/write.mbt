///|
/// Tool definition for `write`: creates a new file at `arguments.path` with
/// `arguments.content`, or overwrites an existing non-source file. Overwriting
/// an existing `.mbt`/`.mbt.md` source file is rejected (use `edit`/`multi_edit`,
/// which also insert). Missing parent directories are created (so `dir/moon.pkg`
/// works without a separate mkdir).
///
/// ## Arguments
/// - `path` (string, required): filesystem path to write.
/// - `content` (string, required): text to write. The file is truncated
///   before writing.
/// - `revert_on_parse_errors` (boolean, optional, default true): before a new
///   syncheck input (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`) is written, its
///   content is parsed standalone (`moonc syncheck`); content with lex/parse
///   errors is rejected and the errors are returned with excerpts — nothing
///   lands on disk. In `.mbt.md` only the checked fenced blocks are parsed. Set
///   false only to intentionally create a file that does not parse (e.g. a
///   fixture).
///
/// ## Result
/// - `Respond(ToolOutput("ok: wrote <n> chars to <path>"))` when a new file is
///   created; the message gains ` (overwrote existing file)` when the path
///   already existed, so the model can tell it clobbered prior content.
/// - `Respond(ToolOutput("rejected: the content for <path> ...", is_error=true))`
///   when the parse gate refused non-parsing content.
/// - `Respond(ToolOutput("error writing <path>: <error>", is_error=true))`
///   if the write fails.
/// - `Respond(ToolOutput("error: write requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = @agent_tool.FileStateMap::new(),
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="write",
    description="Create a new file at arguments.path with arguments.content (missing parent directories are created), or overwrite an existing non-source file. Overwriting an existing .mbt/.mbt.md source file is rejected: use edit or multi_edit to change existing source (an empty old_string inserts new code). New syntax-checkable content (.mbt, .mbt.md, moon.mod, moon.pkg) that fails to lex/parse is rejected BEFORE writing and the parse errors are returned — see revert_on_parse_errors. Do not use write to route shell-generated rewrites back into source files. Do not create Markdown or README files unless the user explicitly asks for them.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "content": { "type": "string" },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": "Syntax gate, on by default. Before a new syntax-checkable file (.mbt, .mbt.md, moon.mod, moon.pkg) is written, its content is parsed standalone (moonc syncheck); content with lex/parse errors is REJECTED — nothing is written — and the call returns the errors with excerpts of the offending lines. A file that does not parse is never a valid intermediate state, and write cannot overwrite existing source, so the retry is another write with corrected content. Type errors never trigger the gate (they may be a legitimate transient state during multi-file work); in .mbt.md only the checked (`mbt check` / `moonbit check`) fenced blocks are parsed. Set false only to intentionally create a file that does not parse (e.g. a test fixture).",
          "examples": [false],
        },
      },
      "required": ["path", "content"],
    }),
    execute=Async(arguments => {
      execute_with_workspace(workspace_root, file_state, arguments)
    }),
  )
}

///|
async fn execute(arguments : Json) -> @agent_tool.ToolAction {
  execute_with_workspace(".", @agent_tool.FileStateMap::new(), arguments)
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
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
  write_file(input, path~, file_state~)
}

///|
async fn write_file(
  input : @decode.WriteInput,
  path~ : String,
  file_state~ : @agent_tool.FileStateMap,
) -> @agent_tool.ToolAction {
  try {
    if @manifest_error.write_error(path, input.content) is Some(message) {
      return @agent_tool.ToolAction::respond(
        "error writing \{path}: \{message}",
        is_error=true,
        brief="write \{@agent_tool.brief_basename(path)}",
      )
    }
    // Resolve symlinks once, up front: the realpath decides both whether this
    // is an existing-source overwrite to reject and — for the syntax gate below
    // — what KIND the written file really is. A brand-new path has no target, so
    // realpath fails and it falls back to its own name.
    let target = @fs.realpath(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => path
    }
    // Guard the last unguarded source-write path: `write` is not sandboxed (it
    // is an in-process file write, unlike `shell`), so overwriting an existing
    // `.mbt`/`.mbt.md` file here would bypass the line-anchored edit discipline
    // and risk silently dropping content. Existing source must change through
    // `edit`/`multi_edit` (which also insert). Creating a NEW source file, or
    // writing non-source files, is still allowed. Resolving the symlink first
    // stops a link named `x.txt` pointing at `lib.mbt` from slipping past the
    // suffix check and truncating the source through CreateOrTruncate below.
    if @fs.exists(path) && (is_mbt_source(path) || is_mbt_source(target)) {
      return @agent_tool.ToolAction::respond(
        "error writing \{path}: existing source file — use edit or multi_edit to change it (an empty old_string inserts new code); write is for creating new files",
        is_error=true,
        brief="write \{@agent_tool.brief_basename(path)}",
      )
    }
    // Pre-write syntax gate for syncheck inputs (`.mbt`, `.mbt.md`, `moon.mod`,
    // `moon.pkg`): parse the candidate content in a scratch file first (moonc
    // syncheck needs no project context), so malformed content is rejected
    // before anything — parent directories included — is created on disk. Gate
    // under every kind this file could be classified as (from both the path and
    // its symlink target), so malformed content written THROUGH a link (e.g.
    // `alias.txt -> moon.pkg`) is caught too. A non-parsing file is never a
    // valid intermediate state, and since `write` refuses to overwrite existing
    // source, the natural retry is another `write` with corrected content.
    // Fail-open: when the gate cannot run (moonc missing), write as usual.
    if input.revert_on_parse_errors {
      for gate_path in @auto_check.gate_paths(path, target) {
        let gate = @auto_check.content_parse_errors(gate_path, input.content) catch {
          error if @async.is_being_cancelled() => raise error
          _ => None
        }
        if gate is Some(gate) && gate.errors.length() > 0 {
          let bound = if gate.truncated { "≥" } else { "" }
          return @agent_tool.ToolAction::respond(
            write_reject_report(path, input.content, gate),
            is_error=true,
            brief="write rejected (\{bound}\{gate.errors.length()} parse error(s))",
          )
        }
      }
    }
    create_parent_dirs(path)
    // Probe before writing so the result can tell the model whether it created a
    // new file or clobbered an existing one — a wholesale `write` over content it
    // never read is a common way to lose work. A non-ENOENT `exists` error (e.g.
    // ENOTDIR) falls through to the write below and the `catch` reports it.
    let existed = @fs.exists(path)
    // Truncation is allowed ONLY for a genuine pre-existing non-source file;
    // everything else commits to CreateNew, which fails instead of writing
    // through when (a) the "new" path gained a file since the probe — for a
    // source path that racer's file would otherwise be truncated despite the
    // guard above — or (b) a DANGLING symlink lurks at the path (`exists`
    // follows links, so it reads false, but O_CREAT would create the link's
    // target, e.g. alias.txt -> lib/new.mbt landing ungated source).
    @fs.write_file(
      path,
      input.content,
      create_mode=if existed && !is_mbt_source(path) {
        CreateOrTruncate
      } else {
        CreateNew
      },
    )
    // Record this write's provenance for the session so `remove` can later tell
    // a file the agent created from one it merely overwrote.
    if existed {
      file_state.record_modified(path)
    } else {
      file_state.record_created(path)
    }
    let chars = input.content.length()
    let summary = if existed {
      "ok: wrote \{chars} chars to \{path} (overwrote existing file)"
    } else {
      "ok: wrote \{chars} chars to \{path}"
    }
    let ok_brief = @agent_tool.brief_line(
      if existed {
        "overwrote \{input.path}"
      } else {
        "wrote \{chars} chars to \{input.path}"
      },
    )
    let content = @auto_check.append_summary(path, summary)
    @agent_tool.ToolAction::respond(content, brief=ok_brief)
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
/// From this many parse errors up, the reject report stops suggesting a plain
/// re-issue and pushes writing the file in smaller parts instead: parse errors
/// cascade, so several of them usually mean the content is malformed wholesale
/// (truncated generation, stray markdown fences, non-MoonBit text), and a
/// smaller skeleton that parses is the reliable way back.
const SmallerPartsHintThreshold : Int = 3

///|
/// The rejected-write report: nothing was written, the first parse errors with
/// excerpts synthesized from the rejected content, and how to retry — a plain
/// re-issue for a small slip, smaller incremental writes when the errors
/// suggest wholesale malformed content.
fn write_reject_report(
  path : String,
  content : String,
  gate : @auto_check.ParseGate,
) -> String {
  let count = gate.errors.length()
  // A truncated capture makes the count a lower bound; never state an exact
  // number the gate does not know.
  let count_label = if gate.truncated {
    "at least \{count}"
  } else {
    "\{count}"
  }
  let head = "rejected: the content for \{path} has \{count_label} parse error(s); nothing was written."
  let formatted = @auto_check.format_parse_gate_errors(
    path,
    content,
    gate.errors,
  )
  let listed = if formatted.is_empty() {
    ""
  } else {
    "\nfirst \{formatted.length()} parse error(s), with the rejected content excerpted:\n\{formatted.join("\n")}"
  }
  let retry = if count >= SmallerPartsHintThreshold {
    "\n\{count_label} parse errors usually means the content is malformed wholesale (truncated or not valid MoonBit). Do not re-issue the same content: write a smaller file first — a minimal skeleton that parses — then grow it in small pieces with edit (an empty old_string inserts), checking after each step."
  } else {
    "\nre-issue write with the corrected full content."
  }
  let opt_out = "\n(To intentionally create a file that does not parse, e.g. a test fixture, pass revert_on_parse_errors=false.)"
  "\{head}\{listed}\{retry}\{opt_out}"
}

///|
/// Whether `path` is a hand-written MoonBit source file (`.mbt` or `.mbt.md`).
/// `.mbti` interface files are excluded on purpose: generated ones are rejected
/// by the manifest guard, and hand-maintained ones are rare and editable.
fn is_mbt_source(path : String) -> Bool {
  path.has_suffix(".mbt") || path.has_suffix(".mbt.md")
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
  let slash = path.rev_find("/").unwrap_or(-1)
  let backslash = path.rev_find("\\").unwrap_or(-1)
  let cut = if slash > backslash { slash } else { backslash }
  if cut <= 0 {
    ""
  } else {
    path[:cut].to_owned()
  }
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
async test "write truncates existing files" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/truncate.txt"
    @fs.write_file(path, "long original content", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "content": "short" })
    guard result is Respond(output) else { fail("expected Respond") }
    // The path already existed, so the result flags the overwrite.
    assert_eq(
      output.content,
      "ok: wrote 5 chars to \{path} (overwrote existing file)",
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
    assert_eq(first.content, "ok: wrote 2 chars to \{path}")
    // Writing again clobbers the existing file, which the result now calls out.
    let overwritten = execute({ "path": path, "content": "v2!" })
    guard overwritten is Respond(second) else { fail("expected Respond") }
    assert_eq(
      second.content,
      "ok: wrote 3 chars to \{path} (overwrote existing file)",
    )
  })
}

///|
async test "write accepts empty content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.txt"
    @fs.write_file(path, "previous", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "content": "" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: wrote 0 chars to \{path} (overwrote existing file)",
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
    @fs.write_file(path, "old interface", create_mode=CreateOrTruncate)
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
    @fs.write_file(
      path,
      "pub fn f() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
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
    @fs.write_file(path, "# old\n", create_mode=CreateOrTruncate)
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
    @fs.write_file(
      src,
      "pub fn f() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
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
async test "write fails on a dangling symlink instead of creating its target" {
  @vfs.with_tmpdir(dir => {
    // alias.txt -> lib/new.mbt where the target does not exist: `exists`
    // follows the link (false), so an O_CREAT write would create ungated
    // source THROUGH the link. CreateNew on the not-existed probe makes the
    // write fail instead.
    @fs.mkdir("\{dir}/lib", recursive=true)
    let link = "\{dir}/alias.txt"
    @fs.symlink(target="lib/new.mbt", link)
    let result = execute({ "path": link, "content": "not moonbit (" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("error writing"))
    assert_false(@fs.exists("\{dir}/lib/new.mbt"))
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
test "write_reject_report excerpts the rejected content and asks for a re-issue" {
  let content =
    #|///|
    #|pub fn f() -> Int {
    #|  let y =
    #|}
  inspect(
    write_reject_report("lib/a.mbt", content, {
      errors: [
        {
          loc: "4:1-4:2",
          message: "Parse error, unexpected token `}`.",
          context: "",
        },
      ],
      truncated: false,
    }),
    content=(
      #|rejected: the content for lib/a.mbt has 1 parse error(s); nothing was written.
      #|first 1 parse error(s), with the rejected content excerpted:
      #|lib/a.mbt:4:1-4:2: Parse error, unexpected token `}`.
      #|  3 |  let y =
      #|  4 |}
      #|re-issue write with the corrected full content.
      #|(To intentionally create a file that does not parse, e.g. a test fixture, pass revert_on_parse_errors=false.)
    ),
  )
}

///|
test "write_reject_report pushes smaller parts when parse errors cascade" {
  let errors = [
    for index in 0..<4 => {
      (
        { loc: "\{index + 1}:1", message: "e\{index}", context: "" } :
        @auto_check.ParseGateError)
    }
  ]
  let report = write_reject_report("lib/a.mbt", "x\ny\nz\nw", {
    errors,
    truncated: false,
  })
  assert_true(report.contains("4 parse errors usually means"))
  assert_true(report.contains("write a smaller file first"))
  assert_false(
    report.contains("re-issue write with the corrected full content"),
  )
  // A truncated capture reports a lower bound, never an exact count.
  let clipped = write_reject_report("lib/a.mbt", "x", {
    errors: [{ loc: "1:1", message: "e", context: "" }],
    truncated: true,
  })
  assert_true(clipped.contains("has at least 1 parse error(s)"))
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
      "content": "///|\npub fn f() -> Int {\n  let x =\n}\n",
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
      "content": "///|\npub fn g() -> Int {\n  42\n}\n",
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
      "content": "# Doc\n\nprose only\n",
    })
    guard doc is Respond(md) else { fail("expected Respond") }
    assert_false(md.is_error)
    assert_true(@fs.exists("\{dir}/lib/doc.mbt.md"))
    // .mbt.md with a broken ```mbt check block: gated like source, rejected.
    let broken_doc = execute({
      "path": "\{dir}/lib/broken.mbt.md",
      "content": "# Doc\n\n```mbt check\n///|\npub fn h() -> Int {\n  let x =\n}\n```\n",
    })
    guard broken_doc is Respond(bad) else { fail("expected Respond") }
    assert_true(bad.is_error)
    assert_false(@fs.exists("\{dir}/lib/broken.mbt.md"))
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

///|
async test "write records a new file as Created and keeps it on overwrite" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap::new()
    let run = match definition(file_state=state).execute {
      Async(run) => run
      Sync(_) => fail("write tool should be async")
    }
    let path = "\{dir}/note.txt"
    // A brand-new file the agent wrote is recorded as its own creation.
    let _ = run({ "path": path, "content": "v1" })
    assert_true(state.get(path) is Some(Created))
    // Overwriting that same non-source file keeps the stronger Created state.
    let _ = run({ "path": path, "content": "v2" })
    assert_true(state.get(path) is Some(Created))
  })
}

///|
async test "write records an overwrite of a pre-existing file as Modified" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap::new()
    let path = "\{dir}/pre.txt"
    // The file exists before the agent touches it this session.
    @fs.write_file(path, "old", create_mode=CreateOrTruncate)
    let run = match definition(file_state=state).execute {
      Async(run) => run
      Sync(_) => fail("write tool should be async")
    }
    let _ = run({ "path": path, "content": "new" })
    assert_true(state.get(path) is Some(Modified))
  })
}
