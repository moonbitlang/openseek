///|
priv struct UserEditAction {
  sequence : Int32
  disabled : Bool
  sending : Bool
} derive(Eq)

///|
fn Input::user_edit_action(
  self : Input,
  item : @transcript.TranscriptItem,
) -> UserEditAction? {
  guard self.source is OpenSeek &&
    self.can_fork &&
    item.kind is User(..) &&
    item.sequence is Some(sequence) &&
    self.editable_users.contains(sequence) else {
    return None
  }
  Some({
    sequence,
    disabled: self.fork_busy || self.edit_busy,
    sending: self.fork_busy,
  })
}

///|
fn UserEditAction::render(
  self : UserEditAction,
  locale~ : @i18n.Locale,
  edit : @cmd.Cmd,
) -> @html.Html {
  let label = match locale {
    SimplifiedChinese => "编辑消息"
    TraditionalChinese => "編輯訊息"
    English => "Edit message"
    Japanese => "メッセージを編集"
    Spanish => "Editar mensaje"
  }
  @html.button(
    class="message-copy message-edit",
    type_="button",
    title=if self.disabled && !self.sending {
      match locale {
        SimplifiedChinese => "任务运行时无法编辑消息"
        TraditionalChinese => "任務執行時無法編輯訊息"
        English => "Messages cannot be edited while a task is running"
        Japanese =>
          "タスクの実行中はメッセージを編集できません"
        Spanish =>
          "No se pueden editar mensajes mientras hay una tarea en curso"
      }
    } else {
      label
    },
    disabled=self.disabled,
    attrs=@html.Attrs::build()
      .id("user-message-edit-trigger-\{self.sequence}")
      .aria_label(label),
    on_click=edit,
    @icons.icon(@icons.icon_edit),
  )
}

///|
priv enum MessageEditor {
  EditorClosed
  EditorDraft(@composer.Draft)
} derive(Eq)

///|
priv enum MessageEditorMsg {
  BeginEdit
  EditText(String)
  CancelEdit
  SendEdit
}

///|
fn Block::user_edit(self : Block) -> UserEditAction? {
  if self.content is Item(edit~, ..) {
    edit
  } else {
    None
  }
}

///|
/// Editing belongs to this keyed row. Typing never updates the root composer
/// or forks a conversation; only the explicit Send action leaves this row.
fn MessageEditor::update(
  self : MessageEditor,
  block : Block,
  msg : MessageEditorMsg,
  send : @cmd.Emit[(Int32, @composer.Draft)],
  unpin~ : @cmd.Cmd,
) -> (MessageEditor, @cmd.Cmd) {
  guard block.user_edit() is Some(action) &&
    (!action.disabled || (msg is CancelEdit && !action.sending)) else {
    return (self, @cmd.none)
  }
  match msg {
    BeginEdit => {
      guard block.content is Item(item~, ..) &&
        item.kind is User(content~) &&
        @composer.Draft::from_content(content) is Some(draft) else {
        return (self, @cmd.none)
      }
      (
        EditorDraft(draft),
        @cmd.batch([
          unpin,
          focus_message_edit("user-message-edit-\{action.sequence}"),
        ]),
      )
    }
    EditText(task) => {
      guard self is EditorDraft(draft) else { return (self, @cmd.none) }
      (EditorDraft({ ..draft, task, }), @cmd.none)
    }
    CancelEdit =>
      (
        EditorClosed,
        focus_message_edit("user-message-edit-trigger-\{action.sequence}"),
      )
    SendEdit => {
      guard self is EditorDraft(draft) && !draft.is_blank() else {
        return (self, @cmd.none)
      }
      // Retain the editor during the request and on failure. The owning
      // conversation disappears only after a successful, explicit send.
      (self, send((action.sequence, draft)))
    }
  }
}

///|
fn message_editor_state(
  block : @rabbita.Val[Block],
  actions : Actions,
  unpin~ : @cmd.Cmd,
) -> (@rabbita.Val[MessageEditor], @cmd.Emit[MessageEditorMsg]) {
  @rabbita.create_state_with_input(
    input=block,
    init=(_, _) => (EditorClosed, @cmd.none),
    update=(state, block, msg, _) => {
      state.update(block, msg, actions.edit_user, unpin~)
    },
  )
}

///|
fn focus_message_edit(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(id).to_option() is Some(element) &&
        element.to_html_element() is Some(element) {
        element.focus_with_options(prevent_scroll=true)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn MessageEditor::view(
  self : MessageEditor,
  block : Block,
  locale~ : @i18n.Locale,
  emit : @cmd.Emit[MessageEditorMsg],
) -> @html.Html? {
  guard self is EditorDraft(draft) && block.user_edit() is Some(action) else {
    return None
  }
  let (edit_label, cancel_label, send_label, sending_label) = match locale {
    SimplifiedChinese => ("编辑消息", "取消", "发送", "正在发送…")
    TraditionalChinese =>
      ("編輯訊息", "取消", "傳送", "正在傳送…")
    English => ("Edit message", "Cancel", "Send", "Sending…")
    Japanese =>
      ("メッセージを編集", "キャンセル", "送信", "送信中…")
    Spanish => ("Editar mensaje", "Cancelar", "Enviar", "Enviando…")
  }
  let attachments : Array[@html.Html] = []
  for image in draft.images {
    attachments.push(
      @html.div(class="composer-image", [
        @html.img(src=image.url, alt=image.name, title=image.name),
      ]),
    )
  }
  for mention in draft.mentions {
    attachments.push(
      @html.span(
        class="mention-chip",
        @html.span(class="mention-body", [
          @html.span(
            class="mention-glyph",
            @mention_context.glyph(mention.ref_),
          ),
          @html.span(
            class="mention-label",
            @mention_context.label(mention.ref_),
          ),
        ]),
      ),
    )
  }
  Some(
    @html.div(
      class="message-editor composer-surface",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        @html.textarea(
          id="user-message-edit-\{action.sequence}",
          class="message-edit-input composer-textarea",
          value=draft.task,
          rows=1,
          disabled=action.disabled,
          on_input=emit.map(text => EditText(text)),
          attrs=@html.Attrs::build()
            .aria_label(edit_label)
            .data_set("focus-target", "")
            .on_keydown(event => {
              if !event.is_composing() && event.key() == "Escape" {
                event.prevent_default()
                event.stop_propagation()
                emit(CancelEdit)
              } else if @composer.is_submit_shortcut(event) {
                event.prevent_default()
                event.stop_propagation()
                emit(SendEdit)
              } else {
                @cmd.none
              }
            }),
          @html.nothing,
        ),
        @html.div(class="message-edit-attachments", attachments),
        @html.div(class="message-edit-actions", [
          @html.button(
            type_="button",
            class="button secondary",
            disabled=action.sending,
            on_click=emit(CancelEdit),
            cancel_label,
          ),
          @html.button(
            type_="button",
            class="button primary",
            disabled=action.disabled || draft.is_blank(),
            on_click=emit(SendEdit),
            if action.sending {
              sending_label
            } else {
              send_label
            },
          ),
        ]),
      ],
    ),
  )
}
