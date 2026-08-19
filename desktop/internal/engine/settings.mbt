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
/// The SeekMoon relay origin: remote access (browser sign-in) and the
/// update manifest live here. The hosted chat proxy that used to live on
/// this origin is retired — runs are bring-your-own-key only — so this
/// origin no longer serves any chat-completions traffic.
const RelayServerOrigin : String = "https://openseek-api.moonbitlang.cn"

///|
/// The chat endpoint selection: where runs send their requests. SeekMoon
/// runs only on bring-your-own-key providers. `Deepseek` is the official
/// DeepSeek endpoint with the user's own key; `Custom` is any other
/// OpenAI-compatible endpoint, whose key is optional. The retired hosted
/// proxy names (`openseek` / `openseek-staging`) still parse as `Deepseek`
/// so old settings files and old clients degrade to the BYOK default
/// instead of wedging.
priv enum ApiProvider {
  Deepseek
  Custom
}

///|
fn ApiProvider::wire(self : ApiProvider) -> String {
  match self {
    Deepseek => "deepseek"
    Custom => "custom"
  }
}

///|
/// `None` for an unknown wire name: loading falls back to the default
/// quietly (a corrupted store degrades instead of wedging), while
/// `settings.set` rejects it loudly. The retired hosted provider names are
/// accepted aliases of `Deepseek` — a stored proxy selection (or a legacy
/// client's migration) must land on the BYOK default, never on a rejected
/// write.
fn ApiProvider::parse(value : String) -> ApiProvider? {
  match value {
    "openseek" | "openseek-staging" | "deepseek" => Some(Deepseek)
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
  guard fields.get(key) is Some(String(value)) && !value.is_blank() else {
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
    .unwrap_or(Deepseek),
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
    // Presence ORs in the DEEPSEEK environment fallback exactly as the run
    // config resolves it (`configured_api_key`): an env-configured install
    // is runnable, and the frontend gates Send on this bit.
    has_deepseek_key: settings.deepseek_api_key is Some(_) ||
    @env.get("DEEPSEEK") is Some(_),
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
      "engine settings were written by a newer SeekMoon; update the app to change them",
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
/// The SeekMoon relay origin remote access signs in to. The relay is a
/// SeekMoon-hosted service on the same origin as the update manifest, and
/// it no longer depends on the chat provider — only the chat proxy was
/// retired, so remote access stays available for every provider.
/// `OPENSEEK_SERVER_URL` overrides the origin for development against a
/// local or ad-hoc server.
///
/// The settings snapshot is awaited but discarded: the origin no longer
/// derives from the stored provider. The await holds this function's
/// published `async` signature stable across the BYOK cutover (the
/// committed `pkg.generated.mbti` pins it); drop it at the next interface
/// reshape and regenerate with `moon info`.
pub async fn remote_server_base(manager : EngineManager) -> String? {
  if @env.get("OPENSEEK_SERVER_URL") is Some(base) && !base.is_blank() {
    return Some(base.trim().to_owned())
  }
  let (_, _) = manager.settings_snapshot()
  Some(RelayServerOrigin)
}

// The settings store's contract: tolerant reads, merge-preserving atomic
// writes, the version guard, and the run-config resolution built on it.
