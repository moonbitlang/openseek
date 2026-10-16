///|
/// One local desktop profile store. File locking also serializes separate
/// packaged application windows/processes; profiles never contain model keys.
pub struct Store {
  directory : String
}

///|
pub fn Store::Store(directory : String) -> Store {
  { directory, }
}

///|
pub suberror SshError {
  SshError(String)
  ProfileIdentityChanged(String)
}

///|
pub impl Show for SshError with fn output(self, logger) {
  match self {
    SshError(message) | ProfileIdentityChanged(message) =>
      logger.write_string(message)
  }
}

///|
pub extend SshError with Show::{to_string, output}

///|
fn validate(profile : @protocol.SshProfile) -> Unit raise {
  guard profile.id.has_prefix("ssh_") &&
    profile.id.length() > 4 &&
    profile.id.iter().all(ch => ch is ('a'..<='z' | '0'..<='9' | '_' | '-')) else {
    raise SshError("Invalid SSH host identity")
  }
  for
    value in [
      profile.name,
      profile.destination,
      profile.launcher,
      profile.data_dir,
      profile.build_id,
    ] {
    guard !value.is_blank() &&
      !value.contains("\u0000") &&
      !value.contains("\n") &&
      !value.contains("\r") else {
      raise SshError("SSH profile fields must be nonempty single-line values")
    }
  }
  guard !profile.destination.has_prefix("-") &&
    profile.launcher.has_prefix("/") &&
    profile.data_dir.has_prefix("/") else {
    raise SshError(
      "SSH requires a destination and absolute remote launcher/data paths",
    )
  }
  if profile.server_id is Some(id) && id.is_blank() {
    raise SshError("Saved server identity cannot be empty")
  }
}

///|
pub async fn Store::list(self : Store) -> @protocol.SshProfiles {
  let text = @fsx.read_text_if_exists(
    @pathx.Path(self.directory).join("ssh-hosts.json"),
  )
  guard text is Some(text) else { return { hosts: [], } }
  let value = @json.parse(text)
  guard value is { "version": 1, .. } else {
    raise SshError("Unsupported or missing SSH profile schema version")
  }
  let profiles : @protocol.SshProfiles = @json.from_json(value)
  let ids : Set[String] = Set([])
  for profile in profiles.hosts {
    validate(profile)
    guard !ids.contains(profile.id) else {
      raise SshError("Duplicate SSH profile identity")
    }
    ids.add(profile.id)
  }
  profiles
}

///|
pub async fn Store::get(self : Store, id : String) -> @protocol.SshProfile {
  for profile in self.list().hosts {
    if profile.id == id {
      return profile
    }
  }
  raise SshError("SSH profile no longer exists")
}

///|
async fn[T] Store::locked(self : Store, body : async () -> T) -> T {
  let lock = @fs.open(
    self.directory + "/ssh-hosts.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  @async.with_timeout(10000, () => lock.lock(Exclusive))
  @async.protect_from_cancel(body)
}

///|
async fn Store::write(
  self : Store,
  hosts : Array[@protocol.SshProfile],
) -> Unit {
  let temp = self.directory + "/ssh-hosts-" + @uuid.mint() + ".tmp"
  defer @fsx.remove_if_exists(Path(temp))
  {
    let file = @fs.open(
      temp,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    defer file.close()
    file.write(({ "version": 1, "hosts": hosts } : Json).stringify())
    file.sync()
  }
  @fs.rename(temp, self.directory + "/ssh-hosts.json")
  if !(@async.platform is Windows) {
    let directory = @fs.open(self.directory, mode=ReadOnly)
    defer directory.close()
    directory.sync()
  }
}

///|
async fn Store::save_locked(
  self : Store,
  input : @protocol.SshProfileWrite,
) -> @protocol.SshProfile {
  self.locked(() => {
    let profiles = self.list().hosts
    let previous = match input.id {
      Some(id) => Some(self.get(id))
      None => None
    }
    let profile : @protocol.SshProfile = {
      id: match previous {
        Some(profile) => profile.id
        None => "ssh_" + @uuid.mint()
      },
      name: input.name,
      destination: input.destination,
      launcher: input.launcher,
      data_dir: input.data_dir,
      build_id: input.build_id,
      // Editing an alias/path cannot silently reset its identity association.
      server_id: match previous {
        Some(profile) => profile.server_id
        None => None
      },
    }
    validate(profile)
    let hosts = profiles.filter(existing => existing.id != profile.id)
    hosts.push(profile)
    self.write(hosts)
    profile
  })
}

///|
/// Commit the first observed identity before a window publishes Connected.
/// Re-read under the lock: another process may have pinned or edited it while
/// this window's SSH initialize was in flight.
async fn Store::pin_locked(
  self : Store,
  configured : @protocol.SshProfile,
  server_id : String,
) -> Unit {
  self.locked(() => {
    let profiles = self.list().hosts
    let current = self.get(configured.id)
    guard current.destination == configured.destination &&
      current.launcher == configured.launcher &&
      current.data_dir == configured.data_dir &&
      current.build_id == configured.build_id else {
      raise SshError(
        "SSH profile changed; reopen this window to use its new configuration",
      )
    }
    if current.server_id is Some(expected) {
      guard expected == server_id else {
        raise ProfileIdentityChanged(
          "working-host server identity changed; create a new profile to reassociate explicitly",
        )
      }
      return
    }
    let pinned = { ..current, server_id: Some(server_id), }
    validate(pinned)
    self.write(
      profiles.map(profile => {
        if profile.id == current.id {
          pinned
        } else {
          profile
        }
      }),
    )
  })
}

///|
pub async fn Store::save(
  self : Store,
  input : @protocol.SshProfileWrite,
) -> @protocol.SshProfile {
  match input.id {
    Some(id) => self.deployment_locked(id, () => self.save_locked(input))
    None => self.save_locked(input)
  }
}

///|
pub async fn Store::pin(
  self : Store,
  configured : @protocol.SshProfile,
  server_id : String,
) -> Unit {
  self.deployment_locked(configured.id, () => {
    self.pin_locked(configured, server_id)
  })
}
