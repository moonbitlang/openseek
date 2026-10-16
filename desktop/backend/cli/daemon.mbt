///|
async fn read_endpoint(data_dir : String) -> @transport.Endpoint {
  guard @journal.read_json(data_dir + "/endpoint.json") is Some(value) else {
    fail("working-host endpoint is unavailable")
  }
  let endpoint : @transport.Endpoint = @json.from_json(value)
  endpoint.validate()
  endpoint
}

///|
async fn endpoint_status(data_dir : String, build_id : String) -> Json {
  let endpoint = read_endpoint(data_dir)
  let status = control_rpc(data_dir, build_id, "server.status", {})
  guard status is Object(fields) &&
    fields.get("instance_id") == Some(Json(endpoint.instance_id)) else {
    fail("working-host endpoint identity changed")
  }
  fields["endpoint"] = endpoint.to_json()
  Json(fields)
}

///|
async fn control_rpc(
  data_dir : String,
  build_id : String,
  method_ : String,
  params : Json,
) -> Json {
  @async.with_timeout(10000, () => {
    let endpoint = read_endpoint(data_dir)
    let ws = @websocket.Conn::connect("ws://127.0.0.1:\{endpoint.port}/host")
    defer ws.close()
    ws.send_text(
      (
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "server.initialize",
          "params": {
            "build_id": build_id,
            "protocol_version": @host_control.ProtocolVersion,
          },
        } : Json).stringify(),
    )
    guard control_response(ws, 1) is { "instance_id": String(id), .. } &&
      id == endpoint.instance_id else {
      fail("working-host endpoint identity changed")
    }
    ws.send_text(
      ({ "jsonrpc": "2.0", "id": 2, "method": method_, "params": params } : Json).stringify(),
    )
    control_response(ws, 2)
  })
}

///|
async fn control_response(ws : @websocket.Conn, id : Int32) -> Json {
  for ;; {
    let message = ws.recv()
    guard message.kind is Text else { fail("invalid controller response") }
    let data = Buffer()
    while message.read_some(max_len=65536) is Some(bytes) {
      guard data.length() + bytes.length() <= 1024 * 1024 else {
        fail("controller response limit exceeded")
      }
      data.write_bytes(bytes)
    }
    let response = @json.parse(@utf8.decode(data.to_bytes()))
    if response is { "id": Number(response_id, ..), "result": result, .. } &&
      response_id == id.to_double() {
      return result
    }
    if response is { "id": Number(response_id, ..), "error": error, .. } &&
      response_id == id.to_double() {
      fail("controller RPC failed: \{error.stringify()}")
    }
  }
}

///|
async fn stopped_status(data_dir : String) -> Json {
  let owner = @journal.read_json(data_dir + "/owner.json")
  let entries = @fs.readdir(data_dir + "/recovery") catch {
    @os_error.OSError(_) as e if e.is_ENOENT() => []
    e => raise e
  }
  let pending : Array[String] = []
  for id in entries {
    let dir = data_dir + "/recovery/" + id
    if !@journal.is_cleared(dir) {
      pending.push(id)
    }
  }
  {
    "status": "not_running",
    "recovery_required": !pending.is_empty(),
    "unsettled_instances": pending,
    "owner": owner,
  }
}

///|
async fn daemon(
  action : String,
  options : @argparse.Matches,
  engine~ : String,
  build_id~ : String,
  data_dir~ : String,
  listen~ : String,
) -> Unit {
  // Validate a new launch before restart can stop the existing owner. Status,
  // stop do not need the optional Codex installation to be usable.
  let codex_command = if action == "start" ||
    action == "restart" ||
    action == "upgrade" {
    ignore(configured_moonbit_source(options))
    ignore(foreground_resources(value(options, "viz-dir")))
    configured_codex_command(options)
  } else {
    None
  }
  let lifecycle = @fs.open(
    data_dir + "/lifecycle.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lifecycle.close()
  @async.with_timeout(10000, () => lifecycle.lock(Exclusive))
  let owner = @fs.open(
    data_dir + "/owner.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer owner.close()
  let seconds = match value(options, "shutdown-grace-seconds") {
    Some(value) =>
      @host_control.shutdown_grace_seconds({
        "shutdown_grace_seconds": @json.parse(value),
      })
    None => 60
  }
  let free = owner.try_lock(Exclusive)
  if action == "start" || action == "restart" || action == "upgrade" {
    check_data_schema(data_dir, create=false)
  }
  if action == "upgrade" {
    let result = upgrade_daemon(
      options,
      owner,
      free,
      engine~,
      build_id~,
      data_dir~,
      listen~,
      codex_command~,
    )
    @stdio.stdout.write(result.stringify() + "\n")
    return
  }

  if action == "status" {
    let result = if free {
      stopped_status(data_dir)
    } else {
      endpoint_status(data_dir, build_id)
    }
    @stdio.stdout.write(result.stringify() + "\n")
    return
  }
  if action == "recover" {
    guard !free &&
      options.flags.get("confirm-external-tools-stopped") is Some(true) else {
      fail(
        "running recovery service and explicit --confirm-external-tools-stopped are required",
      )
    }
    let result = control_rpc(data_dir, build_id, "server.recover", {
      "instance_id": required(options, "acknowledge-instance"),
      "confirm_external_tools_stopped": true,
    })
    @stdio.stdout.write(result.stringify() + "\n")
    return
  }
  if action == "stop" || action == "restart" {
    if !free {
      let deadline = @async.now() + seconds.to_int64() * 1000L + 10000L
      ignore(
        control_rpc(data_dir, build_id, "server.shutdown", {
          "shutdown_grace_seconds": seconds,
        }),
      )
      while !owner.try_lock(Exclusive) {
        guard @async.now() < deadline else {
          fail(
            "old owner did not release ownership within shutdown budget; restart refused",
          )
        }
        @async.sleep(25)
      }
    }
    if action == "stop" {
      @stdio.stdout.write(stopped_status(data_dir).stringify() + "\n")
      return
    }
  } else if action != "start" {
    fail("unknown daemon action")
  }
  if action == "start" && !free {
    let status = endpoint_status(data_dir, build_id)
    @stdio.stdout.write(status.stringify() + "\n")
    return
  }
  let result = launch_daemon(
    options,
    owner,
    engine~,
    build_id~,
    data_dir~,
    listen~,
    codex_command~,
  )
  @stdio.stdout.write(result.stringify() + "\n")
}

///|
async fn launch_daemon(
  options : @argparse.Matches,
  owner : @fs.File,
  engine~ : String,
  build_id~ : String,
  data_dir~ : String,
  listen~ : String,
  codex_command~ : String?,
) -> Json {
  owner.unlock()
  let args = [
    "app-server", "--data-dir", data_dir, "--listen", listen, "--engine", engine,
    "--build-id", build_id,
  ]
  for name in ["moonbit-platform", "moonbit-seed-dir"] {
    if value(options, name) is Some(value) {
      args.append(["--" + name, value])
    }
  }
  if codex_command is Some(command) {
    args.append(["--codex-command", command])
  }
  if value(options, "viz-dir") is Some(directory) {
    ignore(foreground_resources(Some(directory)))
    args.append(["--viz-dir", directory])
  }
  let input = @process.redirect_from_file("/dev/null")
  let output = @process.redirect_to_file(
    data_dir + "/daemon.log",
    append=true,
    permission=0o600,
    shared=true,
  )
  defer output.close()
  let pid = @process.spawn_orphan(
    engine,
    args,
    stdin=input,
    stdout=output,
    stderr=output,
    cwd=data_dir,
  )
  @journal.atomic_json(data_dir + "/daemon-process.json", { "pid": pid })
  let deadline = @async.now() + 15000L
  for ;; {
    let status = endpoint_status(data_dir, build_id) catch {
      error => {
        guard @async.now() < deadline else {
          fail(
            "daemon failed initialize readiness: \{error}; inspect \{data_dir}/daemon.log",
          )
        }
        @async.sleep(50)
        continue
      }
    }
    guard status is { "data_dir": String(actual), .. } && actual == data_dir else {
      fail("daemon data directory identity mismatch")
    }
    return status
  }
}
