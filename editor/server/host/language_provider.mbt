///|
/// Language provider backed by the `moon` command line. Hover shells out to
/// `moon ide hover --output-json` and definitions to `moon ide peek-def
/// --json` against the workspace on disk; diagnostics flow through the `moon
/// check` push path (`MoonCheckDiagnostics`) instead of a pull provider.
/// Remaining semantic features without a machine-readable `moon` query return
/// empty results.
struct MoonWorkspaceLanguageProvider {
  /// Shared with the host's workspace switching, so every request runs
  /// against the currently served root.
  root : Ref[String]
  moon_command : String
  run_moon : async (String, String, Array[String]) -> (Int, String)?
}

///|
/// Creates a moon-command language provider over a shared workspace root.
fn new_moon_workspace_language_provider(
  root : Ref[String],
  moon_command? : String = "moon",
) -> MoonWorkspaceLanguageProvider {
  new_moon_workspace_language_provider_with_runner(
    root, moon_command, collect_moon_command_output,
  )
}

///|
fn new_moon_workspace_language_provider_with_runner(
  root : Ref[String],
  moon_command : String,
  run_moon : async (String, String, Array[String]) -> (Int, String)?,
) -> MoonWorkspaceLanguageProvider {
  { root, moon_command, run_moon, }
}

///|
async fn collect_moon_command_output(
  command : String,
  root : String,
  args : Array[String],
) -> (Int, String)? {
  let output = Some(@process.collect_stdout(command, args, cwd=root)) catch {
    _ => None
  }
  match output {
    Some((exit_code, data)) =>
      Some((exit_code, data.text())) catch {
        _ => None
      }
    None => None
  }
}

///|
/// The root a request runs against, captured once per request so a
/// concurrent switch cannot mix two roots inside one query.
fn MoonWorkspaceLanguageProvider::current_root(
  self : MoonWorkspaceLanguageProvider,
) -> String {
  normalize_host_path(self.root.val)
}

///|
async fn MoonWorkspaceLanguageProvider::provide_hover_with_runner(
  self : MoonWorkspaceLanguageProvider,
  model : @model.TextModel,
  position : @base_common.Position,
  run : async (String, Array[String]) -> (Int, String)?,
) -> @language.Hover? {
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let model_identity = model.identity()
      let model_version = model.version
      let content_version = model.get_version_id()
      let model_uri = model.uri.to_string()
      let model_revision = model.revision
      let model_text = model.snapshot.get_value()
      guard read_native_disk_snapshot(root, path) is Some(before) else {
        return None
      }
      guard before.signature == model_revision &&
        before.normalized_text == model_text else {
        return None
      }
      guard !model.is_disposed() &&
        model.identity() == model_identity &&
        model.version == model_version &&
        model.get_version_id() == content_version &&
        model.uri.to_string() == model_uri &&
        model.revision == model_revision &&
        model.snapshot.get_value() == model_text else {
        return None
      }
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = run(root, ["ide", "hover", "--loc", loc, "--output-json"])
      guard read_native_disk_snapshot(root, path) is Some(after) &&
        after == before &&
        !model.is_disposed() &&
        model.identity() == model_identity &&
        model.version == model_version &&
        model.get_version_id() == content_version &&
        model.uri.to_string() == model_uri &&
        model.revision == model_revision &&
        model.snapshot.get_value() == model_text else {
        return None
      }
      match output {
        // A missing hover exits nonzero with a plain-text notice, so only an
        // exit-0 payload is parsed.
        Some((0, raw)) => parse_moon_hover_output(raw, position)
        _ => None
      }
    }
    RemotePathError(_) => None
  }
}

///|
async fn MoonWorkspaceLanguageProvider::provide_locations(
  self : MoonWorkspaceLanguageProvider,
  model : @model.TextModel,
  position : @base_common.Position,
  token : @language.CancellationToken,
  subcommand : String,
) -> Array[@language.Location] {
  if token.is_cancellation_requested() {
    return []
  }
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = (self.run_moon)(self.moon_command, root, [
        "ide", subcommand, "--loc", loc, "--json",
      ])
      if token.is_cancellation_requested() {
        return []
      }
      match output {
        Some((0, raw)) => parse_moon_definition_output_impl(root, raw)
        _ => []
      }
    }
    RemotePathError(_) => []
  }
}

///|
/// Parses `moon ide hover --output-json` output: a 1-based
/// `line:col-line:col` range plus markdown content strings. A malformed or
/// empty payload yields no hover; a missing or malformed range degrades to a
/// one-column range at the requested position.
fn parse_moon_hover_output_impl(
  raw : String,
  position : @base_common.Position,
) -> @language.Hover? {
  guard (Some(@json.parse(raw)) catch { _ => None }) is Some(json) else {
    return None
  }
  let contents : Array[@language.HoverContent] = match json {
    { "contents": Array(items), .. } =>
      [
        for item in items if item is String(text) && text != "" => {
          Markdown(text)
        }
      ]
    _ => []
  }
  if contents.is_empty() {
    return None
  }
  let range = match json {
    { "range": String(loc), .. } if parse_moon_loc(loc) is Some(range) => range
    _ =>
      Range(
        position.line_number,
        position.column,
        position.line_number,
        position.column + 1,
      )
  }
  Some({ range, contents, })
}

///|
/// Parses the ordered location array emitted by `moon ide peek-def --json` and
/// `moon ide find-references --json`. Absolute paths must be contained by
/// `root`; safe root-relative paths are also accepted. Invalid entries are
/// ignored independently.
fn parse_moon_definition_output_impl(
  root : String,
  raw : String,
) -> Array[@language.Location] {
  guard (Some(@json.parse(raw)) catch { _ => None }) is Some(Array(items)) else {
    return []
  }
  let locations : Array[@language.Location] = []
  for item in items {
    if item is { "path": String(path), "range": String(raw_range), .. } {
      match
        (
          definition_uri_under_root(root, path),
          parse_moon_definition_range(raw_range),
        ) {
        (Some(uri), Some(range)) => locations.push({ uri, range, })
        _ => ()
      }
    }
  }
  locations
}

///|
fn definition_uri_under_root(
  root : String,
  raw_path : String,
) -> @base_common.Uri? {
  let root = normalize_host_path(root)
  let path = normalize_host_path(raw_path)
  let root_prefix = if root == "/" { "/" } else { "\{root}/" }
  let relative = if path.has_prefix(root_prefix) {
    path[root_prefix.length():].to_owned()
  } else if path.has_prefix("/") {
    return None
  } else {
    path
  }
  match @workspace.SourcePath::normalize_root_relative_path(relative) {
    ParsedSourcePath(path) => @server.remote_document_uri(path.to_string())
    SourcePathError(_) => None
  }
}

///|
fn parse_moon_definition_range(raw : String) -> @base_common.Range? {
  guard raw.find("-") is Some(dash) else { return None }
  match
    (
      parse_positive_position(raw[0:dash]),
      parse_positive_position(raw[dash + 1:]),
    ) {
    (Some(start), Some(end)) =>
      if start.is_before_or_equal(end) {
        Some(@base_common.Range::from_positions(start, end))
      } else {
        None
      }
    _ => None
  }
}

///|
fn parse_positive_position(raw : StringView) -> @base_common.Position? {
  parse_check_position(raw).filter(position => {
    position.line_number >= 1 && position.column >= 1
  })
}
