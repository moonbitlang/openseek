///|
/// Calls `tool` on the MCP server `server` through the current OpenSeek
/// host's MCP host. `server` and `tool` are the server's own names, as
/// `search` lists them; `arguments` is forwarded unchanged. A tool failure is
/// a result with `is_error`; a connection/protocol failure, and a run with no
/// MCP host, raise `TransportError`. Never retries. MCP calls never wait for
/// approval, so every call keeps the ordinary 125-second deadline.
pub async fn call(
  server : String,
  tool : String,
  arguments : Json,
) -> CallResult {
  let reply = send(Call(server~, tool~, arguments~))
  {
    content: reply.content,
    is_error: reply.is_error,
    data: reply.data,
    images: reply.images,
  }
}

///|
/// Searches the MCP tools the current host has connected. `server` alone lists
/// that server's tools in order; `query` ranks tools by relevance, within
/// `server` when both are given; neither lists every tool. A blank string is the
/// same as leaving it out. Pages hold at most `limit` tools (default 8) from
/// `offset` (default 0). No match is a page with no tools.
///
/// The search runs in the script. The first search downloads the host's
/// catalog and later ones reuse it. The host waits a bounded time for servers
/// still connecting before it lists them: for `server` when it is given, for
/// every server otherwise, so a search for another server, or for every
/// server, downloads the catalog again unless it waited for every server
/// already. A search changes nothing, so every
/// failure raises `SearchError` and the search may simply run again: an
/// unknown server, a `limit` below 1, a negative or past-the-end `offset`, and
/// a catalog that could not be downloaded (no MCP host, or a transport
/// failure).
pub async fn search(
  query? : String,
  server? : String,
  limit? : Int32,
  offset? : Int32,
) -> SearchPage raise SearchError {
  let catalog = catalog(server.filter(name => !name.is_blank()))
  let page = catalog.search(query?, server?, limit?, offset?) catch {
    @catalog.SearchError(message) => raise SearchError(message)
  }
  {
    text: page.text,
    instructions: page.instructions,
    tools: page.tools.map(entry => {
      server: entry.server,
      name: entry.tool.name,
      description: entry.tool.description,
      input_schema: entry.tool.input_schema,
      output_schema: entry.tool.output_schema,
    }),
    total: page.total,
    next_offset: page.next_offset,
  }
}

///|
const INVALID_CATALOG = "Invalid MCP catalog from the MCP host"

///|
/// The catalog this script downloaded, with the server the host waited for
/// before listing it (`None` when it waited for every server). The host's
/// catalog changes only as a server finishes connecting or loses its
/// connection, and a call to a server still connecting waits for it, so one
/// download serves every search it waited for.
let downloaded : Ref[(@catalog.Catalog, String?)?] = Ref(None)

///|
/// The host's catalog once `server` (every server when `None`) has settled:
/// the one this script already downloaded when the host waited for it then,
/// or a fresh download. A failed download is not kept, so the next search
/// tries again.
async fn catalog(server : String?) -> @catalog.Catalog raise SearchError {
  if downloaded.val is Some((catalog, waited)) &&
    (waited is None || waited == server) {
    return catalog
  }
  let catalog = decode_catalog(download(server))
  downloaded.val = Some((catalog, server))
  catalog
}

///|
/// Every catalog item, one `list` request per reply's worth, in the host's
/// order. The first request names `server`, for the host to wait for before
/// it lists the catalog. Every request after the first names the snapshot the
/// first reply came from, so a catalog that changes meanwhile cannot shift
/// the pages.
async fn download(server : String?) -> Array[Json] raise SearchError {
  let items : Array[Json] = []
  let mut cursor = None
  let mut snapshot = None
  for ;; {
    let reply = send(
      List(
        cursor~,
        snapshot~,
        server=if snapshot is None { server } else { None },
      ),
    ) catch {
      TransportError(message) => raise SearchError(message)
    }
    // A cursor the host refuses arrives as an error result with the reason.
    guard !reply.is_error else { raise SearchError(reply.content) }
    guard reply.data is Some({ "items": Array(page), .. } as data) else {
      raise SearchError(INVALID_CATALOG)
    }
    items.append(page)
    match data {
      { "snapshot": Number(id, ..), .. } => snapshot = Some(id.to_int())
      { "snapshot": _, .. } => raise SearchError(INVALID_CATALOG)
      _ => ()
    }
    match data {
      { "next_cursor": Number(next, ..), .. } => cursor = Some(next.to_int())
      { "next_cursor": _, .. } => raise SearchError(INVALID_CATALOG)
      _ => break
    }
  }
  items
}

///|
/// A configured server as the catalog items describe it.
priv struct Server {
  name : String
  instructions : String?
  error : String?
  tools : Array[@catalog.Tool]
}

///|
/// The catalog of `items`: each server, in configuration order, followed by
/// its tools.
fn decode_catalog(items : Array[Json]) -> @catalog.Catalog raise SearchError {
  let servers : Array[Server] = []
  for item in items {
    match item {
      { "server": String(name), "tool": tool, .. } => {
        guard servers.last() is Some(server) && server.name == name else {
          raise SearchError(INVALID_CATALOG)
        }
        server.tools.push(decode_tool(tool))
      }
      { "server": String(name), .. } =>
        servers.push({
          name,
          instructions: optional_text(item, "instructions"),
          error: optional_text(item, "error"),
          tools: [],
        })
      _ => raise SearchError(INVALID_CATALOG)
    }
  }
  @catalog.Catalog(
    servers.map(server => {
      match server.error {
        // An unavailable server has no tools.
        Some(error) => @catalog.Source::unavailable(name=server.name, error~)
        None =>
          @catalog.Source(
            name=server.name,
            instructions?=server.instructions,
            tools=server.tools,
          )
      }
    }),
  )
}

///|
/// The string field `key` of `item`, `None` when absent.
fn optional_text(item : Json, key : String) -> String? raise SearchError {
  guard item is Object(fields) && fields.get(key) is Some(value) else {
    return None
  }
  guard value is String(text) else { raise SearchError(INVALID_CATALOG) }
  Some(text)
}

///|
fn decode_tool(tool : Json) -> @catalog.Tool raise SearchError {
  guard tool
    is {
      "name": String(name),
      "description": String(description),
      "input_schema": input_schema,
      ..
    } else {
    raise SearchError(INVALID_CATALOG)
  }
  let output_schema = match tool {
    { "output_schema": output_schema, .. } => Some(output_schema)
    _ => None
  }
  @catalog.Tool(name~, description~, input_schema~, output_schema?)
}
