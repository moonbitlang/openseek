// Shell half of unified Quick Open. The palette owns its query, rows, and
// Host search cache; this file owns the three things that are the shell's:
// which conversation and editor tabs it searches, whether it may open at all,
// and where an accepted row lands.

///|
/// Project the focused conversation and its open editor tabs into the palette.
/// The projection is read-only; the opaque palette state itself is stored once
/// in the application Model.
fn Model::quick_open_input(self : Model) -> @quick_open.Input {
  let active = self
    .active_checkout()
    .unwrap_or({
      owner: { channel: self.focused, session: "" },
      placement: None,
    })
  @quick_open.Input(
    owner=active.owner,
    root=active.placement.bind(placement => placement.checkout_root()),
    open_files=self.live_editor_files(),
    active_file=@dock.active_file(self.dock),
  )
}

///|
/// Answer the shortcut. Whether the palette may appear is a shell question:
/// another modal or a lost bridge already owns the screen, and the palette
/// would render over it with no way back. The topbar's app launcher is not an
/// exclusion but a casualty — the palette's backdrop covers it, so it closes.
fn open_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  provider : @quick_open.Provider,
) -> (@cmd.Cmd, Model) {
  guard model.project_picker is None &&
    model.archive_confirm is None &&
    model.archived_delete_confirm is None &&
    !(model.update_ux is ConfirmingRestart(..)) &&
    !(model.bridge_state() is BridgeLost(_)) &&
    model.active_checkout() is Some(_) else {
    return (@cmd.none, model)
  }
  let (cmd, quick_open) = model.quick_open.open(
    dispatch.map(msg => QuickOpen(msg)),
    model.quick_open_input(),
    provider,
  )
  (cmd, { ..model, quick_open, launcher: { ..model.launcher, open: false } })
}

///|
/// Route one palette message and, when it accepted a row, open that row in the
/// same root transition. Keeping both halves in one message is what lets panel
/// reconciliation see a single `opens_file_before_panel_reconciliation` pass
/// rather than a close followed by an open.
fn update_quick_open(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  msg : @quick_open.Msg,
) -> (@cmd.Cmd, Model) {
  let (cmd, quick_open, accepted) = model.quick_open.handle(
    dispatch.map(msg => QuickOpen(msg)),
    msg,
    model.quick_open_input(),
  )
  let model = { ..model, quick_open, }
  guard accepted is Some(target) else { return (cmd, model) }
  // Settings and catalog surfaces return to Chat because they have no editor.
  // Codex keeps its owning surface so the editor resolves the accepted row
  // against that task's checkout instead of the hidden OpenSeek conversation.
  let screen = if model.screen is Screen::Codex {
    Screen::Codex
  } else {
    Screen::Chat
  }
  let (open_cmd, model) = open_editor_at(
    dispatch,
    { ..model, screen, },
    target.path,
    target.range,
  )
  (@cmd.batch([cmd, open_cmd]), model)
}
