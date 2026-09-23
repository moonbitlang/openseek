///|
using @cmd {trait Scheduler}

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

///|
/// Use the browser's URL parser to preserve relative URLs and normalization.
fn resolve_browser_url(url : String) -> Result[(String, String), String] {
  let base : String = @js.Value::cast_from(@dom.document()).get_with_string(
    "baseURI",
  )
  @base_browser.resolve_url(url, base~)
}

///|
fn open_link_in_browser(url : String) -> Unit {
  guard resolve_browser_url(url) is Ok((href, protocol)) else { return }
  guard protocol == "mailto:" || protocol == "http:" || protocol == "https:" else {
    return
  }
  let anchor = @dom.document().create_element("a")
  anchor.set_attribute("href", href)
  if protocol != "mailto:" {
    anchor.set_attribute("target", "_blank")
    anchor.set_attribute("rel", "noopener noreferrer")
  }
  if anchor.to_html_element() is Some(element) {
    element.click()
  }
}
