// `seekmoon mcp`: the host's tools as a stdio MCP server, for a client that
// wants them as MCP tools rather than as commands. A user lists it in an MCP
// configuration like any other server —
//
//   {"mcpServers": {"seekmoon": {"command": "seekmoon", "args": ["mcp"]}}}
//
// — and the engine that reads the file starts it. The process inherits that
// engine's environment, and with it the grant that says where the host is
// and which conversation this is (`Server::grant`).
//
// The host's server already speaks MCP, so this is a relay: each line read
// from the client is one JSON-RPC message, POSTed to the host as it is, and
// the host's reply is written back as one line. Messages are relayed
// concurrently, so a slow tool call does not hold up a `ping` behind it.
//
// `seekmoon mcp browser` offers only the tools of the groups it names. Every
// tool a server lists rides every request its client makes, and a client
// caps how many it will take, so a configuration can ask for less than all.

///|
/// The command line of `seekmoon mcp`, after those two words.
fn mcp_command() -> @argparse.Command {
  Command(
    McpCommand,
    about="Serve the app's tools to an MCP client over stdin and stdout.",
    positionals=[
      PositionArg(
        "groups",
        about="Offer only these groups of tools (for example `browser`); all of them when none is named.",
        num_args=ValueRange(lower=0),
      ),
    ],
  )
}

///|
/// The subcommand that serves MCP instead of running one tool.
pub const McpCommand : String = "mcp"

///|
/// The group a tool belongs to: its name up to the first underscore, or the
/// whole name when it has none.
fn tool_group(name : String) -> String {
  match name.split_once("_") {
    Some((group, _)) => group.to_owned()
    None => name
  }
}

///|
/// Run `seekmoon mcp` with `args` (the command line after `mcp`): relay MCP
/// between `input`/`output` and the host until `input` ends, which is how a
/// client stops a stdio server. Requests already read are still answered
/// before this returns, so a session piped in whole gets all of its replies.
pub async fn serve_stdio(
  args : Array[String],
  env : Map[String, String],
  input : &@io.Reader,
  output : &@io.Writer,
) -> CliOutcome {
  guard env.get(UrlEnv) is Some(url) && env.get(TokenEnv) is Some(token) else {
    return { code: 2, stdout: "", stderr: ungranted_message(), }
  }
  let matches = mcp_command().parse(argv=args, env={}) catch {
    error => return { code: 2, stdout: "", stderr: "\{error}", }
  }
  let groups = matches.values.get("groups").unwrap_or([])
  // One writer at a time: a reply is one line, and two written at once
  // would interleave.
  let writing = @async.Mutex()
  @async.with_task_group(group => {
    for ;; {
      guard input.read_until("\n") is Some(line) else { break }
      let line = line.trim(chars="\r\n").to_owned()
      if line.is_empty() {
        continue
      }
      group.spawn_bg(allow_failure=true, () => {
        guard relay(url, token, groups, line) is Some(reply) else { return }
        writing.acquire()
        defer writing.release()
        output.write("\{reply.stringify()}\n")
      })
    }
  })
  { code: 0, stdout: "", stderr: "", }
}

///|
/// Relay one message to the host, returning what to write back: the host's
/// reply, or an error in its place when the host could not be asked. `None`
/// for a message that expects nothing.
async fn relay(
  url : String,
  token : String,
  groups : Array[String],
  line : String,
) -> Json? {
  let message = @json.parse(line) catch {
    _ => return Some(failure(Json::null(), -32700, "Parse error"))
  }
  let id : Json? = match message {
    { "method": _, "id": id, .. } => Some(id)
    _ => None
  }
  let offered = (name : String) => {
    groups.is_empty() || groups.contains(tool_group(name))
  }
  // A tool this server was asked not to offer does not exist as far as its
  // client is concerned, whatever the host would say.
  if message
    is { "method": "tools/call", "params": { "name": String(name), .. }, .. } &&
    !offered(name) {
    return id.map(id => failure(id, InvalidParams, "Unknown tool: \{name}"))
  }
  let reply = post_message(url, token, line) catch {
    error if @async.is_being_cancelled() => raise error
    // The host is gone or has restarted: the request still gets an answer,
    // and the client stays connected for when the host is back.
    Unavailable(reason) =>
      return id.map(id => failure(id, HostUnavailable, reason))
    error => return id.map(id => failure(id, HostUnavailable, "\{error}"))
  }
  match reply {
    Some({ "result": Object(result), .. } as reply) if message
      is { "method": "tools/list", .. } =>
      match (reply, result.get("tools")) {
        (Object(fields), Some(Array(tools))) => {
          let result = result.copy()
          result["tools"] = Json(
            tools.filter(tool => {
              tool is { "name": String(name), .. } && offered(name)
            }),
          )
          let fields = fields.copy()
          fields["result"] = Json::object(result)
          Some(Json::object(fields))
        }
        _ => Some(reply)
      }
    reply => reply
  }
}
