// Root-owned coordination for inline title editing. The shared WebView menu
// lives with each keyed row; only the asynchronous rename operation crosses
// into the application model.

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
  let rename = match self.conversation_rename {
    Some(rename) if rename.id == input.id =>
      Some(@conversation.RenameInput::{
        draft: rename.draft,
        saving: rename.saving,
      })
    _ => None
  }
  { ..input, rename, }
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
