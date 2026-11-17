///|
priv struct Entry {
  info : @protocol.ConnectorInfo
  resource : String
  oauth : @config.OAuthConfig?
}

///|
priv struct Attempt {
  id : String
  pending : @oauth.Pending
  entry : Entry
}

///|
/// Owns device authorization attempts for a host; credentials stay on that host.
struct Service {
  bundled : @pathx.Path?
  attempts : Map[String, Attempt]
  lock : @async.Mutex
}

///|
pub fn Service::Service(bundled : @pathx.Path?) -> Service {
  { bundled, attempts: Map([]), lock: Mutex(), }
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
            info: { ..info, error: Some("\{error}"), },
            resource: "",
            oauth: None,
          })
          continue
        }
      }
      guard parsed is [Http(url~, oauth=Some(oauth), ..)] else { continue }
      let connected = (@oauth.token(url, oauth) is Some(_)) catch {
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
      self.attempts.remove(request.id)
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
    let entries = self.entries()
    guard entries.iter().find_first(e => e.info.id == request.id) is Some(entry) &&
      entry.oauth is Some(config) else {
      fail(
        "This connector has no available OAuth configuration; refresh the list",
      )
    }
    match operation {
      "connect" => {
        self.attempts.remove(request.id)
        let pending = @oauth.begin(config)
        guard @entropy.random_hex(16) is Some(id) else {
          fail("Cannot create authorization attempt")
        }
        self.attempts[request.id] = { id, pending, entry, }
        reply(entries, authorization={
          attempt: id,
          url: pending.authorization_url(),
          code: pending.user_code(),
        })
      }
      "poll" => {
        guard self.attempts.get(request.id) is Some(attempt) &&
          request.attempt == Some(attempt.id) else {
          fail("Authorization was cancelled or replaced; connect again")
        }
        guard attempt.entry.oauth == entry.oauth &&
          attempt.entry.resource == entry.resource else {
          self.attempts.remove(request.id)
          fail("Connector configuration changed; connect again")
        }
        errdefer self.attempts.remove(request.id)
        let result = @oauth.poll(attempt.pending, entry.resource, config)
        match result {
          Waiting =>
            reply(entries, authorization={
              attempt: attempt.id,
              url: attempt.pending.authorization_url(),
              code: attempt.pending.user_code(),
            })
          Authorized => {
            self.attempts.remove(request.id)
            reply(self.entries())
          }
        }
      }
      "disconnect" => {
        self.attempts.remove(request.id)
        @oauth.disconnect(entry.resource, config)
        reply(self.entries())
      }
      _ => fail("Unknown connector operation")
    }
  } catch {
    error => failure(error)
  }
}
