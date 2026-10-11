// The host's MCP server: a loopback Streamable HTTP endpoint through which
// the engines this host spawns call host-owned tools. The MCP client those
// engines use lives in the root module's `mcp/`; this is the other end.
//
// One principal is fenced out and one is let in. An engine is let in by the
// bearer token its conversation was granted, which also names the
// conversation — a handler learns who is calling from the token, never from
// arguments the model wrote. A web page is fenced out: loopback binding
// limits reachability, not identity, and a page an agent opened can reach
// this port, so a request carrying an `Origin` header is refused before its
// token is looked at. Processes already running as the user are not defended
// against (desktop/AGENTS.md).
//
// Every reply is one `application/json` body. The optional GET stream and
// SSE are not offered: the server sends no requests of its own.

///|
/// The `mcpServers` entry this server is configured under, and therefore the
/// middle of every tool's model-facing name: `mcp__seekmoon__<tool>`.
const ServerName = "seekmoon"

///|
const EndpointPath = "/mcp"

///|
/// Cap on one request body. A `tools/call` carries a tool name and a small
/// arguments object; anything near this size is not one.
const MaxRequestBytes : Int = 1048576

///|
/// Deadline for a client to deliver its whole request, so a connection that
/// opens and then says nothing does not hold a task for the app's lifetime.
const RequestReadTimeoutMs : Int = 10000

///|
/// A failure of the server itself, as opposed to one of its tools.
pub suberror ServerError {
  ServerError(String)
}

///|
pub impl Show for ServerError with fn output(self, logger) {
  let ServerError(message) = self
  logger.write_string(message)
}

///|
pub extend ServerError with Show::{output, to_string}

///|
struct Server {
  listener : @http.Server
  // Reported as `serverInfo.version`.
  version : String
  tools : Map[String, Tool]
  // Where each conversation's engine config is written; see `config.mbt`.
  config_dir : @pathx.Path
  // Bearer token to the conversation it was granted to, and back. A grant
  // lasts for the launch: a conversation's engine is respawned many times
  // (model change, idle retirement), and every one of them is the same caller.
  sessions : Map[String, String]
  tokens : Map[String, String]
}

///|
/// Bind the loopback listener on an ephemeral port. `run` serves it; binding
/// first lets engine configs name the port before anything is accepted.
pub async fn Server::bind(
  tools : Array[Tool],
  version~ : String,
  config_dir~ : @pathx.Path,
) -> Server {
  {
    listener: Server(@socket.Addr::parse("127.0.0.1:0")),
    version,
    tools: Map::from_array(tools.map(tool => (tool.name, tool))),
    config_dir,
    sessions: Map([]),
    tokens: Map([]),
  }
}

///|
/// The endpoint an engine's MCP client is pointed at.
pub fn Server::url(self : Server) -> String {
  "http://127.0.0.1:\{self.listener.addr.port()}\{EndpointPath}"
}

///|
/// The bearer token `session`'s engines authenticate with, minted on first
/// use.
fn Server::token(self : Server, session : String) -> String raise ServerError {
  if self.tokens.get(session) is Some(token) {
    return token
  }
  guard @entropy.random_hex(32) is Some(token) else {
    // No OS entropy is a hard failure, never weak randomness.
    raise ServerError("no OS entropy available for the tool server token")
  }
  self.tokens[session] = token
  self.sessions[token] = session
  token
}

///|
/// The conversation a request's bearer token was granted to.
fn Server::caller(self : Server, request : @http.Request) -> String? {
  guard request.headers.get("authorization") is Some(value) &&
    value.strip_prefix("Bearer ") is Some(token) else {
    return None
  }
  self.sessions.get(token.to_owned())
}

///|
/// Accept and serve connections for the app's lifetime. Each connection is
/// its own task and answers one request: a tool call can take a while, and
/// must not hold up another conversation's.
pub async fn Server::run(self : Server) -> Unit {
  defer self.listener.close()
  @async.with_task_group(group => {
    for ;; {
      let (conn, _) = self.listener.accept()
      group.spawn_bg(allow_failure=true, () => self.handle(conn))
    }
  })
}

///|
async fn Server::handle(self : Server, conn : @http.ServerConnection) -> Unit {
  defer conn.close()
  let received = @async.with_timeout(RequestReadTimeoutMs, () => {
    let request = conn.read_request()
    guard request.path == EndpointPath else { return Refused(404, "Not Found") }
    guard request.headers.get("origin") is None else {
      return Refused(403, "Forbidden")
    }
    guard self.caller(request) is Some(session) else {
      return Refused(401, "Unauthorized")
    }
    guard request.meth is Post else {
      return Refused(405, "Method Not Allowed")
    }
    match read_body(conn) {
      Some(body) => Accepted(session~, body~)
      None => Refused(413, "Content Too Large")
    }
  })
  match received {
    Refused(code, reason) => respond_status(conn, code, reason)
    Accepted(session~, body~) => {
      let message = @json.parse(@utf8.decode(body)) catch {
        _ => {
          respond_json(
            conn,
            400,
            "Bad Request",
            failure(Json::null(), -32700, "Parse error"),
          )
          return
        }
      }
      match self.dispatch(session, message) {
        Some(answer) => respond_json(conn, 200, "OK", answer)
        None => respond_status(conn, 202, "Accepted")
      }
    }
  }
}

///|
/// What reading one request came to.
priv enum Received {
  Accepted(session~ : String, body~ : Bytes)
  Refused(Int, String)
}

///|
/// The request body, or `None` once it exceeds `MaxRequestBytes`.
async fn read_body(conn : @http.ServerConnection) -> Bytes? {
  let buffer = @buffer.Buffer()
  for ;; {
    guard conn.read_some(max_len=65536) is Some(chunk) else { break }
    guard buffer.length() + chunk.length() <= MaxRequestBytes else {
      return None
    }
    buffer.write_bytes(chunk)
  }
  Some(buffer.contents())
}

///|
async fn respond_json(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : Json,
) -> Unit {
  let bytes = @utf8.encode(body.stringify())
  conn.send_response(code, reason, extra_headers={
    "Content-Type": "application/json",
    "Content-Length": bytes.length().to_string(),
    "Cache-Control": "no-store",
    "Connection": "close",
  })
  conn.write(bytes)
  conn.end_response()
}

///|
async fn respond_status(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Length": "0",
    "Connection": "close",
  })
  conn.end_response()
}
