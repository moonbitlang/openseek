///|
fn Model::ssh_dialog_open(self : Model) -> Bool {
  self.ssh_ui.editor_open || self.ssh_ui.details is Some(_)
}

///|
/// Keep the last rendered contents in fixed slots. Closing a dialog changes
/// its native open state, not its place in the shell or the text fading out.
fn shell_dialog_views(
  state : @rabbita.Val[Model],
  sources : @rabbita.Val[@html.Html],
  dispatch : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  let mut ssh = @html.nothing
  let mut project = @html.nothing
  let mut followup = @html.nothing
  let mut restart = @html.nothing
  let mut archive = @html.nothing
  let mut codex_archive = @html.nothing
  let mut permission = @html.nothing
  let mut github = @html.nothing
  state.view2(sources, (model, sources) => {
    if model.ssh_dialog_open() {
      ssh = ssh_modal(dispatch, model)
    }
    if model.project_picker is Some(picker) {
      project = @project_picker.view(
        locale=model.locale,
        dispatch.map(msg => ProjectPicker(msg)),
        picker,
        location?=if model.is_desktop {
          Some(ssh_locations(dispatch, model, sources))
        } else {
          None
        },
      )
    }
    if model.artifact_followup is Some(f) {
      followup = artifact_followup_dialog(dispatch, model, f)
    }
    if model.update_ux is ConfirmingRestart(version~) {
      restart = update_confirm_modal(locale=model.locale, dispatch, version)
    }
    if model.archive_confirm is Some(confirm) {
      archive = @composer.WorktreeArchiveDialog::{
        refusal: confirm.refusal,
        conversation_noun: "chat",
        cancel: dispatch(CancelArchiveDiscard),
        confirm: dispatch(ConfirmArchiveDiscard),
      }.render(locale=model.locale, id="chat-worktree-archive-dialog")
    }
    if model.github.checkout is Some({ phase: Confirming, .. } as checkout) {
      github = @github.checkout_dialog(
        locale=model.locale,
        checkout,
        dispatch.map(msg => Github(msg)),
      )
    }
    if model.screen is Codex {
      let emit = dispatch.map(msg => Codex(channel=model.focused, msg))
      if model.codex.confirming_full_access() {
        permission = @codex.permission_dialog(locale=model.locale, emit)
      }
      if model.codex.archive_dialog(locale=model.locale, emit) is Some(dialog) {
        codex_archive = dialog
      }
    }
    @html.div(style=["display:contents"], [
      ssh,
      project,
      followup,
      restart,
      api_setup_modal(dispatch, model),
      archive,
      codex_archive,
      permission,
      github,
    ])
  })
}

///|
/// A confirmed action, host update or navigation can finish a prompt just as
/// a dismissal can. Close the mounted element even on those non-button paths.
fn close_finished_shell_dialogs(before : Model, after : Model) -> @cmd.Cmd {
  let commands = []
  if before.ssh_dialog_open() && !after.ssh_dialog_open() {
    commands.push(@dialog.close("ssh-modal"))
  }
  if before.project_picker is Some(_) && after.project_picker is None {
    commands.push(@dialog.close("project-picker-dialog"))
  }
  if before.artifact_followup is Some(_) && after.artifact_followup is None {
    commands.push(@dialog.close("artifact-followup-dialog"))
  }
  if before.update_ux is ConfirmingRestart(_) &&
    !(after.update_ux is ConfirmingRestart(_)) {
    commands.push(@dialog.close("update-restart-dialog"))
  }
  if before.api_setup_open &&
    !before.cloud_selected() &&
    (!after.api_setup_open || after.cloud_selected()) {
    commands.push(@dialog.close("api-setup-dialog"))
  }
  if before.archive_confirm is Some(_) && after.archive_confirm is None {
    commands.push(@dialog.close("chat-worktree-archive-dialog"))
  }
  if before.github.checkout is Some({ phase: Confirming, .. }) &&
    !(after.github.checkout is Some({ phase: Confirming, .. })) {
    commands.push(@dialog.close("github-checkout-dialog"))
  }
  if before.screen is Codex {
    if before.codex.confirming_full_access() &&
      (!(after.screen is Codex) || !after.codex.confirming_full_access()) {
      commands.push(@dialog.close("codex-permission-dialog"))
    }
    if before.codex.confirming_archive() &&
      (!(after.screen is Codex) || !after.codex.confirming_archive()) {
      commands.push(@dialog.close("worktree-archive-dialog"))
    }
  }
  @cmd.batch(commands)
}
