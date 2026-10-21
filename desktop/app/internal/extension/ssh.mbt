///|
let ssh_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  "ssh.event",
)

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
