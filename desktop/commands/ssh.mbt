///|
pub let ssh_profiles : Command[@protocol.EmptyPayload, @protocol.SshProfiles] = Command(
  "ssh.profiles",
)

///|
pub let ssh_save : Command[@protocol.SshProfile, @protocol.SshReply] = Command(
  "ssh.save",
)

///|
pub let ssh_connect : Command[@protocol.SshProfileTarget, @protocol.EmptyReply] = Command(
  "ssh.connect",
)

///|
pub let ssh_disconnect : Command[
  @protocol.SshProfileTarget,
  @protocol.EmptyReply,
] = Command("ssh.disconnect")

///|
pub let ssh_request : Command[@protocol.SshRequest, @protocol.SshReply] = Command(
  "ssh.request",
)
