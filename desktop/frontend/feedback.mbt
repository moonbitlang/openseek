///|
fn Model::submit_feedback(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  identity : @composer.Identity,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard self.accepts_composer_action(identity) else { return (@cmd.none, self) }
  let metadata : @protocol.FeedbackMetadata = {
    message,
    environment: {
      "app_version": Json(self.app_version),
      "client": Json(
        if self.is_desktop {
          "desktop"
        } else if self.is_android_app {
          "android"
        } else {
          "browser"
        },
      ),
      "platform": Json(app_shortcut_browser_platform()),
      "locale": Json(self.locale.tag()),
    },
  }
  if @interop.js_prop(
      @js.Value::cast_from(@dom.window().navigator()),
      "userAgent",
    )
    is Some(value) &&
    (@js.Cast::into(value) : String?) is Some(agent) {
    metadata.environment["user_agent"] = Json(agent)
  }
  let command = @cmd.perform(
    result => dispatch(FeedbackFinished(identity, result)),
    () => {
      guard self.account is Some(credentials) else {
        return Err("Sign in to submit feedback.")
      }
      match identity.owner {
        Host(key) => {
          guard key.channel is Local ||
            (key.channel is Remote("host") && self.is_local_console()) else {
            return Err("Open this session on its host to submit feedback.")
          }
          guard self.conversation_for_composer_action(identity) is Some(conv) else {
            return Err("The conversation is unavailable.")
          }
          let source : @protocol.SessionExportPayload = {
            session: key.session,
            workspace: conv.project().path,
            title: self
            .activate(key.channel, key.session, conv.project())
            .selected_conversation_title(),
            archived: conv.is_archived_read_only(),
          }
          @interop.bridge_request(key.channel, @commands.session_feedback, {
            user_id: credentials.user.user_id,
            source,
            metadata,
          }) catch {
            error => Err(@interop.bridge_error_text(error))
          }
        }
        Cloud(account~, session~) => {
          guard credentials.user.user_id == account else {
            return Err("Sign in to submit feedback.")
          }
          guard self.cloud.draft_identity() != Some(identity.owner) else {
            return Err("Open an existing Cloud session to submit feedback.")
          }
          Ok(@cloud.submit_feedback(credentials.token, session, metadata)) catch {
            error => Err(error.to_string())
          }
        }
      }
    },
  )
  (command, self)
}
