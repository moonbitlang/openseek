///|
/// Serialize deployment and edits for one profile without holding the whole
/// store lock during SSH. New profiles use their freshly minted local ID.
async fn[T] Store::deployment_locked(
  self : Store,
  id : String,
  body : async () -> T,
) -> T {
  guard id.has_prefix("ssh_") &&
    id.iter().all(ch => ch is ('a'..<='z' | '0'..<='9' | '_' | '-')) else {
    raise SshError("Invalid SSH profile identity")
  }
  let file = @fs.open(
    self.directory + "/" + id + ".prepare.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer file.close()
  @async.with_timeout(1000, () => file.lock(Exclusive)) catch {
    @async.TimeoutError =>
      raise SshError(
        "This SSH profile is being prepared or edited in another window; try again when it finishes",
      )
    error => raise error
  }
  body()
}

///|
pub async fn Store::prepare(
  self : Store,
  request : @protocol.SshPreparationRequest,
  bootstrap : String,
  progress : (String) -> Unit,
) -> @protocol.SshProfile {
  self.prepare_using(
    request,
    progress,
    install=(destination, directory, progress) => {
      @headless_installer.install(
        destination~,
        directory~,
        bootstrap~,
        progress~,
      )
    },
    activate=(installation, destination, data_dir, expected_server_id) => {
      @headless_installer.activate(
        installation,
        destination~,
        data_dir~,
        expected_server_id?,
      )
    },
  )
}

///|
async fn Store::prepare_using(
  self : Store,
  request : @protocol.SshPreparationRequest,
  progress : (String) -> Unit,
  install~ : async (String, String, (String) -> Unit) -> @headless_installer.Installation,
  activate~ : async (@headless_installer.Installation, String, String, String?) -> @headless_installer.Activation,
) -> @protocol.SshProfile {
  guard !request.directory.is_blank() else {
    raise SshError("Select a local headless package directory")
  }
  let previous = match request.target {
    Existing(id~) => Some(self.get(id))
    New(..) => None
  }
  let (id, name, destination, data_dir, expected) = match
    (request.target, previous) {
    (Existing(..), Some(profile)) => {
      guard profile.server_id is Some(server_id) else {
        raise SshError(
          "Open this host once to verify its identity before preparing an update",
        )
      }
      (
        profile.id,
        profile.name,
        profile.destination,
        profile.data_dir,
        Some(server_id),
      )
    }
    (New(name~, destination~, data_dir~), None) =>
      ("ssh_" + @uuid.mint(), name, destination, data_dir, None)
    _ => raise SshError("Invalid preparation target")
  }
  for value in [name, destination, data_dir] {
    guard !value.is_blank() &&
      !value.iter().any(ch => ch is ('\u0000'..<='\u001f' | '\u007f')) else {
      raise SshError(
        "Host name, SSH destination and remote data directory must be nonempty single-line values",
      )
    }
  }
  guard !destination.has_prefix("-") &&
    !destination.iter().any(ch => ch == ' ') &&
    data_dir.has_prefix("/") &&
    !data_dir.split("/").any(part => part == "..") else {
    raise SshError(
      "Use an SSH destination and an absolute remote data directory without parent traversal",
    )
  }
  self.deployment_locked(id, () => {
    if previous is Some(profile) && self.get(id) != profile {
      raise SshError(
        "SSH profile changed before preparation; reload hosts and retry",
      )
    }
    let installed = install(destination, request.directory, progress)
    progress("activate")
    let identity = match activate(installed, destination, data_dir, expected) {
      Ready(identity) => identity
      Busy(running_build_id~, upgrade_record~, ..) =>
        raise SshError(
          "Working host is busy on " +
          running_build_id +
          "; finish or cancel active work before retrying. Upgrade record: " +
          upgrade_record,
        )
    }
    guard identity.status == "ready" &&
      identity.build_id == installed.build_id &&
      identity.protocol_version == @host_control.ProtocolVersion &&
      identity.data_dir.has_prefix("/") &&
      !identity.server_id.is_blank() else {
      raise SshError(
        "Prepared host returned an invalid ready identity; profile was not saved",
      )
    }
    if expected is Some(expected) && identity.server_id != expected {
      raise ProfileIdentityChanged(
        "Working-host identity changed; profile was not saved",
      )
    }
    progress("save_profile")
    self.locked(() => {
      let profiles = self.list().hosts
      if previous is Some(profile) && self.get(id) != profile {
        raise SshError(
          "SSH profile changed during activation; inspect the running host before retrying",
        )
      }
      let result : @protocol.SshProfile = {
        id,
        name,
        destination,
        launcher: installed.launcher,
        data_dir: identity.data_dir,
        build_id: installed.build_id,
        server_id: Some(identity.server_id),
      }
      validate(result)
      let hosts = profiles.filter(profile => profile.id != id)
      hosts.push(result)
      self.write(hosts)
      result
    })
  })
}
