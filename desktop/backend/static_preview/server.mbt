///|
/// Owns one read-only loopback process per preview tab.
pub struct Server {
  priv command : String
  priv wasm : String?
  priv mut group : @async.TaskGroup[Unit]?
  priv tabs : Map[Int32, (@async.Queue[String], @async.Task[Unit])]
}

///|
pub fn Server::Server(command~ : String = "moonrun", wasm? : String) -> Server {
  { command, wasm, group: None, tabs: Map([]), }
}

///|
pub fn Server::start(self : Server, group : @async.TaskGroup[Unit]) -> Unit {
  self.group = Some(group)
}

///|
pub async fn Server::open(
  self : Server,
  id : Int32,
  path : String,
  root? : String,
) -> String {
  guard self.group is Some(group) && self.wasm is Some(wasm) else {
    fail("Local HTML preview runtime is unavailable")
  }
  self.close(id)
  let ready : @async.Queue[String] = @async.Queue(kind=Blocking(1))
  let task = group.spawn(no_wait=true, allow_failure=true, () => {
    defer (if self.tabs.get(id) is Some((current, _)) &&
      physical_equal(current, ready) {
      self.tabs.remove(id)
    })
    serve(self.command, wasm, path, root?, ready) catch {
      error => ready.close(error~)
    }
    ready.close()
  })
  self.tabs[id] = (ready, task)
  errdefer (if self.tabs.get(id) is Some((current, _)) &&
    physical_equal(current, ready) {
    self.close(id)
  })
  let url = ready.get()
  guard self.tabs.get(id) is Some((current, _)) &&
    physical_equal(current, ready) else {
    fail("Preview was closed")
  }
  url
}

///|
pub fn Server::close(self : Server, id : Int32) -> Unit {
  if self.tabs.get(id) is Some((ready, task)) {
    self.tabs.remove(id)
    ready.close()
    task.cancel()
  }
}

///|
pub fn Server::clear(self : Server) -> Unit {
  for _, (ready, task) in self.tabs {
    ready.close()
    task.cancel()
  }
  self.tabs.clear()
}

///|
fn absolute(path : String) -> @pathx.Absolute raise {
  @pathx.Absolute::parse_resource_path(path) catch {
    _ => {
      guard @pathx.Path(path).to_absolute() is Some(path) else {
        fail("Preview paths must be absolute")
      }
      path.normalize()
    }
  }
}

///|
async fn serve(
  command : String,
  wasm : String,
  path : String,
  root? : String,
  ready : @async.Queue[String],
) -> Unit {
  let file = absolute(path)
  guard file.to_path().extname().to_owned().to_lower() is (".html" | ".htm") else {
    fail("Preview requires an HTML or HTM file")
  }
  let directory = match root {
    Some(root) => absolute(root)
    None => file.to_path().dirname().resolve()
  }
  guard directory.contains(file) &&
    file.relative_to(root=directory) is Some(relative) else {
    fail("Preview file is outside its workspace")
  }
  let fixed = absolute(@fs.realpath(directory.to_string()))
  let resolved = absolute(@fs.realpath(file.to_string()))
  guard fixed.contains(resolved) && @fs.kind(resolved.to_string()) is Regular else {
    fail("Preview file is outside its root or is not a regular file")
  }
  guard @entropy.random_hex(32) is Some(token) else {
    fail("No OS entropy available for the preview URL")
  }
  let temp = @fs.tmpdir(prefix="seekmoon-preview-")
  defer (@fs.rmdir(temp, recursive=true) catch { _ => () })
  let policy_path = temp + "/policy.json"
  let policy : Json = {
    "fs": { "read": [fixed.to_string()] },
    "net": { "bind": ["127.0.0.1:0"] },
  }
  @fs.write_file(policy_path, policy.stringify())
  @async.with_task_group(group => {
    let (stdin, lease) = @process.write_to_process()
    defer lease.close()
    let (output, stdout) = @process.read_from_process()
    defer output.close()
    let (errors, stderr) = @process.read_from_process()
    defer errors.close()
    let child = @process.spawn(
      group,
      command,
      [
        "--policy",
        policy_path,
        wasm,
        "--host",
        "127.0.0.1",
        "--port",
        "0",
        "--preview-token",
        token,
        "--",
        fixed.to_string(),
      ],
      stdin~,
      stdout~,
      stderr~,
      no_console_window=true,
      cancel_handler=@process.hard_cancel(),
    )
    let diagnostics = group.spawn(() => errors.read_all().text())
    let port = @async.with_timeout(10000, () => {
      guard output.read_until("\n") is Some(line) else {
        fail(
          "Local HTML preview exited before listening: " +
          diagnostics.wait().trim().to_owned(),
        )
      }
      let port = @string.parse_int(line.trim())
      guard port > 0 && port <= 65535 else { fail("Invalid preview port") }
      port
    })
    @fs.rmdir(temp, recursive=true)
    let escaped = relative
      .to_string()
      .split("/")
      .map(part => @percent.encode(part))
      .join("/")
    ready.put("http://127.0.0.1:\{port}/\{token}/\{escaped}")
    let _ = child.wait()
  })
}
