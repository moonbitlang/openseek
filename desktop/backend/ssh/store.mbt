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
let profile_write_lock : @semaphore.Semaphore = Semaphore(1, initial_value=1)

///|
async fn save_profiles(hosts : Array[@protocol.SshProfile]) -> Unit {
  let path = @pathx.Path(profile_path())
  @fs.mkdir(path.dirname().to_string(), recursive=true, allow_existing=true)
  @fsx.write_text_atomic(
    path,
    @protocol.SshProfiles::{ hosts, }.to_json().stringify(),
  )
}
