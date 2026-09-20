///|
using @cmd {trait Scheduler}

///|
extern "js" fn open_link_in_browser(url : String) -> Unit =
  #| (url) => {
  #|   let parsed;
  #|   try { parsed = new URL(url, document.baseURI); } catch (_) { return; }
  #|   if (parsed.protocol === "mailto:") {
  #|     const anchor = document.createElement("a");
  #|     anchor.href = parsed.href;
  #|     anchor.click();
  #|     return;
  #|   }
  #|   if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return;
  #|   const anchor = document.createElement("a");
  #|   anchor.href = parsed.href;
  #|   anchor.target = "_blank";
  #|   anchor.rel = "noopener noreferrer";
  #|   anchor.click();
  #| }

///|
/// Browser-console links cannot call the Proton-local system opener. Use the
/// browser's own navigation surface while retaining the same scheme allowlist.
fn open_browser_link(url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => open_link_in_browser(url))
}

///|
/// Ask the Proton-local bridge to hand an external URL to the system browser.
/// Failures re-enter update as the same host-action toast used by file/app
/// openers; the browser page never emits this command.
fn open_external_link(dispatch : @cmd.Emit[Msg], url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
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
    |> ignore
  })
}
