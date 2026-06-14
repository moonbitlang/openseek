// Turning a `start` payload into the validated configuration a serve engine
// is spawned with.

///|
const DefaultModel = "deepseek-v4-pro"

///|
const DefaultMaxSteps = 1000

///|
/// Sent as the API key when a custom endpoint is configured without one: the
/// engine refuses to start with an empty key, but an endpoint like the
/// default OpenSeek proxy does not validate it.
const PlaceholderApiKey = "unused"

///|
priv struct RunConfig {
  task : String
  api_key : String
  // Custom chat-completions endpoint; None means the engine's built-in
  // default (the official DeepSeek endpoint).
  api_url : String?
  model : String
  max_steps : Int
  engine : String
  // Where the engine process runs: natively, or inside a WSL distro. In WSL
  // mode `engine` above (the bundled Windows binary) still serves the
  // host's own one-shot session queries; the serve process runs the
  // distro's engine instead.
  host : EngineHost
  cwd : String?
  session : String?
  session_root : String?
}

///|
fn required_secret(
  value : String?,
  env_name : String,
) -> String raise HostError {
  if value is Some(value) {
    return value
  }
  if @env.get(env_name) is Some(value) {
    return value
  }
  raise HostError(
    "DeepSeek API key is required; pass api_key or set " + env_name,
  )
}

///|
fn configured_max_steps(value : Int?) -> Int raise HostError {
  let parsed = if value is Some(value) {
    value
  } else if @env.get("OPENSEEK_MAX_STEPS") is Some(text) {
    @string.parse_int(text) catch {
      _ => raise HostError("OPENSEEK_MAX_STEPS must be a positive integer")
    }
  } else {
    DefaultMaxSteps
  }
  guard parsed > 0 else {
    raise HostError("max_steps must be a positive integer")
  }
  parsed
}

///|
async fn run_config(payload : StartPayload, engine : String) -> RunConfig {
  let task = payload.task.trim().to_owned()
  guard !task.is_empty() else { raise HostError("task must not be empty") }
  let api_url = match payload.api_url {
    Some(url) => Some(url)
    None => @env.get("OPENSEEK_API_URL")
  }
  // Only the official endpoint strictly needs a key; a custom endpoint
  // decides for itself, so a missing key becomes a placeholder there.
  let api_key = required_secret(payload.api_key, "DEEPSEEK") catch {
    error => if api_url is Some(_) { PlaceholderApiKey } else { raise error }
  }
  let session = payload.session
  let host = engine_host(payload, engine)
  {
    task,
    api_key,
    api_url,
    model: match payload.model {
      Some(model) => model
      None => @env.get("DEEPSEEK_MODEL").unwrap_or(DefaultModel)
    },
    max_steps: configured_max_steps(payload.max_steps),
    engine,
    host,
    cwd: resolved_run_cwd(payload.cwd, session, host~),
    session,
    session_root: if session is Some(_) {
      @sessiondirs.resolved_session_root(payload.session_root)
    } else {
      None
    },
  }
}

///|
/// Engine working directory for a run. An explicit payload value must be an
/// existing directory — a typo fails the run with a clear message instead of a
/// cryptic engine error. When unset, the conversation gets its own workspace
/// directory derived from its durable session id (created on demand by
/// `start_run`), so the agent's files land somewhere the user can find and
/// resuming the session returns to them. With no session either, fall back to
/// the user's home directory: inheriting the host's own cwd would hand the
/// agent whatever directory the app happened to be launched from (`/` under
/// Finder), which is never a sensible place to work in.
///
/// A WSL run may name an absolute Linux path — a directory that exists only
/// inside the distro, which the host cannot probe; it is passed through for
/// `wsl --cd` to resolve (and reject) there.
async fn resolved_run_cwd(
  payload_cwd : String?,
  session : String?,
  host~ : EngineHost,
) -> String? {
  if payload_cwd is Some(cwd) {
    if host is Wsl(..) && is_linux_abs_path(cwd) {
      return Some(cwd)
    }
    let cwd = @home.expand(cwd)
    guard is_dir(cwd) else {
      raise HostError("working directory does not exist: " + cwd)
    }
    return Some(cwd)
  }
  if session is Some(session) &&
    @sessiondirs.session_workspace_dir(session) is Some(dir) {
    return Some(dir)
  }
  @home.dir()
}

///|
/// Whether `path` exists and is a directory; probe failures mean "no".
async fn is_dir(path : String) -> Bool {
  let kind = @fs.kind(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  kind is Directory
}

///|
/// The manager's map key for a run: its durable session id, or the one shared
/// slot for session-less runs (the desktop client always names a session).
fn session_key(config : RunConfig) -> String {
  config.session.unwrap_or("")
}

///|
/// Everything that pins a serve process to a config: a prompt whose
/// fingerprint differs (model change, new session, …) must replace the
/// process. The task is deliberately excluded — prompts vary per turn.
fn engine_fingerprint(config : RunConfig) -> String {
  [
    config.engine,
    config.host.fingerprint(),
    config.api_key,
    config.api_url.unwrap_or(""),
    config.model,
    config.max_steps.to_string(),
    config.cwd.unwrap_or(""),
    config.session.unwrap_or(""),
    config.session_root.unwrap_or(""),
  ].join("\u{0}")
}
