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
  let (preview, id) = @preview.open_page(self.preview, url~)
  let current = self.dock_state_for(ctx.owner)
  let dock = if current.active is Some(FilePicker) {
    @dock.resolve_pick(current, Browser(id~))
  } else {
    @dock.open_browser(current, id)
  }
  let dark = self.theme.is_dark(self.system_dark)
  let root = ctx.root().map(root => root.path)
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request_in_order(
        Local,
        @commands.browser_preview,
        { id, path: file.path, root, dark, session: Some(owner.session), },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              Preview(
                @preview.Msg::LoadFailed(
                  id~,
                  url~,
                  text=@interop.bridge_error_text(error),
                ),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(Preview(@preview.Msg::Navigated(id~, url=reply.url))),
      )
    })
    |> ignore
  })
  (
    command,
    {
      ..self.begin_editor_navigation().with_dock_state_for(ctx.owner, dock),
      preview,
      browser_pane: { shown: None, rect: None, geo: None, },
      right_panel_open: true,
      right_panel_menu_open: false,
    },
  )
}
