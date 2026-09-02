// The host's `lsp.*` language services — hover, diagnostics, and the
// composer's `#` symbol search — served by one-shot `moon` CLI runs instead
// of a resident language server (Moon IDE navigation lives in
// moonide_ops.mbt). `lsp.hover` shells out to `moon ide hover --output-json`
// at the requested position; `lsp.open` runs `moon check --output-json` over
// the file's module and converts the emitted diagnostics to the LSP-shaped
// arrays the wire protocol already speaks; `lsp.workspace_symbols` fans
// `moon ide workspace-symbols --json` across the workspace's module roots.
// Hover and open receive the editor's exact root plus a path relative to it,
// then choose the deepest module root containing that file; symbols retain
// their conversation-scoped workspace request. Everything is best-effort: no
// module yet, a failed spawn, or a file moon does not know all just yield
// nothing. moon serializes concurrent runs on a module with its own build
// lock, so requests spawn directly with no pooling.

///|
/// The most milliseconds one `moon` run may take before it is killed and the
/// request answers empty. Generous because a first `moon check` on a fresh
/// project builds the whole dependency graph; the timeout only exists so a
/// wedged toolchain (a hung registry fetch) cannot pin a request forever.
const MoonCliTimeoutMs : Int = 300_000

///|
/// The most module roots discovered under one workspace. A workspace rarely
/// holds more than a couple of modules; the cap bounds a pathological tree
/// (a folder of sample projects), where the most recently modified win.
const MaxModuleRoots = 6

///|
/// The most symbol rows a search returns, across all of a conversation's
/// module roots — enough to fill the menu, bounded so a short query can't
/// flood it.
const MaxSymbolResults = 50

///|
/// One resolved way to launch the selected toolchain's `moon` binary with its
/// complete child environment.
priv struct ToolSpawnConfig {
  command : String
  env : Map[String, String]?
}

///|
/// Cached outcome of the one-shot toolchain resolution. `ToolUnavailable` is
/// a diagnosed terminal state — the reason was already logged — so later
/// language requests answer empty instead of retrying or spawning an ambient
/// `moon` whose provenance is unknown.
priv enum ToolSpawnResolution {
  ToolUnresolved
  ToolUnavailable
  ToolResolved(ToolSpawnConfig)
}

///|
/// Process-wide state behind the CLI-served ops: how to launch `moon`
/// (resolved once), which files each module root last had diagnostics on
/// (so a fixed file gets an explicit clear), and the bounded lane that
/// carries diagnostic pushes to the transports.
priv struct MoonCliState {
  engine : String
  runtime_dir : @pathx.Path?
  // Resolved on first use; concurrent first requests may both resolve, which
  // is benign — bundled preparation serializes itself and the results agree.
  mut command : ToolSpawnResolution
  // Module root → the files the last `moon check` reported diagnostics on.
  // The next run pushes an empty array for any file that dropped out, the
  // wire's "squiggles fixed" signal. Bounded by the module roots touched in
  // one app run — a handful of small path arrays.
  published : Map[@pathx.Absolute, Array[@pathx.Absolute]]
  diagnostics : @async.Queue[DiagnosticsPush]
}

///|
fn MoonCliState::MoonCliState(
  engine : String,
  runtime_dir? : @pathx.Path,
) -> MoonCliState {
  {
    engine,
    runtime_dir,
    command: ToolUnresolved,
    published: Map([]),
    diagnostics: Queue(kind=DiscardOldest(256)),
  }
}

///|
/// Forward the bounded diagnostics output for the app lifetime.
async fn MoonCliState::forward_diagnostics(
  self : MoonCliState,
  emit : async (DiagnosticsPush) -> Unit,
) -> Unit {
  for ;; {
    emit(self.diagnostics.get())
  }
}

///|
async fn MoonCliState::resolve_command(self : MoonCliState) -> ToolSpawnConfig? {
  match self.command {
    ToolResolved(config) => return Some(config)
    ToolUnavailable => return None
    ToolUnresolved => ()
  }
  let toolchain = @moonbit.resolve_toolchain(
    self.engine,
    runtime_dir?=self.runtime_dir,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    @moonbit.ToolchainUnavailable as unavailable => {
      @xlog.warn() <?
        {
          "event": "desktop_moon_cli_toolchain_unavailable",
          "reason": "\{unavailable}",
        }
      self.command = ToolUnavailable
      return None
    }
    error => {
      @xlog.warn() <?
        { "event": "desktop_moon_cli_toolchain_error", "error": "\{error}" }
      self.command = ToolUnavailable
      return None
    }
  }
  let config = {
    command: toolchain.moon.to_string(),
    env: Some(toolchain.tool_env()),
  }
  self.command = ToolResolved(config)
  Some(config)
}

///|
/// Run one `moon` command in `cwd`, returning its exit code, stdout text,
/// and stderr text. `None` when the binary cannot be spawned, the output is
/// not text, or the run outlives `MoonCliTimeoutMs` (the child is killed).
/// Cancellation propagates and kills the child with it.
async fn MoonCliState::run_moon(
  self : MoonCliState,
  args : Array[String],
  cwd : @pathx.Absolute,
) -> (Int, String, String)? {
  guard self.resolve_command() is Some(config) else { return None }
  @async.with_timeout_opt(MoonCliTimeoutMs, () => {
    // Moon commands are non-interactive here. Giving them EOF prevents an
    // accidental prompt and remains valid when a Windows GUI host has no
    // standard-input handle to inherit.
    let (code, stdout, stderr) = @processx.collect_output_no_stdin(
      config.command,
      args,
      extra_env?=config.env,
      inherit_env=config.env is None,
      cwd=cwd.0,
    )
    (code, stdout.text(), stderr.text())
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
/// The module root answering for `file` under workspace `dir`: the deepest
/// discovered root containing it, or `None` when no module holds the file.
async fn moon_module_root(
  dir : @pathx.Absolute,
  file : @pathx.Absolute,
) -> @pathx.Absolute? {
  let mut best : @pathx.Absolute? = None
  for root in workspace_module_roots(dir) {
    guard root.contains(file) else { continue }
    if best is Some(current) && current.0.length() >= root.0.length() {
      continue
    }
    best = Some(root)
  }
  best
}

///|
/// The module directories moon commands should be rooted at. The workspace
/// itself when it carries a module/workspace manifest (covering a root project
/// and multi-module `moon.work` workspaces in one root); otherwise its
/// immediate subdirectories that are modules — the common `<cwd>/<project>`
/// layout — one root each. A bounded scan: only the root and its direct
/// children. When more modules than `MaxModuleRoots` sit side by side, the
/// most recently modified win the slots.
async fn workspace_module_roots(
  workspace_dir : @pathx.Absolute,
) -> Array[@pathx.Absolute] {
  if manifest_mtime(workspace_dir) is Some(_) {
    return [workspace_dir]
  }
  let names = @fs.readdir(workspace_dir.to_string(), sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  // Child directories that are modules, paired with their manifest mtime for
  // the recency cut when there are too many.
  let modules : Array[(@pathx.Absolute, Int64)] = []
  for name in names {
    let child = workspace_dir.join((name : @pathx.Relative))
    let is_dir = (@fs.kind(child.to_string()) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
    guard is_dir else { continue }
    guard manifest_mtime(child) is Some(mtime) else { continue }
    modules.push((child, mtime))
  }
  // Drop the oldest until within the cap (rare; usually a handful at most).
  while modules.length() > MaxModuleRoots {
    let mut oldest = 0
    for index, entry in modules {
      if entry.1 < modules[oldest].1 {
        oldest = index
      }
    }
    modules.remove(oldest) |> ignore
  }
  modules.map(entry => entry.0)
}

///|
/// The newest mtime (in whole seconds) among the module manifests directly in
/// `dir`, or `None` when `dir` holds none — i.e. it is not a module root.
async fn manifest_mtime(dir : @pathx.Absolute) -> Int64? {
  let mut newest : Int64? = None
  for name in ["moon.mod", "moon.mod.json", "moon.work"] {
    let path = dir.join((name : @pathx.Relative)).to_string()
    guard @fs.exists(path) else { continue }
    let (seconds, _) = @fs.mtime(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => continue
    }
    newest = match newest {
      Some(current) => Some(if seconds > current { seconds } else { current })
      None => Some(seconds)
    }
  }
  newest
}

///|
/// Route hover by an explicit absolute root plus a root-relative file path,
/// then answer it with one `moon ide hover` run at the requested position.
async fn lsp_hover_op(
  state : MoonCliState,
  payload : LspHoverPayload,
) -> LspHoverReply {
  ignore(LanguagePath::authorized_root(payload.session, payload.root))
  let request_root = WirePath::parse(payload.root)
  let file = request_root.resolve(payload.path)
  guard moon_module_root(request_root.absolute, file) is Some(root) else {
    return no_hover()
  }
  // The op speaks 0-based LSP positions; `--loc` is 1-based.
  let loc = "\{file.0}:\{payload.line + 1}:\{payload.character + 1}"
  guard state.run_moon(["ide", "hover", "--loc", loc, "--output-json"], root)
    is Some((0, output, _)) else {
    // A non-zero exit is `moon ide hover`'s "nothing at this position".
    return no_hover()
  }
  parse_ide_hover(output)
}

///|
/// Serve the editor opening the file at `path`: run `moon check` over its
/// module, reply with the file's diagnostics, and push every other file's
/// changed diagnostics (including explicit clears) as `lsp.diagnostics`
/// events. Best-effort with two distinct empty shapes: a file outside every
/// module truthfully has no diagnostics, while a run that could not produce
/// results (a failed spawn, a broken manifest) answers with the field absent
/// so the client keeps its markers and earlier push state stays untouched.
async fn lsp_open_op(
  state : MoonCliState,
  payload : LspOpenPayload,
) -> LspDiagnosticsReply {
  ignore(LanguagePath::authorized_root(payload.session, payload.root))
  let request_root = WirePath::parse(payload.root)
  let file = request_root.resolve(payload.path)
  guard moon_module_root(request_root.absolute, file) is Some(root) else {
    return { diagnostics: Some([]), }
  }
  guard state.run_moon(["check", "--output-json"], root)
    is Some((code, stdout, stderr)) else {
    return { diagnostics: None, }
  }
  // The pinned toolchain prints diagnostics on stdout (the summary goes to
  // stderr), but the engine's auto-check consumes this command with merged
  // streams — parse both so a moon that reports on stderr still counts. The
  // parser skips non-JSON lines, so the summary noise is harmless.
  let current = parse_check_output(stdout + "\n" + stderr, root)
  // `moon check` exits non-zero for ordinary type errors too — those arrive
  // as parsed diagnostics. A non-zero exit with nothing parsed is the run
  // itself failing (a broken manifest, a plan error): report no data and
  // keep the previous state rather than wrongly clearing every file.
  if current.is_empty() && code != 0 {
    return { diagnostics: None, }
  }
  let previous = state.published.get(root).unwrap_or([])
  for push in diagnostics_pushes(request_root.absolute, previous, current) {
    ignore(state.diagnostics.try_put(push) catch { _ => false })
  }
  let paths : Array[@pathx.Absolute] = []
  for path, _ in current {
    paths.push(path)
  }
  state.published.set(root, paths)
  { diagnostics: Some(current.get(file).unwrap_or([])), }
}

///|
/// The pushes one fresh check result implies: every file's current
/// diagnostics, plus an empty array for each file that had some last run and
/// has none now.
fn diagnostics_pushes(
  request_root : @pathx.Absolute,
  previous : Array[@pathx.Absolute],
  current : Map[@pathx.Absolute, Array[@protocol.LspDiagnostic]],
) -> Array[DiagnosticsPush] raise HostError {
  let pushes : Array[DiagnosticsPush] = []
  let root = request_root.resource_path()
  for path, items in current {
    // `moon check` reports module files. Express only files addressable by the
    // request root in the root-relative notification contract.
    guard path.relative_to(root=request_root) is Some(relative) else {
      continue
    }
    pushes.push({ root, path: relative.0, diagnostics: items, })
  }
  for path in previous {
    if !current.contains(path) {
      guard path.relative_to(root=request_root) is Some(relative) else {
        continue
      }
      pushes.push({ root, path: relative.0, diagnostics: [], })
    }
  }
  pushes
}

///|
/// Group `moon check --output-json` stdout into LSP-shaped diagnostic arrays
/// per absolute file path. The pinned toolchain reports absolute paths, but
/// older moons emit them relative to the checked module — resolve those
/// against `root` so lookups and pushes always speak the absolute form the
/// wire expects. Lines that are not diagnostic JSON (progress noise, partial
/// writes) are skipped.
fn parse_check_output(
  output : String,
  root : @pathx.Absolute,
) -> Map[@pathx.Absolute, Array[@protocol.LspDiagnostic]] {
  let by_file : Map[@pathx.Absolute, Array[@protocol.LspDiagnostic]] = Map([])
  for line in output.split("\n") {
    let line = line.trim()
    guard !line.is_empty() else { continue }
    let json = @json.parse(line) catch { _ => continue }
    guard json
      is {
        "$message_type": String("diagnostic"),
        "level": String(level),
        "path": String(path),
        "message": String(message),
        ..
      } else {
      continue
    }
    // A file- or module-level diagnostic (the engine's auto-check parser
    // documents the shape) carries no `loc`; anchor it at the file start so
    // the run still counts as real results and the error can surface.
    let span = if json is { "loc": String(loc), .. } {
      parse_span(loc)
    } else {
      None
    }
    let (start_line, start_col, end_line, end_col) = span.unwrap_or(
      (0, 0, 0, 0),
    )
    guard absolute_diagnostic_path(path, root) is Some(path) else { continue }
    by_file
    .get_or_init(path, () => [])
    .push({
      range: {
        start: { line: start_line, character: start_col, },
        end: { line: end_line, character: end_col, },
      },
      severity: Some(check_severity(level)),
      message,
      tags: check_tags(message),
    })
  }
  by_file
}

///|
/// A diagnostic's path in the absolute form the wire speaks. Older moons
/// report paths relative to the checked module; resolve those against the
/// module root.
fn absolute_diagnostic_path(
  path : String,
  root : @pathx.Absolute,
) -> @pathx.Absolute? {
  let path = @pathx.Path(path)
  if path.to_absolute() is Some(absolute) {
    Some(absolute.normalize())
  } else if path.to_relative() is Some(relative) {
    root.to_path().join(relative).normalize().to_absolute()
  } else {
    None
  }
}

///|
/// Map moonc's diagnostic level to an LSP `DiagnosticSeverity`.
fn check_severity(level : String) -> Int {
  match level {
    "error" => 1
    "warning" => 2
    _ => 3
  }
}

///|
/// The LSP `tags` the viewer renders specially — faded for unnecessary code,
/// struck through for deprecated use — recovered from moonc's message prefix,
/// the only place the diagnostic JSON carries the warning's name.
fn check_tags(message : String) -> Array[Int]? {
  if message.has_prefix("Warning (unused") {
    Some([1])
  } else if message.has_prefix("Warning (deprecated") {
    Some([2])
  } else {
    None
  }
}

///|
/// Decode one `moon ide hover --output-json` object into the flat reply the
/// front-end consumes: the markdown sections joined under rules, and the
/// 1-based `range` shifted to the 0-based positions the wire speaks. Anything
/// unrecognized collapses to `no_hover`.
fn parse_ide_hover(output : String) -> LspHoverReply {
  let json = @json.parse(output.trim()) catch { _ => return no_hover() }
  guard json is { "contents": Array(parts), .. } else { return no_hover() }
  let sections : Array[String] = []
  for part in parts {
    guard part is String(text) else { continue }
    let text = text.trim()
    if !text.is_empty() {
      sections.push(text.to_owned())
    }
  }
  guard !sections.is_empty() else { return no_hover() }
  let value = sections.join("\n\n---\n\n")
  let range = if json is { "range": String(span), .. } {
    parse_span(span)
  } else {
    None
  }
  match range {
    Some((start_line, start_character, end_line, end_character)) =>
      {
        value,
        markdown: true,
        has_range: true,
        start_line,
        start_character,
        end_line,
        end_character,
      }
    None =>
      {
        value,
        markdown: true,
        has_range: false,
        start_line: 0,
        start_character: 0,
        end_line: 0,
        end_character: 0,
      }
  }
}

///|
/// Parse moonc's 1-based `"line:col-line:col"` span into 0-based
/// `(start_line, start_col, end_line, end_col)`.
fn parse_span(span : StringView) -> (Int, Int, Int, Int)? {
  guard span.split_once("-") is Some((start, end_)) else { return None }
  guard parse_position(start) is Some((start_line, start_col)) &&
    parse_position(end_) is Some((end_line, end_col)) else {
    return None
  }
  Some((start_line, start_col, end_line, end_col))
}

///|
fn parse_position(position : StringView) -> (Int, Int)? {
  guard position.split_once(":") is Some((line, col)) else { return None }
  let line = @string.parse_int(line) catch { _ => return None }
  let col = @string.parse_int(col) catch { _ => return None }
  guard line >= 1 && col >= 1 else { return None }
  Some((line - 1, col - 1))
}

///|
/// An empty hover reply — "nothing to show here".
fn no_hover() -> LspHoverReply {
  {
    value: "",
    markdown: false,
    has_range: false,
    start_line: 0,
    start_character: 0,
    end_line: 0,
    end_character: 0,
  }
}

///|
test "parse_span shifts 1-based moonc spans to 0-based positions" {
  assert_eq(parse_span("9:7-9:19"), Some((8, 6, 8, 18)))
  assert_eq(parse_span("15:3-16:1"), Some((14, 2, 15, 0)))
  assert_eq(parse_span("0:1-1:1"), None)
  assert_eq(parse_span("9:7"), None)
  assert_eq(parse_span("a:b-c:d"), None)
}

///|
test "parse_ide_hover joins sections and shifts the range" {
  let reply = parse_ide_hover(
    "{\"range\":\"10:3-10:6\",\"contents\":[\"```moonbit\\nfn add(a : Int, b : Int) -> Int\\n```\",\"\\n Adds two integers together.\"]}",
  )
  assert_eq(
    reply.value,
    "```moonbit\nfn add(a : Int, b : Int) -> Int\n```\n\n---\n\nAdds two integers together.",
  )
  assert_true(reply.markdown)
  assert_true(reply.has_range)
  assert_eq(
    (
      reply.start_line,
      reply.start_character,
      reply.end_line,
      reply.end_character,
    ),
    (9, 2, 9, 5),
  )
}

///|
test "parse_ide_hover collapses malformed or empty output" {
  assert_eq(parse_ide_hover("").value, "")
  assert_eq(parse_ide_hover("No hover information found").value, "")
  assert_eq(parse_ide_hover("{\"contents\":[]}").value, "")
  let no_range = parse_ide_hover("{\"contents\":[\"Int\"]}")
  assert_eq(no_range.value, "Int")
  assert_false(no_range.has_range)
}

///|
#cfg(not(platform="windows"))
test "parse_check_output groups diagnostics per file in LSP shape" {
  guard @pathx.Path("/w").to_absolute() is Some(root) else {
    fail("expected an absolute fixture root")
  }
  let warning =
    #|{"$message_type":"diagnostic","level":"warning","error_code":2,"path":"/w/src/lib.mbt","loc":"9:7-9:19","message":"Warning (unused_value): Unused variable 'x'","context":"..."}
  let error_ =
    #|{"$message_type":"diagnostic","level":"error","error_code":4014,"path":"/w/src/lib.mbt","loc":"15:3-15:15","message":"Expr Type Mismatch","context":"..."}
  let other =
    #|{"$message_type":"diagnostic","level":"warning","error_code":1,"path":"/w/src/other.mbt","loc":"1:1-1:2","message":"Warning (deprecated): gone","context":"..."}
  // Older moons report the path relative to the checked module.
  let relative =
    #|{"$message_type":"diagnostic","level":"warning","error_code":2,"path":"src/rel.mbt","loc":"2:1-2:2","message":"Warning (unused_value): Unused variable 'y'","context":"..."}
  // A file-level diagnostic carries no `loc`: anchored at the file start.
  let file_level =
    #|{"$message_type":"diagnostic","level":"error","path":"/w/moon.pkg","message":"module-level boom"}
  let noise = "Finished. moon: ran 2 tasks"
  let grouped = parse_check_output(
    [warning, error_, other, relative, file_level, noise, ""].join("\n"),
    root,
  )
  guard @pathx.Path("/w/src/rel.mbt").to_absolute() is Some(relative_path) &&
    @pathx.Path("/w/moon.pkg").to_absolute() is Some(package_path) &&
    @pathx.Path("/w/src/lib.mbt").to_absolute() is Some(lib_path) &&
    @pathx.Path("/w/src/other.mbt").to_absolute() is Some(other_path) else {
    fail("expected absolute diagnostic fixture paths")
  }
  assert_true(grouped.get(relative_path) is Some([_]))
  guard grouped.get(package_path) is Some([anchored]) else {
    fail("expected the loc-less diagnostic to survive")
  }
  assert_eq(anchored, {
    range: {
      start: { line: 0, character: 0, },
      end: { line: 0, character: 0, },
    },
    severity: Some(1),
    message: "module-level boom",
    tags: None,
  })
  guard grouped.get(lib_path) is Some([first, second]) else {
    fail("expected two diagnostics for lib.mbt")
  }
  assert_eq(first, {
    range: {
      start: { line: 8, character: 6, },
      end: { line: 8, character: 18, },
    },
    severity: Some(2),
    message: "Warning (unused_value): Unused variable 'x'",
    tags: Some([1]),
  })
  assert_eq(second, {
    range: {
      start: { line: 14, character: 2, },
      end: { line: 14, character: 14, },
    },
    severity: Some(1),
    message: "Expr Type Mismatch",
    tags: None,
  })
  guard grouped.get(other_path) is Some([deprecated]) else {
    fail("expected one diagnostic for other.mbt")
  }
  assert_eq(deprecated, {
    range: {
      start: { line: 0, character: 0, },
      end: { line: 0, character: 1, },
    },
    severity: Some(2),
    message: "Warning (deprecated): gone",
    tags: Some([2]),
  })
}

///|
#cfg(not(platform="windows"))
test "diagnostics_pushes uses root-relative paths and clears dropped files" {
  guard @pathx.Path("/w").to_absolute() is Some(root) else {
    fail("expected an absolute request root")
  }
  guard @pathx.Path("/w/a.mbt").to_absolute() is Some(a) &&
    @pathx.Path("/w/b.mbt").to_absolute() is Some(b) else {
    fail("expected absolute diagnostic fixture paths")
  }
  let boom : @protocol.LspDiagnostic = {
    range: {
      start: { line: 0, character: 0, },
      end: { line: 0, character: 1, },
    },
    severity: Some(1),
    message: "boom",
    tags: None,
  }
  let current : Map[@pathx.Absolute, Array[@protocol.LspDiagnostic]] = Map([
    (a, [boom]),
  ])
  let pushes = diagnostics_pushes(root, [a, b], current)
  assert_eq(pushes.length(), 2)
  assert_eq(pushes[0].root, "/w")
  assert_eq(pushes[0].path, "a.mbt")
  assert_eq(pushes[0].diagnostics, [boom])
  assert_eq(pushes[1].root, "/w")
  assert_eq(pushes[1].path, "b.mbt")
  assert_eq(pushes[1].diagnostics, [])
}

///|
/// Search the explicit root's symbols for `query` — the same fuzzy
/// match the LSP `workspace/symbol` request performs, served by
/// `moon ide workspace-symbols`. Fans the query across every module root,
/// relativizing each result against the supplied root (the common ancestor)
/// so rows from `<root>/a`
/// and `<root>/b` come back as `a/...` and `b/...`. Sequential is fine for the
/// usual one or two roots. Best-effort: a missing root, a failed run, or
/// nothing matching all yield no symbols; an empty query is valid — it lists
/// every symbol, which backs the bare `#` menu (capped like any other result).
async fn workspace_symbols_op(
  state : MoonCliState,
  payload : WorkspaceSymbolsPayload,
) -> WorkspaceSymbolsReply {
  let workspace = LanguagePath::authorized_root(payload.session, payload.root)
  let symbols : Array[SymbolItem] = []
  for root in workspace_module_roots(workspace) {
    if symbols.length() >= MaxSymbolResults {
      break
    }
    guard state.run_moon(
        ["ide", "workspace-symbols", payload.query, "--json"],
        root,
      )
      is Some((0, output, _)) else {
      continue
    }
    for symbol in parse_symbol_rows(output, workspace) {
      if symbols.length() >= MaxSymbolResults {
        break
      }
      symbols.push(symbol)
    }
  }
  { symbols, }
}

///|
/// Flatten a `moon ide workspace-symbols --json` array into the rows the
/// front-end consumes: the declaration head reduced to the bare symbol name,
/// the kind name mapped to its LSP `SymbolKind` number, the absolute path
/// relativized against the workspace, and the 1-based span shifted to the
/// 0-based range the wire speaks (all zeros when the row carries none). A row
/// missing a name or path is skipped; unparseable output yields no symbols.
fn parse_symbol_rows(
  output : String,
  workspace : @pathx.Absolute,
) -> Array[SymbolItem] {
  let json = @json.parse(output.trim()) catch { _ => return [] }
  guard json is Array(items) else { return [] }
  let symbols : Array[SymbolItem] = []
  for item in items {
    if symbols.length() >= MaxSymbolResults {
      break
    }
    guard item is Object(fields) else { continue }
    guard fields.get("name") is Some(String(name)) &&
      bare_symbol_name(name) is Some(name) else {
      continue
    }
    guard fields.get("location") is Some(Object(location)) else { continue }
    guard location.get("path") is Some(String(path)) else { continue }
    let kind = if fields.get("kind") is Some(String(kind)) {
      lsp_symbol_kind(kind)
    } else {
      None
    }
    let display_path = if @pathx.Path(path).to_absolute() is Some(absolute) &&
      absolute.relative_to(root=workspace) is Some(relative) {
      relative.0
    } else {
      path
    }
    symbols.push({
      name,
      kind,
      // The declaration head already carries any `Type::` qualifier in the
      // name; moon reports no separate container.
      container: None,
      path: display_path,
      range: symbol_row_range(location),
    })
  }
  symbols
}

///|
/// The bare symbol name out of a declaration head — the last
/// whitespace-separated token, so `pub fn Point::flip` reads as `Point::flip`
/// and `const MaxSize` as `MaxSize`. `None` for a blank head.
fn bare_symbol_name(head : String) -> String? {
  guard [..head.trim().split(" ")] is [.., last] && !last.is_empty() else {
    return None
  }
  Some(last.to_owned())
}

///|
/// A symbol row's zero-based range from its 1-based `"line:col-line:col"`
/// span, or the wire's all-zeros stand-in when the row carries none.
fn symbol_row_range(location : Map[String, Json]) -> SymbolRange {
  guard location.get("range") is Some(String(span)) &&
    parse_span(span) is Some((start_line, start_col, end_line, end_col)) else {
    return { start: { line: 0, col: 0, }, end: { line: 0, col: 0, }, }
  }
  {
    start: { line: start_line, col: start_col, },
    end: { line: end_line, col: end_col, },
  }
}

///|
/// Map an LSP `SymbolKind` name — what `moon ide workspace-symbols` emits —
/// to its protocol number; `None` for a name outside the LSP set.
fn lsp_symbol_kind(kind : String) -> Int? {
  match kind {
    "File" => Some(1)
    "Module" => Some(2)
    "Namespace" => Some(3)
    "Package" => Some(4)
    "Class" => Some(5)
    "Method" => Some(6)
    "Property" => Some(7)
    "Field" => Some(8)
    "Constructor" => Some(9)
    "Enum" => Some(10)
    "Interface" => Some(11)
    "Function" => Some(12)
    "Variable" => Some(13)
    "Constant" => Some(14)
    "String" => Some(15)
    "Number" => Some(16)
    "Boolean" => Some(17)
    "Array" => Some(18)
    "Object" => Some(19)
    "Key" => Some(20)
    "Null" => Some(21)
    "EnumMember" => Some(22)
    "Struct" => Some(23)
    "Event" => Some(24)
    "Operator" => Some(25)
    "TypeParameter" => Some(26)
    _ => None
  }
}

///|
test "parse_symbol_rows strips declaration heads and relativizes paths" {
  guard @pathx.Path("/w").to_absolute() is Some(workspace) else {
    fail("expected an absolute fixture workspace")
  }
  let output =
    #|[{"name":"pub fn Point::flip","kind":"Function","location":{"path":"/w/src/kinds.mbt","range":"19:1-21:2"}},
    #| {"name":"pub struct Point","kind":"Object","location":{"path":"/w/src/kinds.mbt","range":"2:1-5:2"}},
    #| {"name":"const MaxSize","kind":"Variable","location":{"path":"/elsewhere/x.mbt"}},
    #| {"name":"","kind":"Function","location":{"path":"/w/a.mbt","range":"1:1-1:2"}},
    #| {"name":"pub fn orphan","kind":"Mystery","location":{"path":"/w/a.mbt","range":"bad"}}]
  let rows = parse_symbol_rows(output, workspace)
  guard rows is [flip, point, max_size, orphan] else {
    fail("expected four rows, got \{rows.length()}")
  }
  assert_eq(flip.name, "Point::flip")
  assert_eq(flip.kind, Some(12))
  assert_eq(flip.path, "src/kinds.mbt")
  assert_eq(ToJson::to_json(flip.range), {
    "start": { "line": 18, "col": 0 },
    "end": { "line": 20, "col": 1 },
  })
  assert_eq(point.name, "Point")
  assert_eq(point.kind, Some(19))
  // A row outside the workspace keeps its absolute path; a missing range
  // reads as the all-zeros stand-in.
  assert_eq(max_size.name, "MaxSize")
  assert_eq(max_size.path, "/elsewhere/x.mbt")
  assert_eq(ToJson::to_json(max_size.range), {
    "start": { "line": 0, "col": 0 },
    "end": { "line": 0, "col": 0 },
  })
  // An unknown kind and a malformed span degrade, not skip.
  assert_eq(orphan.name, "orphan")
  assert_eq(orphan.kind, None)
  assert_eq(ToJson::to_json(orphan.range), {
    "start": { "line": 0, "col": 0 },
    "end": { "line": 0, "col": 0 },
  })
}

///|
test "parse_symbol_rows tolerates unparseable output" {
  guard @pathx.Path("/w").to_absolute() is Some(workspace) else {
    fail("expected an absolute fixture workspace")
  }
  assert_eq(parse_symbol_rows("", workspace).length(), 0)
  assert_eq(parse_symbol_rows("No symbols found", workspace).length(), 0)
  assert_eq(parse_symbol_rows("{\"not\":\"an array\"}", workspace).length(), 0)
}
