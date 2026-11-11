///|
fn preview_request_owner(
  request : @protocol.PreviewOpenRequest,
) -> @interop.ConversationIdentity {
  match request {
    Local(session~, ..) => @interop.Host({ channel: Local, session, })
    Cloud(account~, session~, ..) => @interop.Cloud(account~, session~)
  }
}

///|
fn Model::queue_preview(
  self : Model,
  request : @protocol.PreviewOpenRequest,
) -> Model {
  guard self.is_desktop else { return self }
  if request is Cloud(account~, ..) &&
    self.account.map(a => a.user.user_id) != Some(account) {
    return self
  }
  let owner = preview_request_owner(request)
  let pending_previews = self.pending_previews.copy()
  pending_previews[owner] = [
    ..pending_previews.get(owner).unwrap_or([]),
    request,
  ]
  { ..self, pending_previews, }
}

///|
/// There is one foreground editor. Park background requests with their real
/// owner, then use the same open/preview paths when that owner becomes visible.
fn Model::open_pending_preview(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> (@cmd.Cmd, Model) {
  guard self.is_desktop && self.screen is Chat && self.management_dialog is None else {
    return (@cmd.none, self)
  }
  let ctx = file_ctx(self)
  let owner = ctx.owner
  guard ctx.root() is Some(root) &&
    self.pending_previews.get(owner) is Some([request, .. rest]) else {
    return (@cmd.none, self)
  }
  let pending_previews = self.pending_previews.copy()
  if rest.is_empty() {
    pending_previews.remove(owner)
  } else {
    pending_previews[owner] = rest.to_owned()
  }
  let model = { ..self, pending_previews, }
  let more = if rest.is_empty() { @cmd.none } else { dispatch(OpenNextPreview) }
  let (path, current) = match request {
    Local(workspace~, path~, ..) =>
      (path, @resource.of_path(Local, workspace) == Some(root))
    Cloud(account~, path~, ..) =>
      (path, model.account.map(a => a.user.user_id) == Some(account))
  }
  // A retained request must not silently move into a replacement worktree.
  // TODO: surface a parked request whose original workspace is no longer available.
  guard current else { return (more, model) }
  let resource = @resource.join_relative(root, Relative(path))
  let (open, model) = if @fileeditor.is_html_file(path) {
    model.preview_file(dispatch, resource.to_string())
  } else {
    let model = model.begin_editor_navigation()
    show_editor_resource(
      dispatch,
      model,
      resource,
      None,
      file_link_generation=model.file_panel.file_link_generation,
    )
  }
  (@cmd.batch([open, more]), model)
}
