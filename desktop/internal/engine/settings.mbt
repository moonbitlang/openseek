// The host-owned engine endpoint settings: which provider runs use and its
// credentials. They live in the host's runtime dir
// (`engine-settings.json`) — never in a client — so a browser page cannot
// leak one host's key to another, and the desktop window and every remote
// page see the same configuration. Clients edit them through the
// `settings.get`/`settings.set` methods and learn about others' edits from
// the `settings.changed` broadcast; runs read them at config time, so a
// change respawns the conversation's engine on its next start (the
// fingerprint covers the resolved values).
//
// File format rules (the versioning contract):
// - `version` is written on every save; a real reshape bumps it and adds a
//   read-side migration. Missing reads as 1.
// - Reads are tolerant: missing fields are defaults, unknown fields are
//   ignored — and preserved verbatim on save (see `update_settings`), so a
//   downgrade's edit never eats a newer build's fields.
// - A file written by a newer version (version above ours) is read
//   best-effort but refused for writing.
// - Saves are atomic: temp file + rename, 0600.

///|
const EngineSettingsVersion = 2

///|
const EngineSettingsFileName = "engine-settings.json"

///|
/// Durable compatibility fence. The first settings write sets it; a retried
/// localStorage import then returns the current settings without replacing a
/// newer browser or desktop edit.
const LegacyMigrationFence = "legacy_client_settings_migrated"

///|
/// The official OpenSeek proxy endpoint runs use when the server is
/// `Openseek` — the zero-config default.
const OpenseekProxyUrl : String = "https://openseek-api.moonbitlang.cn/chat/completions"

///|
/// The staging twin of `OpenseekProxyUrl`, for testing against the next
/// server build.
const OpenseekStagingProxyUrl : String = "https://openseek-api-staging.moonbitlang.cn/chat/completions"

///|
/// The one server selection: which OpenSeek server (or foreign endpoint)
/// this install talks to. It decides the chat-completions endpoint, the
/// update channel, and the remote-access relay in one move. `Openseek` is
/// the zero-config default (the proxy needs no user key);
/// `OpenseekStaging` is the same service's staging deployment; `Deepseek`
/// is the official DeepSeek endpoint with the user's own key; `Custom` is
/// any other DeepSeek-compatible endpoint. Remote access exists only on
/// the OpenSeek servers — `Deepseek`/`Custom` have no relay to sign in to.
priv enum ApiProvider {
  Openseek
  OpenseekStaging
  Deepseek
  Custom
}

///|
fn ApiProvider::wire(self : ApiProvider) -> String {
  match self {
    Openseek => "openseek"
    OpenseekStaging => "openseek-staging"
    Deepseek => "deepseek"
    Custom => "custom"
  }
}

///|
/// `None` for an unknown wire name: loading falls back to the default
/// quietly (a corrupted store degrades instead of wedging), while
/// `settings.set` rejects it loudly.
fn ApiProvider::parse(value : String) -> ApiProvider? {
  match value {
    "openseek" => Some(Openseek)
    "openseek-staging" => Some(OpenseekStaging)
    "deepseek" => Some(Deepseek)
    "custom" => Some(Custom)
    _ => None
  }
}

///|
/// The decoded settings plus `raw`, the file's own object — the save path
/// works on `raw` so fields this build does not know survive a rewrite.
priv struct EngineSettings {
  raw : Map[String, Json]
  version : Int
  provider : ApiProvider
  custom_api_url : String?
  deepseek_api_key : String?
  custom_api_key : String?
}

///|
fn settings_file(runtime_dir : @pathx.Path) -> @pathx.Path {
  runtime_dir.join(EngineSettingsFileName)
}

///|
/// Read the settings, tolerating absence and corruption as defaults — a
/// broken file only costs the stored values, never the app; it is not
/// overwritten until the next explicit save.
async fn load_engine_settings(runtime_dir : @pathx.Path?) -> EngineSettings {
  let fields : Map[String, Json] = Map([])
  if runtime_dir is Some(dir) &&
    (@fsx.try_read_text(settings_file(dir)) catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    })
    is Some(text) &&
    (@json.parse(text) catch { _ => Json::null() }) is Object(parsed) {
    for key, value in parsed {
      fields[key] = value
    }
  }
  decode_settings(fields)
}

///|
fn settings_text(fields : Map[String, Json], key : String) -> String? {
  guard fields.get(key) is Some(String(value)) && !value.trim().is_empty() else {
    return None
  }
  Some(value)
}

///|
fn decode_settings(raw : Map[String, Json]) -> EngineSettings {
  {
    raw,
    // Missing reads as 1: version stamping arrived with the first format,
    // so an unstamped file can only be that format (or hand-written).
    version: match raw.get("version") {
      Some(Number(version, ..)) => version.to_int()
      _ => 1
    },
    provider: settings_text(raw, "provider")
    .bind(value => ApiProvider::parse(value))
    .unwrap_or(Openseek),
    custom_api_url: settings_text(raw, "custom_api_url"),
    deepseek_api_key: settings_text(raw, "deepseek_api_key"),
    custom_api_key: settings_text(raw, "custom_api_key"),
  }
}

///|
/// One `settings.set` request, decoded by the transport layer. Every field
/// is optional: absent = leave unchanged. A present string field is
/// trimmed; empty after trimming clears the stored value.
pub(all) struct SettingsPatch {
  provider : String?
  custom_api_url : String?
  deepseek_api_key : String?
  custom_api_key : String?
}

///|
/// The `settings.get`/`settings.set` reply, and the `settings.changed`
/// broadcast params. Key material never leaves the host — only presence.
fn settings_status_payload(
  settings : EngineSettings,
  revision : Int,
) -> @protocol.SettingsStatusPayload {
  {
    revision,
    provider: settings.provider.wire(),
    custom_api_url: settings.custom_api_url,
    has_deepseek_key: settings.deepseek_api_key is Some(_),
    has_custom_key: settings.custom_api_key is Some(_),
  }
}

///|
/// Read one coherent settings snapshot. Every production reader goes through
/// the manager-owned lock, so it cannot observe another client's partial
/// read-modify-write or the Windows replace fallback's remove/rename window.
async fn EngineManager::settings_snapshot(
  self : EngineManager,
) -> (EngineSettings, Int) {
  self.settings_lock.acquire()
  defer self.settings_lock.release()
  (load_engine_settings(self.runtime_dir), self.settings_revision)
}

///|
/// The `settings.get` reply.
pub async fn settings_status(
  manager : EngineManager,
) -> @protocol.SettingsStatusPayload {
  let (settings, revision) = manager.settings_snapshot()
  settings_status_payload(settings, revision)
}

///|
/// Apply one patch and persist it, returning the updated status. The write
/// merges into the file's own object, so fields a newer build added are
/// preserved; a file from a newer version is refused rather than rewritten.
pub async fn update_settings(
  manager : EngineManager,
  patch : SettingsPatch,
  legacy_migration? : Bool = false,
  on_committed? : (@protocol.SettingsStatusPayload) -> Unit,
) -> @protocol.SettingsStatusPayload {
  manager.settings_lock.acquire()
  defer manager.settings_lock.release()
  guard manager.runtime_dir is Some(dir) else {
    raise EngineError("engine settings cannot persist: no runtime directory")
  }
  let current = load_engine_settings(manager.runtime_dir)
  guard current.version <= EngineSettingsVersion else {
    raise EngineError(
      "engine settings were written by a newer OpenSeek; update the app to change them",
    )
  }
  let raw = current.raw
  // A migration may be retried after its commit reply was lost. It is also
  // possible for a modern client to write first. In both cases the durable
  // fence wins and the old localStorage snapshot is merely acknowledged so
  // the desktop can delete it.
  let store_claimed = raw.get(LegacyMigrationFence) is Some(True) ||
    raw.get("provider") is Some(_) ||
    raw.get("custom_api_url") is Some(_) ||
    raw.get("deepseek_api_key") is Some(_) ||
    raw.get("custom_api_key") is Some(_)
  if legacy_migration && store_claimed {
    return settings_status_payload(current, manager.settings_revision)
  }
  if patch.provider is Some(value) {
    guard ApiProvider::parse(value.trim().to_owned()) is Some(provider) else {
      raise EngineError("unknown API provider '\{value}'")
    }
    raw["provider"] = Json::string(provider.wire())
  }
  apply_text_patch(raw, "custom_api_url", patch.custom_api_url)
  apply_text_patch(raw, "deepseek_api_key", patch.deepseek_api_key)
  apply_text_patch(raw, "custom_api_key", patch.custom_api_key)
  // Version 2 retired the WSL engine mode. A settings write also removes the
  // old group so the durable file no longer advertises an ignored capability.
  raw.remove("wsl")
  raw[LegacyMigrationFence] = Json::boolean(true)
  raw["version"] = Json::number(EngineSettingsVersion.to_double())
  write_settings_file(dir, Json::object(raw).stringify(indent=2))
  // Disk is now committed. Advance the process-local order and publish while
  // still holding the same lock, so two clients can never observe revision 2
  // before revision 1. The API shields this finite commit+broadcast section
  // from requester cancellation.
  manager.settings_revision = manager.settings_revision + 1
  let status = settings_status_payload(
    decode_settings(raw),
    manager.settings_revision,
  )
  if on_committed is Some(callback) {
    callback(status)
  }
  status
}

///|
/// A present string field is an instruction: trimmed non-empty replaces the
/// stored value, empty clears it. Absent fields never reach here.
fn apply_text_patch(
  fields : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  guard value is Some(value) else { return }
  let value = value.trim().to_owned()
  if value.is_empty() {
    fields.remove(key)
  } else {
    fields[key] = Json::string(value)
  }
}

///|
/// Atomic save: write a 0600 temp file, then rename over the target. The
/// file holds a credential, so a crash mid-write must never leave a
/// truncated store — the temp file keeps the full content until the rename
/// lands. Windows may refuse to rename over an existing file; removing the
/// target first narrows atomicity to that one platform's small window.
async fn write_settings_file(runtime_dir : @pathx.Path, text : String) -> Unit {
  let target = settings_file(runtime_dir)
  let temp = runtime_dir.join(EngineSettingsFileName + ".tmp")
  @fs.write_file(
    temp.to_string(),
    text,
    create_mode=CreateOrTruncate,
    permission=0o600,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not write engine settings: \{error}")
  }
  @fs.rename(temp.to_string(), target.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      @fsx.remove_if_exists(target) catch {
        error if @async.is_being_cancelled() => raise error
        error =>
          raise EngineError("could not replace engine settings: \{error}")
      }
      @fs.rename(temp.to_string(), target.to_string()) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise EngineError("could not save engine settings: \{error}")
      }
    }
  }
}

///|
/// The endpoint a run talks to, resolved from the settings. `api_url` is
/// `None` for the engine's built-in default (the official DeepSeek
/// endpoint). The client no longer sends credentials — this is the one
/// place they enter a run's config.
priv struct ResolvedEndpoint {
  api_key : String
  api_url : String?
}

///|
fn resolved_endpoint(
  settings : EngineSettings,
) -> ResolvedEndpoint raise EngineError {
  match settings.provider {
    Openseek => {
      let url = OpenseekProxyUrl
      let key = configured_api_key(api_url=url)
      { api_key: key, api_url: Some(url) }
    }
    OpenseekStaging => {
      let url = OpenseekStagingProxyUrl
      let key = configured_api_key(api_url=url)
      { api_key: key, api_url: Some(url) }
    }
    Deepseek => {
      let key = configured_api_key(
        stored_key?=settings.deepseek_api_key,
        deepseek_env?=@env.get("DEEPSEEK"),
      )
      { api_key: key, api_url: None }
    }
    Custom => {
      guard settings.custom_api_url is Some(url) else {
        raise EngineError("custom endpoint URL is required; set it in Settings")
      }
      let key = configured_api_key(
        stored_key?=settings.custom_api_key,
        api_url=url,
      )
      { api_key: key, api_url: Some(url) }
    }
  }
}

///|
/// The OpenSeek server origin the current server selection points remote
/// access at — `None` for `Deepseek`/`Custom`, which have no relay to sign
/// in to. Derived from the proxy URLs so the origins have one home;
/// `OPENSEEK_SERVER_URL` overrides the selection for development against a
/// local or ad-hoc server.
pub async fn remote_server_base(manager : EngineManager) -> String? {
  if @env.get("OPENSEEK_SERVER_URL") is Some(base) && !base.trim().is_empty() {
    return Some(base.trim().to_owned())
  }
  let (settings, _) = manager.settings_snapshot()
  let proxy = match settings.provider {
    Openseek => OpenseekProxyUrl
    OpenseekStaging => OpenseekStagingProxyUrl
    Deepseek | Custom => return None
  }
  proxy.strip_suffix("/chat/completions").map(origin => origin.to_owned())
}

// The settings store's contract: tolerant reads, merge-preserving atomic
// writes, the version guard, and the run-config resolution built on it.

///|
async fn with_settings_dir(
  body : async (@pathx.Path, EngineManager) -> Unit,
) -> Unit {
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-settings-"))
  body(dir, new_engine_manager("openseek", runtime_dir=dir)) catch {
    error => {
      @fs.rmdir(dir.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  @fs.rmdir(dir.to_string(), recursive=true) catch {
    _ => ()
  }
}

///|
async test "missing settings read as the zero-config defaults" {
  with_settings_dir(async fn(_dir, manager) {
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Openseek)
    assert_true(settings.deepseek_api_key is None)
    json_inspect(settings_status(manager), content={
      "revision": 0,
      "provider": "openseek",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
  })
}

///|
async test "a saved key round-trips as presence, never as text" {
  with_settings_dir(async fn(dir, manager) {
    let status = update_settings(manager, {
      provider: Some("deepseek"),
      custom_api_url: None,
      deepseek_api_key: Some("  sk-secret  "),
      custom_api_key: None,
    })
    json_inspect(status, content={
      "revision": 1,
      "provider": "deepseek",
      "has_deepseek_key": true,
      "has_custom_key": false,
    })
    // The status never carries the key; the file carries it trimmed.
    assert_false(status.to_json().stringify().contains("sk-secret"))
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"sk-secret\""))
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_true(reloaded.deepseek_api_key is Some("sk-secret"))
    assert_true(reloaded.provider is Deepseek)
  })
}

///|
async test "the staging server round-trips and resolves its own endpoints" {
  with_settings_dir(async fn(_dir, manager) {
    let status = update_settings(manager, {
      provider: Some("openseek-staging"),
      custom_api_url: None,
      deepseek_api_key: None,
      custom_api_key: None,
    })
    json_inspect(status, content={
      "revision": 1,
      "provider": "openseek-staging",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_true(reloaded.provider is OpenseekStaging)
    debug_inspect(
      remote_server_base(manager),
      content="Some(\"https://openseek-api-staging.moonbitlang.cn\")",
    )
    let _ = update_settings(manager, {
      provider: Some("deepseek"),
      custom_api_url: None,
      deepseek_api_key: None,
      custom_api_key: None,
    })
    debug_inspect(remote_server_base(manager), content="None")
  })
}

///|
async test "a present-but-blank field clears the stored value" {
  with_settings_dir(async fn(_dir, manager) {
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://proxy.example/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: Some("sk-custom"),
    })
    let status = update_settings(manager, {
      provider: None,
      custom_api_url: Some("   "),
      deepseek_api_key: None,
      custom_api_key: Some(""),
    })
    json_inspect(status, content={
      "revision": 2,
      "provider": "custom",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
  })
}

///|
async test "a save removes the retired WSL settings group" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 1, \"provider\": \"deepseek\", \"wsl\": {\"enabled\": true, \"distro\": \"Ubuntu\"}}",
    )
    let _ = update_settings(manager, {
      provider: None,
      custom_api_url: None,
      deepseek_api_key: Some("sk-kept"),
      custom_api_key: None,
    })
    guard @json.parse(@fsx.read_text(settings_file(dir))) is Object(fields) else {
      fail("settings file is not valid JSON")
    }
    assert_true(fields.get("wsl") is None)
    assert_true(
      fields.get("version") is Some(Number(version, ..)) &&
      version.to_int() == 2,
    )
  })
}

///|
async test "legacy migration cannot replay over a newer settings write" {
  with_settings_dir(async fn(_dir, manager) {
    let migrated = update_settings(
      manager,
      {
        provider: Some("deepseek"),
        custom_api_url: None,
        deepseek_api_key: Some("sk-old"),
        custom_api_key: None,
      },
      legacy_migration=true,
    )
    assert_eq(migrated.revision, 1)
    let modern = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://new.example/chat"),
      deepseek_api_key: Some(""),
      custom_api_key: Some("sk-new"),
    })
    assert_eq(modern.revision, 2)
    // This is the desktop retry after the first migration's reply was lost.
    // It gets the current status so the client can clear localStorage, but
    // neither advances the revision nor restores the stale values.
    let replay = update_settings(
      manager,
      {
        provider: Some("deepseek"),
        custom_api_url: None,
        deepseek_api_key: Some("sk-old"),
        custom_api_key: None,
      },
      legacy_migration=true,
    )
    assert_eq(replay.revision, 2)
    let current = load_engine_settings(manager.runtime_dir)
    assert_true(current.provider is Custom)
    assert_true(current.deepseek_api_key is None)
    assert_true(current.custom_api_key is Some("sk-new"))
  })
}

///|
async test "concurrent disjoint settings patches merge and publish in revision order" {
  with_settings_dir(async fn(dir, manager) {
    let committed : Array[Int] = []
    let ready : @async.Queue[Unit] = Queue(kind=Blocking(2))
    // Queue both callers behind the manager lock so the test exercises the
    // same contended path as two remote clients instead of relying on I/O
    // scheduling to happen to overlap them.
    manager.settings_lock.acquire()
    @async.with_task_group(group => {
      let endpoint = group.spawn(() => {
        ready.put(())
        update_settings(
          manager,
          {
            provider: Some("deepseek"),
            custom_api_url: None,
            deepseek_api_key: Some("sk-concurrent"),
            custom_api_key: None,
          },
          on_committed=fn(status) { committed.push(status.revision) },
        )
      })
      let custom = group.spawn(() => {
        ready.put(())
        update_settings(
          manager,
          {
            provider: None,
            custom_api_url: Some("https://custom.example/chat"),
            deepseek_api_key: None,
            custom_api_key: Some("sk-custom"),
          },
          on_committed=fn(status) { committed.push(status.revision) },
        )
      })
      ready.get()
      ready.get()
      manager.settings_lock.release()
      let endpoint_status = endpoint.wait()
      let custom_status = custom.wait()
      let revisions = [endpoint_status.revision, custom_status.revision]
      revisions.sort()
      assert_eq(revisions, [1, 2])
    })
    assert_eq(committed, [1, 2])
    let text = @fsx.read_text(settings_file(dir))
    guard @json.parse(text) is Object(fields) else {
      fail("settings file is not valid JSON")
    }
    assert_true(fields.get("provider") is Some(String("deepseek")))
    assert_true(fields.get("deepseek_api_key") is Some(String("sk-concurrent")))
    assert_true(
      fields.get("custom_api_url")
      is Some(String("https://custom.example/chat")),
    )
    assert_true(fields.get("custom_api_key") is Some(String("sk-custom")))
    // Revision is a host-process epoch, not a persistence-format change.
    assert_true(fields.get("revision") is None)
    assert_eq(settings_status(manager).revision, 2)
  })
}

///|
async test "saves preserve fields a newer build added" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 1, \"future_field\": \"kept\", \"provider\": \"deepseek\"}",
    )
    let _ = update_settings(manager, {
      provider: None,
      custom_api_url: None,
      deepseek_api_key: Some("sk-new"),
      custom_api_key: None,
    })
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"future_field\""))
    assert_true(text.contains("\"kept\""))
    // The untouched provider survives the patch too.
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_true(reloaded.provider is Deepseek)
    assert_true(reloaded.deepseek_api_key is Some("sk-new"))
  })
}

///|
async test "a newer-version file is read best-effort but never rewritten" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 99, \"provider\": \"deepseek\", \"deepseek_api_key\": \"sk-kept\"}",
    )
    // Reads still surface what this build understands.
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Deepseek)
    assert_true(settings.deepseek_api_key is Some("sk-kept"))
    // Writes are refused so a downgrade cannot eat the newer schema.
    let refused = try
      update_settings(manager, {
        provider: Some("openseek"),
        custom_api_url: None,
        deepseek_api_key: None,
        custom_api_key: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("newer"))
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"version\": 99"))
  })
}

///|
async test "an unknown provider is refused on write, defaulted on read" {
  with_settings_dir(async fn(dir, manager) {
    let refused = try
      update_settings(manager, {
        provider: Some("acme"),
        custom_api_url: None,
        deepseek_api_key: None,
        custom_api_key: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("unknown API provider"))
    // A corrupted store degrades to the zero-config default.
    @fsx.write_text(settings_file(dir), "{\"provider\": \"acme\"}")
    assert_true(load_engine_settings(manager.runtime_dir).provider is Openseek)
  })
}

///|
async test "a corrupt file reads as defaults and survives until a save" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(settings_file(dir), "{ not json")
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Openseek)
    // Nothing rewrote the broken file behind the user's back.
    assert_eq(@fsx.read_text(settings_file(dir)), "{ not json")
  })
}

///|
async test "run config resolves the endpoint from the stored provider" {
  with_settings_dir(async fn(_dir, manager) {
    let _ = update_settings(manager, {
      provider: Some("deepseek"),
      custom_api_url: None,
      deepseek_api_key: Some("sk-stored"),
      custom_api_key: None,
    })
    let config = run_config(manager, {
      task: "hello",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-settings-default",
      workspace: None,
    })
    // The official endpoint is the engine default: no URL override.
    assert_true(config.api_url is None)
    assert_eq(config.api_key, "sk-stored")
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://proxy.example/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    })
    let custom = run_config(manager, {
      task: "hello",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-settings-custom",
      workspace: None,
    })
    assert_true(
      custom.api_url is Some("https://proxy.example/chat/completions"),
    )
    // A custom endpoint without a key gets the placeholder, never the
    // stored DeepSeek key.
    assert_eq(custom.api_key, PlaceholderApiKey)
  })
}

///|
async test "a custom provider without a URL refuses to start" {
  with_settings_dir(async fn(_dir, manager) {
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: None,
      deepseek_api_key: None,
      custom_api_key: None,
    })
    let refused = try
      run_config(manager, {
        task: "hello",
        submission_id: None,
        model: None,
        max_steps: None,
        session: "s-settings-missing-url",
        workspace: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("custom endpoint URL is required"))
  })
}
