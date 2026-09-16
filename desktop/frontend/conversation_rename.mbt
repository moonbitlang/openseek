// Root-owned coordination for the title dialog. The shared action-menu
// component owns transient WebView menu state; only the asynchronous rename
// operation crosses into the application model.

///|
priv struct ConversationRename {
  id : @conversation.Id
  draft : String
  saving : Bool
  error : String?
} derive(Eq)

///|
fn Model::decorate_conversation_input(
  self : Model,
  input : @conversation.Input,
) -> @conversation.Input {
  let openseek = match input.id.source() {
    OpenSeekLive | OpenSeekArchived => true
    _ => false
  }
  let selected = match input.id.source() {
    OpenSeekLive | OpenSeekArchived =>
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
  { ..input, active: selected, loading, load_failed, }
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
        .get_element_by_id("conversation-rename-dialog")
        .to_option()
        is Some(element) &&
        element.to_html_dialog_element() is Some(dialog) {
        dialog.show_modal()
      }
      if @dom.document()
        .get_element_by_id("conversation-rename-input")
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
        OpenSeekLive => {
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
        CodexLive => {
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

///|
/// The dialog's controls in tab order. Disabled buttons drop out while a save
/// is pending, so Tab never lands on an inert control.
fn conversation_rename_focus_slots(
  dialog : @dom.Element,
) -> Array[@dom.Element] {
  let slots : Array[@dom.Element] = []
  for
    slot in dialog.query_selector_all(
      "button:not([disabled]), input:not([disabled])",
    ) {
    slots.push(slot)
  }
  slots
}

///|
/// Move focus by `delta` controls inside the rename dialog, wrapping at either
/// end. Native `dialog` navigation parks on the document between the first and
/// last control, so the dialog wraps Tab itself to keep focus on a control.
fn move_conversation_rename_focus(delta : Int) -> @cmd.Cmd {
  // Run after the pending draft render so the Save button's enabled state is
  // current: typing can enable it in the same flush as this keydown.
  @cmd.custom_cmd(
    _ => {
      guard @dom.document()
        .get_element_by_id("conversation-rename-dialog")
        .to_option()
        is Some(dialog) else {
        return
      }
      let slots = conversation_rename_focus_slots(dialog)
      let count = slots.length()
      guard count > 0 else { return }
      let active = @dom.document().get_active_element()
      // Without a known control, `Tab` starts at the first and `Shift+Tab` at the
      // last, so the wrapped destination still lands on a control.
      let mut index = if delta > 0 { count - 1 } else { 0 }
      if active is Some(active_element) {
        let mut position = 0
        for slot in slots {
          if slot.is_same_node(active_element.as_node()) {
            index = position
          }
          position += 1
        }
      }
      let next = (index + delta + count) % count
      if slots[next].to_html_element() is Some(element) {
        element.focus()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn close_conversation_rename() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    if @dom.document()
      .get_element_by_id("conversation-rename-dialog")
      .to_option()
      is Some(element) &&
      element.to_html_dialog_element() is Some(dialog) {
      dialog.close()
    }
  })
}

///|
fn conversation_rename_dialog(
  dispatch : @cmd.Emit[Msg],
  rename : ConversationRename,
) -> @html.Html {
  let valid = !rename.draft.trim().is_empty() && !rename.saving
  @html.dialog(
    id="conversation-rename-dialog",
    class="modal conversation-rename-dialog",
    on_cancel=dispatch(ConversationRenameCancelled(rename.id)),
    attrs=@html.Attrs::build()
      .aria_label("Rename conversation")
      .on_keydown(event => {
        event.stop_propagation()
        if event.is_composing() || event.key() != "Tab" {
          return @cmd.none
        }
        event.prevent_default()
        move_conversation_rename_focus(if event.shift_key() { -1 } else { 1 })
      }),
    [
      @html.div(class="modal-title", "Rename conversation"),
      @html.input(
        id="conversation-rename-input",
        input_type=Text,
        class="conversation-rename-input",
        value=rename.draft,
        on_input=value => {
          dispatch(ConversationRenameChanged(id=rename.id, value~))
        },
        attrs=@html.Attrs::build()
          .aria_label("Rename conversation")
          .readonly_(rename.saving)
          .on_keydown(event => {
            guard !event.is_composing() && event.key() == "Enter" else {
              return @cmd.none
            }
            event.prevent_default()
            if valid {
              dispatch(ConversationRenameSubmitted(rename.id))
            } else {
              @cmd.none
            }
          }),
      ),
      ..rename.error.map_or([], error => {
        [
          @html.div(
            class="conversation-rename-error",
            attrs=@html.Attrs::build().role("alert"),
            error,
          ),
        ]
      }),
      @html.div(class="modal-actions", [
        @html.button(
          class="button secondary",
          type_="button",
          disabled=rename.saving,
          on_click=dispatch(ConversationRenameCancelled(rename.id)),
          "Cancel",
        ),
        @html.button(
          class="button primary",
          type_="button",
          disabled=!valid,
          on_click=dispatch(ConversationRenameSubmitted(rename.id)),
          if rename.saving {
            "Saving…"
          } else {
            "Save"
          },
        ),
      ]),
    ],
  )
}
