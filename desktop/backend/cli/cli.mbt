///|
pub fn command() -> @argparse.Command {
  Command(
    "app-server",
    about="Run the working-host service over loopback TCP.",
    subcommands=[
      Command(
        "remote",
        flags=[FlagArg("reconnect", long="reconnect")],
        about="Native SSH working-host JSONL client (explicit connection scope).",
        options=[
          OptionArg("ssh", long="ssh", default_values=["/usr/bin/ssh"]),
          OptionArg("host", long="host", required=true),
          OptionArg("launcher", long="launcher", required=true),
          OptionArg("expected-server-id", long="expected-server-id"),
          OptionArg("host-id", long="host-id"),
        ],
      ),
      Command("daemon", subcommand_required=true, subcommands=[
        Command("start"),
        Command("status"),
        Command("stop"),
        Command("restart"),
        Command(
          "upgrade",
          about="Activate this build only when the current host is idle; preserve upgrade records.",
          options=[OptionArg("expected-server-id", long="expected-server-id")],
        ),
        Command(
          "recover",
          about="Acknowledge inspected external tools; restart is required.",
          options=[
            OptionArg(
              "acknowledge-instance",
              long="acknowledge-instance",
              required=true,
            ),
          ],
          flags=[
            FlagArg(
              "confirm-external-tools-stopped",
              long="confirm-external-tools-stopped",
            ),
          ],
        ),
      ]),
    ],
    options=[
      OptionArg(
        "moonbit-platform",
        global=true,
        long="moonbit-platform",
        env="OPENSEEK_HOST_MOONBIT_PLATFORM",
      ),
      OptionArg(
        "moonbit-seed-dir",
        global=true,
        long="moonbit-seed-dir",
        env="OPENSEEK_HOST_MOONBIT_SEED_DIR",
      ),
      OptionArg(
        "shutdown-grace-seconds",
        long="shutdown-grace-seconds",
        global=true,
      ),
      OptionArg(
        "data-dir",
        global=true,
        long="data-dir",
        about="Private working-host data directory.",
      ),
      OptionArg(
        "listen",
        global=true,
        long="listen",
        about="IPv4 loopback bind address (default 127.0.0.1:0).",
      ),
      OptionArg(
        "codex-command",
        global=true,
        long="codex-command",
        env="OPENSEEK_HOST_CODEX_COMMAND",
        about="Absolute preinstalled Codex executable; missing Codex only disables Codex features.",
      ),
      OptionArg(
        "viz-dir",
        global=true,
        long="viz-dir",
        env="OPENSEEK_HOST_VIZ_DIR",
        about="Absolute directory containing matching index.html and viz_app.js.",
      ),
      OptionArg(
        "engine",
        global=true,
        long="engine",
        env="OPENSEEK_HOST_ENGINE",
        about="Absolute openseek engine launcher.",
      ),
      OptionArg(
        "build-id",
        global=true,
        long="build-id",
        env="OPENSEEK_HOST_BUILD_ID",
        about="Exact installed build identity.",
      ),
    ],
  )
}

///|
fn value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn required(matches : @argparse.Matches, name : String) -> String raise {
  guard value(matches, name) is Some(value) && !value.is_empty() else {
    fail("app-server requires --\{name} or its launcher environment")
  }
  value
}

///|
fn default_data_dir() -> String raise {
  if @env.get("XDG_DATA_HOME") is Some(root) {
    return root + "/seekmoon"
  }
  guard @home.dir() is Some(home) else { fail("home directory is unavailable") }
  home.to_string() + "/.local/share/seekmoon"
}

///|
async fn private_directory(path : String) -> String {
  guard @pathx.Path(path).is_host_absolute() else {
    fail("directory must be absolute")
  }
  @fs.mkdir(path, recursive=true, allow_exist=true, permission=0o700)
  guard @fs.kind(path, follow_symlink=false) is Directory else {
    fail("private directory must not be a symlink")
  }
  @fs.chmod(path, 0o700)
  @fs.realpath(path)
}

///|
async fn host_platform() -> String {
  let (code, output, error) = @processx.collect_output_no_stdin("uname", ["-sm"])
  guard code == 0 else { fail(error.text()) }
  output.text().trim().to_owned().replace_all(old=" ", new="-")
}

///|
async fn persistent_server_id(data_dir : String) -> String {
  let path = data_dir + "/server-id"
  let existing = @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => {
      let id = @uuid.mint()
      @fs.write_file(
        path,
        id,
        create_mode=CreateNew,
        permission=0o600,
        sync=Full,
      )
      return id
    }
    error => raise error
  }
  guard !existing.is_blank() else { fail("empty server identity file") }
  existing
}

///|
fn leaf(matches : @argparse.Matches) -> @argparse.Matches {
  match matches.subcommand {
    Some((_, next)) => leaf(next)
    None => matches
  }
}

///|
pub async fn run(matches : @argparse.Matches) -> Unit {
  let config = leaf(matches)
  if matches.subcommand is Some(("remote", _)) {
    remote(config)
    return
  }
  let engine = @fs.realpath(required(config, "engine"))
  let build_id = required(config, "build-id")
  let data_dir = private_directory(
    value(config, "data-dir").unwrap_or_else(default_data_dir),
  )
  let listen = value(config, "listen").unwrap_or("127.0.0.1:0")
  let address = @socket.Addr::parse(listen)
  guard !address.is_ipv6() &&
    address.ip() == @socket.Addr::parse("127.0.0.1:0").ip() else {
    fail("app-server must listen on 127.0.0.1")
  }
  if matches.subcommand is Some((_, arguments)) {
    guard arguments.subcommand is Some((action, options)) else {
      fail("missing daemon action")
    }
    daemon(action, options, engine~, build_id~, data_dir~, listen~)
    return
  }
  foreground(
    engine~,
    build_id~,
    data_dir~,
    listen~,
    viz_dir?=value(config, "viz-dir"),
    codex_command?=configured_codex_command(config),
    moonbit=configured_moonbit_source(config),
  )
}

///|
async fn foreground(
  engine~ : String,
  build_id~ : String,
  data_dir~ : String,
  listen~ : String,
  viz_dir? : String,
  codex_command? : String,
  moonbit~ : @moonbit.ToolchainSource,
) -> Unit {
  let resources = { ..foreground_resources(viz_dir), moonbit, }
  let address = @socket.Addr::parse(listen)
  let lock_path = data_dir + "/owner.lock"
  let owner = @fs.open(
    lock_path,
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer owner.close()
  guard owner.try_lock(Exclusive) else {
    fail("working host already owns this data directory")
  }
  check_data_schema(data_dir, create=true)
  @workspaces.configure_headless_store(
    @pathx.Path(data_dir + "/registry").resolve(),
  )
  let server_id = persistent_server_id(data_dir)
  let instance_id = @uuid.mint()
  let journal = @journal.Journal::open(data_dir~, instance_id~, build_id~)
  record_launch(
    data_dir, instance_id, build_id, engine, listen, codex_command, viz_dir, moonbit,
  )
  let recovering = journal.needs_recovery()
  guard @home.dir() is Some(home) else { fail("home directory is unavailable") }
  let home = @fs.realpath(home.to_string())
  let platform = host_platform()
  let service = @backend_api.ApiState(
    {
      data_dir: Path(data_dir),
      engine_executable: engine,
      codex: CodexSettings(
        command=codex_command.unwrap_or_else(@codex.command),
        home=Some(Path(data_dir + "/codex")),
      ),
      resources,
      build_id,
      mode: Headless,
    },
    @runtime.HostRuntime::without_terminal(),
  )
  if recovering {
    service.require_recovery()
  }
  let identity : @host_control.Identity = {
    server_id,
    instance_id,
    build_id,
    protocol_version: @host_control.ProtocolVersion,
    platform,
    home,
    data_dir,
    status: service.status(),
  }
  let listener = @socket.TcpServer(address)
  defer listener.close()
  defer @async.protect_from_cancel(() => {
    @fs.remove(data_dir + "/endpoint.json") catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => ()
      error => raise error
    }
  })
  @signal.set_global_cancellation_signals([SIGINT, SIGTERM])
  let shutdown : @async.Queue[Int32] = Queue(kind=Blocking(1))
  let grace : Ref[Int32?] = Ref(None)
  let requested_at : Ref[Int64?] = Ref(None)
  let settled = Ref(false)
  @async.with_task_group(outer => {
    // The outer signal cancels the waiter. This shield keeps the service and
    // its children alive until the same drain path used by RPC has finished.
    let running = outer.spawn(() => {
      @async.protect_from_cancel(() => {
        @async.with_task_group(group => {
          if !recovering {
            group.spawn_bg(() => service.run())
          }
          let endpoint : @transport.Endpoint = {
            port: listener.addr.port(),
            instance_id,
          }
          @journal.atomic_json(data_dir + "/endpoint.json", endpoint.to_json())
          group.spawn_bg(() => {
            listener.run_forever(
              (stream, _) => {
                let ws = @async.with_timeout(10000, () => {
                  let http = @http.ServerConnection::new(stream)
                  errdefer http.close()
                  let request = http.read_request()
                  guard request.path == "/host" &&
                    request.headers.get("Origin") is None else {
                    fail("unknown working-host endpoint")
                  }
                  @websocket.Conn::from_http_server(request, http)
                })
                defer ws.close()
                let requested_here = Ref(false)
                defer (if requested_here.val && grace.val is Some(seconds) {
                  ignore(shutdown.try_put(seconds) catch { _ => false })
                })
                let controls : Array[@transport.RequestHandler] = [
                  {
                    name: "server.recovery",
                    invoke: _ => journal.diagnostics(),
                  },
                  {
                    name: "server.recover",
                    invoke: params => {
                      guard params
                        is {
                          "instance_id": String(id),
                          "confirm_external_tools_stopped": True,
                          ..
                        } else {
                        fail(
                          "explicit external-tool acknowledgement is required",
                        )
                      }
                      journal.acknowledge(id, true)
                      ({ "restart_required": true } : Json)
                    },
                  },
                  {
                    name: "server.status",
                    invoke: _ => {
                      { ..identity, status: service.status(), }.to_json()
                    },
                  },
                  {
                    name: "server.prepare_upgrade",
                    invoke: params => {
                      guard params is { "instance_id": String(expected), .. } &&
                        expected == instance_id else {
                        fail("upgrade owner identity mismatch")
                      }
                      guard service.try_upgrade() else {
                        return (
                          { "status": "busy", "instance_id": instance_id } :
                          Json)
                      }
                      requested_here.val = true
                      grace.val = Some(60)
                      requested_at.val = Some(@async.now())
                      group.spawn_bg(() => {
                        @async.sleep(1000)
                        ignore(shutdown.try_put(60))
                      })
                      (
                        { "status": "draining", "instance_id": instance_id } :
                        Json)
                    },
                  },
                  {
                    name: "server.shutdown",
                    invoke: params => {
                      let seconds = @host_control.shutdown_grace_seconds(params)
                      service.begin_drain()
                      requested_here.val = true
                      if grace.val is None {
                        grace.val = Some(seconds)
                        requested_at.val = Some(@async.now())
                        // A disappeared or non-reading requester cannot pin Draining.
                        // Normal shutdown starts on the real flush acknowledgement.
                        group.spawn_bg(() => {
                          @async.sleep(1000)
                          ignore(shutdown.try_put(seconds))
                        })
                      }
                      ({ "status": "draining" } : Json)
                    },
                  },
                ]
                service
                .direct_client(controls)
                .serve_initialized(
                  ws,
                  identity={ ..identity, status: service.status(), },
                  on_response_sent=method_ => {
                    if (
                        method_ == "server.shutdown" ||
                        method_ == "server.prepare_upgrade"
                      ) &&
                      requested_here.val &&
                      grace.val is Some(seconds) {
                      ignore(shutdown.try_put(seconds) catch { _ => false })
                    }
                  },
                )
              },
              allow_failure=true,
              max_connections=64,
            )
          })
          @stdio.stderr.write("working host ready: \{listener.addr}\n")
          let seconds = shutdown.get()
          service.begin_drain()
          let deadline = requested_at.val.unwrap_or_else(@async.now) +
            seconds.to_int64() * 1000L
          while service.has_active_work() && @async.now() < deadline {
            @async.sleep(25)
          }
          settled.val = !service.has_active_work()
          group.return_immediately(())
        })
      })
    })
    if @async.handle_cancellation(() => running.wait()) is None {
      @async.protect_from_cancel(() => {
        service.begin_drain()
        ignore(shutdown.try_put(60))
        running.wait()
      })
    }
  })
  if settled.val {
    @async.protect_from_cancel(() => journal.clean())
  }
}

///|
fn foreground_resources(viz_dir : String?) -> @host.HostResources raise {
  let resources = @host.HostResources::from_path()
  guard viz_dir is Some(directory) else { return resources }
  guard @pathx.Path(directory).is_host_absolute() else {
    fail("app-server --viz-dir must be absolute")
  }
  {
    ..resources,
    viz: Some({
      shell: @pathx.Path(directory).join("index.html").to_string(),
      bundle: @pathx.Path(directory).join("viz_app.js").to_string(),
    }),
  }
}

///|
/// Preserve an explicit executable as one argv entry, without requiring it to
/// exist: Codex availability must not prevent the rest of the host starting.
fn configured_codex_command(matches : @argparse.Matches) -> String? raise {
  match value(matches, "codex-command") {
    None => None
    Some(command) => {
      guard @pathx.Path(command).is_host_absolute() else {
        fail("--codex-command must be an absolute executable path")
      }
      Some(command)
    }
  }
}

///|
async fn configured_moonbit_source(
  matches : @argparse.Matches,
) -> @moonbit.ToolchainSource {
  match
    (value(matches, "moonbit-platform"), value(matches, "moonbit-seed-dir")) {
    (None, None) => External
    (Some(platform), Some(seed_dir)) => {
      guard @moonbit.bundled_source(
          platform~,
          seed_dir~,
          host_platform=host_platform(),
        )
        is Some(source) else {
        fail("MoonBit seed version stamp is missing or empty: \{seed_dir}")
      }
      source
    }
    _ =>
      fail(
        "--moonbit-platform and --moonbit-seed-dir must be configured together",
      )
  }
}
