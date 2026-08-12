///|
using @cmd {trait Scheduler}

///|
/// Ask the Proton-local bridge to hand an external URL to the system browser.
/// Failures re-enter update as the same host-action toast used by file/app
/// openers; the browser page never emits this command.
fn open_external_link(dispatch : @cmd.Emit[Msg], url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          @interop.ChannelId::Local,
          @commands.shell_open_external,
          { url, },
        ) catch {
          error => {
            scheduler.add(
              dispatch(HostActionFailed(@interop.bridge_error_text(error))),
            )
            return
          }
        },
      )
    })
  })
}
