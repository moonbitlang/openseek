// Root-owned coordination for renaming a conversation in place. The sidebar
// row renders the title field; the draft and the asynchronous rename live in
// the application model.

///|
priv struct ConversationRename {
  id : @conversation.Id
  // The title when editing began: a draft that still matches it saves nothing.
  original : String
  draft : String
  saving : Bool
  // The pending save began as focus left the field, so its answer must not
  // pull focus back to the row.
  focus_left : Bool
} derive(Eq)

///|
fn Model::decorate_conversation_input(
  self : Model,
  input : @conversation.Input,
) -> @conversation.Input {
  let openseek = match input.id.source() {
    @conversation.OpenSeekLive | @conversation.OpenSeekArchived => true
    _ => false
  }
  let selected = match input.id.source() {
    @conversation.OpenSeekLive | @conversation.OpenSeekArchived =>
      // Remembered OpenSeek selection survives page switches, but its row
      // must stop highlighting while Codex or another page is on screen.
      self.screen is Chat &&
      self
      .conversation_selection()
      .map_or(false, selection => selection.matches_id(input.id))
    _ => input.active
  }
  let load_failed = selected &&
    self.conversation_load_failure is Some(failure) &&
    failure.target.matches_id(input.id)
  let loading = openseek &&
    selected &&
    !self.selected_conversation_loaded() &&
    !load_failed
  let rename = match self.conversation_rename {
    Some(rename) if rename.id == input.id =>
      Some(@conversation.Rename::{ draft: rename.draft, saving: rename.saving, })
    _ => None
  }
  { ..input, active: selected, loading, load_failed, rename, }
}

///|
/// Put the caret in the row's title field with the whole title selected.
fn focus_conversation_rename() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(@conversation.RenameFieldId)
        .to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "select",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Hand focus from the closing title field back to the row's title, for an
/// edit that ended with focus still in the field.
fn focus_conversation_title(id : @conversation.Id) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(@conversation.open_id(id))
        .to_option()
        is Some(title) &&
        title.to_html_element() is Some(title) {
        title.focus()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Apply one edit from the row's title field. Like the Finder's name field,
/// Enter and moving focus away both commit, and a blank or unchanged name
/// keeps the current title without a save. While a save is in flight the
/// field is locked and only the host's answer ends the edit.
fn Model::edit_conversation_rename(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  rename : ConversationRename,
  edit : @conversation.RenameEdit,
) -> (@cmd.Cmd, Model) {
  fn close(refocus : Bool) -> (@cmd.Cmd, Model) {
    (
      if refocus {
        focus_conversation_title(rename.id)
      } else {
        @cmd.none
      },
      { ..self, conversation_rename: None, },
    )
  }

  let title = rename.draft.trim()
  match edit {
    // The host's answer must not pull focus back once the user has moved on.
    Left if rename.saving =>
      (
        @cmd.none,
        { ..self, conversation_rename: Some({ ..rename, focus_left: true, }), },
      )
    _ if rename.saving => (@cmd.none, self)
    Typed(draft) =>
      (@cmd.none, { ..self, conversation_rename: Some({ ..rename, draft, }), })
    Cancelled => close(true)
    Submitted | Left if title.is_empty() || title == rename.original.trim() =>
      close(edit is Submitted)
    Submitted | Left => {
      let saving = { ..rename, saving: true, focus_left: edit is Left, }
      (
        rename_conversation(locale=self.locale, dispatch, saving),
        { ..self, conversation_rename: Some(saving), },
      )
    }
  }
}

///|
/// The host answered a pending save: close the field. Focus goes back to the
/// row's title unless the user has already moved on.
fn Model::finish_conversation_rename(
  self : Model,
  rename : ConversationRename,
) -> (@cmd.Cmd, Model) {
  (
    if rename.focus_left {
      @cmd.none
    } else {
      focus_conversation_title(rename.id)
    },
    { ..self, conversation_rename: None, },
  )
}

///|
fn rename_conversation(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  rename : ConversationRename,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      guard @interop.ChannelId::from_uri_authority(rename.id.channel())
        is Some(channel) else {
        scheduler.add(
          dispatch(
            ConversationRenameFailed(
              id=rename.id,
              message=match locale {
                SimplifiedChinese => "对话连接不可用"
                TraditionalChinese => "對話連線不可用"
                Japanese => "チャットの接続が利用できません"
                English => "Conversation channel is unavailable"
                Spanish => "El canal de la conversación no está disponible"
              },
            ),
          ),
        )
        return
      }
      let title = rename.draft.trim().to_owned()
      match rename.id.source() {
        @conversation.OpenSeekLive => {
          guard rename.id.root() is Some(workspace) else {
            scheduler.add(
              dispatch(
                ConversationRenameFailed(
                  id=rename.id,
                  message=match locale {
                    SimplifiedChinese => "对话工作区不可用"
                    TraditionalChinese => "對話工作區不可用"
                    Japanese =>
                      "チャットのワークスペースが利用できません"
                    English => "Conversation workspace is unavailable"
                    Spanish =>
                      "El espacio de trabajo de la conversación no está disponible"
                  },
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
        @conversation.CodexLive => {
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
                message=match locale {
                  SimplifiedChinese => "无法重命名此对话"
                  TraditionalChinese => "無法重新命名此對話"
                  Japanese =>
                    "このチャットの名前を変更できません"
                  English => "This conversation cannot be renamed"
                  Spanish =>
                    "No se puede cambiar el nombre de esta conversación"
                },
              ),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(ConversationRenameSucceeded(rename.id)))
    })
    |> ignore
  })
}
