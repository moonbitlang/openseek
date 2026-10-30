///|
fn Model::share_file(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  path : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(self)
  guard self.workspace_file(path) is Some(file) else {
    return (@cmd.none, self)
  }
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

///|
/// Resolve menu targets against the owning workspace without opening a preview.
/// Rendered references have already removed editor/Office location suffixes.
fn Model::workspace_file(self : Model, path : String) -> @common.Uri? {
  let ctx = file_ctx(self)
  guard ctx.root() is Some(root) else { return None }
  let file = if path.contains("://") {
    @common.Uri::parse(path) catch {
      _ => return None
    }
  } else if ctx.owner is @interop.Host(owner) &&
    (path.has_prefix("/") || path.clamped_view() =~ re"^[A-Za-z]:[\\/]") {
    guard @resource.of_path(owner.channel, @common.Uri::file(path).path)
      is Some(file) else {
      return None
    }
    file
  } else {
    guard @workspace_file_ref.parse(
        @workspace_file_ref.FenceLanguage,
        path,
        closed=true,
      )
      is Some(reference) else {
      return None
    }
    @resource.join_relative(root, Relative(reference.path))
  }
  guard @resource.relative_to(file, root) is Some(relative) &&
    !relative.is_root() else {
    return None
  }
  Some(file)
}
