///|
/// Owns one read-only loopback process per preview tab.
pub struct Server {
  priv moonx : @moonbit.MoonxProvider
  priv mut group : @async.TaskGroup[Unit]?
  priv tabs : Map[Int32, (@async.Queue[String], @async.Task[Unit])]
}

///|
pub fn Server::Server(
  engine~ : String = "",
  runtime_dir? : @pathx.Path,
) -> Server {
  {
    moonx: @moonbit.MoonxProvider(engine~, runtime_dir~, source=DesktopBundle),
    group: None,
    tabs: Map([]),
  }
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
  guard self.group is Some(group) else {
    fail("Local HTML preview runtime is unavailable")
  }
  self.close(id)
  let ready : @async.Queue[String] = @async.Queue(kind=Blocking(1))
  let task = group.spawn(no_wait=true, allow_failure=true, () => {
    defer (if self.tabs.get(id) is Some((current, _)) &&
      physical_equal(current, ready) {
      self.tabs.remove(id)
    })
    serve(self.moonx, path, root?, ready) catch {
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
  moonx : @moonbit.MoonxProvider,
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
  let provider = moonx.resolve()
  let temp = @fs.tmpdir(prefix="seekmoon-preview-")
  defer (@fs.rmdir(temp, recursive=true) catch { _ => () })
  let policy_path = temp + "/policy.json"
  let policy : Json = {
    "fs": { "read": [fixed.to_string()] },
    "net": { "bind": ["127.0.0.1:0"] },
  }
  @fs.write_file(policy_path, policy.stringify())
  @async.with_task_group(group => {
    // GUI launches on Windows need a valid stdin handle even for a CLI
    // that does not read from it.
    let (stdin, input) = @process.write_to_process()
    input.close()
    let (output, stdout) = @process.read_from_process()
    defer output.close()
    let (errors, stderr) = @process.read_from_process()
    defer errors.close()
    let child = @process.spawn(
      group,
      provider.command,
      [
        "--experimental-policy",
        policy_path,
        "cli/serve@0.1.1",
        "--",
        "--host",
        "127.0.0.1",
        "--port",
        "0",
        "--",
        fixed.to_string(),
      ],
      stdin~,
      stdout~,
      stderr~,
      inherit_env=false,
      extra_env=provider.environment,
      no_console_window=true,
      cancel_handler=if @async.platform is Windows {
        // moonx delegates to a child moonrun on Windows rather than exec.
        CancellationHandler(pid => {
          @processx.collect_output_no_stdin("taskkill", [
            "/PID",
            pid.to_string(),
            "/T",
            "/F",
          ])
          |> ignore
        })
      } else {
        @process.hard_cancel()
      },
    )
    let port = @async.with_timeout(120000, () => {
      // moonx may report a first-run download before serve starts listening.
      for ;; {
        guard errors.read_until("\n") is Some(line) else {
          fail("Local HTML preview exited before listening")
        }
        guard line.has_prefix("Serving ") &&
          line.split_once(" on http://127.0.0.1:") is Some((_, port_text)) else {
          continue
        }
        let port = @string.parse_int(port_text.trim())
        guard port > 0 && port <= 65535 else { fail("Invalid preview port") }
        break port
      }
    })
    @fs.rmdir(temp, recursive=true)
    let escaped = relative
      .to_string()
      .split("/")
      .map(part => @percent.encode(part))
      .join("/")
    ready.put("http://127.0.0.1:\{port}/\{escaped}")
    let _ = child.wait()
  })
}
