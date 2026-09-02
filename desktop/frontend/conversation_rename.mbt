// Root-owned coordination for inline title editing. The shared action-menu
// component owns transient WebView menu state; only the asynchronous rename
// operation crosses into the application model.

///|
priv struct ConversationRename {
  id : @conversation.Id
  draft : String
  saving : Bool
} derive(Eq)

///|
fn Model::decorate_conversation_input(
  self : Model,
  input : @conversation.Input,
) -> @conversation.Input {
  let openseek = match input.id.source() {
    "openseek.live" | "openseek.archived" => true
    _ => false
  }
  let selected = match input.id.source() {
    "openseek.live" | "openseek.archived" =>
      match self.selected_conversation {
        Some(id) => id == input.id
        None => input.active
      }
    _ => input.active
  }
  let load_failed = selected &&
    self.conversation_load_failure is Some(failure) &&
    failure.target == input.id
  let loading = openseek &&
    selected &&
    !self.selected_conversation_loaded() &&
    !load_failed
  let rename = match self.conversation_rename {
    Some(rename) if rename.id == input.id =>
      Some(@conversation.RenameInput::{
        draft: rename.draft,
        saving: rename.saving,
      })
    _ => None
  }
  { ..input, active: selected, loading, load_failed, rename, }
}

///|
fn Model::cancel_unsubmitted_conversation_rename(self : Model) -> Model {
  match self.conversation_rename {
    Some(rename) if !rename.saving => { ..self, conversation_rename: None, }
    _ => self
  }
}

///|
fn focus_conversation_rename() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(@conversation.RenameInputId)
        .to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "select",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn rename_conversation(
  dispatch : @cmd.Emit[Msg],
  rename : ConversationRename,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      guard @interop.ChannelId::from_uri_authority(rename.id.channel())
        is Some(channel) else {
        scheduler.add(
          dispatch(
            ConversationRenameFailed(
              id=rename.id,
              message="Conversation channel is unavailable",
            ),
          ),
        )
        return
      }
      let title = rename.draft.trim().to_owned()
      match rename.id.source() {
        "openseek.live" => {
          guard rename.id.root() is Some(workspace) else {
            scheduler.add(
              dispatch(
                ConversationRenameFailed(
                  id=rename.id,
                  message="Conversation workspace is unavailable",
                ),
              ),
            )
            return
          }
          let _ : @protocol.EmptyReply = @interop.bridge_request(
            channel,
            @commands.session_rename,
            { session: rename.id.conversation(), workspace, title, },
          ) catch {
            error => {
              scheduler.add(
                dispatch(
                  ConversationRenameFailed(
                    id=rename.id,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
        }
        "codex.live" => {
          let _ : @protocol.EmptyReply = @interop.codex_request(
            channel,
            @commands.codex_thread_rename,
            { thread_id: rename.id.conversation(), name: title, },
          ) catch {
            error => {
              scheduler.add(
                dispatch(
                  ConversationRenameFailed(
                    id=rename.id,
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
        }
        _ => {
          scheduler.add(
            dispatch(
              ConversationRenameFailed(
                id=rename.id,
                message="This conversation cannot be renamed",
              ),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(ConversationRenameSucceeded(rename.id)))
    })
  })
}
