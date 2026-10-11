// The engine side of a grant. An engine learns its MCP servers from one JSON
// file named by `--mcp-config`, read once when it starts; that file is the
// only channel that can carry this server's URL and the conversation's
// bearer token to it.
//
// An engine takes exactly one such file, and the user may already have one
// (`OPENSEEK_MCP_CONFIG`, inherited from the login shell). Naming ours would
// replace theirs, so the file written here is theirs with this server added.

///|
/// The config `session`'s engine is started with: the servers of `inherited`
/// (the user's own config, when they have one) plus this one, carrying
/// `session`'s bearer token. Rewritten on every call — a token lasts for one
/// launch, and an engine reads the file once.
///
/// `session` becomes a file name, so it must be a single path component;
/// callers reject ids that are not.
pub async fn Server::engine_config(
  self : Server,
  session~ : String,
  inherited? : @pathx.Path,
) -> @pathx.Path {
  let token = self.token(session)
  let theirs : Json? = if inherited is Some(path) {
    // An unreadable or malformed user config costs the user's servers, not
    // this one. The engine would have reported it in the transcript; here
    // the log is the only place left to say so.
    Some(@json.parse(@fsx.read_text(path))) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        @xlog.warn(category="mcp") <?
          {
            "event": "mcp_inherited_config_ignored",
            "path": path.to_string(),
            "error": "\{error}",
          }
        None
      }
    }
  } else {
    None
  }
  let config = merged_config(theirs, url=self.url(), token~)
  @fsx.ensure_dir(self.config_dir)
  let target = self.config_dir.join(Relative("\{session}.json"))
  // The file holds a credential: owner-only where the platform has modes.
  @fs.write_file(
    target.to_string(),
    config.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  target
}

///|
/// `inherited` with this server's entry added under `ServerName`. Everything
/// else in the user's file is kept as written, for the engine to judge; an
/// entry of theirs under the same name is replaced.
fn merged_config(inherited : Json?, url~ : String, token~ : String) -> Json {
  let root : Map[String, Json] = if inherited is Some(Object(fields)) {
    fields.copy()
  } else {
    Map([])
  }
  let servers : Map[String, Json] = if root.get("mcpServers")
    is Some(Object(servers)) {
    servers.copy()
  } else {
    Map([])
  }
  servers[ServerName] = {
    "url": url.to_json(),
    "headers": { "Authorization": "Bearer \{token}".to_json() },
  }
  root["mcpServers"] = Json::object(servers)
  Json::object(root)
}
