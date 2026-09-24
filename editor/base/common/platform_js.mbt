///|
/// Preserve Monaco's Node-first platform classification.
fn detect_platform_code() -> Int {
  let mut node : String? = None
  read_node_platform(value => node = Some(value))
  if node is Some(platform) {
    return match platform {
      "darwin" => 1
      "win32" => 2
      _ => 3
    }
  }
  let mut agent : String? = None
  read_platform_user_agent(value => agent = Some(value))
  if agent is Some(agent) {
    if agent.contains("Macintosh") {
      return 1
    }
    if agent.contains("Windows") {
      return 2
    }
    if agent.contains("Linux") {
      return 3
    }
  }
  0
}

///|
extern "js" fn read_node_platform(found : (String) -> Unit) -> Unit = "found => { if (typeof process !== 'undefined' && process.platform) found(process.platform); }"

///|
extern "js" fn read_platform_user_agent(found : (String) -> Unit) -> Unit = "found => { if (typeof navigator !== 'undefined' && navigator.userAgent) found(navigator.userAgent); }"
