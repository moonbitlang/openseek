// The window's native dialogs. Proton exposes them only to a command handler
// holding the window's context, so this is the one Proton command extension
// the desktop still registers: `dialog.save_file` on the injected
// `__MoonBit__.openseek_window`, which the page calls before `session.export`
// to choose the destination. Everything else the page asks the host for
// travels over the loopback WebSocket (docs/remote-protocol.md).

///|
let dialog_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="openseek-window-dialogs",
  js_namespace=@commands.WindowDialogNamespace,
)

///|
let save_file_dialog : @proton_contract.Command[
  @protocol.SaveFileDialogPayload,
  @protocol.SaveFileDialogReply,
] = dialog_contract.command(@commands.SaveFileDialogCommand)

///|
/// The renderer capability granting the window's page its native dialogs.
pub fn dialogs_capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(
    @proton_extension.typed(
      dialog_contract,
      [save_file_dialog.contract_route()],
      registrar => {
        registrar.bind(save_file_dialog, async fn(context, payload) {
          // Closing the dialog returns `None` and creates no file.
          guard context.window() is Some(window) else {
            raise @host.HostError(
              "could not open the save dialog: window is unavailable",
            )
          }
          let path = window.save_file(
            Some(payload.title),
            Some(payload.suggested_name),
          ) catch {
            error =>
              raise @host.HostError("could not open the save dialog: \{error}")
          }
          { path, }
        })
      },
    ),
  )
}
