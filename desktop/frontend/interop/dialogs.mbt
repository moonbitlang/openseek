// The desktop window's native dialogs. Proton only opens them for a command
// holding the window's context, so they stay on its injected runtime
// (`__MoonBit__.openseek_window`) rather than on the wire; the page opens
// one and then sends the chosen destination to the host over its ordinary
// channel. A browser console has no injected runtime and never calls this.

///|
/// Ask the window for a native save dialog. `None` when the user dismissed
/// it; raises when this page has no injected runtime or the dialog failed.
pub async fn save_file_dialog(
  title~ : String,
  suggested_name~ : String,
) -> String? {
  guard moonbit_bridge_root() is Some(root) &&
    js_prop(root, @commands.WindowDialogNamespace) is Some(dialogs) &&
    js_prop(dialogs, @commands.SaveFileDialogCommand) is Some(_) else {
    raise BridgeUnsent("Native dialogs are unavailable on this page")
  }
  let payload : @protocol.SaveFileDialogPayload = { title, suggested_name, }
  let reply = js_method_promise(
    dialogs,
    @commands.SaveFileDialogCommand,
    @js.Value::from_json(payload.to_json()),
  ).wait()
  let decoded : @protocol.SaveFileDialogReply = decode_reply(
    @commands.SaveFileDialogCommand,
    reply,
  )
  decoded.path
}
