// Shell half of unified Quick Open. The palette owns its query, rows, and
// Host search cache; this file owns the three things that are the shell's:
// which conversation and editor tabs it searches, whether it may open at all,
// and where an accepted row lands.

///|
/// Project the focused conversation and its open editor tabs into the palette.
/// The projection is read-only. A Cloud session supplies its authenticated
/// file source; a Host conversation supplies its directory placement. Home
/// and other surfaces without either source have no palette input.
fn Model::quick_open_input(self : Model) -> @quick_open.Input? {
  if self.cloud_selected() {
    let ctx = file_ctx(self)
    guard self.cloud_identity() is Some(owner) &&
      ctx.root() is Some(root) &&
      ctx.cloud_files is Some(access) else {
      return None
    }
    return Some(
      @quick_open.Input::cloud(
        owner~,
        root~,
        access={ token: access.token, epoch: access.epoch, },
        open_files=self.live_editor_files(),
        active_file=self.active_workspace_file(),
      ),
    )
  }
  guard self.active_checkout() is Some(active) else { return None }
  Some(
    @quick_open.Input(
      owner=active.owner,
      root=active.placement.bind(placement => placement.checkout_root()),
      open_files=self.live_editor_files(),
      active_file=self.active_workspace_file(),
    ),
  )
}

///|
/// Unsupported shortcuts keep their browser meaning. Cloud exposes file
/// browsing, while workspace symbols still require an engine host.
fn Model::quick_open_available(
  self : Model,
  provider : @quick_open.Provider,
) -> Bool {
  self.project_picker is None &&
  self.archive_confirm is None &&
  self.delete_confirm is None &&
  !(self.update_ux is ConfirmingRestart(..)) &&
  (self.cloud_selected() || !(self.bridge_state() is BridgeLost(_))) &&
  !(self.cloud_selected() && provider is @quick_open.Symbols) &&
  self.quick_open_input() is Some(_)
}

///|
/// Answer the shortcut. Whether the palette may appear is a shell question:
/// another modal or a lost bridge already owns the screen, and the palette
/// would render over it with no way back.
fn open_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  provider : @quick_open.Provider,
) -> (@cmd.Cmd, Model) {
  guard model.quick_open_available(provider) &&
    model.quick_open_input() is Some(input) else {
    return (@cmd.none, model)
  }
  let (cmd, quick_open) = model.quick_open.open(
    dispatch.map(msg => QuickOpen(msg)),
    input,
    provider,
  )
  (cmd, { ..model, quick_open, })
}

///|
/// Route one palette message and ask the host to classify an accepted row.
/// The palette closes now; the resolved reply opens the appropriate viewer.
fn update_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  msg : @quick_open.Msg,
) -> (@cmd.Cmd, Model) {
  // The palette searches one checkout. With none on screen it has no owner to
  // answer for, so it closes rather than resolving the message against a
  // conversation or task that is gone.
  guard model.quick_open_input() is Some(input) else {
    let (cmd, quick_open) = model.quick_open.close()
    return (cmd, { ..model, quick_open, })
  }
  let (cmd, quick_open, accepted) = model.quick_open.handle(
    dispatch.map(msg => QuickOpen(msg)),
    msg,
    input,
  )
  let model = { ..model, quick_open, }
  guard accepted is Some(target) else { return (cmd, model) }
  if model.cloud_selected() && model.cloud_identity() is Some(owner) {
    let (open, next) = open_cloud_file(
      dispatch,
      model,
      owner,
      target.path,
      target.range,
    )
    return (@cmd.batch([cmd, open]), next)
  }
  // Settings and catalog surfaces return to Chat because they have no editor.
  // Codex keeps its owning surface so the editor resolves the accepted row
  // against that task's checkout instead of the hidden OpenSeek conversation.
  let screen = if model.screen is Codex { Screen::Codex } else { Chat }
  let (open_cmd, model) = request_open_path(
    dispatch,
    { ..model, screen, },
    target.path,
    target.range,
  )
  (@cmd.batch([cmd, open_cmd]), model)
}
