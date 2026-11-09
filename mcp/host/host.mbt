// The engine's MCP host: a loopback service beside PTC through which scripts
// list the MCP catalog and call servers' tools, with the tools SDK's `mcp`
// package. PTC knows nothing of it; mbtx hands every sandboxed script both
// handoffs.

///|
/// Bounds per session and per request, as PTC sets its own.
const MaxConnections : Int32 = 16

///|
const AdmissionTimeoutMs : Int32 = 5000

///|
const SendTimeoutMs : Int32 = 5000

///|
/// A serialized reply above this is replaced by an explicit "executed but
/// oversized" error. Catalog listings pack their items below it.
const MaxReplyChars : Int32 = 65536

///|
/// Catalog snapshots kept for listings in progress. A listing takes a few
/// requests, so only the latest few catalogs are needed.
const MaxSnapshots : Int32 = 4

///|
/// The script closed its connection before its reply.
priv suberror ScriptGone

///|
/// One session-owned listener with one capability: the host does not know
/// which script is calling, so it records nothing per script.
struct Service {
  server : @socket.TcpServer
  token : String
  /// Call `tool` of `server`.
  call : async (String, String, Json) -> @agent_tool.ToolAction
  /// The catalog's items as they stand now.
  items : () -> Array[Json]
  /// The catalogs recent listings started from, oldest first: every page of
  /// a listing comes from the one it started from, so a catalog that changes
  /// meanwhile cannot shift its pages.
  snapshots : Array[Snapshot]
  mut next_snapshot : Int32
  /// Where a result's images are saved, when there is anywhere.
  image_directory : String?
  mut stop : (async () -> Unit)?
}

///|
/// Serve MCP servers' tools on the session's task group until it ends:
/// `call` calls `tool` of `server`, and `items` is the catalog as it stands
/// now, each item small enough for a reply on its own. This package knows no
/// MCP client; the engine supplies both. Images in call results are saved
/// under `image_directory`, created on first use; without one they are
/// dropped with a note.
pub async fn[X] Service::start(
  group : @async.TaskGroup[X],
  call~ : async (String, String, Json) -> @agent_tool.ToolAction,
  items~ : () -> Array[Json],
  image_directory? : String,
) -> Service {
  guard @env.rand(32) is Some(entropy) else {
    fail("MCP host: secure random capability unavailable")
  }
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  let service : Service = {
    server,
    token: @crypto.bytes_to_hex_string(entropy),
    call,
    items,
    snapshots: [],
    next_snapshot: 0,
    image_directory,
    stop: None,
  }
  let worker = group.spawn(no_wait=true, () => {
    server.run_forever(max_connections=MaxConnections, allow_failure=true, (
      socket,
      _,
    ) => {
      let conn = @http.ServerConnection::new(socket)
      defer conn.close()
      let reader = @loopback_http.RequestReader(socket)
      // Bound the entire admission phase, as PTC does: nothing runs until
      // authentication and body framing have both succeeded.
      let admitted = @async.with_timeout(AdmissionTimeoutMs, () => {
        let headers = reader.head()
        guard !headers.contains("origin") &&
          headers.get("authorization") is Some([.. "Bearer ", .. token]) &&
          token == service.token else {
          return None
        }
        Some(reader.body(headers))
      }) catch {
        _ => {
          send(
            conn,
            error_result(
              "Invalid MCP host request: expected bounded HTTP and UTF-8 JSON within 5 seconds; nothing executed",
            ),
          )
          return
        }
      }
      guard admitted is Some(input) else {
        @async.with_timeout(SendTimeoutMs, () => {
          conn.send_response(403, "Forbidden")
          conn.end_response()
        })
        return
      }
      // One request per connection: once its body is read the script sends
      // nothing more, so a read that returns means it closed the connection,
      // which it does when it is stopped. Cancel what it asked for then, as
      // stopping a script cancels its PTC calls; the MCP client tells the
      // server the request is cancelled.
      let reply = @async.with_task_group(request => {
        request.spawn_bg(no_wait=true, () => {
          ignore(socket.read_some(max_len=1)) catch {
            _ => ()
          }
          raise ScriptGone
        })
        service.answer(input)
      }) catch {
        ScriptGone => return
        error => raise error
      }
      send(conn, reply)
    })
  })
  service.stop = Some(() => {
    worker.cancel()
    @async.protect_from_cancel(() => worker.wait() catch { _ => () })
  })
  group.add_defer(() => service.close())
  service
}

///|
/// Stop serving and close the listener when the session's group ends. Calls
/// in flight are cancelled.
async fn Service::close(self : Service) -> Unit nocancel {
  @async.protect_from_cancel(() => {
    if self.stop is Some(stop) {
      self.stop = None
      stop()
    }
    self.server.close()
  })
}

///|
/// Guest environment for every script: the SDK's `mcp` package handoff.
pub fn Service::env(self : Service) -> Map[String, String] {
  {
    "OPENSEEK_MCP": (
      {
        "version": 1,
        "url": "http://127.0.0.1:\{self.server.addr.port()}/call",
        "token": self.token,
      } : Json).stringify(),
  }
}

///|
/// The reply to one request body.
async fn Service::answer(self : Service, input : Json) -> Json {
  match input {
    { "version": 1, "list": Object(fields), .. } =>
      self.list(fields) catch {
        InvalidList(message) => error_result(message)
      }
    {
      "version": 1,
      "call": {
        "server": String(server),
        "tool": String(tool),
        "arguments": arguments,
        ..
      },
      ..
    } => {
      let reply = match (self.call)(server, tool, arguments) {
        Respond(output) => self.call_reply(output)
        Control(_) => error_result("MCP tool returned unsupported loop control")
      }
      if reply.stringify().length() > MaxReplyChars {
        error_result(
          "MCP tool executed, but its result exceeded the 64K character limit. Do not retry a mutation merely to retrieve output.",
        )
      } else {
        reply
      }
    }
    _ =>
      error_result(
        "MCP host requires version=1 and a list or a call (server, tool, arguments)",
      )
  }
}

///|
/// A `list` request the host cannot answer, with the reason.
priv suberror InvalidList {
  InvalidList(String)
}

///|
/// The reply to a `list` request with these fields: a page of the snapshot
/// it names, or of a new one when it names none.
fn Service::list(
  self : Service,
  fields : Map[String, Json],
) -> Json raise InvalidList {
  let cursor = index(fields, "cursor").unwrap_or(0)
  let snapshot = if index(fields, "snapshot") is Some(id) {
    guard self.snapshots.iter().find_first(snapshot => snapshot.id == id)
      is Some(snapshot) else {
      raise InvalidList(
        "MCP host no longer keeps catalog snapshot \{id}; list the catalog again",
      )
    }
    snapshot
  } else {
    self.snapshot()
  }
  list_reply(snapshot, cursor)
}

///|
/// The optional non-negative integer field `key` of a `list` request.
fn index(fields : Map[String, Json], key : String) -> Int32? raise InvalidList {
  match fields.get(key) {
    None | Some(Null) => None
    Some(Number(number, ..)) if number >= 0.0 && number == number.floor() =>
      Some(number.to_int())
    _ =>
      raise InvalidList("MCP host list requires a non-negative integer \{key}")
  }
}

///|
/// The catalog as it stands now, as a snapshot a listing can page through:
/// the latest one when the catalog has not changed since.
fn Service::snapshot(self : Service) -> Snapshot {
  let items = (self.items)()
  if self.snapshots.last() is Some(latest) && latest.items == items {
    return latest
  }
  let snapshot = { id: self.next_snapshot, items, }
  self.next_snapshot += 1
  self.snapshots.push(snapshot)
  if self.snapshots.length() > MaxSnapshots {
    ignore(self.snapshots.remove(0))
  }
  snapshot
}

///|
/// The catalog's items at one moment, under the id a listing names it by.
priv struct Snapshot {
  id : Int32
  items : Array[Json]
}

///|
/// The snapshot's items from `cursor`: as many whole items as fit one reply
/// (always at least one), the snapshot's id, and the cursor of the rest while
/// any remain.
fn list_reply(snapshot : Snapshot, cursor : Int32) -> Json raise InvalidList {
  let items = snapshot.items
  guard cursor < items.length() || (cursor == 0 && items.is_empty()) else {
    raise InvalidList(
      "MCP host list cursor \{cursor} is past the catalog's \{items.length()} items",
    )
  }
  // Room kept for the envelope, the summary, and the next cursor.
  let budget = MaxReplyChars - 512
  let listed : Array[Json] = []
  let mut used = 0
  for item in items[cursor:] {
    let size = item.stringify().length() + 1
    if !listed.is_empty() && used + size > budget {
      break
    }
    listed.push(item)
    used += size
  }
  let next = cursor + listed.length()
  let data : Map[String, Json] = {
    "items": Json::array(listed),
    "snapshot": Json(snapshot.id),
  }
  if next < items.length() {
    data["next_cursor"] = Json(next)
  }
  let summary = if items.is_empty() {
    "The MCP catalog is empty"
  } else {
    "MCP catalog items \{cursor + 1}–\{next} of \{items.length()}"
  }
  { "version": 1, "content": summary, "is_error": false, "data": data }
}

///|
/// A tool's result as a script receives it. A reply is JSON, so images
/// cannot travel in it: each is saved to a file, its path is named in the
/// text and listed in `images`, and the script shows it to the model with
/// `read_image`.
async fn Service::call_reply(
  self : Service,
  output : @agent_tool.ToolOutput,
) -> Json {
  let notes : Array[String] = []
  let paths : Array[Json] = []
  for image in output.images {
    match self.save_image(image) {
      Ok(path) => {
        notes.push(
          "[image \{image.media_type} saved to \{path}; show it to the model with read_image]",
        )
        paths.push(Json(path))
      }
      Err(reason) =>
        notes.push("[image \{image.media_type} not saved: \{reason}]")
    }
  }
  let content = if notes.is_empty() {
    output.content
  } else if output.content.is_empty() {
    notes.join("\n")
  } else {
    "\{output.content}\n\{notes.join("\n")}"
  }
  let fields : Map[String, Json] = {
    "version": 1,
    "content": Json(content),
    "is_error": Json(output.is_error),
  }
  if output.data is Some(data) {
    fields["data"] = data
  }
  if !paths.is_empty() {
    fields["images"] = Json::array(paths)
  }
  Json::object(fields)
}

///|
/// Save `image` in a file of its own, readable only by the user, or say why
/// it was not. The call has already run, so a failure here only loses the
/// image.
async fn Service::save_image(
  self : Service,
  image : @protocol.Image,
) -> Result[String, String] {
  guard self.image_directory is Some(directory) else {
    return Err("this session has no directory to save images in")
  }
  guard @env.rand(16) is Some(entropy) else {
    return Err("secure random file name unavailable")
  }
  let extension = match image.media_type {
    "image/png" => ".png"
    "image/jpeg" => ".jpg"
    "image/gif" => ".gif"
    "image/webp" => ".webp"
    _ => ""
  }
  let path = "\{directory}/mcp-image-\{@crypto.bytes_to_hex_string(entropy)}\{extension}"
  try {
    @fs.mkdir(directory, permission=0o700, recursive=true, allow_exist=true)
    @fs.write_file(path, image.bytes, create_mode=CreateNew, permission=0o600)
  } catch {
    error => Err("\{error}")
  } noraise {
    _ => Ok(path)
  }
}

///|
fn error_result(message : String) -> Json {
  { "version": 1, "content": message, "is_error": true }
}

///|
async fn send(conn : @http.ServerConnection, result : Json) -> Unit {
  @async.with_timeout(SendTimeoutMs, () => {
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "application/json",
    })
    conn.write(result)
    conn.end_response()
  })
}
