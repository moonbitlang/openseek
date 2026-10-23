///|
fn Model::share_file(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  path : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(self)
  let file = @common.Uri::parse(path) catch { _ => return (@cmd.none, self) }
  guard ctx.root() is Some(root) &&
    @resource.relative_to(file, root) is Some(relative) &&
    !relative.0.is_empty() else {
    return (@cmd.none, self)
  }
  let source : @export_dialog.FileSource = match ctx.owner {
    Host(owner) =>
      HostFile(owner.channel, { path: relative.0, root: Some(root.path), })
    Cloud(account~, session~) => {
      guard self.account is Some(current) && current.user.user_id == account else {
        return (@cmd.none, self)
      }
      CloudFile(account~, session~, path=relative.0)
    }
  }
  let (open, dialog) = self.file_share_dialog.open_file(source)
  let (share, file_share_dialog) = dialog.update(
    dispatch.map(message => FileShareDialog(message)),
    @export_dialog.Share,
    account?=self.account,
    desktop=self.is_desktop,
  )
  (@cmd.batch([open, share]), { ..self, file_share_dialog, })
}
