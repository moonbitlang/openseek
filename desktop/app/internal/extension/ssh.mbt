///|
let ssh_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  "ssh.event",
)

///|
/// Serialize removal with connection startup. A failed disk write leaves the
/// profile and connection available for retry; success retires every attempt.
async fn DesktopBridgeActor::remove_ssh(
  self : DesktopBridgeActor,
  id : String,
  tasks : Map[String, @async.Task[Unit]],
) -> @protocol.SshReply {
  @ssh.remove(id) catch {
    error => return SshRefused("Could not remove SSH host: \{error}")
  }
  if self.routes.get(id) is Some(route) {
    route.close()
  }
  if tasks.get(id) is Some(task) {
    task.cancel()
  }
  self.routes.remove(id)
  tasks.remove(id)
  SshSuccess({})
}

///|
fn DesktopBridgeActor::disconnect_ssh(
  self : DesktopBridgeActor,
  request : @protocol.SshConnect,
  tasks : Map[String, @async.Task[Unit]],
) -> Unit {
  guard self.routes.get(request.id) is Some(route) &&
    route.attempt == request.attempt else {
    return
  }
  route.close()
  if tasks.get(request.id) is Some(task) {
    task.cancel()
  }
  self.routes.remove(request.id)
  tasks.remove(request.id)
}
