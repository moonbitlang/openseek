///|
/// Schema 1 is the existing headless data layout. No automatic cross-schema
/// migration or binary rollback is permitted without a migration implementation.
async fn check_data_schema(data_dir : String, create~ : Bool) -> Unit {
  let path = data_dir + "/data-schema.json"
  match @journal.read_json(path) {
    Some({ "version": 1, .. }) => ()
    None => if create { @journal.atomic_json(path, { "version": 1 }) }
    Some(_) =>
      fail(
        "unsupported working-host data schema; preserve data and inspect migration records",
      )
  }
}

///|
async fn wait_for_owner_exit(owner : @fs.File, deadline : Int64) -> Unit {
  while !owner.try_lock(Exclusive) {
    guard @async.now() < deadline else {
      fail("old owner did not release ownership; version switch refused")
    }
    @async.sleep(25)
  }
}

///|
/// Called with lifecycle.lock held. Every side effect after intent is recorded;
/// failure never invokes the old binary against potentially changed data.
async fn upgrade_daemon(
  options : @argparse.Matches,
  owner : @fs.File,
  free : Bool,
  engine~ : String,
  build_id~ : String,
  data_dir~ : String,
  listen~ : String,
  codex_command~ : String?,
) -> Json {
  check_data_schema(data_dir, create=false)
  let previous = @journal.read_json(data_dir + "/owner.json")
  let current = if free {
    None
  } else {
    guard previous
      is Some(
        {
          "build_id": String(old_build),
          "instance_id": String(old_instance),
          ..
        }
      ) &&
      !old_build.is_blank() &&
      !old_instance.is_blank() else {
      fail("cannot verify old owner identity; refusing upgrade")
    }
    let status = control_rpc(data_dir, old_build, "server.status", {})
    guard status
      is {
        "instance_id": String(instance),
        "server_id": String(_),
        "build_id": String(actual_build),
        "data_dir": String(directory),
        ..
      } &&
      instance == old_instance &&
      actual_build == old_build &&
      directory == data_dir else {
      fail("upgrade owner identity changed")
    }
    Some(status)
  }
  if value(options, "expected-server-id") is Some(expected) {
    guard !expected.is_blank() else {
      fail("expected-server-id must be nonempty")
    }
    let observed = match current {
      Some({ "server_id": String(id), .. }) => Some(id)
      _ =>
        Some(@fs.read_file(data_dir + "/server-id").text()) catch {
          @os_error.OSError(_) as error if error.is_ENOENT() => None
          error => raise error
        }
    }
    guard observed == Some(expected) else {
      fail("working-host server identity changed; upgrade refused")
    }
  }
  if current is Some({ "build_id": String(actual), .. } as status) &&
    actual == build_id {
    return status
  }
  if free {
    guard stopped_status(data_dir) is { "recovery_required": False, .. } else {
      fail("unsettled work requires explicit recovery before upgrade")
    }
  }
  let saved_launch = @journal.read_json(data_dir + "/launch.json")
  if saved_launch is Some(launch) {
    guard launch
      is {
        "schema_version": 1,
        "instance_id": String(_),
        "build_id": String(_),
        "engine": String(_),
        "listen": String(_),
        ..
      } else {
      fail("invalid or unsupported saved launch record")
    }
  }
  let matching_launch = match (previous, saved_launch) {
    (
      Some(
        {
          "instance_id": String(expected),
          "build_id": String(expected_build),
          ..
        }
      ),
      Some(
        { "instance_id": String(actual), "build_id": String(actual_build), .. } as launch
      ),
    ) if expected == actual && expected_build == actual_build => Some(launch)
    _ => None
  }
  guard free || matching_launch is Some(_) else {
    fail(
      "running service has no matching launch record; inspect it before an explicit restart",
    )
  }
  let retained_codex = match matching_launch {
    Some(Object(fields)) =>
      match fields.get("codex_command") {
        None => None
        Some(String(command)) if @pathx.Path(command).is_host_absolute() =>
          Some(command)
        _ => fail("invalid saved Codex executable path")
      }
    _ => None
  }
  let selected_codex = match codex_command {
    Some(_) => codex_command
    None => retained_codex
  }
  let records = private_directory(data_dir + "/upgrades")
  let id = @uuid.mint()
  let record = records + "/" + id + ".json"
  let base : Map[String, Json] = {
    "schema_version": 1,
    "id": Json(id),
    "target_build_id": Json(build_id),
    "target_engine": Json(engine),
    "data_schema_version": 1,
    "migration": "none",
    "automatic_rollback": false,
  }
  if previous is Some(previous) {
    base["previous_owner"] = previous
  }
  if current is Some(identity) {
    base["previous_identity"] = identity
  }
  if matching_launch is Some(launch) {
    base["previous_launch"] = launch
  }
  let last_phase = Ref("prepared")
  async fn record_phase(phase : String, detail : Json?) -> Unit {
    let value = base.copy()
    value["phase"] = Json(phase)
    if detail is Some(detail) {
      value["detail"] = detail
    }
    @journal.atomic_json(record, Json(value))
    last_phase.val = phase
  }
  record_phase("prepared", None)
  try {
    if current
      is Some(
        { "build_id": String(old_build), "instance_id": String(instance), .. }
      ) {
      let response = control_rpc(
        data_dir,
        old_build,
        "server.prepare_upgrade",
        { "instance_id": instance },
      )
      if response is { "status": "busy", "instance_id": String(actual), .. } &&
        actual == instance {
        record_phase("busy", Some(response))
        return {
          "status": "busy",
          "running_build_id": old_build,
          "target_build_id": Json(build_id),
          "instance_id": instance,
          "upgrade_record": record,
        }
      }
      guard response
        is { "status": "draining", "instance_id": String(actual), .. } &&
        actual == instance else {
        fail("old service did not confirm the upgrade barrier")
      }
      record_phase("waiting_for_exit", Some(response))
      wait_for_owner_exit(owner, @async.now() + 70000L)
      guard stopped_status(data_dir) is { "recovery_required": False, .. } else {
        fail("old service left unsettled work; version switch refused")
      }
    }
    check_data_schema(data_dir, create=true)
    record_phase("starting", None)
    let result = launch_daemon(
      options,
      owner,
      engine~,
      build_id~,
      data_dir~,
      listen~,
      codex_command=selected_codex,
    )
    guard result is { "status": "ready", .. } else {
      fail("new service requires recovery; automatic rollback refused")
    }
    if current is Some({ "server_id": String(expected), .. }) {
      guard result is { "server_id": String(actual), .. } && actual == expected else {
        fail("working-host persistent identity changed during upgrade")
      }
    }
    record_phase("ready", Some(result))
    result
  } catch {
    error => {
      record_phase(
        "failed",
        Some({ "message": "\{error}", "last_phase": last_phase.val }),
      ) catch {
        record_error =>
          @stdio.stderr.write(
            "could not persist upgrade failure: \{record_error}\n",
          )
      }
      fail("upgrade did not complete; inspect \{record}: \{error}")
    }
  }
}

///|
async fn record_launch(
  data_dir : String,
  instance_id : String,
  build_id : String,
  engine : String,
  listen : String,
  codex_command : String?,
  viz_dir : String?,
  moonbit : @moonbit.ToolchainSource,
) -> Unit {
  let fields : Map[String, Json] = {
    "schema_version": 1,
    "instance_id": Json(instance_id),
    "build_id": Json(build_id),
    "engine": Json(engine),
    "listen": Json(listen),
  }
  if codex_command is Some(command) {
    fields["codex_command"] = Json(command)
  }
  if viz_dir is Some(directory) {
    fields["viz_dir"] = Json(directory)
  }
  match moonbit {
    Bundled(platform~, seed_dir~) => {
      fields["moonbit_platform"] = Json(platform)
      fields["moonbit_seed_dir"] = Json(seed_dir.to_string())
    }
    _ => ()
  }
  @journal.atomic_json(data_dir + "/launch.json", Json(fields))
}
