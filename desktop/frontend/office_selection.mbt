///|
fn owns_office_selection(
  model : Model,
  owner : @interop.ConversationIdentity,
) -> Bool {
  if owner is @interop.Cloud(..) {
    return model.screen is Chat && model.cloud_identity() == Some(owner)
  }
  guard owner is @interop.Host(owner) else { return false }
  if model.screen is Codex {
    owner.channel == model.focused &&
    model.codex.active_id() == Some(owner.session)
  } else {
    model
    .active_conversation()
    .map(conv => {
      conv.device == owner.channel && conv.session_id == owner.session
    })
    .unwrap_or(false)
  }
}

///|
fn offer_office_selection(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationIdentity,
  selection : String,
) -> (@cmd.Cmd, Model) {
  guard owns_office_selection(model, owner) else { return (@cmd.none, model) }
  match model.file_panel.offer_office_selection(file_ctx(model), selection) {
    Ok(file_panel) => {
      let command = if owner is @interop.Host(_) {
        file_panel
        .pending_office_selection(file_ctx(model))
        .map_or(@cmd.none, preview => {
          @fileeditor.show_office_feedback(
            dispatch.map(message => FileEditor(message)),
            preview,
          )
        })
      } else {
        @cmd.none
      }
      (command, { ..model, file_panel, })
    }
    Err(message) => model.notify_error(dispatch, message)
  }
}

///|
/// Confirmation consumes only the currently displayed preview. A queued click
/// on an older preview or another file/session cannot attach a quotation.
fn confirm_office_selection(
  model : Model,
  candidate : @fileeditor.OfficeSelectionPreview,
  comment? : String,
) -> (@cmd.Cmd, Model) {
  let ctx = file_ctx(model)
  guard model.file_panel.pending_office_selection(ctx) is Some(preview) &&
    preview == candidate &&
    owns_office_selection(model, preview.owner) else {
    return (@cmd.none, model)
  }
  guard preview.owner is @interop.Host(_) else { return (@cmd.none, model) }
  let materialized = if comment is Some(text) && !text.trim().is_empty() {
    let value = @json.parse(preview.materialized) catch {
      _ => return (@cmd.none, model)
    }
    guard value is Object(fields) else { return (@cmd.none, model) }
    fields.set("comment", Json::string(text.trim().to_owned()))
    Json::object(fields).stringify()
  } else {
    preview.materialized
  }
  let (clear, file_panel) = model.file_panel.dismiss_office_selection(
    ctx, preview,
  )
  let model = { ..model, file_panel, }
  if model.screen is Codex {
    return (
      clear,
      { ..model, codex: model.codex.with_office_selection(Some(materialized)), },
    )
  }
  guard model.active_conversation() is Some(conv) else {
    return (@cmd.none, model)
  }
  let draft : @composer.Draft = {
    task: conv.task,
    mentions: conv.mentions,
    images: conv.images,
  }
  (
    clear,
    model.replace_conversation({
      ..conv,
      mentions: draft.with_office_selection(Some(materialized)).mentions,
    }),
  )
}
