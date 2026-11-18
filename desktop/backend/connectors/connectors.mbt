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
/// Tie browser callback listeners to the lifetime of the host.
pub fn Service::attach(self : Service, group : @async.TaskGroup) -> Unit {
  self.group = Some(group)
}

///|
priv enum Authorization {
  Device(@oauth.Pending)
  Browser(BrowserAttempt)
}

///|
async fn Authorization::cancel(self : Authorization) -> Unit {
  match self {
    Device(pending) => pending.cancel()
    Browser(pending) => pending.cancel()
  }
}

///|
fn Attempt::authorization(self : Attempt) -> @protocol.ConnectorAuthorization {
  match self.pending {
    Device(pending) =>
      {
        attempt: self.id,
        url: pending.authorization_url(),
        code: Some(pending.user_code()),
      }
    Browser(pending) =>
      { attempt: self.id, url: pending.authorization.url(), code: None, }
  }
}

///|
async fn Authorization::poll(
  self : Authorization,
  resource : String,
  config : @config.OAuthConfig,
) -> Bool {
  match (self, config) {
    (Device(pending), DeviceCode(config)) =>
      @oauth.poll(pending, resource, config) is Authorized
    (Browser(pending), AuthorizationCode(_)) =>
      pending.task.try_wait() is Some(_)
    _ => fail("Connector configuration changed; connect again")
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
/// Each short RPC polls at most once; navigation/cancel never starts a hidden login.
pub async fn Service::action(
  self : Service,
  operation : String,
  request : @protocol.ConnectorRequest,
) -> @protocol.ConnectorReply {
  // Cancellation must fence an outstanding HTTP poll before waiting on its lock.
  if operation == "cancel" {
    if self.attempts.get(request.id) is Some(attempt) &&
      request.attempt == Some(attempt.id) {
      attempt.pending.cancel()
      // A commit may have yielded while cancellation waited for it. Do not
      // remove a newer attempt that another client started in the meantime.
      if self.attempts.get(request.id) is Some(current) &&
        current.id == attempt.id {
        self.attempts.remove(request.id)
      }
    }
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
      fail(
        "This connector has no available OAuth configuration; refresh the list",
      )
    }
    match operation {
      "connect" => {
        guard @entropy.random_hex(16) is Some(id) else {
          fail("Cannot create authorization attempt")
        }
        let pending = match config {
          DeviceCode(config) => Device(@oauth.begin(config))
          AuthorizationCode(config) => {
            guard self.group is Some(group) else {
              fail("Browser authorization requires a running Desktop host")
            }
            Browser(begin_browser(group, entry.resource, config))
          }
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
          attempt.pending.cancel()
          self.attempts.remove(request.id)
          fail("Connector configuration changed; connect again")
        }
        errdefer self.attempts.remove(request.id)
        if attempt.pending.poll(entry.resource, config) {
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
