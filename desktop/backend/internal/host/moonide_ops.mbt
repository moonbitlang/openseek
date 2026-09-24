// Host-owned Moon IDE navigation (`moonide.definition` / `moonide.references`).
// Each request invokes the checked-out workspace through `moon ide`, whose
// package/build-index semantics are the source of truth for definition and
// reference locations. The `lsp.*` ops (hover, diagnostics, symbol search)
// live in moon_cli_ops.mbt and shell out to the same CLI.

///|
priv enum MoonIdeQuery {
  Definition
  References
}

///|
priv struct MoonIdeRequest {
  lexical_workspace : @pathx.Absolute
  physical_workspace : @pathx.Absolute
  relative_path : String
  line : Int
  column : Int
}

///|
priv struct MoonIdeSpawnConfig {
  executable : String
  extra_env : Map[String, String]?
}

///|
fn moonide_codelens_args(path : String) -> Array[String] {
  ["ide", "codelens", path, "--json"]
}

///|
fn MoonIdeQuery::subcommand(self : MoonIdeQuery) -> String {
  match self {
    Definition => "peek-def"
    References => "find-references"
  }
}

///|
/// The argv handed directly to the process API — never a shell string. `path`
/// has already been reduced to a workspace-relative address, so an absolute
/// client path cannot choose cwd or escape through the CLI.
fn MoonIdeQuery::args(
  self : MoonIdeQuery,
  path : String,
  line : Int,
  column : Int,
) -> Array[String] {
  ["ide", self.subcommand(), "--loc", "\{path}:\{line}:\{column}", "--json"]
}

///|
/// Resolve an already-absolute physical path below `workspace` to the CLI's
/// normalized relative form. Normalizing before the containment check closes
/// lexical `..` escapes; the async owner additionally canonicalizes both paths
/// with `realpath` before calling this helper.
fn moonide_relative_path(
  workspace : @pathx.Absolute,
  absolute : String,
) -> String? {
  let candidate = @pathx.Path(absolute)
  guard candidate.is_host_absolute() else { return None }
  let root = workspace.normalize()
  let candidate = candidate.normalize()
  guard candidate.to_absolute() is Some(candidate) else { return None }
  guard candidate.relative_to(root~) is Some(relative) && !relative.is_root() else {
    return None
  }
  Some(relative.0)
}

///|
/// Establish both root identities from the explicit editor root: the lexical
/// spelling used by existing client models, and the canonical physical root
/// used for CLI cwd, relative locations, and symlink containment.
async fn resolve_moonide_request(
  payload : MoonIdeNavigationPayload,
) -> MoonIdeRequest {
  guard payload.line > 0 && payload.column > 0 else {
    raise PayloadError("line and column must be positive one-based integers")
  }
  let location = LanguagePath::resolve(
    payload.session,
    payload.root,
    payload.path,
  )
  {
    lexical_workspace: location.lexical_root,
    physical_workspace: location.physical_root,
    relative_path: location.physical_relative.0,
    line: payload.line,
    column: payload.column,
  }
}

///|
/// Diagnostics win over fallback: every anomaly — a resolution error, no
/// toolchain anywhere, or a toolchain without a usable `moon` — surfaces to
/// the caller as a [HostError] naming the cause, instead of spawning
/// whatever `moon` the ambient environment happens to serve.
async fn moonide_spawn_config(state : HostState) -> MoonIdeSpawnConfig {
  let toolchain = @moonbit.resolve_toolchain(
    state.engine,
    runtime_dir?=state.runtime_dir,
  ) catch {
    @moonbit.ToolchainUnavailable as unavailable =>
      raise HostError("\{unavailable}")
    error => raise HostError("could not resolve a MoonBit toolchain: \{error}")
  }
  {
    executable: toolchain.moon.to_string(),
    extra_env: Some(toolchain.tool_env()),
  }
}

///|
fn positive_position(text : StringView) -> (Int, Int)? {
  guard [..text.split(":")] is [line_text, column_text] else { return None }
  let line = @string.parse_int(line_text) catch { _ => return None }
  let column = @string.parse_int(column_text) catch { _ => return None }
  if line > 0 && column > 0 {
    Some((line, column))
  } else {
    None
  }
}

///|
/// Parse Moon IDE's compact, one-based `line:column-line:column` range.
/// Reversed and non-positive ranges are malformed rows.
fn parse_moonide_range(text : String) -> (Int, Int, Int, Int)? {
  guard [..text.split("-")] is [start_text, end_text] else { return None }
  guard positive_position(start_text) is Some((start_line, start_column)) &&
    positive_position(end_text) is Some((end_line, end_column)) else {
    return None
  }
  guard end_line > start_line ||
    (end_line == start_line && end_column >= start_column) else {
    return None
  }
  Some((start_line, start_column, end_line, end_column))
}

///|
/// Normalize one CLI result into an absolute candidate. Current Moon IDE emits
/// absolute paths, but accepting relative output against the physical cwd is
/// harmless. This helper deliberately makes no security decision: the owner
/// follows `realpath` and checks the physical workspace afterwards.
fn moonide_result_path(
  physical_workspace : @pathx.Absolute,
  raw : String,
) -> String {
  let raw_path = @pathx.Path(raw)
  if raw_path.to_relative() is Some(relative) {
    physical_workspace.join(relative).normalize().to_string()
  } else {
    raw_path.normalize().to_string()
  }
}

///|
/// Decode the stable Moon IDE JSON shape (`null` or `[{path, range}]`). A bad
/// document is an operation failure; bad individual rows are omitted so one
/// stale compiler location cannot poison the other valid navigation targets.
fn parse_moonide_output(
  output : String,
  physical_workspace : @pathx.Absolute,
) -> MoonIdeLocationsReply raise HostError {
  let json = @json.parse(output) catch {
    _ => raise HostError("moon ide returned malformed JSON")
  }
  let items = match json {
    Null => return { locations: [], }
    Array(items) => items
    _ => raise HostError("moon ide returned an unexpected JSON value")
  }
  let locations : Array[MoonIdeLocation] = []
  for item in items {
    guard item is Object(fields) &&
      fields.get("path") is Some(String(path)) &&
      fields.get("range") is Some(String(range)) else {
      continue
    }
    guard parse_moonide_range(range)
      is Some((start_line, start_column, end_line, end_column)) else {
      continue
    }
    let path = moonide_result_path(physical_workspace, path)
    locations.push({ path, start_line, start_column, end_line, end_column, })
  }
  { locations, }
}

///|
/// The CLI emits a plain absolute file path.
/// Preserve literal percent escapes; only editor resource URIs use URI encoding.
fn parse_moonide_codelens_location(json : Json) -> MoonIdeLocation? {
  guard json is Object(fields) &&
    fields.get("path") is Some(String(raw_path)) &&
    fields.get("range") is Some(String(raw_range)) &&
    parse_moonide_range(raw_range)
    is Some((start_line, start_column, end_line, end_column)) &&
    @pathx.Path(raw_path).to_absolute() is Some(absolute) else {
    return None
  }
  let path = absolute.normalize().to_string()
  Some({ path, start_line, start_column, end_line, end_column, })
}

///|
/// Convert the CLI's one-based compact range to the editor's zero-based range.
fn parse_moonide_codelens_range(json : Json) -> @protocol.LspRange? {
  guard json is String(text) &&
    parse_moonide_range(text)
    is Some((start_line, start_column, end_line, end_column)) else {
    return None
  }
  Some({
    start: { line: start_line - 1, character: start_column - 1, },
    end: { line: end_line - 1, character: end_column - 1, },
  })
}

///|
fn parse_moonide_codelens_position(json : Json) -> @protocol.LspPosition? {
  guard parse_moonide_codelens_range(json) is Some(range) &&
    range.start == range.end else {
    return None
  }
  Some(range.start)
}

///|
/// Decode Moon IDE's CodeLens array with compact one-based ranges. The command ids are
/// the complete supported surface. A malformed row is isolated; a malformed
/// document is an operation failure. The CLI's first command argument is
/// checked for shape but never used as source identity — the authorized
/// request owns that identity.
fn parse_moonide_codelens_output(
  output : String,
) -> MoonIdeCodeLensReply raise HostError {
  let json = @json.parse(output) catch {
    _ => raise HostError("moon ide codelens returned malformed JSON")
  }
  guard json is Array(items) else {
    raise HostError("moon ide codelens returned an unexpected JSON value")
  }
  let lenses : Array[@protocol.MoonIdeCodeLens] = []
  for item in items {
    guard item is Object(fields) &&
      fields.get("range") is Some(raw_range) &&
      fields.get("command") is Some(Object(command)) &&
      command.get("title") is Some(String(title)) &&
      !title.trim().is_empty() &&
      command.get("command") is Some(String(command_id)) &&
      command.get("arguments") is Some(Array(arguments)) else {
      continue
    }
    guard parse_moonide_codelens_range(raw_range) is Some(range) else {
      continue
    }
    let action : MoonIdeCodeLensAction = match (command_id, arguments) {
      (
        "moonbit.action.goToLocations",
        [String(_), raw_position, Array(raw_locations)],
      ) => {
        guard parse_moonide_codelens_position(raw_position) is Some(position) else {
          continue
        }
        let locations : Array[MoonIdeLocation] = []
        for raw_location in raw_locations {
          if parse_moonide_codelens_location(raw_location) is Some(location) {
            locations.push(location)
          }
        }
        Local(position~, locations~)
      }
      ("moonbit.executeReferenceProvider", [String(_), raw_position]) => {
        guard parse_moonide_codelens_position(raw_position) is Some(position) else {
          continue
        }
        Outside(position~)
      }
      _ => continue
    }
    lenses.push({ range, title, action, })
  }
  { lenses, }
}

///|
/// Map one already-canonical result from the physical security identity back
/// to the supplied root's lexical spelling. This keeps model URIs aligned with
/// `fs.read_file` even when that root itself is a symlink.
fn moonide_client_path(
  lexical_workspace : @pathx.Absolute,
  physical_workspace : @pathx.Absolute,
  physical_result : String,
) -> String? raise HostError {
  guard moonide_relative_path(physical_workspace, physical_result)
    is Some(relative) else {
    return None
  }
  Some(lexical_workspace.join(Relative(relative)).normalize().resource_path())
}

///|
/// Follow result symlinks and retain only files physically beneath the exact
/// canonical workspace that owned the request. A safe result is mapped back
/// to the lexical attached root before crossing the wire. Unreadable/stale
/// paths are dropped, while line and column numbers pass through unchanged.
async fn canonical_moonide_locations(
  reply : MoonIdeLocationsReply,
  lexical_workspace : @pathx.Absolute,
  physical_workspace : @pathx.Absolute,
) -> MoonIdeLocationsReply {
  let locations : Array[MoonIdeLocation] = []
  for location in reply.locations {
    let canonical = @fs.realpath(location.path) catch { _ => continue }
    guard moonide_client_path(lexical_workspace, physical_workspace, canonical)
      is Some(path) else {
      continue
    }
    locations.push({
      path,
      start_line: location.start_line,
      start_column: location.start_column,
      end_line: location.end_line,
      end_column: location.end_column,
    })
  }
  { locations, }
}

///|
async fn canonical_moonide_codelenses(
  reply : MoonIdeCodeLensReply,
  lexical_workspace : @pathx.Absolute,
  physical_workspace : @pathx.Absolute,
) -> MoonIdeCodeLensReply {
  let lenses : Array[@protocol.MoonIdeCodeLens] = []
  for lens in reply.lenses {
    let action : MoonIdeCodeLensAction = match lens.action {
      Outside(position~) => Outside(position~)
      Local(position~, locations~) => {
        let canonical = canonical_moonide_locations(
          { locations, },
          lexical_workspace,
          physical_workspace,
        )
        Local(position~, locations=canonical.locations)
      }
    }
    lenses.push({ range: lens.range, title: lens.title, action, })
  }
  { lenses, }
}

///|
async fn moonide_navigation_op(
  state : HostState,
  query : MoonIdeQuery,
  payload : MoonIdeNavigationPayload,
) -> MoonIdeLocationsReply {
  let request = resolve_moonide_request(payload)
  let config = moonide_spawn_config(state)
  let args = query.args(request.relative_path, request.line, request.column)
  let (code, stdout, stderr) = @processx.collect_output_no_stdin(
    config.executable,
    args,
    extra_env?=config.extra_env,
    inherit_env=config.extra_env is None,
    cwd=request.physical_workspace.to_string(),
  ) catch {
    error => raise HostError("could not run moon ide: \{error}")
  }
  if code != 0 {
    let stderr = (stderr.text() catch { _ => "" }).trim().to_owned()
    let stdout = (stdout.text() catch { _ => "" }).trim().to_owned()
    let detail = if !stderr.is_empty() { stderr } else { stdout }
    raise HostError(
      if detail.is_empty() {
        "moon ide \{query.subcommand()} exited with code \{code}"
      } else {
        detail
      },
    )
  }
  let output = stdout.text() catch {
    _ => raise HostError("moon ide returned non-text output")
  }
  canonical_moonide_locations(
    parse_moonide_output(output, request.physical_workspace),
    request.lexical_workspace,
    request.physical_workspace,
  )
}

///|
async fn moonide_navigation_reply(
  state : HostState,
  query : MoonIdeQuery,
  payload : MoonIdeNavigationPayload,
) -> @protocol.MoonIdeNavigationReply {
  let reply = moonide_navigation_op(state, query, payload) catch {
    error if @async.is_being_cancelled() => raise error
    error => return NavigationError("\{error}")
  }
  NavigationLocations(reply)
}

///|
async fn moonide_definition_op(
  state : HostState,
  payload : MoonIdeNavigationPayload,
) -> @protocol.MoonIdeNavigationReply {
  moonide_navigation_reply(state, Definition, payload)
}

///|
async fn moonide_references_op(
  state : HostState,
  payload : MoonIdeNavigationPayload,
) -> @protocol.MoonIdeNavigationReply {
  moonide_navigation_reply(state, References, payload)
}

///|
fn moonide_codelens_failure_text(
  code : Int,
  stream : String,
  data : &@io.Data,
) -> String raise HostError {
  data.text() catch {
    error =>
      raise HostError(
        "moon ide codelens exited with code \{code}, but \{stream} was not valid UTF-8: \{error}",
      )
  }
}

///|
async fn moonide_codelens_op(
  state : HostState,
  payload : MoonIdeCodeLensPayload,
) -> MoonIdeCodeLensReply {
  let location = LanguagePath::resolve(
    payload.session,
    payload.root,
    payload.path,
  )
  let config = moonide_spawn_config(state)
  let (code, stdout, stderr) = @processx.collect_output_no_stdin(
    config.executable,
    moonide_codelens_args(location.physical_relative.0),
    extra_env?=config.extra_env,
    inherit_env=config.extra_env is None,
    cwd=location.physical_root.to_string(),
  ) catch {
    error => raise HostError("could not run moon ide codelens: \{error}")
  }
  if code != 0 {
    let stderr = moonide_codelens_failure_text(code, "stderr", stderr)
      .trim()
      .to_owned()
    let stdout = moonide_codelens_failure_text(code, "stdout", stdout)
      .trim()
      .to_owned()
    let detail = if !stderr.is_empty() { stderr } else { stdout }
    raise HostError(
      if detail.is_empty() {
        "moon ide codelens exited with code \{code}"
      } else {
        detail
      },
    )
  }
  let output = stdout.text() catch {
    _ => raise HostError("moon ide codelens returned non-text output")
  }
  canonical_moonide_codelenses(
    parse_moonide_codelens_output(output),
    location.lexical_root,
    location.physical_root,
  )
}

///|
test "Moon IDE commands use relative one-based locations without a shell" {
  assert_eq(Definition.args("src/main.mbt", 12, 5), [
    "ide", "peek-def", "--loc", "src/main.mbt:12:5", "--json",
  ])
  assert_eq(References.args("src/main.mbt", 12, 5), [
    "ide", "find-references", "--loc", "src/main.mbt:12:5", "--json",
  ])
  assert_eq(moonide_codelens_args("src/main.mbt"), [
    "ide", "codelens", "src/main.mbt", "--json",
  ])
}

///|
test "Moon IDE CodeLens failure keeps output decoding errors distinct" {
  let mut stdout_failure : String? = None
  ignore(moonide_codelens_failure_text(17, "stdout", b"\xff")) catch {
    HostError(detail) => stdout_failure = Some(detail)
  }
  guard stdout_failure is Some(stdout_message) else {
    fail("invalid stdout did not raise HostError")
  }
  assert_true(stdout_message.contains("exited with code 17"))
  assert_true(stdout_message.contains("stdout"))
  assert_true(stdout_message.contains("UTF-8"))
  let mut stderr_failure : String? = None
  ignore(moonide_codelens_failure_text(17, "stderr", b"\xff")) catch {
    HostError(detail) => stderr_failure = Some(detail)
  }
  guard stderr_failure is Some(stderr_message) else {
    fail("invalid stderr did not raise HostError")
  }
  assert_true(stderr_message.contains("exited with code 17"))
  assert_true(stderr_message.contains("stderr"))
  assert_true(stderr_message.contains("UTF-8"))
}

///|
test "Moon IDE relative paths normalize in-root paths and reject escapes" {
  let workspace = @pathx.Path("/workspace").resolve()
  assert_eq(
    moonide_relative_path(workspace, "/workspace/src/../main.mbt"),
    Some("main.mbt"),
  )
  assert_true(moonide_relative_path(workspace, "/outside/main.mbt") is None)
  assert_true(
    moonide_relative_path(workspace, "/workspace/../../outside.mbt") is None,
  )
  assert_true(moonide_relative_path(workspace, "relative.mbt") is None)
  assert_true(moonide_relative_path(workspace, "/workspace") is None)
}

///|
test "Moon IDE parser expands ranges before physical security filtering" {
  let workspace = @pathx.Path("/workspace").resolve()
  let reply = parse_moonide_output(
    (
      #|[
      #|  {"path":"/workspace/src/a.mbt","range":"2:3-4:5"},
      #|  {"path":"src/b.mbt","range":"7:8-7:12"},
      #|  {"path":"/other/c.mbt","range":"1:1-1:2"},
      #|  {"path":"../escape.mbt","range":"1:1-1:2"},
      #|  {"path":"/workspace/bad.mbt","range":"0:1-1:2"},
      #|  {"path":"/workspace/reversed.mbt","range":"3:4-2:1"},
      #|  {"path":"/workspace/missing-range.mbt"}
      #|]
    ),
    workspace,
  )
  assert_eq(ToJson::to_json(reply), {
    "locations": [
      {
        "path": "/workspace/src/a.mbt",
        "start_line": 2,
        "start_column": 3,
        "end_line": 4,
        "end_column": 5,
      },
      {
        "path": "/workspace/src/b.mbt",
        "start_line": 7,
        "start_column": 8,
        "end_line": 7,
        "end_column": 12,
      },
      {
        "path": "/other/c.mbt",
        "start_line": 1,
        "start_column": 1,
        "end_line": 1,
        "end_column": 2,
      },
      {
        "path": "/escape.mbt",
        "start_line": 1,
        "start_column": 1,
        "end_line": 1,
        "end_column": 2,
      },
    ],
  })
  assert_true(parse_moonide_output("null", workspace).locations.is_empty())
}

///|
test "physical Moon IDE results keep the supplied lexical root identity" {
  let lexical = @pathx.Path("/attached/project-link").resolve()
  let physical = @pathx.Path("/private/projects/project").resolve()
  assert_eq(
    moonide_client_path(
      lexical, physical, "/private/projects/project/src/main.mbt",
    ),
    Some("/attached/project-link/src/main.mbt"),
  )
  assert_true(
    moonide_client_path(lexical, physical, "/private/projects/other/main.mbt")
    is None,
  )
  assert_true(
    moonide_client_path(lexical, physical, "/private/projects/project") is None,
  )
}

///|
test "Moon IDE CodeLens parser keeps reference actions and converts compact ranges" {
  let reply = parse_moonide_codelens_output(
    (
      #|[
      #|  {
      #|    "range":"2:3-2:8",
      #|    "command":{"title":"Local: 2 references","command":"moonbit.action.goToLocations","arguments":["/workspace/src/main.mbt","2:5-2:5",[
      #|      {"path":"/workspace/src/main.mbt","range":"3:4-3:9"},
      #|      {"path":"/workspace/src/a%20 b.mbt","range":"1:1-1:2"},
      #|      {"path":"https://example.invalid/leak.mbt","range":"1:1-1:2"},
      #|      {"path":"file:///workspace/old.mbt","range":"1:1-1:2"},
      #|      {"path":"relative.mbt","range":"1:1-1:2"},
      #|      {"path":"","range":"1:1-1:2"}
      #|    ]]}
      #|  },
      #|  {
      #|    "range":"5:1-5:4",
      #|    "command":{"title":"Outside","command":"moonbit.executeReferenceProvider","arguments":["/forged/source.mbt","5:2-5:2"]}
      #|  },
      #|  {
      #|    "range":"1:1-1:2",
      #|    "command":{"title":"Run","command":"moonbit.run","arguments":[]}
      #|  },
      #|  {
      #|    "range":"0:1-1:2",
      #|    "command":{"title":"Bad","command":"moonbit.executeReferenceProvider","arguments":["/workspace/src/main.mbt","1:1-1:1"]}
      #|  }
      #|]
    ),
  )
  assert_eq(ToJson::to_json(reply), {
    "lenses": [
      {
        "range": {
          "start": { "line": 1, "character": 2 },
          "end": { "line": 1, "character": 7 },
        },
        "title": "Local: 2 references",
        "action": {
          "kind": "local",
          "position": { "line": 1, "character": 4 },
          "locations": [
            {
              "path": "/workspace/src/main.mbt",
              "start_line": 3,
              "start_column": 4,
              "end_line": 3,
              "end_column": 9,
            },
            {
              "path": "/workspace/src/a%20 b.mbt",
              "start_line": 1,
              "start_column": 1,
              "end_line": 1,
              "end_column": 2,
            },
          ],
        },
      },
      {
        "range": {
          "start": { "line": 4, "character": 0 },
          "end": { "line": 4, "character": 3 },
        },
        "title": "Outside",
        "action": {
          "kind": "outside",
          "position": { "line": 4, "character": 1 },
        },
      },
    ],
  })
}

///|
test "Moon IDE CodeLens compact ranges reject invalid coordinates and non-point anchors" {
  for
    raw in [
      "", "1:2", "0:1-1:2", "1:0-1:2", "2:1-1:2", "1:3-1:2", "1:1-2147483648:1",
      "1:1-1:2147483648",
    ] {
    assert_true(parse_moonide_codelens_range(raw.to_json()) is None)
    assert_true(parse_moonide_codelens_position(raw.to_json()) is None)
    assert_true(
      parse_moonide_codelens_location({
        "path": "/workspace/main.mbt",
        "range": raw.to_json(),
      })
      is None,
    )
  }
  assert_true(parse_moonide_codelens_position("1:1-1:2") is None)
  assert_true(parse_moonide_codelens_position("1:1-2:1") is None)
  assert_eq(
    parse_moonide_codelens_range("1:1-2:3"),
    Some({ start: { line: 0, character: 0, }, end: { line: 1, character: 2, }, }),
  )
  assert_eq(
    parse_moonide_codelens_position("1:1-1:1"),
    Some({ line: 0, character: 0, }),
  )
}

///|
test "Moon IDE CodeLens parser rejects malformed documents" {
  let malformed = try {
    ignore(parse_moonide_codelens_output("not json"))
    false
  } catch {
    _ => true
  }
  let wrong_shape = try {
    ignore(parse_moonide_codelens_output("null"))
    false
  } catch {
    _ => true
  }
  assert_true(malformed)
  assert_true(wrong_shape)
}

///|
#cfg(not(platform="windows"))
async test "Moon IDE CodeLens canonicalization drops symlink targets outside the workspace" {
  let root = @fs.tmpdir(prefix="openseek-codelens-root-")
  let outside = @fs.tmpdir(prefix="openseek-codelens-outside-")
  defer (@fs.rmdir(outside, recursive=true) catch { _ => () })
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir("\{root}/src", recursive=true)
  @fs.write_file(
    "\{root}/src/inside.mbt",
    "fn inside {}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{outside}/secret.mbt",
    "fn secret {}",
    create_mode=CreateOrTruncate,
  )
  @fs.symlink(target="\{outside}/secret.mbt", "\{root}/src/link.mbt")
  let physical_root = @fs.realpath(root)
  guard @pathx.Path(root).to_absolute() is Some(lexical_workspace) &&
    @pathx.Path(physical_root).to_absolute() is Some(physical_workspace) else {
    fail("temporary root was not absolute")
  }
  let reply : MoonIdeCodeLensReply = {
    lenses: [
      {
        range: {
          start: { line: 0, character: 0, },
          end: { line: 0, character: 6, },
        },
        title: "Local: 3 references",
        action: Local(position={ line: 0, character: 3, }, locations=[
          {
            path: "\{root}/src/inside.mbt",
            start_line: 1,
            start_column: 1,
            end_line: 1,
            end_column: 3,
          },
          {
            path: "\{root}/src/link.mbt",
            start_line: 1,
            start_column: 1,
            end_line: 1,
            end_column: 3,
          },
          {
            path: "\{root}/src/missing.mbt",
            start_line: 1,
            start_column: 1,
            end_line: 1,
            end_column: 3,
          },
        ]),
      },
    ],
  }
  let canonical = canonical_moonide_codelenses(
    reply, lexical_workspace, physical_workspace,
  )
  guard canonical.lenses is [lens] && lens.action is Local(locations~, ..) else {
    fail("canonical CodeLens shape changed")
  }
  assert_eq(locations.length(), 1)
  assert_eq(
    locations[0].path,
    lexical_workspace.join(Relative("src/inside.mbt")).resource_path(),
  )
}
