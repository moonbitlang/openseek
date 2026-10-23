///|
fn Model::editor_feedback_enabled(self : Model) -> Bool {
  match self.cloud_identity() {
    Some(@interop.Cloud(session~, ..)) => self.cloud.can_compose(session)
    _ => !self.cloud_selected()
  }
}

///|
/// Cloud owns no root-model draft. Validate its resource identity, then address
/// the existing composer entry; that component keeps its ordinary send rules.
fn Model::cloud_feedback_reply(
  self : Model,
  resource : @fileeditor.ModelUri,
  content : @composer.ReplyContent,
  send~ : Bool,
  accepted~ : @cmd.Cmd,
) -> @composer.QuoteReply? {
  let ctx = file_ctx(self)
  guard self.cloud_identity() == Some(ctx.owner) &&
    ctx.cloud_files is Some(_) &&
    ctx.root() is Some(root) &&
    @resource.relative_to(resource.resource(), root) is Some(file) &&
    self.composer_input().quote_target() is Some(identity) else {
    return None
  }
  if content is @composer.Annotation(mention) &&
    mention.ref_ is Annotation(file=path, ..) &&
    path != file.0 {
    return None
  }
  Some({ identity, content, images: [], send, accepted, declined: @cmd.none, })
}

///|
/// One route for editor feedback. Owners retain their existing draft writer
/// and send path: Local Send, Codex submission, or component-owned Cloud input.
fn update_editor_feedback(
  dispatch : @cmd.Emit[Msg],
  feedback : @fileeditor.Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match feedback {
    EditorCommentAdded(resource~, file~, range~, quote~, comment~, feedback_id~) => {
      let clear = @fileeditor.remove_editor_feedback(resource, feedback_id)
      if resource.resource().scheme != "openseek-cloud" && model.screen is Codex {
        return (
          clear,
          {
            ..model,
            codex: model.codex.with_editor_comment(
              file.0,
              range,
              comment,
              quote,
            ),
          },
        )
      }
      let mention = @composer.Mention::editor_annotation(
        file.0,
        range,
        quote,
        comment,
      )
      if resource.resource().scheme == "openseek-cloud" {
        let command = model
          .cloud_feedback_reply(
            resource,
            @composer.Annotation(mention),
            send=false,
            accepted=clear,
          )
          .map_or(@cmd.none, reply => dispatch(ComposerReply(reply)))
        return (command, model)
      }
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      let draft : @composer.Draft = {
        task: conv.task,
        images: conv.images,
        mentions: conv.mentions,
      }
      (
        clear,
        model.replace_conversation({
          ..conv,
          mentions: draft.with_mention(mention).mentions,
        }),
      )
    }
    ApplyEditorFeedback(resource) => {
      if resource.resource().scheme != "openseek-cloud" {
        return update_editor_feedback(dispatch, ApplyAllFeedback, model)
      }
      let command = model
        .cloud_feedback_reply(
          resource,
          @composer.Text(quote=None, comment=""),
          send=true,
          accepted=@cmd.none,
        )
        .map_or(@cmd.none, reply => dispatch(ComposerReply(reply)))
      (command, model)
    }
    ApplyAllFeedback =>
      match model.screen {
        Chat => update_msg(dispatch, Send, model)
        Codex => {
          let input = model.codex_composer_input()
          update_msg(
            dispatch,
            CodexComposerAction(
              @composer.DraftSubmitted(
                identity=input.identity,
                draft=input.draft,
              ),
            ),
            model,
          )
        }
        Skills | Schedules | Settings => (@cmd.none, model)
      }
    _ => (@cmd.none, model)
  }
}
