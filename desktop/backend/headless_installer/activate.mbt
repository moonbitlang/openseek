///|
pub(all) enum Activation {
  Ready(@host_control.Identity)
  Busy(
    instance_id~ : String,
    running_build_id~ : String,
    upgrade_record~ : String
  )
}

///|
pub async fn activate(
  installed : Installation,
  destination~ : String,
  data_dir~ : String,
  expected_server_id? : String,
  ssh~ : String = "ssh",
) -> Activation {
  try {
    guard data_dir.has_prefix("/") &&
      !data_dir.split("/").any(part => part == "..") else {
      raise InstallError(
        "activate", "Data directory must be absolute without parent traversal",
      )
    }
    let args = [
      installed.launcher,
      "app-server",
      "daemon",
      "upgrade",
      "--data-dir",
      data_dir,
      "--build-id",
      installed.build_id,
    ]
    if expected_server_id is Some(id) {
      args.append(["--expected-server-id", id])
    }
    let reply = ssh_command(
      destination,
      args.map(quote).join(" "),
      ssh~,
      timeout_ms=120000,
    )
    if reply
      is {
        "status": "busy",
        "target_build_id": String(target),
        "running_build_id": String(running),
        "instance_id": String(instance),
        "upgrade_record": String(record),
        ..
      } &&
      target == installed.build_id &&
      !running.is_blank() &&
      !instance.is_blank() &&
      record.has_prefix("/") {
      return Busy(
        instance_id=instance,
        running_build_id=running,
        upgrade_record=record,
      )
    }
    let identity : @host_control.Identity = @json.from_json(reply)
    guard identity.build_id == installed.build_id &&
      identity.protocol_version == @host_control.ProtocolVersion &&
      identity.status == "ready" &&
      identity.data_dir.has_prefix("/") else {
      raise InstallError(
        "activate", "Working host did not reach matching-build readiness; inspect daemon and upgrade records",
      )
    }
    if expected_server_id is Some(expected) {
      guard identity.server_id == expected else {
        raise InstallError("activate", "Working-host server identity changed")
      }
    }
    Ready(identity)
  } catch {
    InstallError(_, _) as error => raise error
    error => raise InstallError("activate", "\{error}")
  }
}
