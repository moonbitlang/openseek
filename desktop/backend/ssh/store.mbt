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
pub async fn save(profile : @protocol.SshProfile) -> @protocol.SshProfile {
  ignore(arguments(profile.command))
  ignore(remote_command(profile.server))
  let profile = {
    ..profile,
    id: if profile.id.is_empty() {
      "ssh-" + @uuid.mint()
    } else {
      profile.id
    },
  }
  let current = profiles()
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
  let current = profiles()
  if current.hosts.any(host => host.id == id) {
    save_profiles(current.hosts.filter(host => host.id != id))
  }
}

///|
async fn save_profiles(hosts : Array[@protocol.SshProfile]) -> Unit {
  let path = @pathx.Path(profile_path())
  @fs.mkdir(path.dirname().to_string(), recursive=true, allow_exist=true)
  let next = path.to_string() + "." + @uuid.mint() + ".tmp"
  @fs.write_file(next, @protocol.SshProfiles::{ hosts, }.to_json().stringify())
  @fs.rename(next, path.to_string(), replace=true)
}
