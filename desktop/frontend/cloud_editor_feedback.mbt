///|
fn Model::editor_feedback_enabled(self : Model) -> Bool {
  match self.cloud_identity() {
    Some(@interop.Cloud(session~, ..)) => self.cloud.can_compose(session)
    _ => !self.cloud_selected()
  }
}

///|
/// Code feedback joins the component-owned Cloud draft, like Office feedback.
/// The resource authority binds the file to its account and session; a late
/// event from a different preview must never enter the visible composer.
fn Model::cloud_editor_feedback(
  self : Model,
  msg : Msg,
) -> @composer.QuoteReply? {
  let (resource, content, send, accepted) = match msg {
    FileEditor(
      @fileeditor.EditorCommentAdded(
        resource~,
        file~,
        range~,
        quote~,
        comment~,
        feedback_id~
      )
    ) if resource.resource().scheme == "openseek-cloud" => {
      let mention : @composer.Mention = {
        ref_: Annotation(
          file=file.0,
          start_line=range.start_line_number,
          end_line=range.end_line_number,
          quote~,
          comment~,
          side=WorkingRevision,
        ),
        range: Some(range),
      }
      (
        resource,
        @composer.Annotation(mention),
        false,
        @fileeditor.remove_editor_feedback(resource, feedback_id),
      )
    }
    FileEditor(@fileeditor.ApplyCloudFeedback(resource)) =>
      (resource, @composer.Text(quote=None, comment=""), true, @cmd.none)
    _ => return None
  }
  let ctx = file_ctx(self)
  guard self.cloud_identity() == Some(ctx.owner) &&
    ctx.cloud_files is Some(_) &&
    ctx.root() is Some(root) &&
    @resource.relative_to(resource.resource(), root) is Some(file) &&
    self.composer_input().quote_target() is Some(identity) else {
    return None
  }
  // The displayed file, rather than an arbitrary path in the event, owns it.
  if content is @composer.Annotation(mention) &&
    mention.ref_ is Annotation(file=path, ..) &&
    path != file.0 {
    return None
  }
  Some({ identity, content, images: [], send, accepted, declined: @cmd.none, })
}
