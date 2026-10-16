///|
pub let ssh_prepare_begin : Command[
  @protocol.SshPreparationRequest,
  @protocol.SshOperation[@protocol.SshPreparationToken],
] = Command("ssh.prepare.begin")

///|
pub let ssh_prepare_execute : Command[
  @protocol.SshPreparationToken,
  @protocol.SshOperation[@protocol.SshProfile],
] = Command("ssh.prepare.execute")

///|
pub let ssh_prepare_progress : Command[
  @protocol.SshPreparationToken,
  @protocol.SshPreparationProgress,
] = Command("ssh.prepare.progress")

///|
pub let ssh_prepare_cancel : Command[
  @protocol.SshPreparationToken,
  @protocol.EmptyReply,
] = Command("ssh.prepare.cancel")
