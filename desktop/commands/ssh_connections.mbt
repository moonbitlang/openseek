///|
pub let ssh_connect : Command[
  @protocol.SshProfileTarget,
  @protocol.SshOperation[@protocol.EmptyReply],
] = Command("ssh.connect")

///|
pub let ssh_host_request : Command[@protocol.SshHostRequest, @protocol.SshReply] = Command(
  "ssh.host_request",
)

///|
pub let ssh_add : Command[
  @protocol.SshAdd,
  @protocol.SshOperation[@protocol.SshProfile],
] = Command("ssh.add")

///|
pub let ssh_cached_projects : Command[
  @protocol.SshProfileTarget,
  Array[String]?,
] = Command("ssh.cached_projects")

///|
pub let ssh_cache_projects : Command[
  @protocol.SshProjectCatalog,
  @protocol.EmptyReply,
] = Command("ssh.cache_projects")
