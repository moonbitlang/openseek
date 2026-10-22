///|
fn profile_path() -> String raise {
  if @env.get_env_var("SEEKMOON_SSH_PROFILES") is Some(path) {
    return path
  }
  guard @home.dir() is Some(home) else {
    raise SshError("Home directory unavailable")
  }
  home.join(".openseek").join("ssh-profiles.json").to_string()
}

///|
pub async fn profiles() -> @protocol.SshProfiles {
  let text = @fs.read_file(profile_path()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return { hosts: [], }
    error => raise error
  }
  @json.from_json(@json.parse(text.text()))
}

///|
let profile_write_lock : @semaphore.Semaphore = Semaphore(1, initial_value=1)

///|
pub async fn save(profile : @protocol.SshProfile) -> @protocol.SshProfile {
  profile_write_lock.acquire()
  defer profile_write_lock.release()
  ignore(arguments(profile.command))
  let profile = {
    ..profile,
    id: if profile.id.is_empty() {
      "ssh-" + @uuid.mint()
    } else {
      profile.id
    },
  }
  let current = profiles()
  // Renaming a profile must not overwrite a newer project snapshot with the
  // frontend's old copy. Only remember_projects writes this cache.
  let profile = {
    ..profile,
    projects: current.hosts
    .iter()
    .find_first(host => host.id == profile.id)
    .bind(host => host.projects),
  }
  let hosts = current.hosts.map(host => {
    if host.id == profile.id {
      profile
    } else {
      host
    }
  })
  if !current.hosts.any(host => host.id == profile.id) {
    hosts.push(profile)
  }
  save_profiles(hosts)
  profile
}

///|
/// Forget only the local connection profile; remote data is untouched.
pub async fn remove(id : String) -> Unit {
  profile_write_lock.acquire()
  defer profile_write_lock.release()
  let current = profiles()
  if current.hosts.any(host => host.id == id) {
    save_profiles(current.hosts.filter(host => host.id != id))
  }
}

///|
pub async fn remember_projects(snapshot : @protocol.SshProjects) -> Unit {
  profile_write_lock.acquire()
  defer profile_write_lock.release()
  let current = profiles()
  // A late registry response cannot recreate a profile removed meanwhile.
  guard current.hosts.any(host => host.id == snapshot.id) else { return }
  save_profiles(
    current.hosts.map(host => {
      if host.id == snapshot.id {
        { ..host, projects: Some(snapshot.projects), }
      } else {
        host
      }
    }),
  )
}

///|
async fn save_profiles(hosts : Array[@protocol.SshProfile]) -> Unit {
  let path = @pathx.Path(profile_path())
  @fs.mkdir(path.dirname().to_string(), recursive=true, allow_exist=true)
  let next = path.to_string() + "." + @uuid.mint() + ".tmp"
  @fs.write_file(next, @protocol.SshProfiles::{ hosts, }.to_json().stringify())
  @fs.rename(next, path.to_string(), replace=true)
}
