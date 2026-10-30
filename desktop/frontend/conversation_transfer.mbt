///|
const ConversationTransferTarget = "conversation-transfer"

///|
priv struct ConversationTransferInput {
  locale : @i18n.Locale
  visible : Bool
  narrow : Bool
  source : (@interop.ChannelId, @protocol.SessionExportPayload)?
  cloud : @interop.ConversationIdentity?
  overview_available : Bool
  overview_open : Bool
} derive(Eq)

///|
fn Model::conversation_transfer_input(
  self : Model,
) -> ConversationTransferInput {
  let source = match self.chat_column() {
    Transcript(conversation=conv, ..) if self.screen is Chat &&
      !conv.messages.is_empty() =>
      Some(
        (
          conv.device,
          @protocol.SessionExportPayload::{
            session: conv.session_id,
            workspace: conv.project().path,
            title: self.selected_conversation_title(),
            archived: conv.is_archived_read_only(),
          },
        ),
      )
    _ => None
  }
  {
    locale: self.locale,
    visible: self.screen is Chat &&
    (
      !self.cloud_selected() ||
      (self.narrow && self.cloud_identity() is Some(_))
    ),
    narrow: self.narrow,
    source,
    cloud: self.cloud_identity(),
    overview_available: self.screen is Chat &&
    !self.cloud_selected() &&
    self.active_conversation() is Some(_),
    overview_open: self.overview_open,
  }
}

///|
fn conversation_transfer_button(
  locale : @i18n.Locale,
  narrow~ : Bool = false,
) -> @html.Html {
  let label = shell_text(
    locale,
    if narrow {
      ConversationActions
    } else {
      ConversationTransfer
    },
  )
  @html.button(
    class="panel-toggle",
    title=label,
    attrs=@action_menu.button_attrs(
      ConversationTransferTarget,
      align_right=narrow,
    ).aria_label(label),
    @icons.icon(@icons.icon_more),
  )
}

///|
/// The menu has dismissed before this runs. Focus its durable trigger so the
/// modal can restore focus there when it closes.
fn open_conversation_transfer(command : @cmd.Cmd) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if @dom.document()
      .get_element_by_id(ConversationTransferTarget + ":actions-trigger")
      .to_option()
      is Some(element) &&
      element.to_html_element() is Some(button) {
      button.focus()
    }
    scheduler.add(command)
  })
}

///|
fn conversation_transfer_menu(
  emit : @cmd.Emit[Msg],
  input : ConversationTransferInput,
  target : String,
) -> @action_menu.Definition? {
  let { locale, source, .. } = input
  guard input.visible && target == ConversationTransferTarget else {
    return None
  }
  let entries : Array[@action_menu.Entry] = []
  entries.push(
    Action({
      label: shell_text(locale, ExportConversation),
      title: "",
      icon: Some(icon(icon_chat_export)),
      enabled: input.cloud is Some(_) || source is Some(_),
      destructive: false,
      command: if input.cloud is Some(_) {
        open_conversation_transfer(emit(OpenCloudExport))
      } else {
        match source {
          Some((channel, source)) =>
            open_conversation_transfer(emit(OpenExport(channel, source)))
          None => @cmd.none
        }
      },
    }),
  )
  if input.cloud is None {
    entries.push(
      Action({
        label: shell_text(locale, ImportConversation),
        title: "",
        icon: Some(@icons.icon(@icons.icon_chat_import)),
        enabled: true,
        destructive: false,
        command: open_conversation_transfer(emit(OpenSessionImport)),
      }),
    )
  }
  if input.narrow && input.overview_available {
    entries.push(Separator)
    entries.push(
      Action({
        label: @conversation_overview.toggle_label(locale~, input.overview_open),
        title: "",
        icon: Some(icon(@icons.icon_preview)),
        enabled: true,
        destructive: false,
        command: open_conversation_transfer(emit(ToggleOverview)),
      }),
    )
  }
  Some({
    label: shell_text(
      locale,
      if input.narrow {
        ConversationActions
      } else {
        ConversationTransfer
      },
    ),
    entries,
  })
}
