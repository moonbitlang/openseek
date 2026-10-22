///|
pub let ssh_profiles : Command[@protocol.EmptyPayload, @protocol.SshProfiles] = Command(
  "ssh.profiles",
)

///|
pub let ssh_save : Command[@protocol.SshProfile, @protocol.SshReply] = Command(
  "ssh.save",
)

///|
pub let ssh_projects_save : Command[@protocol.SshProjects, @protocol.EmptyReply] = Command(
  "ssh.projects.save",
)

///|
pub let ssh_connect : Command[@protocol.SshConnect, @protocol.EmptyReply] = Command(
  "ssh.connect",
)

///|
pub let ssh_disconnect : Command[@protocol.SshConnect, @protocol.EmptyReply] = Command(
  "ssh.disconnect",
)

///|
pub let ssh_remove : Command[@protocol.SshProfileTarget, @protocol.SshReply] = Command(
  "ssh.remove",
)

///|
pub let ssh_request : Command[@protocol.SshRequest, @protocol.SshReply] = Command(
  "ssh.request",
)

///|
pub let ssh_auth_respond : Command[
  @protocol.SshAuthResponse,
  @protocol.SshReply,
] = Command("ssh.auth.respond")
