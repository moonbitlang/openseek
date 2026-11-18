///|
priv struct Entry {
  info : @protocol.ConnectorInfo
  resource : String
  oauth : @config.OAuthConfig?
}

///|
priv struct Attempt {
  id : String
  pending : Authorization
  entry : Entry
}

///|
/// Owns MCP authorization attempts and their host-local credentials.
struct Service {
  bundled : @pathx.Path?
  attempts : Map[String, Attempt]
  lock : @async.Mutex
  mut group : @async.TaskGroup?
}

///|
pub fn Service::Service(bundled : @pathx.Path?) -> Service {
  { bundled, attempts: Map([]), lock: Mutex(), group: None, }
}

///|
/// Tie authorization tasks to the lifetime of the host.
pub fn Service::attach(self : Service, group : @async.TaskGroup) -> Unit {
  self.group = Some(group)
}

///|
priv struct Authorization {
  url : String
  code : String?
  credential : @oauth.CredentialCommit
  task : @async.Task[Unit]
}

///|
async fn Authorization::cancel(self : Authorization) -> Unit {
  self.credential.cancel()
  self.task.cancel()
}

///|
fn Attempt::authorization(self : Attempt) -> @protocol.ConnectorAuthorization {
  { attempt: self.id, url: self.pending.url, code: self.pending.code, }
}

///|
async fn begin_device(
  group : @async.TaskGroup,
  config : @config.DeviceOAuthConfig,
  credential : @oauth.CredentialCommit,
) -> Authorization {
  let device = @oauth.device_auth(config)
  let task = group.spawn(no_wait=true, allow_failure=true, () => {
    credential.save(@oauth.device_access_token(config, device))
  })
  {
    url: device.verification_uri(),
    code: Some(device.user_code()),
    credential,
    task,
  }
}

///|
async fn Service::entries(self : Service) -> Array[Entry] {
  let mut library = if self.bundled is Some(path) {
    @agent_skill.discover_skills(path.to_string())
  } else {
    []
  }
  if @skills.global_library_dir() is Some(path) {
    library = @agent_skill.merge_skills(
      library,
      overrides=@agent_skill.discover_skills(path.to_string()),
    )
  }
  let result = []
  for skill in library {
    let skill_path = @pathx.Path(skill.path())
    guard skill_path.basename() == "SKILL.md" else { continue }
    let dir = skill_path.dirname().to_string()
    let path = skill_path.dirname().join("mcp.json").to_string()
    let text = @fs.read_text(path) catch {
      @os_error.OsError(NotFound, ..) => continue
      error => {
        result.push(
          error_entry(path, skill.name(), "Cannot read mcp.json: \{error}"),
        )
        continue
      }
    }
    let json = @json.parse(text) catch {
      _ => {
        result.push(error_entry(path, skill.name(), "Invalid mcp.json"))
        continue
      }
    }
    guard json is { "mcpServers": Object(servers), .. } else {
      result.push(
        error_entry(path, skill.name(), "mcpServers must be an object"),
      )
      continue
    }
    for name, server in servers {
      let id = "\{path}#\{name}"
      let auth = match server {
        { "oauth": _, .. } => "oauth"
        { "headersHelper": _, .. } => "helper"
        _ => "external"
      }
      let info : @protocol.ConnectorInfo = {
        id,
        name,
        skill: skill.name(),
        source: path,
        auth,
        connected: false,
        error: None,
      }
      if auth != "oauth" {
        result.push({ info, resource: "", oauth: None, })
        continue
      }
      let env = @env.get_env_vars()
      env["OPENSEEK_SKILL_DIR"] = dir
      let parsed = @config.decode(
        { "mcpServers": Json::object(Map([(name, server)])) },
        env~,
      ) catch {
        error => {
          result.push({
            info: { ..info, auth: "invalid", error: Some("\{error}"), },
            resource: "",
            oauth: None,
          })
          continue
        }
      }
      guard parsed is [Http(url~, oauth=Some(oauth), ..)] else { continue }
      let connected = @oauth.authorized(url, oauth) catch {
        error => {
          result.push({
            info: { ..info, error: Some("Cannot read credentials: \{error}"), },
            resource: url,
            oauth: Some(oauth),
          })
          continue
        }
      }
      result.push({
        info: { ..info, connected, },
        resource: url,
        oauth: Some(oauth),
      })
    }
  }
  result
}

///|
fn error_entry(path : String, skill : String, error : String) -> Entry {
  {
    info: {
      id: path,
      name: skill,
      skill,
      source: path,
      auth: "external",
      connected: false,
      error: Some(error),
    },
    resource: "",
    oauth: None,
  }
}

///|
fn reply(
  entries : Array[Entry],
  authorization? : @protocol.ConnectorAuthorization,
) -> @protocol.ConnectorReply {
  { connectors: entries.map(e => e.info), authorization, error: None, }
}

///|
fn failure(error : Error) -> @protocol.ConnectorReply {
  { connectors: [], authorization: None, error: Some("\{error}"), }
}

///|
pub async fn Service::list(self : Service) -> @protocol.ConnectorReply {
  reply(self.entries()) catch {
    error => failure(error)
  }
}

///|
async fn Service::cancel_requested_attempt(
  self : Service,
  request : @protocol.ConnectorRequest,
) -> Unit {
  if self.attempts.get(request.id) is Some(attempt) &&
    request.attempt == Some(attempt.id) {
    attempt.pending.cancel()
    // A commit may have yielded while cancellation waited for it.
    if self.attempts.get(request.id) is Some(current) &&
      current.id == attempt.id {
      self.attempts.remove(request.id)
    }
  }
}

///|
/// Start, observe, or cancel a user-initiated authorization.
pub async fn Service::action(
  self : Service,
  operation : String,
  request : @protocol.ConnectorRequest,
) -> @protocol.ConnectorReply {
  if operation == "cancel" {
    self.cancel_requested_attempt(request)
    return self.list()
  }
  if operation == "disconnect" || operation == "connect" {
    if self.attempts.get(request.id) is Some(attempt) {
      attempt.pending.cancel()
    }
  }
  self.lock.acquire()
  defer self.lock.release()
  try {
    if operation == "connect" || operation == "disconnect" {
      // A second request may have published an attempt while this one waited.
      if self.attempts.get(request.id) is Some(attempt) {
        attempt.pending.cancel()
        self.attempts.remove(request.id)
      }
    }
    let entries = self.entries()
    guard entries.iter().find_first(e => e.info.id == request.id) is Some(entry) &&
      entry.oauth is Some(config) else {
      if operation == "poll" {
        self.cancel_requested_attempt(request)
      }
      fail(
        "This connector has no available OAuth configuration; refresh the list",
      )
    }
    match operation {
      "connect" => {
        guard @entropy.random_hex(16) is Some(id) else {
          fail("Cannot create authorization attempt")
        }
        guard self.group is Some(group) else {
          fail("Authorization requires a running Desktop host")
        }
        let credential = @oauth.CredentialCommit(
          config,
          resource=entry.resource,
        )
        let pending = match config {
          DeviceCode(config) => begin_device(group, config, credential)
          AuthorizationCode(config) =>
            begin_browser(group, entry.resource, config, credential)
        }
        let attempt = { id, pending, entry, }
        self.attempts[request.id] = attempt
        reply(entries, authorization=attempt.authorization())
      }
      "poll" => {
        guard self.attempts.get(request.id) is Some(attempt) &&
          request.attempt == Some(attempt.id) else {
          fail("Authorization was cancelled or replaced; connect again")
        }
        guard attempt.entry.oauth == entry.oauth &&
          attempt.entry.resource == entry.resource else {
          self.cancel_requested_attempt(request)
          fail("Connector configuration changed; connect again")
        }
        errdefer self.attempts.remove(request.id)
        if attempt.pending.task.try_wait() is Some(_) {
          self.attempts.remove(request.id)
          reply(self.entries())
        } else {
          reply(entries, authorization=attempt.authorization())
        }
      }
      "disconnect" => {
        @oauth.disconnect(entry.resource, config)
        reply(self.entries())
      }
      _ => fail("Unknown connector operation")
    }
  } catch {
    error => failure(error)
  }
}
