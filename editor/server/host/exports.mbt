// Deliberate reusable native-host contracts. These entry points are documented
// for embedders but have no non-test dependent-package consumers in this repo.

///|
/// Creates a moon-command language provider over a shared workspace root.
pub fn MoonWorkspaceLanguageProvider::MoonWorkspaceLanguageProvider(
  root : Ref[String],
  moon_command? : String = "moon",
) -> MoonWorkspaceLanguageProvider {
  new_moon_workspace_language_provider(root, moon_command~)
}

///|
/// Runs `moon ide hover` at the requested position.
pub impl @language.HoverProvider for MoonWorkspaceLanguageProvider with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  self.provide_hover_with_runner(model, position, (root, args) => {
    let output = Some(
      @process.collect_stdout(self.moon_command, args, cwd=root),
    ) catch {
      _ => None
    }
    match output {
      Some((exit_code, data)) =>
        Some((exit_code, data.text())) catch {
          _ => None
        }
      None => None
    }
  })
}

///|
/// Runs `moon ide peek-def --loc <path:line:column> --json`.
pub impl @language.DefinitionProvider for MoonWorkspaceLanguageProvider with fn provide_definition(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = Some(
        @process.collect_stdout(
          self.moon_command,
          ["ide", "peek-def", "--loc", loc, "--json"],
          cwd=root,
        ),
      ) catch {
        _ => None
      }
      if token.is_cancellation_requested() {
        return []
      }
      match output {
        Some((0, data)) =>
          parse_moon_definition_output(root, data.text()) catch {
            _ => []
          }
        _ => []
      }
    }
    RemotePathError(_) => []
  }
}

///|
/// Runs `moon ide find-references --loc <path:line:column> --json`.
pub impl @language.ReferencesProvider for MoonWorkspaceLanguageProvider with fn provide_references(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = Some(
        @process.collect_stdout(
          self.moon_command,
          ["ide", "find-references", "--loc", loc, "--json"],
          cwd=root,
        ),
      ) catch {
        _ => None
      }
      if token.is_cancellation_requested() {
        return []
      }
      match output {
        Some((0, data)) =>
          parse_moon_definition_output(root, data.text()) catch {
            _ => []
          }
        _ => []
      }
    }
    RemotePathError(_) => []
  }
}

///|
/// `moon` has no machine-readable document-symbol query.
pub impl @language.DocumentSymbolProvider for MoonWorkspaceLanguageProvider with fn provide_document_symbols(
  _self,
  _model,
  _token,
) {
  []
}

///|
pub fn parse_moon_hover_output(
  raw : String,
  position : @base_common.Position,
) -> @language.Hover? {
  parse_moon_hover_output_impl(raw, position)
}

///|
pub fn parse_moon_definition_output(
  root : String,
  raw : String,
) -> Array[@language.Location] {
  parse_moon_definition_output_impl(root, raw)
}

///|
pub fn MoonCheckDiagnostics::MoonCheckDiagnostics(
  root : Ref[String],
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  moon_command? : String = "moon",
) -> MoonCheckDiagnostics {
  new_native_moon_check_diagnostics(root, publish, moon_command~)
}

///|
pub fn MoonCheckDiagnostics::reset(self : MoonCheckDiagnostics) -> Unit {
  self.reset_impl()
}

///|
pub fn MoonCheckDiagnostics::note_document(
  self : MoonCheckDiagnostics,
  document : @workspace.DocumentSnapshot,
) -> Unit {
  self.note_document_impl(document)
}

///|
pub fn MoonCheckDiagnostics::schedule(
  self : MoonCheckDiagnostics,
  spawn_task : (async () -> Unit) -> Unit,
) -> Unit {
  self.schedule_impl(spawn_task)
}

///|
pub fn parse_moon_check_diagnostics(
  root : String,
  raw : String,
) -> Map[String, Array[@language.Diagnostic]] {
  parse_moon_check_diagnostics_impl(root, raw)
}

///|
pub fn NativeServerHost::NativeServerHost() -> NativeServerHost {
  new_native_server_host()
}

///|
pub fn NativeServerHost::with_poll_interval(
  poll_interval_ms : Int,
) -> NativeServerHost {
  native_server_host_with_poll_interval(poll_interval_ms)
}

///|
pub fn native_server_host() -> &@server.ServerHost {
  NativeServerHost()
}

///|
pub impl @server.ServerHost for NativeServerHost with fn read_text_file(
  self,
  root,
  path,
) {
  ignore(self)
  read_native_text_file(root, path)
}

///|
pub impl @server.ServerHost for NativeServerHost with fn read_directory(
  self,
  root,
  relative,
) {
  ignore(self)
  read_native_directory(root, relative)
}

///|
pub impl @server.ServerHost for NativeServerHost with fn watch_text_file(
  self,
  root,
  path,
  listener,
  spawn_watch,
) {
  let disposed = Ref(false)
  spawn_watch(async fn() {
    poll_native_file_watch(
      root,
      path,
      self.poll_interval_ms,
      disposed,
      listener,
    )
  })
  ServerWatch(() => disposed.val = true)
}

///|
pub extend MoonWorkspaceLanguageProvider with @language.DefinitionProvider::{
  provide_definition,
}

///|
pub extend MoonWorkspaceLanguageProvider with @language.DocumentSymbolProvider::{
  provide_document_symbols,
}

///|
pub extend MoonWorkspaceLanguageProvider with @language.HoverProvider::{
  provide_hover,
}

///|
pub extend MoonWorkspaceLanguageProvider with @language.ReferencesProvider::{
  provide_references,
}

///|
pub extend NativeServerHost with @server.ServerHost::{
  read_directory,
  read_text_file,
  watch_text_file,
}
