///|
const ConversationTransferTarget = "conversation-transfer"

///|
fn Model::session_import_target(
  self : Model,
  channel : @interop.ChannelId,
  workspace : @common.Uri,
) -> @session_import.Target? {
  guard self.device_state(channel) is Some(dev) &&
    dev.projects.contains(workspace) &&
    !dev.is_chat_workspace(workspace) else {
    return None
  }
  Some({
    channel,
    connection_generation: dev.connection_generation,
    workspace: workspace.path,
    worktree_of: None,
  })
}

///|
#derive(Eq)
priv struct ConversationExportSource {
  channel : @interop.ChannelId
  payload : @protocol.SessionExportPayload
}

///|
#derive(Eq)
priv struct ConversationTransferInput {
  locale : @i18n.Locale
  visible : Bool
  narrow : Bool
  overview_available : Bool
  overview_open : Bool
  export_source : ConversationExportSource?
}

///|
fn Model::conversation_transfer_input(
  self : Model,
) -> ConversationTransferInput {
  let source = match self.chat_column() {
    Transcript(conversation=conv, ..) if self.screen is Chat &&
      !conv.messages.is_empty() =>
      Some(ConversationExportSource::{
        channel: conv.device,
        payload: {
          session: conv.session_id,
          workspace: conv.project().path,
          title: self.selected_conversation_title(),
          archived: conv.is_archived_read_only(),
        },
      })
    _ => None
  }
  {
    locale: self.locale,
    visible: self.screen is Chat,
    narrow: self.narrow,
    // Match the wide titlebar, which offers the overview only beside a
    // transcript it can describe.
    overview_available: self.screen is Chat &&
    self.chat_column() is Transcript(..),
    overview_open: self.overview_open,
    export_source: source,
  }
}

///|
fn conversation_transfer_button(
  locale : @i18n.Locale,
  narrow~ : Bool = false,
) -> @html.Html {
  @rui.popover_trigger(
    id=ConversationTransferTarget + ":actions-trigger",
    target_id=ConversationTransferTarget + ":actions-content",
    variant=Ghost,
    size=IconXs,
    class="panel-toggle",
    title=shell_text(locale, ConversationTransfer),
    attrs=@action_menu.button_attrs(
      ConversationTransferTarget,
      align_right=narrow,
    ).aria_label(shell_text(locale, ConversationTransfer)),
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
  let { locale, visible, export_source, .. } = input
  guard visible && target == ConversationTransferTarget else { return None }
  let entries : Array[@action_menu.Entry] = []
  entries.push(
    Action({
      label: shell_text(locale, ExportConversation),
      title: "",
      icon: Some(
        @html.span(
          id="conversation-export-action",
          class="icon",
          attrs=@html.Attrs::build().aria_hidden("true"),
          icon_chat_export(),
        ),
      ),
      enabled: export_source is Some(_),
      destructive: false,
      command: match export_source {
        Some({ channel, payload, }) =>
          open_conversation_transfer(emit(OpenExport(channel, payload)))
        None => @cmd.none
      },
    }),
  )
  if input.narrow && input.overview_available {
    entries.push(Separator)
    entries.push(
      Action({
        label: @conversation_overview.toggle_label(locale~, input.overview_open),
        title: "",
        icon: Some(
          @html.span(
            id="conversation-overview-action",
            class="icon",
            attrs=@html.Attrs::build().aria_hidden("true"),
            @icons.icon_preview(),
          ),
        ),
        enabled: true,
        destructive: false,
        command: open_conversation_transfer(emit(ToggleOverview)),
      }),
    )
  }
  Some({ label: shell_text(locale, ConversationTransfer), entries, })
}

///|
test "the narrow actions menu offers the overview only beside a transcript" {
  let base = test_model()
  guard base.active_conversation() is Some(conv) else {
    fail("conversation expected")
  }
  let target = {
    channel: conv.device,
    session: conv.session_id,
    workspace: conv.project(),
    record: LiveRecord,
  }
  let model = {
    ..base,
    narrow: true,
    selected_conversation: Some(HostSelection(target)),
  }
  assert_true(model.chat_column() is Transcript(..))
  assert_true(model.conversation_transfer_input().overview_available)
  let failed = {
    ..model,
    conversation_load_failure: Some({ target, message: "load failed", }),
  }
  assert_true(failed.active_conversation() is Some(_))
  assert_true(failed.chat_column() is LoadFailed(..))
  assert_false(failed.conversation_transfer_input().overview_available)
}
