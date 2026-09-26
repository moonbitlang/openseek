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
/// - `Respond(ToolOutput("ok: wrote <n> line(s) (<m> chars) to <path>"))` when a
///   new file is created; the message gains ` (overwrote existing file)` when the
///   path already existed, so the model can tell it clobbered prior content. The
///   line count matches what the read workflow reports for the same file (empty content is
///   0 lines; a trailing newline counts a final empty segment).
/// - `Respond(ToolOutput("rejected: the content for <path> ...", is_error=true))`
///   when the parse gate refused non-parsing content.
/// - `Respond(ToolOutput("error writing <path>: <error>", is_error=true))`
///   if the write fails.
/// - `Respond(ToolOutput("error: write requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="write",
    description=(
      #|Create a new file at arguments.path with arguments.content (missing parent
      #|directories are created), or overwrite an existing non-source file. Overwriting an
      #|existing .mbt/.mbt.md source file is rejected: use edit or multi_edit to change
      #|existing source (an empty old_string inserts new code). New syntax-checkable
      #|content (.mbt, .mbt.md, moon.mod, moon.pkg) that fails to lex/parse is rejected
      #|BEFORE writing and the parse errors are returned — see revert_on_parse_errors. Do
      #|not use write to copy a snippet-generated rewrite of a file back over source. Do not
      #|create Markdown or README files unless the user explicitly asks for them.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "content": { "type": "string" },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": (
            #|Syntax gate, on by default. Before a new syntax-checkable file (.mbt,
            #|.mbt.md, moon.mod, moon.pkg) is written, its content is parsed standalone
            #|(moonc syncheck); content with lex/parse errors is REJECTED — nothing is
            #|written — and the call returns the errors with excerpts of the offending
            #|lines. A file that does not parse is never a valid intermediate state, and
            #|write cannot overwrite existing source, so the retry is another write with
            #|corrected content. Type errors never trigger the gate (they may be a
            #|legitimate transient state during multi-file work); in .mbt.md only the
            #|checked (`mbt check` / `moonbit check`) fenced blocks are parsed. Set false
            #|only to intentionally create a file that does not parse (e.g. a test
            #|fixture).
          ),
          "examples": [false],
        },
      },
      "required": ["path", "content"],
    }),
    execute=Async(arguments => {
      execute_with_workspace(
        workspace_root,
        file_state,
        arguments,
        write_scope?,
      )
    }),
  )
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
        "error: write requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  // Containment gate for confined (worker) registries; re-checked below
  // immediately before the file is written.
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    return @agent_tool.respond(
      "error writing \{path}: write blocked: \{reason}",
      is_error=true,
      brief="write \{@agent_tool.brief_basename(path)}",
    )
  }
  write_file(input, path~, file_state~, write_scope?)
}

///|
async fn write_file(
  input : @decode.WriteInput,
  path~ : String,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  fn err(message : String) -> @agent_tool.ToolAction {
    // Every failure names the file it tried to write, as `edit`/`remove` do.
    // Built here rather than once per call: the success path never needs it.
    @agent_tool.respond(
      "error writing \{path}: \{message}",
      is_error=true,
      brief="write \{@agent_tool.brief_basename(path)}",
    )
  }

  if @manifest_error.write_error(path, input.content) is Some(message) {
    return err(message)
  }
  // Resolve symlinks once, up front: the realpath decides both whether this
  // is an existing-source overwrite to reject and — for the syntax gate below
  // — what KIND the written file really is. A brand-new path has no target, so
  // realpath fails and it falls back to its own name.
  let target = @fs.realpath(path) catch { _ => path }
  // Guard the last unguarded source-write path: `write` is an in-process file
  // write with no sandbox in front of it, so overwriting an existing
  // `.mbt`/`.mbt.md` file here would bypass the line-anchored edit discipline
  // and risk silently dropping content. Existing source must change through
  // `edit`/`multi_edit` (which also insert). Creating a NEW source file, or
  // writing non-source files, is still allowed. Resolving the symlink first
  // stops a link named `x.txt` pointing at `lib.mbt` from slipping past the
  // suffix check and truncating the source through CreateOrTruncate below.
  if @fs.exists(path) && (is_mbt_source(path) || is_mbt_source(target)) {
    return err(
      "existing source file — use edit or multi_edit to change it (an empty old_string inserts new code); write is for creating new files",
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
        _ => None
      }
      if gate is Some(gate) && gate.errors.length() > 0 {
        let bound = if gate.truncated { "≥" } else { "" }
        return @agent_tool.respond(
          write_reject_report(path, input.content, gate),
          is_error=true,
          brief="write rejected (\{bound}\{gate.errors.length()} parse error(s))",
        )
      }
    }
  }
  // Containment re-check at the moment of writing (before parent directories
  // are created for the target): the early gate decided on filesystem state
  // that awaits ago may have changed underneath the tool.
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    return err("write blocked: \{reason}")
  }
  file_state.create_parent_directories(path)
  // Probe before writing so the result can tell the model whether it created a
  // new file or clobbered an existing one — a wholesale `write` over content it
  // never read is a common way to lose work. A non-ENOENT `exists` error (e.g.
  // ENOTDIR) falls through to the write below, and the dispatch boundary in
  // `@agent_tool.execute_tool_call` reports the fault.
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
  // Record this write's provenance and content digest for the session so
  // `remove` can later tell a file the agent created from one it merely
  // overwrote, and confirm its content has not been rebound since. A write is
  // a wholesale replacement, so the file now holds the agent's content
  // regardless of what was there — no continuity check is needed.
  let digest = @agent_tool.content_digest(input.content)
  if existed {
    file_state.record_modified(path, digest)
  } else {
    file_state.record_created(path, digest)
  }
  let chars = input.content.length()
  // Line count matches read's `split("\n")` total, so the numbers agree across
  // tools: empty content is 0 lines, and a trailing newline counts a final
  // empty segment (e.g. "a\nb\n" is 3 lines). Computed in constant space —
  // count newline delimiters in a single pass rather than materializing a
  // per-line array just to read its length, since a large generated write can
  // hold very many lines.
  let lines = if input.content == "" {
    0
  } else {
    input.content.iter().count_if(ch => ch == '\n') + 1
  }
  let line_word = if lines == 1 { "line" } else { "lines" }
  let summary = if existed {
    "ok: wrote \{lines} \{line_word} (\{chars} chars) to \{path} (overwrote existing file)"
  } else {
    "ok: wrote \{lines} \{line_word} (\{chars} chars) to \{path}"
  }
  let ok_brief = @agent_tool.brief_line(
    if existed {
      "overwrote \{input.path} (\{lines} \{line_word})"
    } else {
      "wrote \{lines} \{line_word} to \{input.path}"
    },
  )
  let content = @auto_check.append_summary(path, summary)
  @agent_tool.respond(content, brief=ok_brief)
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
        { loc: "\{index + 1}:1", message: "e\{index}", context: "", } :
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
    errors: [{ loc: "1:1", message: "e", context: "", }],
    truncated: true,
  })
  assert_true(clipped.contains("has at least 1 parse error(s)"))
}
