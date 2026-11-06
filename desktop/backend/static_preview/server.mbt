///|
/// An app-owned, lazy loopback listener. Each browser tab owns one capability
/// URL and a fixed physical root. This server has no command or bridge routes.
pub struct Server {
  priv mut listener : @http.Server?
  priv ready : @async.Queue[Unit]
  priv roots : Map[String, @static_files.Directory]
  priv tabs : Map[Int32, String]
  priv openings : Map[Int32, Int32]
  priv mut generation : Int32
  priv binding : @async.Mutex
}

///|
pub fn Server::Server() -> Server {
  {
    listener: None,
    ready: @async.Queue(kind=Blocking(1)),
    roots: Map([]),
    tabs: Map([]),
    openings: Map([]),
    generation: 0,
    binding: @async.Mutex(),
  }
}

///|
/// Bind only when a validated preview is first opened. The caller keeps run
/// on the app task group, independently of individual command lifetimes.
pub async fn Server::open(
  self : Server,
  id : Int32,
  path : String,
  root? : String,
) -> String {
  self.generation += 1
  let generation = self.generation
  self.openings[id] = generation
  errdefer (if self.openings.get(id) == Some(generation) {
    self.openings.remove(id)
  })
  let file = absolute(path)
  let extension = file.to_path().extname().to_owned().to_lower()
  guard extension is (".html" | ".htm") else {
    fail("Preview requires an HTML or HTM file")
  }
  let directory = match root {
    Some(root) => absolute(root)
    None => file.to_path().dirname().resolve()
  }
  let serving = @static_files.Directory(directory.to_string())
  let fixed = absolute(serving.path())
  guard directory.contains(file) else {
    fail("Preview file is outside its workspace")
  }
  let resolved = absolute(@fs.realpath(file.to_string()))
  guard fixed.contains(resolved) && @fs.kind(resolved.to_string()) is Regular else {
    fail("Preview file is outside its root or is not a regular file")
  }
  guard file.relative_to(root=directory) is Some(relative) else {
    fail("Preview file is outside its workspace")
  }
  guard @entropy.random_hex(32) is Some(token) else {
    fail("No OS entropy available for the preview URL")
  }
  // Filesystem reads may finish after a tab closes or its page reloads. Only
  // the current opening may bind/register, and concurrent opens share a port.
  self.binding.acquire()
  defer self.binding.release()
  guard self.openings.get(id) == Some(generation) else {
    fail("Preview was closed")
  }
  let listener = match self.listener {
    Some(listener) => listener
    None => {
      let listener = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      self.listener = Some(listener)
      self.ready.put(())
      listener
    }
  }
  guard self.openings.get(id) == Some(generation) else {
    fail("Preview was closed")
  }
  self.close(id)
  self.tabs[id] = token
  self.roots[token] = serving
  let escaped = relative
    .to_string()
    .split("/")
    .map(part => @percent.encode(part))
    .join("/")
  "http://127.0.0.1:\{listener.addr.port()}/\{token}/\{escaped}"
}

///|
pub fn Server::close(self : Server, id : Int32) -> Unit {
  self.openings.remove(id)
  if self.tabs.get(id) is Some(token) {
    self.roots.remove(token)
    self.tabs.remove(id)
  }
}

///|
pub fn Server::clear(self : Server) -> Unit {
  self.openings.clear()
  self.roots.clear()
  self.tabs.clear()
}

///|
pub async fn Server::run(self : Server) -> Unit {
  defer self.clear()
  self.ready.get()
  guard self.listener is Some(listener) else { return }
  defer {
    listener.close()
    self.listener = None
  }
  @async.with_task_group(group => {
    for ;; {
      let (connection, _) = listener.accept()
      group.spawn_bg(allow_failure=true, () => {
        self.handle(connection, listener.addr.port())
      })
    }
  })
}

///|
fn absolute(path : String) -> @pathx.Absolute raise {
  let parsed = match @pathx.Absolute::from_uri_path(path) {
    Some(parsed) => Some(parsed)
    None => @pathx.Path(path).to_absolute()
  }
  guard parsed is Some(path) else { fail("Preview paths must be absolute") }
  path.normalize()
}

///|
async fn Server::handle(
  self : Server,
  conn : @http.ServerConnection,
  port : Int32,
) -> Unit {
  defer conn.close()
  let request = @async.with_timeout(10000, () => conn.read_request())
  guard request.headers.get("host") == Some("127.0.0.1:\{port}") else {
    respond_status(conn, 403, "Forbidden")
    return
  }
  guard request.meth is (Get | Head) else {
    respond_status(conn, 405, "Method Not Allowed")
    return
  }
  let path = match request.path.split_once("?") {
    Some((path, _)) => path.to_owned()
    None => request.path
  }
  guard path.strip_prefix("/") is Some(rest) &&
    rest.split_once("/") is Some((token, name)) &&
    self.roots.get(token.to_owned()) is Some(directory) else {
    respond_status(conn, 404, "Not Found")
    return
  }
  let token = token.to_owned()
  directory.serve(request, conn, path="/" + name.to_owned(), active=() => {
    self.roots.get(token) is Some(_)
  })
}

///|
async fn respond_status(
  conn : @http.ServerConnection,
  code : Int32,
  reason : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Length": "0",
    "Cache-Control": "no-store",
    "Connection": "close",
  })
  conn.end_response()
}
