///|
/// The shared folder picker belongs to the composer that requested it. Root
/// ownership lets native browser views and global shortcuts respect its modal.
priv struct FolderReference {
  identity : @composer.Identity
  root : @common.Uri
  screen : Screen
} derive(Eq)

///|
fn Model::accepts_folder_reference(
  self : Model,
  reference : FolderReference,
) -> Bool {
  guard self.is_desktop &&
    reference.identity.owner.channel == @interop.Local &&
    self.screen == reference.screen else {
    return false
  }
  let input = match self.screen {
    Chat => {
      guard self.conversation_for_composer_action(reference.identity)
        is Some(conv) &&
        conv.device == self.focused &&
        conv.session_id == self.active_session else {
        return false
      }
      self.composer_input()
    }
    Codex => {
      guard self.codex.accepts_composer_identity(
        reference.identity,
        self.focused,
      ) else {
        return false
      }
      self.codex_composer_input()
    }
    _ => return false
  }
  input.root == Some(reference.root) &&
  !input.presentation.disabled &&
  input.goal.draft is None
}

///|
fn open_folder_reference(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  identity : @composer.Identity,
  root : @common.Uri,
) -> (@cmd.Cmd, Model) {
  let reference = { identity, root, screen: model.screen, }
  guard model.project_picker is None &&
    model.accepts_folder_reference(reference) else {
    return (@cmd.none, model)
  }
  let (close, quick_open) = model.quick_open.close()
  let (browse, picker) = @project_picker.State::open(
    identity.owner.channel,
    dispatch.map(msg => ProjectPicker(msg)),
  )
  (
    @cmd.batch([close, browse]),
    {
      ..model,
      quick_open,
      project_picker: Some(picker),
      folder_reference: Some(reference),
    },
  )
}

///|
fn Model::reconcile_folder_reference(self : Model) -> Model {
  guard self.folder_reference is Some(reference) else { return self }
  if self.project_picker is None || !self.accepts_folder_reference(reference) {
    { ..self, project_picker: None, folder_reference: None, }
  } else {
    self
  }
}

///|
fn Model::add_folder_reference(
  self : Model,
  reference : FolderReference,
  channel : @interop.ChannelId,
  path : String,
) -> Model {
  guard channel == reference.identity.owner.channel &&
    self.accepts_folder_reference(reference) else {
    return { ..self, project_picker: None, folder_reference: None, }
  }
  let self = { ..self, project_picker: None, folder_reference: None, }
  if reference.screen is Codex {
    return { ..self, codex: self.codex.with_path_reference(path), }
  }
  guard self.conversation_for_composer_action(reference.identity) is Some(conv) else {
    return self
  }
  let draft : @composer.Draft = {
    task: conv.task,
    mentions: conv.mentions,
    images: conv.images,
  }
  self.replace_conversation({
    ..conv,
    mentions: draft.with_mention({
      ref_: @mention_context.File(path~),
      range: None,
    }).mentions,
  })
}
