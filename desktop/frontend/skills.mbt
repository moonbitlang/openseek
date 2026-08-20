// The one skills call the root makes for itself. Browsing the registry and
// changing the library belong to the Skills page (`frontend/skills`); the
// library's *contents* are a focused-host mirror the whole app reads, so
// re-reading them stays here.

///|
/// Refresh the local skills library's contents.
fn fetch_installed_skills(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.skills_installed,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(InstalledSkillsFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(InstalledSkillsLoaded(@skills.installed_from_reply(reply))),
      )
    })
  })
}
