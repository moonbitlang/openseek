// The topbar's branch chip: ask the host for the git branch of a
// conversation's workspace through the `git.branch` method. Probed when a
// run starts (the workspace is created lazily on the first one), when a
// stored session opens, and when a run finishes (the agent may have created
// the repository or switched branches mid-turn). Any failure just reads as
// "no branch" — the chip hides.

///|
fn fetch_branch(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  cwd : @pathx.Absolute?,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      @interop.set_trimmed(payload, "cwd", workspace_token(cwd))
      let reply = @interop.bridge_request(
        channel,
        "git.branch",
        payload.to_value(),
      ) catch {
        _ => {
          scheduler.add(dispatch(BranchLoaded(session~, branch=None)))
          return
        }
      }
      scheduler.add(
        dispatch(
          BranchLoaded(
            session~,
            branch=decode_branch(@interop.reply_json_text(reply)),
          ),
        ),
      )
    })
  })
}

///|
/// The reply's `branch` — absent (None) when the workspace is not a git
/// repository, and None likewise for a malformed reply.
fn decode_branch(text : String) -> String? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  @jsonx.json_text(reply, "branch")
}
