// Compatibility between main's bundled desktop page and the shared v2 host
// catalog. This is deliberately a Proton-only adapter: remote WebSockets see
// the catalog names and opaque string run ids unchanged. Remove this file
// once the desktop frontend itself speaks the v2 catalog.

///|
priv struct LegacyWslPayload {
  distro : String?
  engine : String?
} derive(FromJson)

///|
priv struct LegacyStartPayload {
  task : String
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  session : String?
  workspace : String?
  wsl : LegacyWslPayload?
} derive(FromJson)

///|
priv struct LegacyCompactPayload {
  session : String
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  workspace : String?
  wsl : LegacyWslPayload?
} derive(FromJson)

///|
priv struct LegacyEngineSettings {
  api_key : String?
  api_url : String?
  wsl : LegacyWslPayload?
}

///|
fn LegacyStartPayload::settings(
  self : LegacyStartPayload,
) -> LegacyEngineSettings {
  { api_key: self.api_key, api_url: self.api_url, wsl: self.wsl }
}

///|
fn LegacyCompactPayload::settings(
  self : LegacyCompactPayload,
) -> LegacyEngineSettings {
  { api_key: self.api_key, api_url: self.api_url, wsl: self.wsl }
}

///|
/// Mirror the old desktop's local settings into the new host-owned store
/// immediately before a start or compact. The old page sends the effective
/// endpoint, so the provider follows directly from that value.
fn LegacyEngineSettings::patch(
  self : LegacyEngineSettings,
) -> @engine.SettingsPatch {
  let provider = match self.api_url {
    Some(url) if url.has_prefix("https://openseek-api.moonbitlang.cn/") =>
      "openseek"
    Some(_) => "custom"
    None => "deepseek"
  }
  let custom_url = if provider == "custom" {
    Some(self.api_url.unwrap_or(""))
  } else {
    None
  }
  let deepseek_key = if provider == "deepseek" {
    Some(self.api_key.unwrap_or(""))
  } else {
    None
  }
  let custom_key = if provider == "custom" {
    Some(self.api_key.unwrap_or(""))
  } else {
    None
  }
  let wsl : @engine.WslPatch = match self.wsl {
    Some(wsl) => { enabled: true, distro: wsl.distro, engine: wsl.engine }
    None => { enabled: false, distro: None, engine: None }
  }
  {
    provider: Some(provider),
    custom_api_url: custom_url,
    deepseek_api_key: deepseek_key,
    custom_api_key: custom_key,
    wsl: Some(wsl),
  }
}

///|
async fn LegacyEngineSettings::apply(
  self : LegacyEngineSettings,
  state : @api.ApiState,
) -> Unit {
  ignore(
    @engine.update_settings(state.manager(), self.patch(), on_committed=fn(
      status,
    ) {
      state.publish("settings.changed", status)
    }),
  )
}

///|
fn LegacyStartPayload::catalog_params(self : LegacyStartPayload) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["task"] = Json::string(self.task)
  if self.model is Some(model) {
    fields["model"] = Json::string(model)
  }
  if self.max_steps is Some(max_steps) {
    fields["max_steps"] = Json::number(max_steps.to_double())
  }
  if self.session is Some(session) {
    fields["session"] = Json::string(session)
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = Json::string(workspace)
  }
  Json::object(fields)
}

///|
fn LegacyCompactPayload::catalog_params(self : LegacyCompactPayload) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json::string(self.session)
  if self.model is Some(model) {
    fields["model"] = Json::string(model)
  }
  if self.max_steps is Some(max_steps) {
    fields["max_steps"] = Json::number(max_steps.to_double())
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = Json::string(workspace)
  }
  Json::object(fields)
}

///|
fn DesktopBridgeActor::legacy_method_names(
  self : DesktopBridgeActor,
) -> Array[String] {
  ignore(self)
  [
    "connect", "start", "cancel", "steer", "compact", "list_sessions", "load_session",
    "list_workspaces", "add_workspace", "remove_workspace", "pick_workspace", "skills_catalog",
    "skill_install", "skills_installed", "skill_uninstall", "open_path", "check_update",
    "download_update", "apply_update", "workspace_branch", "archive_session", "unarchive_session",
    "archived_sessions", "list_apps", "launch_app", "read_directory", "list_files",
    "read_file", "stat_files", "watch_workspace", "hover", "lsp_open", "workspace_symbols",
  ]
}

///|
/// Register the compatibility surface separately from the catalog so a
/// WebSocket can never invoke the local folder chooser or receive legacy ids.
fn DesktopBridgeActor::bind_legacy_ops(
  self : DesktopBridgeActor,
  context : @app.AppCommandExtensionContext,
) -> Unit raise {
  for method_ in self.legacy_method_names() {
    match method_ {
      "connect" =>
        context.op_async(method_, (_ : Json) => {
          self.attach(context, LegacyDesktop)
          Json::empty_object()
        })
      "pick_workspace" =>
        context.op_async_with_context(method_, (request_context, _ : Json) => {
          self.pick_workspace(request_context)
        })
      _ =>
        context.op_async(method_, (params : Json) => {
          self.legacy_dispatch(method_, params)
        })
    }
  }
}

///|
fn DesktopBridgeActor::legacy_id(
  self : DesktopBridgeActor,
  remote_id : String,
) -> Int {
  if self.legacy_ids.get(remote_id) is Some(id) {
    return id
  }
  let id = self.next_legacy_id
  self.next_legacy_id = id + 1
  self.legacy_ids[remote_id] = id
  self.remote_ids[id] = remote_id
  id
}

///|
fn DesktopBridgeActor::legacy_request_params(
  self : DesktopBridgeActor,
  params : Json,
) -> Json raise {
  guard params is Object(source) else {
    raise @host.PayloadError("malformed request payload")
  }
  let fields : Map[String, Json] = Map([])
  for key, value in source {
    fields[key] = value
  }
  if fields.get("run_id") is Some(Number(value, ..)) {
    let legacy_id = value.to_int()
    guard self.remote_ids.get(legacy_id) is Some(remote_id) else {
      raise @host.PayloadError("unknown desktop run id")
    }
    fields["run_id"] = Json::string(remote_id)
  }
  Json::object(fields)
}

///|
fn DesktopBridgeActor::legacy_reply(
  self : DesktopBridgeActor,
  reply : Json,
) -> Json {
  guard reply is Object(source) else { return reply }
  let fields : Map[String, Json] = Map([])
  for key, value in source {
    fields[key] = value
  }
  if fields.get("run_id") is Some(String(remote_id)) {
    fields["run_id"] = Json::number(self.legacy_id(remote_id).to_double())
  }
  Json::object(fields)
}

///|
async fn DesktopBridgeActor::legacy_dispatch(
  self : DesktopBridgeActor,
  method_ : String,
  params : Json,
) -> Json {
  match method_ {
    "start" => {
      let payload : LegacyStartPayload = @json.from_json(params) catch {
        _ => raise @host.PayloadError("malformed request payload")
      }
      payload.settings().apply(self.state)
      self.legacy_reply(
        @api.dispatch(self.state, "agent.start", payload.catalog_params()),
      )
    }
    "compact" => {
      let payload : LegacyCompactPayload = @json.from_json(params) catch {
        _ => raise @host.PayloadError("malformed request payload")
      }
      payload.settings().apply(self.state)
      @api.dispatch(self.state, "agent.compact", payload.catalog_params())
    }
    "cancel" =>
      self.legacy_reply(
        @api.dispatch(
          self.state,
          "agent.cancel",
          self.legacy_request_params(params),
        ),
      )
    "steer" =>
      self.legacy_reply(
        @api.dispatch(
          self.state,
          "agent.steer",
          self.legacy_request_params(params),
        ),
      )
    "watch_workspace" =>
      if params is Object(fields) &&
        fields.get("session") is Some(String(session)) &&
        session.is_empty() {
        @api.dispatch(self.state, "fs.unwatch", Json::empty_object())
      } else {
        @api.dispatch(self.state, "fs.watch", params)
      }
    _ => {
      let catalog_method = match method_ {
        "list_sessions" => "session.list"
        "load_session" => "session.load"
        "list_workspaces" => "workspace.list"
        "add_workspace" => "workspace.add"
        "remove_workspace" => "workspace.remove"
        "skills_catalog" => "skills.catalog"
        "skill_install" => "skills.install"
        "skills_installed" => "skills.installed"
        "skill_uninstall" => "skills.uninstall"
        "open_path" => "host.open_path"
        "check_update" => "update.check"
        "download_update" => "update.download"
        "apply_update" => "update.apply"
        "workspace_branch" => "git.branch"
        "archive_session" => "session.archive"
        "unarchive_session" => "session.unarchive"
        "archived_sessions" => "session.list_archived"
        "list_apps" => "app.list"
        "launch_app" => "app.launch"
        "read_directory" => "fs.read_directory"
        "list_files" => "fs.list_files"
        "read_file" => "fs.read_file"
        "stat_files" => "fs.stat_files"
        "hover" => "lsp.hover"
        "lsp_open" => "lsp.open"
        "workspace_symbols" => "lsp.workspace_symbols"
        _ => raise @api.UnknownMethod(method_)
      }
      @api.dispatch(self.state, catalog_method, params)
    }
  }
}

///|
fn DesktopBridgeActor::legacy_notification(
  self : DesktopBridgeActor,
  notification : @api.Notification,
) -> @api.Notification? {
  let method_ = match notification.method_ {
    "agent.started" => "started"
    "agent.event" => "event"
    "agent.error" => "error"
    "agent.finished" => "finished"
    "agent.connected" => "connected"
    "lsp.diagnostics" => "diagnostics"
    "fs.changed" => "fs_changed"
    _ => return None
  }
  Some({ method_, params: self.legacy_reply(notification.params) })
}

///|
test "legacy desktop assigns stable local ids without changing remote ids" {
  let bridge = DesktopBridgeActor::new(@api.ApiState::new(engine="openseek"))
  let first = bridge.legacy_reply({
    "run_id": "7f9d6fd4c6760da5",
    "status": "accepted",
  })
  guard first is Object(first_fields) &&
    first_fields.get("run_id") is Some(Number(first_id, ..)) else {
    fail("legacy reply did not expose a numeric run id")
  }
  let second = bridge.legacy_reply({ "run_id": "7f9d6fd4c6760da5" })
  guard second is Object(second_fields) &&
    second_fields.get("run_id") is Some(Number(second_id, ..)) else {
    fail("legacy reply did not reuse the numeric run id")
  }
  assert_eq(first_id.to_int(), second_id.to_int())
  let request = bridge.legacy_request_params({
    "run_id": first_id,
    "text": "continue",
  })
  guard request is Object(request_fields) else {
    fail("legacy request did not remain an object")
  }
  assert_eq(
    request_fields.get("run_id"),
    Some(Json::string("7f9d6fd4c6760da5")),
  )
}

///|
test "legacy desktop settings preserve the old endpoint choices" {
  let openseek = (
    {
      api_key: None,
      api_url: Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      wsl: None,
    } : LegacyEngineSettings).patch()
  assert_eq(openseek.provider, Some("openseek"))
  assert_true(openseek.wsl is Some({ enabled: false, .. }))
  let deepseek = (
    { api_key: Some("sk-deepseek"), api_url: None, wsl: None } :
    LegacyEngineSettings).patch()
  assert_eq(deepseek.provider, Some("deepseek"))
  assert_eq(deepseek.deepseek_api_key, Some("sk-deepseek"))
  let custom = (
    {
      api_key: Some("sk-custom"),
      api_url: Some("https://example.test/v1/chat/completions"),
      wsl: Some({ distro: Some("Ubuntu"), engine: None }),
    } : LegacyEngineSettings).patch()
  assert_eq(custom.provider, Some("custom"))
  assert_eq(
    custom.custom_api_url,
    Some("https://example.test/v1/chat/completions"),
  )
  assert_eq(custom.custom_api_key, Some("sk-custom"))
  assert_true(custom.wsl is Some({ enabled: true, distro: Some("Ubuntu"), .. }))
}
