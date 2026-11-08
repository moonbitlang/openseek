///|
#derive(Eq)
priv struct ArtifactFollowup {
  slot : String
  identity : @composer.Identity
  prompt : String
  title : String
  snapshot : @mention_context.ArtifactSnapshot?
}

///|
fn Model::artifact_followup_target(
  self : Model,
  slot : String,
) -> @composer.Identity? {
  guard self.artifact_quote_target(slot) is Some(ChatComposer(identity)) &&
    identity.owner is @interop.Host(_) else {
    return None
  }
  match self.composer_input().presentation.primary_action {
    @composer.Send(available=true)
    | @composer.Running(steer_available=true, submit=Steer | Queue, ..) =>
      Some(identity)
    _ => None
  }
}

///|
fn confirm_artifact_followup(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  let closed = { ..model, artifact_followup: None, }
  guard model.artifact_followup is Some(followup) &&
    model.artifact_followup_target(followup.slot) == Some(followup.identity) &&
    model.active_conversation() is Some(conversation) else {
    return (@cmd.none, closed)
  }
  let mentions : Array[@composer.Mention] = match followup.snapshot {
    Some(snapshot) =>
      [{ ref_: @mention_context.InteractiveAnswer(snapshot), range: None, }]
    None => []
  }
  // Send the confirmed message through the normal turn path. The composer
  // keeps its own draft, including while this submission awaits a receipt.
  let (command, submitted) = update_msg(
    dispatch,
    Send,
    closed.replace_conversation({
      ..conversation,
      task: followup.prompt,
      mentions,
      images: [],
    }),
  )
  guard submitted.active_conversation() is Some(next) else {
    return (command, submitted)
  }
  (
    command,
    submitted.replace_conversation({
      ..next,
      task: conversation.task,
      mentions: conversation.mentions,
      images: conversation.images,
      composer_draft_present: conversation.composer_draft_present,
    }),
  )
}

///|
fn artifact_followup_dialog(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> @html.Html {
  guard model.artifact_followup is Some(followup) else { return @html.nothing }
  let locale = model.locale
  let cancel = dispatch(ArtifactFollowupDismissed)
  let title = if followup.title.is_empty() {
    match locale {
      SimplifiedChinese => "发送追问？"
      TraditionalChinese => "傳送追問？"
      Japanese => "追加の質問を送信しますか？"
      Spanish => "¿Enviar pregunta de seguimiento?"
      English => "Send follow-up?"
    }
  } else {
    followup.title
  }
  let send = match locale {
    SimplifiedChinese => "发送"
    TraditionalChinese => "傳送"
    Japanese => "送信"
    Spanish => "Enviar"
    English => "Send"
  }
  @rui.dialog(
    id="artifact-followup-dialog",
    class="dialog-size-small",
    show_close=false,
    on_cancel=cancel,
    attrs=@html.Attrs::build().aria_labelledby("artifact-followup-title"),
    [
      @rui.dialog_header(@rui.dialog_title(id="artifact-followup-title", title)),
      @html.div(
        style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
        followup.prompt,
      ),
      match followup.snapshot {
        Some(snapshot) =>
          @html.details([
            @html.summary(snapshot.title),
            @html.pre(
              style=["white-space:pre-wrap", "overflow-wrap:anywhere"],
              snapshot.state.stringify(indent=2),
            ),
          ])
        None => @html.nothing
      },
      @rui.dialog_footer([
        @html.button(
          class="button secondary",
          on_click=cancel,
          shell_text(locale, CancelLabel),
        ),
        @html.button(
          class="button primary",
          on_click=dispatch(ArtifactFollowupConfirmed),
          disabled=model.artifact_followup_target(followup.slot) !=
            Some(followup.identity),
          send,
        ),
      ]),
    ],
  )
}
