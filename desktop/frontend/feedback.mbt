///|
extern "js" fn browser_build_version() -> String =
  #| () => globalThis.__SEEKMOON_BROWSER_RELEASE__ ?? "unknown"

///|
fn Model::submit_feedback(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  identity : @composer.Identity,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard self.accepts_composer_action(identity) && !self.export_dialog.is_open() else {
    return (@cmd.none, self)
  }
  let metadata : @protocol.FeedbackMetadata = {
    message,
    environment: {
      "app_version": Json(
        if self.is_desktop {
          self.app_version
        } else {
          browser_build_version()
        },
      ),
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
  let feedback : @export_dialog.Feedback = { identity, metadata, }
  let (show, export_dialog) = match identity.owner {
    Host(key) => {
      guard key.channel is Local ||
        (key.channel is Remote("host") && self.is_local_console()) else {
        return self.notify_error(
          dispatch, "Open this session on its host to submit feedback.",
        )
      }
      guard self.conversation_for_composer_action(identity) is Some(conv) else {
        return (@cmd.none, self)
      }
      self.export_dialog.open(
        conv.export_source(
          self
          .activate(key.channel, key.session, conv.project())
          .selected_conversation_title(),
        ),
        channel=key.channel,
        feedback~,
      )
    }
    Cloud(session~, ..) => {
      guard self.cloud.draft_identity() != Some(identity.owner) else {
        return self.notify_error(
          dispatch, "Open an existing Cloud session to submit feedback.",
        )
      }
      self.export_dialog.open_cloud(session~, feedback~)
    }
  }
  let (share, next) = update_msg(dispatch, ExportDialog(Share), {
    ..self,
    export_dialog,
  })
  (@cmd.batch([show, share]), next)
}
