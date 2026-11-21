///|
extern "js" fn browser_build_version() -> String =
  #| () => globalThis.__SEEKMOON_BROWSER_RELEASE__ ?? "unknown"

///|
fn Model::submit_feedback(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  identity : @composer.Identity,
  request : String,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard self.accepts_composer_action(identity) else { return (@cmd.none, self) }
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
  let command = @cmd.perform(
    result => {
      dispatch(
        ComposerCommandResult(
          @composer.FeedbackSettled(identity, request, result),
        ),
      )
    },
    () => {
      guard self.account is Some(credentials) else {
        return Err(@composer.SignInRequired)
      }
      match identity.owner {
        Host(key) => {
          guard key.channel is Local ||
            (key.channel is Remote("host") && self.is_local_console()) else {
            return Err(
              Diagnostic("Open this session on its host to submit feedback."),
            )
          }
          guard self.conversation_for_composer_action(identity) is Some(conv) else {
            return Err(Diagnostic("The conversation is unavailable."))
          }
          let title = self
            .activate(key.channel, key.session, conv.project())
            .selected_conversation_title()
          let reply = @interop.bridge_request(
            key.channel,
            @commands.session_feedback,
            {
              source: conv.export_source(title),
              idempotency_key: request,
              user_id: credentials.user.user_id,
              metadata,
            },
          ) catch {
            error => return Err(Diagnostic(@interop.bridge_error_text(error)))
          }
          match reply {
            Submitted(..) => Ok(())
            Failed(message~) => Err(Diagnostic(message))
            SignInRequired => Err(@composer.SignInRequired)
          }
        }
        Cloud(account~, session~) => {
          guard credentials.user.user_id == account else {
            return Err(
              Diagnostic("This conversation belongs to a different account."),
            )
          }
          guard self.cloud.draft_identity() != Some(identity.owner) else {
            return Err(
              Diagnostic("Open an existing Cloud session to submit feedback."),
            )
          }
          let _ = @cloud.submit_feedback(credentials.token, session, metadata) catch {
            @cloud.RequestError::RequestError(Unauthorized) =>
              return Err(@composer.SignInRequired)
            @cloud.RequestError::RequestError(failure) =>
              return Err(Diagnostic(failure.text(self.locale)))
            error => return Err(Diagnostic(error.to_string()))
          }
          Ok(())
        }
      }
    },
  )
  (command, self)
}

///|
/// Browser sign-in navigates this tab away. Keep only the explicitly retried
/// draft in this tab, and consume it once on return to its conversation.
extern "js" fn remember_feedback_login(record : String) -> Bool =
  #| record => {
  #|   try { sessionStorage.setItem("seekmoon.feedback.login", record); return true; }
  #|   catch { return false; }
  #| }

///|
extern "js" fn take_feedback_login() -> @js.Nullable[String] =
  #| () => {
  #|   try {
  #|     const value = sessionStorage.getItem("seekmoon.feedback.login");
  #|     sessionStorage.removeItem("seekmoon.feedback.login");
  #|     return value;
  #|   } catch { return null; }
  #| }

///|
fn feedback_login_draft() -> (String, String, String?)? {
  guard take_feedback_login().to_option() is Some(record) else { return None }
  let json = @json.parse(record) catch { _ => return None }
  guard json is { "owner": String(owner), "draft": String(draft), .. } else {
    return None
  }
  let held = if json is { "held": String(command), .. } {
    Some(command)
  } else {
    None
  }
  Some((owner, draft, held))
}
