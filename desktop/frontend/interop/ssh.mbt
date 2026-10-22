///|
let ssh_epochs : Map[String, Int32] = Map([])

///|
let ssh_profiles : Map[String, @protocol.SshProfile] = Map([])

///|
pub fn is_native_ssh(channel : ChannelId) -> Bool {
  channel is Remote(id) && ssh_profiles.contains(id)
}

///|
/// Only the native subscription advances the transport epoch. Notifications
/// and replies from an older connection cannot update the replacement page.
pub fn set_ssh_epoch(channel : ChannelId, epoch : Int32?) -> Unit {
  match epoch {
    Some(value) => ssh_epochs[channel.device_id()] = value
    None => ssh_epochs.remove(channel.device_id())
  }
}

///|
pub fn register_ssh_profile(profile : @protocol.SshProfile) -> Unit {
  ssh_profiles[profile.id] = profile
}

///|
pub fn current_ssh_epoch(channel : ChannelId) -> Int32? {
  ssh_epochs.get(channel.device_id())
}

///|
async fn ssh_request(
  channel : ChannelId,
  op : String,
  payload : @js.Value,
) -> @js.Value {
  guard is_native_ssh(channel) &&
    current_ssh_epoch(channel) is Some(epoch) &&
    openseek_api() is Some(api) &&
    js_prop(api, "ssh.request") is Some(_) else {
    raise BridgeUnsent("SSH connection is unavailable")
  }
  let request : @protocol.SshRequest = {
    host_id: channel.device_id(),
    epoch,
    method_: op,
    params: payload.to_json(),
  }
  // A native promise failure can happen after the remote mutation was sent.
  // Preserve Unknown even though this page also has a local Proton bridge.
  let reply = wait_bridge_promise(
    js_method_promise(
      api,
      "ssh.request",
      @js.Value::from_json(request.to_json()),
    ),
  ) catch {
    error => raise BridgeError(bridge_error_text(error))
  }
  guard current_ssh_epoch(channel) == Some(epoch) else {
    raise BridgeError(
      "SSH reply belongs to a retired connection; refresh to reconcile",
    )
  }
  let outcome : @protocol.SshReply = decode_reply("ssh.request", reply)
  match outcome {
    SshSuccess(value) => @js.Value::from_json(value)
    SshUnsent(message) => raise BridgeUnsent(message)
    SshRefused(message) => raise BridgeRefused(message)
    SshUnknown(message) => raise BridgeError(message)
  }
}
