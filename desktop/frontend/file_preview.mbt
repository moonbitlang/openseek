///|
fn Model::preview_file(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  path : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(self)
  if ctx.owner is Cloud(session~, ..) {
    guard ctx.cloud_files is Some(access) &&
      ctx.root() is Some(root) &&
      self.workspace_file(path) is Some(file) &&
      @resource.relative_to(file, root) is Some(relative) &&
      @fileeditor.is_html_file(file.path) else {
      return (@cmd.none, self)
    }
    let owner = ctx.owner
    let auth_epoch = access.epoch
    let command = @cmd.custom_cmd(scheduler => {
      @js.Promise::from_async(() => {
        let result : Result[String, @fileeditor.Failure] = Ok(
          @cloud_client.create_preview(access.token, session, relative.0),
        ) catch {
          @cloud_client.RequestError::RequestError(failure) =>
            Err(@fileeditor.Cloud(failure))
          error => Err(@fileeditor.Bridge(@interop.bridge_problem(error)))
        }
        scheduler.add(
          dispatch(CloudFilePreviewCreated(owner~, auth_epoch~, result~)),
        )
      })
      |> ignore
    })
    return (command, self)
  }
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
    .add_browser_tab(ctx.owner, resolve_picker=true)
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
    {
      ..model,
      preview: @preview.update(LoadingChanged(id~, loading=true), model.preview),
      browser_pane: { shown: None, rect: None, geo: None, },
      right_panel_open: true,
      right_panel_menu_open: false,
    },
  )
}
