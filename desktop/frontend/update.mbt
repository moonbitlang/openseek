// Root update orchestration and cross-panel synchronization.

///|
/// The file-editor package's view of the active conversation: which session
/// the panel serves, the workspace hint its fs ops carry, and the viewer's
/// theme. Recomputed per dispatch — it is only a projection of the model.
fn file_ctx(model : Model) -> @fileeditor.Ctx {
  let conv = model.active()
  let checkout = model.checkout_placement(conv)
  let file_body_visible = match model.dock.active {
    Some(File(_)) | Some(FilePicker) => true
    None | Some(Browser(_)) => false
  }
  {
    // Keep the real identity even while placement is unresolved or missing.
    // Both panel packages use the typed checkout state to park host work; the
    // stable owner lets an interrupted changed-file review resume after Repair
    // without ever treating the project root as a fallback checkout.
    owner: { channel: model.focused, session: conv.session_id },
    request_epoch: model.file_panel.request_epoch,
    workspace: conv.workspace,
    checkout,
    dark_mode: model.theme.is_dark(model.system_dark),
    tree_layout: model.tree_layout,
    narrow: model.narrow,
    // The dock's projection: strip membership and the active tab are the
    // dock's truth, handed to the file subsystem read-only.
    // The dock preference survives Skills/Settings navigation, and an open
    // dock can instead show its browser or empty-strip launcher. CSS hides the
    // file body in all three cases. Report actual visibility so the file
    // subsystem parks its workspace watches and Changes refreshes off-screen.
    panel_open: model.dock.open && model.screen is Chat && file_body_visible,
    open_files: @dock.file_paths(model.dock),
    active_file: @dock.active_file(model.dock),
  }
}

///|
/// The terminal package's view of the active conversation. The conversation's
/// device owns every PTY opened from this context; a remote connection is
/// considered unavailable from its first socket loss because its old PTYs are
/// torn down at that boundary, even before the page escalates to BridgeLost.
fn terminal_ctx(model : Model) -> @terminal.Ctx {
  let conv = model.active()
  let connected = match model.device_state(conv.device) {
    Some(dev) => dev.bridge is Connected && dev.reconnect_failures == 0
    None => false
  }
  {
    channel: conv.device,
    session: conv.session_id,
    workspace: conv.workspace,
    checkout: model.checkout_placement(conv),
    dark_mode: model.theme.is_dark(model.system_dark),
    connected,
  }
}

///|
/// Reconcile the terminal panel's emulator display with the active
/// conversation after every message (see `@terminal.sync`) — a conversation
/// switch changes which workspace's terminals belong on screen without
/// producing any terminal message.
fn sync_terminal_panel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let (panel, cmd) = @terminal.sync(
    dispatch.map(msg => Terminal(msg)),
    model.terminal_panel,
    terminal_ctx(model),
  )
  ({ ..model, terminal_panel: panel }, cmd)
}

///|
/// Reconcile the dock strip, then the file subsystem, with the active
/// conversation after every message (see `@dock.sync` /
/// `@fileeditor.sync`). Order matters: the dock parks/restores the strip
/// first, so the file sync sees the fresh projection and re-roots its
/// document table from it. Centralizing it here keeps every
/// conversation-switching handler from having to re-root the panel itself.
fn sync_file_panel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let ctx = file_ctx(model)
  // Placement health is carried separately from identity, so a missing
  // checkout keeps this conversation's strip while both content subsystems
  // refuse host-backed work until Repair settles.
  let dock = @dock.sync(model.dock, ctx.owner)
  let model = { ..model, dock, }
  let (panel, cmd) = @fileeditor.sync(
    dispatch.map(msg => FileEditor(msg)),
    model.file_panel,
    file_ctx(model),
  )
  ({ ..model, file_panel: panel }, cmd)
}

///|
fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let previous = model
  let (cmd, model) = update_msg(dispatch, msg, model)
  // On the narrow layout the sidebar is a full-screen drawer, so any
  // navigation that lands somewhere else — switching or creating a
  // conversation, opening Skills or Settings — closes it; centralizing the
  // rule here keeps every navigation handler drawer-agnostic.
  let model = if model.narrow &&
    model.sidebar_open &&
    (
      model.active_session != previous.active_session ||
      model.focused != previous.focused ||
      model.screen != previous.screen
    ) {
    { ..model, sidebar_open: false }
  } else {
    model
  }
  // The quick pick belongs to the focused conversation captured when it
  // opened. Device/session switches can arrive through many messages (and
  // background pushes), so fence it once here rather than in every branch.
  let model = close_stale_quick_open(model)
  // The composer's git popover belongs to the checkout that was on screen,
  // and is fenced the same way and for the same reason. It cannot rely on its
  // click-away listener here: a switch by keyboard — Cmd+N, Quick Open — makes
  // no click at all, and neither does a checkout losing its repository under
  // it. Left standing the flag would spring the popover open on the
  // conversation arriving, once its branch probe answered, and meanwhile keep
  // `desired_browser_view` hiding the native browser with no chip on screen to
  // click — a blank pane with nothing to explain it.
  //
  // The second clause is the invariant rather than a list of paths: no chip,
  // no popover, however the branch came to be gone.
  let model = if model.git_details_open &&
    (
      model.active_session != previous.active_session ||
      model.focused != previous.focused ||
      !model.active().shows_git_chip()
    ) {
    { ..model, git_details_open: false }
  } else {
    model
  }
  let (model, panel_cmd) = sync_file_panel(dispatch, model)
  let (model, terminal_cmd) = sync_terminal_panel(dispatch, model)
  let (model, browser_cmd) = sync_browser_view(dispatch, model)
  (@cmd.batch([cmd, panel_cmd, terminal_cmd, browser_cmd]), model)
}
