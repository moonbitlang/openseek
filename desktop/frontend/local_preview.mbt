///|
fn Model::preview_local_file(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  path : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(self)
  guard self.is_desktop && ctx.owner is Host(owner) && owner.channel is Local else {
    return (@cmd.none, self)
  }
  let file = if path.contains("://") {
    @common.Uri::parse(path) catch {
      _ => return (@cmd.none, self)
    }
  } else if path.has_prefix("/") || path.clamped_view() =~ re"^[A-Za-z]:[\\/]" {
    guard @resource.of_path(Local, @common.Uri::file(path).path) is Some(file) else {
      return (@cmd.none, self)
    }
    file
  } else {
    guard ctx.root() is Some(root) else { return (@cmd.none, self) }
    @resource.join_relative(root, Relative(path))
  }
  guard @resource.belongs_to(file, Local) && @fileeditor.is_html_file(file.path) else {
    return (@cmd.none, self)
  }
  let url = @uri.file_url(file.path)
  let (id, model) = self
    .begin_editor_navigation()
    .add_browser_tab(ctx.owner, url~, resolve_picker=true)
  let dark = self.theme.is_dark(self.system_dark)
  let root = ctx.root().map(root => root.path)
  (
    browser_op(
      dispatch,
      @commands.browser_preview,
      { id, path: file.path, root, dark, session: Some(owner.session), },
      quiet=false,
      on_error=text => Preview(@preview.Msg::LoadFailed(id~, url~, text~)),
    ),
    { ..model, browser_pane: { shown: None, rect: None, geo: None, }, },
  )
}
