///|
fn can_stop(conv : Conversation) -> Bool {
  conv.run is Open(..)
}

///|
fn token_label(locale? : @i18n.Locale = English, tokens : Int) -> String {
  dynamic_text(locale, DTokens(@labels.compact_count(tokens).to_string()))
}

///|
/// Build one full-width settings select from the shared custom control. Menu
/// identity and open state stay in the root model, while the component owns
/// the DOM, keyboard behavior, and focus restoration used everywhere.
fn SelectMenu::setting_control(
  self : SelectMenu,
  dispatch : @cmd.Emit[Msg],
  model : Model,
  id~ : String,
  options~ : Array[@select_control.Option],
  selected~ : String,
  aria_label~ : String,
  change~ : @cmd.Emit[String],
  disabled? : Bool = false,
) -> @html.Html {
  @select_control.Control::{
    id,
    groups: [{ label: aria_label, options, }],
    selected,
    disabled,
    open: model.select_menu is Some(menu) && menu == self,
    toggle: dispatch(ToggleSelectMenu(self)),
    dismiss: dispatch(CloseSelectMenu),
    change,
    title: aria_label,
    aria_label,
    presentation: Setting,
  }.render()
}

///|
fn conversation_title(
  locale? : @i18n.Locale = English,
  conv : Conversation,
) -> String {
  // Titles follow the committed user transcript.
  for item in conv.messages {
    if item.kind is User(content=prompt) {
      // A prompt sent with chips titles by what was typed (or, chips alone,
      // by their labels) — never by the raw `<user_mentions>` envelope.
      let title = user_display_text(prompt.text()).trim().to_owned()
      if !title.is_empty() {
        return title
      }
    }
  }
  // The first submit makes the conversation a sidebar item immediately,
  // before the durable User event can make the round trip from the engine.
  // Use the exact recoverable submission during that interval so the new row
  // never flashes a generic product name.
  if conv.pending_prompt is Some(pending) {
    let title = user_display_text(
        @composer.Draft::{
          images: [],
          task: pending.draft,
          mentions: pending.mentions,
        }.prompt(),
      )
      .trim()
      .to_owned()
    if !title.is_empty() {
      return title
    }
  }
  let task = conv.task.trim().to_owned()
  if task.is_empty() {
    // The live draft text is component-local, so the root knows only that it
    // exists. Keep the row's pre-submit label truthful without mirroring the
    // text on every key; the durable User item supplies the real title.
    if conv.composer_draft_present {
      shell_text(locale, NewChatLabel)
    } else {
      "SeekMoon"
    }
  } else {
    task
  }
}

///|
/// One sidebar row's component input. A conversation with a turn in flight
/// gets a pulsing dot, so background work stays visible while another
/// conversation is on screen. A durable, idle row also carries a
/// hover-revealed archive button. `children` holds the sub-run transcripts
/// this conversation folded under it; the conversation component owns their
/// disclosure. `subrun` marks the row as one of those children — indented a
/// step. Nested children have no independent archive action because
/// archiving their parent moves the whole family; a legacy orphan that
/// surfaces as a root row does get the action so old split state remains
/// repairable.
fn session_component_input(
  model : Model,
  channel : @interop.ChannelId,
  session_id : String,
  label : String,
  archivable? : Bool = false,
  nested? : Bool = false,
  worktree? : String,
  subrun? : Bool = false,
  root? : String,
  children? : Array[@conversation.Input] = [],
) -> @conversation.Input {
  let active = model.screen is Chat &&
    channel == model.focused &&
    session_id == model.active_session
  let conv = model.find_conversation(channel, session_id)
  let running = conv is Some(conv) && conv.is_running()
  let unseen_outcome = match conv {
    Some(conv) if conv.unseen_finish =>
      Some(
        match conv.run {
          NoRun(ended=Some(RunFinished(Completed))) => @conversation.Completed
          NoRun(ended=Some(RunFinished(RunFailed) | RunFailed | RunErrored)) =>
            @conversation.Failed
          NoRun(ended=Some(RunFinished(Aborted))) => @conversation.Stopped
          _ => @conversation.Ended
        },
      )
    _ => None
  }
  let run_mark = @conversation.RunMark::for_task(
    running~,
    needs_input=conv is Some(conv) &&
      conv.pending_approval is Some({ answered: false, .. }),
    unseen_outcome~,
  )
  // The row's own tooltip carries the worktree name, joined from the
  // registry (or the local binding while the first turn is still on its way
  // to the store).
  let title = if worktree is Some(name) {
    dynamic_text(
      model.locale,
      DWorktreeArchiveHint(session_id.to_string(), name.to_string()),
    )
  } else {
    session_id
  }
  model.decorate_conversation_input({
    // The store placement rides in `root`: session ids may repeat across
    // project stores, and without it two same-id rows would collide on one
    // key in the sidebar's keyed container.
    id: @conversation.Id(
      source=@conversation.OpenSeekLive,
      channel=channel.uri_authority(),
      conversation=session_id,
      root?,
    ),
    title,
    label,
    nested,
    subrun,
    active,
    loading: false,
    load_failed: false,
    running,
    openable: true,
    worktree,
    // Keep the capability in the row input while a run is active: Proton
    // presents Archive disabled, while the browser fallback hides it.
    run_mark,
    trailing: if archivable {
      [@conversation.Archive(title=shell_text(model.locale, ArchiveHint))]
    } else {
      []
    },
    children,
  })
}

///|
/// A sidebar entry's display label: its engine-reported title, or the session
/// id when the durable record has no user-authored title yet.
fn session_item_label(item : @transcript.SessionListItem) -> String {
  if item.title is Some(title) && !title.is_blank() {
    title
  } else {
    item.id
  }
}

///|
/// One group's conversation inputs: the app-run-only (unlisted) conversations
/// newest first, then the store's durable sessions in list order — the same
/// ordering the flat sidebar always had, applied per group. A fresh chat on
/// screen is represented by its active project instead of a redundant "New
/// chat" child row. An off-screen unsent draft still gets a row so it remains
/// recoverable, and a submitted conversation appears immediately while its
/// first turn is starting.
fn Model::push_group_component_inputs(
  self : Model,
  rows : Array[(RowStamp, @conversation.Input)],
  dev : DeviceState,
  workspace : @common.Uri,
  listed~ : (String) -> Bool,
  archived~ : (String) -> Bool,
  standalone? : Bool = false,
) -> Unit {
  let composing = self.composing_new_chat()
  // Every row in this group shares the group's store placement; it becomes
  // the `root` half of each conversation's component id.
  let root = workspace.path
  let items : Array[@transcript.SessionListItem] = []
  let local_worktrees : Map[String, String?] = Map([])
  for conv in self.conversations.rev_iter() {
    if conv.device != dev.channel ||
      conv.project() != workspace ||
      listed(conv.session_id) ||
      archived(conv.session_id) {
      continue
    }
    let worth_keeping = conv.worth_keeping()
    let on_screen = self.screen is Chat &&
      conv.device == self.focused &&
      conv.session_id == self.active_session
    // The new-chat page belongs to the highlighted project until it becomes
    // real work. Do not manufacture a selected child row merely because its
    // client-local session id already exists.
    if composing && on_screen && !standalone {
      continue
    }
    if !worth_keeping && !standalone {
      continue
    }
    // A fresh worktree conversation knows its binding locally; once the
    // first turn is durable the registry mapping takes over.
    let worktree = if conv.worktree_name() is Some(name) {
      Some(name)
    } else {
      worktree_name_for(dev, workspace, conv.session_id)
    }
    local_worktrees[conv.session_id] = worktree
    items.push({
      id: conv.session_id,
      title: Some(
        if standalone &&
          !conv.has_begun() &&
          conv.task.is_empty() &&
          conv.pending_prompt is None {
          shell_text(self.locale, NewChatLabel)
        } else {
          conversation_title(locale=self.locale, conv)
        },
      ),
      workspace,
      workspace_name: workspace.path,
      updated_at_ms: None,
    })
  }
  // A child opened from Workflows may not be in the host inventory yet.
  // Fold live and listed sessions together so either source can own a parent
  // or child without creating a second top-level conversation.
  for item in dev.sessions {
    if item.workspace == workspace && !archived(item.id) {
      items.push(item)
    }
  }
  // Sub-run transcripts fold under the conversation that launched them: they
  // are that turn's evidence, not conversations of their own. They ride the
  // parent's component input, so their disclosure state lives in the
  // conversation component. A label follows the live conversation while it
  // is the one on screen (its title settles at the first send), and
  // otherwise comes from the host's listing.
  for tree in @transcript.session_tree(items) {
    let parent_label = if tree.item.title is Some(title) && !title.is_blank() {
      title
    } else if self.find_conversation(dev.channel, tree.item.id) is Some(conv) &&
      dev.channel == self.focused &&
      tree.item.id == self.active_session {
      conversation_title(locale=self.locale, conv)
    } else {
      session_item_label(tree.item)
    }
    let children : Array[@conversation.Input] = []
    for child in tree.children {
      // The ordinal leads the row: it is what the transcript's sub-run
      // lines name, and it orders runs whose questions read alike. A child
      // that never got a question keeps the ordinal alone — its id would
      // only repeat the parent's.
      let question = match child.title {
        Some(title) if !title.is_blank() => Some(title)
        _ => None
      }
      let child_label = match (@transcript.subrun_label(child.id), question) {
        (Some(ordinal), Some(title)) => "\{ordinal} · \{title}"
        (Some(ordinal), None) => ordinal
        (None, _) => session_item_label(child)
      }
      children.push(
        session_component_input(
          self,
          dev.channel,
          child.id,
          child_label,
          nested=!standalone,
          subrun=true,
          root~,
        ),
      )
    }
    let stamp = if local_worktrees.contains(tree.item.id) {
      ComposingNow
    } else {
      match tree.item.updated_at_ms {
        Some(ms) => ActiveAt(ms)
        None => Unstamped
      }
    }
    rows.push(
      (
        stamp,
        session_component_input(
          self,
          dev.channel,
          tree.item.id,
          parent_label,
          // Ordinary children are folded below a live parent and receive no
          // action. A child-shaped root is legacy split state (or belongs to a
          // parent in another store), so it remains independently archivable;
          // once beside its archived parent, family restore picks it up.
          archivable=!local_worktrees.contains(tree.item.id),
          nested=!standalone,
          worktree?=match local_worktrees.get(tree.item.id) {
            Some(worktree) => worktree
            None => worktree_name_for(dev, workspace, tree.item.id)
          },
          root~,
          children~,
        ),
      ),
    )
  }
}

///|
/// When one project row holds conversations from two sources, recency is the
/// only shared ordering. This session's still-composing rows lead (nothing
/// durable stamps them yet), stamped rows follow newest-first, and rows whose
/// stamp could not be read keep the tail — the same place the engine's own
/// listing puts them.
priv enum RowStamp {
  ComposingNow
  ActiveAt(Double)
  Unstamped
}

///|
fn RowStamp::rank(self : RowStamp) -> Int {
  match self {
    ComposingNow => 0
    ActiveAt(_) => 1
    Unstamped => 2
  }
}

///|
/// Order one project's rows for display. Equal ranks and equal stamps keep
/// the assembly order — OpenSeek's composing rows, its durable listing, then
/// Codex's — so the sort is stable across both sources.
fn ordered_by_recency(
  rows : Array[(RowStamp, @conversation.Input)],
) -> Array[@conversation.Input] {
  let keyed = rows.mapi((index, row) => (index, row.0, row.1))
  keyed.sort_by((a, b) => {
    let (a_index, a_stamp, _) = a
    let (b_index, b_stamp, _) = b
    if a_stamp.rank() != b_stamp.rank() {
      a_stamp.rank().compare(b_stamp.rank())
    } else if a_stamp is ActiveAt(a_ms) &&
      b_stamp is ActiveAt(b_ms) &&
      a_ms != b_ms {
      b_ms.compare(a_ms)
    } else {
      a_index.compare(b_index)
    }
  })
  keyed.map(row => row.2)
}

///|
/// One device's sections: each attached project as a folder row with its
/// conversations nested beneath it, and the archived group at the tail. Rows
/// stay clickable while runs are active — switching between conversations
/// mid-run is the point of keeping them concurrent.
fn Model::sidebar_component_sections(
  self : Model,
  dev : DeviceState,
) -> Array[@section.Input] {
  let listed = (id : String) => dev.sessions.any(item => item.id == id)
  // An archived record has moved out of the live store, so the live list
  // normally cannot contain it; the filter covers the moment between the
  // archive reply and the list refetch that follows it.
  let archived = (id : String) => dev.archived.any(item => item.id == id)
  let channel = dev.channel.uri_authority()
  let chat_selected = self.screen is Chat && dev.channel == self.focused
  // The activation identity handed to sections and projects: which
  // conversation is on screen. A branch folded during one activation stays
  // folded until a different one lands in it.
  let activation = (holds_active : Bool) => {
    if chat_selected && holds_active {
      Some(self.active_session)
    } else {
      None
    }
  }
  let sections : Array[@section.Input] = []
  // Codex conversations share the Projects section instead of owning one:
  // its threads nest under the same project rows, grouped by the registered
  // root. Codex state mirrors the focused device only, so other devices'
  // rows are OpenSeek's alone.
  let codex_context : @codex.SidebarContext? = if dev.channel == self.focused {
    let registered_projects = dev.projects.filter_map(project => {
      @resource.path_for(project, dev.channel)
    })
    Some({
      channel: dev.channel,
      selected: self.screen is Codex,
      registered_projects,
    })
  } else {
    None
  }
  let projects : Array[@section.Entry] = []
  let chat_rows : Array[(RowStamp, @conversation.Input)] = []
  let mut chats_activation : String? = None
  for path in dev.projects {
    let standalone = dev.is_chat_workspace(path)
    let stamped : Array[(RowStamp, @conversation.Input)] = []
    self.push_group_component_inputs(
      stamped,
      dev,
      path,
      listed~,
      archived~,
      standalone~,
    )
    let mut codex_activation : String? = None
    if codex_context is Some(context) &&
      @resource.path_for(path, dev.channel) is Some(root) {
      // The selected Codex draft is the project's new-chat page, not a child
      // conversation yet. `project_draft` returns only an off-screen draft
      // that needs a recovery row.
      if self.codex.project_draft(
          locale=self.locale,
          context,
          root,
          include_selected=standalone,
        )
        is Some(draft) {
        stamped.push((ComposingNow, draft))
      }
      for
        row in self.codex.project_conversations(
          locale=self.locale,
          context,
          root,
        ) {
        let stamp = match row.updated_at_ms {
          Some(ms) => ActiveAt(ms)
          None => Unstamped
        }
        stamped.push((stamp, self.decorate_conversation_input(row.input)))
      }
      codex_activation = self.codex.project_activation(context, root)
    }
    let openseek_activation = activation(
      dev.active_project is Some(project) && project == path,
    )
    if standalone {
      for (stamp, row) in stamped {
        chat_rows.push((stamp, { ..row, nested: false, }))
      }
      if openseek_activation is Some(_) {
        chats_activation = openseek_activation
      }
      if codex_activation is Some(_) {
        chats_activation = codex_activation
      }
      continue
    }
    let conversations = ordered_by_recency(stamped)
    projects.push(
      @section.Project({
        id: @project.Id(source="openseek.projects", channel~, root=path.path),
        title: path.path,
        label: @resource.label(path),
        // The Chat and Codex screens are exclusive, so at most one side
        // claims the row's activation.
        activation: if openseek_activation is Some(_) {
          openseek_activation
        } else {
          codex_activation
        },
        can_start: true,
        managed: true,
        conversations,
      }),
    )
  }
  if codex_context is Some(context) {
    // Codex threads in unregistered roots keep top-level rows at the end of
    // the section, as they did in the retired Codex section.
    for entry in self.codex.loose_entries(locale=self.locale, context) {
      projects.push(
        match entry {
          @section.Conversation(input) =>
            @section.Conversation(self.decorate_conversation_input(input))
          other => other
        },
      )
    }
  }
  let openseek_section_activation = activation(
    dev.active_project is Some(project) && !dev.is_chat_workspace(project),
  )
  sections.push({
    id: @section.Id(source="openseek.chats", channel~),
    label: @sidebar_messages.text(self.locale, Chats),
    initially_collapsed: false,
    preview_limit: Some(3),
    activation: chats_activation,
    action: Some({
      title: if self.chat_creation_pending() {
        @sidebar_messages.text(self.locale, CreatingChat)
      } else {
        @sidebar_messages.text(self.locale, NewChat)
      },
      disabled: self.chat_creation_pending() ||
      self.pending_project_adoption is Some(_) ||
      dev.bridge != Connected,
    }),
    entries: ordered_by_recency(chat_rows).map(row => @section.Conversation(row)),
  })
  sections.push({
    id: @section.Id(source="openseek.projects", channel~),
    label: @sidebar_messages.text(self.locale, Projects),
    initially_collapsed: false,
    preview_limit: None,
    activation: if openseek_section_activation is Some(_) {
      openseek_section_activation
    } else if codex_context is Some(context) &&
      context.selected &&
      chats_activation is None {
      self.codex.active_id()
    } else {
      None
    },
    action: Some({
      title: @sidebar_messages.text(self.locale, AddProject),
      disabled: false,
    }),
    entries: projects,
  })
  // Archived conversations fold behind a collapsed section at the end of the
  // list. Their records live in the store's `archived` twin, so they come
  // from the host's archived reply, not the live list; each row carries a
  // restore control and the permanent delete instead of the archive one.
  // A parent and its archived sub-run records are one conversation: restore
  // or delete the root row and the host moves the complete family together.
  // An old orphan child still owns a row and can therefore be restored.
  let archived_entries : Array[@section.Entry] = []
  for tree in @transcript.session_tree(dev.archived) {
    let item = tree.item
    let active = self.focused == dev.channel &&
      self.active_session == item.id &&
      self.find_conversation(dev.channel, item.id) is Some(conv) &&
      conv.is_archived_read_only()
    archived_entries.push(
      @section.Conversation(
        self.decorate_conversation_input({
          id: @conversation.Id(
            source=@conversation.OpenSeekArchived,
            channel~,
            conversation=item.id,
            root=item.workspace.path,
          ),
          title: item.id,
          label: session_item_label(item),
          nested: false,
          subrun: false,
          active,
          loading: false,
          load_failed: false,
          running: false,
          openable: true,
          worktree: None,
          run_mark: @conversation.NoRunMark,
          trailing: [
            @conversation.Restore(title=shell_text(self.locale, RestoreHint)),
            @conversation.Delete(
              title=shell_text(self.locale, DeleteArchivedHint),
            ),
          ],
          children: [],
        }),
      ),
    )
  }
  if dev.channel == self.focused {
    for
      entry in self.codex.archived_sidebar_entries(
        locale=self.locale,
        dev.channel,
      ) {
      archived_entries.push(
        match entry {
          @section.Conversation(input) =>
            @section.Conversation(self.decorate_conversation_input(input))
          other => other
        },
      )
    }
  }
  sections.push({
    id: @section.Id(source="archived", channel~),
    label: @sidebar_messages.text(
      self.locale,
      ArchivedChats(archived_entries.length()),
    ),
    initially_collapsed: true,
    preview_limit: None,
    // Opening an archived transcript never force-reveals the section; its
    // fold stays purely user-controlled, as before.
    activation: None,
    action: None,
    entries: archived_entries,
  })
  sections
}

///|
/// The sole root-to-sidebar projection. This method is data-only and is
/// mapped into `Val[Input]` once in `boot`; the sidebar package owns all DOM
/// composition and child state after that boundary. Both the desktop window
/// and browser console project only the sections for one selected device
/// channel. In the browser, `?device=` makes that selection a page/tab
/// boundary: another device belongs in another page, not in this scroll box.
/// Roster loading and failure states only replace the sections when that
/// channel has no connected device state; an existing device remains usable
/// while a refresh is in flight.
fn Model::sidebar_component_input(self : Model) -> @sidebar.Input {
  let notices : Array[String] = []
  let sections = match self.focused_device() {
    Some(dev) => {
      if dev.chat_root is Some(Err(message)) {
        notices.push(
          dynamic_text(self.locale, DStorageUnavailable(message.to_string())),
        )
      }
      self.sidebar_component_sections(dev)
    }
    None => {
      match self.console.roster_sync {
        RosterLoading => notices.push(shell_text(self.locale, LoadingDevice))
        RosterFailed(message) => notices.push(message)
        RosterReady =>
          if self.console.roster.is_empty() {
            notices.push(shell_text(self.locale, NoDevices))
          } else {
            notices.push(shell_text(self.locale, NoOnlineDevice))
          }
      }
      []
    }
  }
  // The footer's update button tracks the automatic download so its progress
  // stays visible from any screen, and asks for the restart once the release
  // is staged.
  let update_label : String? = match self.update_ux {
    UpdateAvailable(installable=true, ..) =>
      Some(shell_text(self.locale, UpdateLabel))
    DownloadingUpdate(progress~, ..) =>
      Some(progress.sidebar_label(locale=self.locale))
    UpdateReady(..) | ConfirmingRestart(..) =>
      Some(shell_text(self.locale, RestartToUpdateLabel))
    RestartingForUpdate(..) => Some(shell_text(self.locale, RestartingLabel))
    _ => None
  }
  // The browser console's account row: who is signed in, a roster refresh,
  // and the sign-out — with the last account-level failure inline beneath
  // it. The desktop window's session is its own host's, with nothing to sign
  // out of, so it shows no account.
  let account : @sidebar.Account? = match self.console.auth {
    AuthSignedIn(login~, avatar~) if !self.is_desktop =>
      Some({
        login,
        avatar,
        busy: self.console.busy,
        notice: self.console.notice,
      })
    _ => None
  }
  {
    notices,
    locale: self.locale,
    sections,
    update_label,
    update_enabled: self.update_ux is (UpdateAvailable(..) | UpdateReady(..)),
    schedules_active: self.screen is Schedules,
    skills_active: self.screen is Skills,
    settings_active: self.screen is Settings,
    account,
  }
}

///|
/// The one-line display form of a submitted prompt (steer bubbles, sidebar
/// titles): a submission that carried chips is shown as its typed text plus
/// `$name`/`#name` markers rather than the raw `<user_mentions>` envelope the
/// engine receives.
fn user_display_text(text : String) -> String {
  guard @mention_context.parse(text) is Some(parsed) else { return text }
  parsed.display_text()
}

///|
/// The archived conversation's only bottom action. Keeping it separate from
/// the live composer means there is no textarea, model selector, goal editor,
/// Send, or Stop control for an archived durable record.
fn Conversation::archived_read_only_view(
  locale? : @i18n.Locale = English,
  self : Conversation,
  dispatch : @cmd.Emit[Msg],
) -> @html.Html {
  @html.div(class="composer archived-read-only", [
    @html.div(class="archived-read-only-bar", [
      @html.span(
        class="archived-read-only-text",
        shell_text(locale, ArchivedReadOnly),
      ),
      @html.button(
        class="archived-read-only-restore",
        type_="button",
        title=shell_text(locale, RestoreBeforeContinue),
        on_click=dispatch(UnarchiveSession(self.device, self.session_id)),
        shell_text(locale, RestoreLabel),
      ),
    ]),
  ])
}

///|
/// The Codex group's rows: connection and account state, and the account
/// actions themselves. Sign-in and sign-out live here rather than on the
/// Codex conversation topbar — Settings is where the desktop manages every
/// account it holds.
fn codex_account_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let codex = model.codex
  let channel = model.focused
  let rows : Array[@html.Html] = [
    @settings.row(
      @settings.text(model.locale, Status),
      [],
      desc="\{codex.connection_label(locale=model.locale)} · \{codex.account_label(locale=model.locale)}",
    ),
  ]
  if codex.signed_in() {
    rows.push(
      @settings.row(
        @settings.text(model.locale, Account),
        [
          @html.button(
            class="button secondary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::logout())),
            @settings.text(model.locale, SignOut),
          ),
        ],
        desc=@settings.text(model.locale, SignOutDescription),
      ),
    )
  } else if codex.sign_in_required() {
    rows.push(
      @settings.row(
        @settings.text(model.locale, SignIn),
        [
          @html.button(
            class="button primary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::login())),
            @settings.text(model.locale, SignInChatGPT),
          ),
        ],
        desc=@settings.text(model.locale, CodexAccountDescription),
      ),
    )
  }
  if codex.pending_auth_url() is Some(url) {
    rows.push(
      @settings.row(
        @settings.text(model.locale, SignInPage),
        [
          // The shared external-link listener keeps the desktop webview in
          // place and hands this URL to the system browser.
          @html.a(
            class="button secondary setting-link",
            href=url,
            target=Blank,
            rel="noopener noreferrer",
            [
              icon(icon_link_external),
              @html.span(@settings.text(model.locale, Open)),
            ],
          ),
          @html.button(
            class="button secondary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::cancel_login())),
            @settings.text(model.locale, CancelSignIn),
          ),
        ],
        desc=@settings.text(model.locale, FinishSignIn),
      ),
    )
  }
  rows.push(
    @settings.row(
      @settings.text(model.locale, Configuration),
      [
        @html.button(
          class="button secondary",
          on_click=dispatch(OpenCodexConfig),
          @settings.text(model.locale, OpenConfig),
        ),
      ],
      desc=@settings.text(model.locale, ConfigDescription),
    ),
  )
  rows
}

///|
/// The Remote access group's rows: sign-in state against the SeekMoon
/// relay. The relay no longer depends on the chat provider — only the
/// hosted chat proxy was retired — so it is always available.
fn remote_access_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  // A development build serves this very frontend on loopback for the
  // system browser, so the console can be worked on against this host with
  // no relay in between. Open carries the launch token that grants the
  // browser its session.
  if model.console_url is Some(url) {
    rows.push(
      @settings.row(
        "Local console",
        [
          @html.a(
            class="button secondary setting-link",
            href=url,
            target=Blank,
            rel="noopener noreferrer",
            [icon(icon_link_external), @html.span("Open")],
          ),
        ],
        desc="Development build — open the console this host serves in a browser on this machine.",
      ),
    )
  }
  match model.remote_access {
    None =>
      rows.push(
        @settings.row(
          @settings.text(model.locale, RemoteControl),
          [],
          desc=@settings.text(model.locale, CheckingSignIn),
        ),
      )
    Some(status) =>
      if status.managed_by_env {
        rows.push(
          @settings.row(
            @settings.text(model.locale, RemoteControl),
            [],
            desc=@settings.text(model.locale, EnvironmentRelay),
          ),
        )
      } else if status.user_login is Some(login) {
        let state = if status.connected {
          @settings.text(model.locale, OnlineRelay)
        } else {
          @settings.text(model.locale, ConnectingRelay)
        }
        rows.push(
          @settings.row(
            @settings.text(model.locale, SignedInAs),
            [
              @html.button(
                class="button secondary",
                on_click=dispatch(RemoteDisconnectClicked),
                @settings.text(model.locale, Disconnect),
              ),
            ],
            desc="@\{login} — \{state}",
          ),
        )
        if status.device_url is Some(url) {
          let name = status.device_name.unwrap_or(
            @settings.text(model.locale, ThisMachine),
          )
          rows.push(
            @settings.row(
              @settings.text(model.locale, DevicePage),
              [
                // The shared external-link listener keeps the desktop webview
                // in place and hands this URL to the system browser.
                @html.a(
                  class="button secondary setting-link",
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  [
                    icon(icon_link_external),
                    @html.span(@settings.text(model.locale, Open)),
                  ],
                ),
              ],
              desc=@settings.text(
                model.locale,
                DevicePageDescription(name, url),
              ),
            ),
          )
        }
      } else {
        let target = match status.server_url {
          Some(server) => @settings.text(model.locale, RegisterServer(server))
          None => @settings.text(model.locale, RegisterRelay)
        }
        let controls : Array[@html.Html] = [
          // Once the sign-in completes this same slot becomes the Disconnect
          // button, and rabbita patches the existing element. `disabled~`
          // would set a DOM property, which its diff cannot clear (`delete`
          // on a prototype accessor is a no-op), leaving Disconnect dead; the
          // attribute form is removed correctly.
          @html.button(
            class="button primary",
            attrs=@html.Attrs::build().disabled(model.remote_connecting),
            on_click=dispatch(RemoteConnectClicked),
            if model.remote_connecting {
              @settings.text(model.locale, WaitingBrowser)
            } else {
              @settings.text(model.locale, ConnectGitHub)
            },
          ),
        ]
        // Appended after the stable Connect button, so its appearance
        // never re-seats that node.
        if model.remote_connecting {
          controls.push(
            @html.button(
              class="button secondary",
              on_click=dispatch(RemoteCancelClicked),
              @settings.text(model.locale, Cancel),
            ),
          )
        }
        rows.push(
          @settings.row(
            @settings.text(model.locale, SignIn),
            controls,
            desc=target,
          ),
        )
      }
  }
  if model.remote_error is Some(message) {
    rows.push(
      @settings.row(@settings.text(model.locale, Problem), [], desc=message),
    )
  }
  rows
}

///|
/// The Settings check-for-updates row: the last check's outcome — status
/// text, a download's progress, the restart button once a release is
/// staged, or the accent Update button a failed download restored — on the
/// left, the Check button on the right.
fn update_check_controls(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let controls : Array[@html.Html] = []
  match model.update_ux {
    UpdateUnknown => ()
    CheckingForUpdate =>
      controls.push(
        @html.span(
          class="update-status",
          @settings.text(model.locale, CheckingUpdate),
        ),
      )
    UpToDate =>
      controls.push(
        @html.span(
          class="update-status",
          @settings.text(model.locale, UpToDate),
        ),
      )
    UpdateAvailable(version~, installable~) =>
      if installable {
        controls.push(
          @html.button(
            class="button primary",
            on_click=dispatch(UpdateClicked),
            @settings.text(model.locale, UpdateTo(version)),
          ),
        )
      } else {
        controls.push(
          @html.span(
            class="update-status",
            @settings.text(model.locale, CannotInstallUpdate(version)),
          ),
        )
      }
    UpdateReady(version~) =>
      // The release is staged; this button is the restart the flow waits for.
      controls.push(
        @html.button(
          class="button primary",
          on_click=dispatch(UpdateClicked),
          @settings.text(model.locale, RestartToInstall(version)),
        ),
      )
    ConfirmingRestart(version~) =>
      // The interrupt modal is up over this row; keep the button visible
      // behind it so the row does not blink while the user decides.
      controls.push(
        @html.button(
          class="button primary",
          @settings.text(model.locale, RestartToInstall(version)),
        ),
      )
    DownloadingUpdate(version~, progress~) => {
      let (fill_class, fill_style) = match progress.percentage() {
        Some(percent) =>
          ("update-progress-fill", ["--progress-width: \{percent}%"])
        None => ("update-progress-fill indeterminate", [])
      }
      controls.push(
        @html.div(class="update-progress", [
          @html.span(
            class="update-status",
            progress.status_text(version, locale=model.locale),
          ),
          // The runtime supplies only the measured percentage. CSS owns the
          // width property and appearance; the adjacent text is the
          // accessible progress value.
          @html.div(class="update-progress-track", [
            @html.div(class=fill_class, style=fill_style, ""),
          ]),
        ]),
      )
    }
    RestartingForUpdate(version~) =>
      controls.push(
        @html.span(
          class="update-status",
          @settings.text(model.locale, RestartingVersion(version)),
        ),
      )
    UpdateCheckFailed(message~) =>
      controls.push(@html.span(class="update-status update-error", message))
  }
  controls.push(
    @html.button(
      class="button secondary",
      disabled=model.update_ux
        is (CheckingForUpdate
        | DownloadingUpdate(..)
        | UpdateReady(..)
        | RestartingForUpdate(..)),
      on_click=dispatch(CheckForUpdates),
      @settings.text(model.locale, CheckUpdates),
    ),
  )
  controls
}

///|
fn provider_hint(model : Model, provider : ApiProvider) -> String {
  match provider {
    Deepseek => @settings.text(model.locale, DeepseekHint)
    Glm => @settings.text(model.locale, GlmHint)
    OpenRouter => @settings.text(model.locale, OpenRouterHint)
    Custom => @settings.text(model.locale, CustomHint)
  }
}

///|
/// The bring-your-own-key guide shown at the top of the API group while the
/// configured endpoint is not usable. SeekMoon ships no hosted API: every
/// request goes straight from this machine to the user's own model
/// provider, so a key (official) or an endpoint URL (custom) must be
/// configured first. The steps follow the selected provider.
fn byok_setup_guide(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let provider = model.api_provider
  // Account setup belongs in the user's system browser, even while this
  // guide is displayed over Chat. Bypass Rabbita's dock URL routing.
  let provider_link = (url, label) => {
    @html.a(
      class="button secondary setting-link",
      href=url,
      target=Blank,
      rel="noopener noreferrer",
      escape=true,
      attrs=@html.Attrs::build().on_click(event => {
        if model.is_desktop {
          event.prevent_default()
          open_external_link(dispatch, url)
        } else {
          @cmd.none
        }
      }),
      [icon(icon_link_external), @html.span(label)],
    )
  }
  let step : (Int, String) -> @html.Html = (index, text) => {
    @html.div(class="setup-guide-step", [
      @html.span(class="setup-guide-index", index.to_string()),
      @html.span(class="setup-guide-text", text),
    ])
  }
  let steps : Array[@html.Html] = match provider {
    Deepseek =>
      [
        step(1, @settings.text(model.locale, DeepseekStepOne)),
        step(2, @settings.text(model.locale, CreateKey)),
        step(3, @settings.text(model.locale, DeepseekPasteKey)),
      ]
    Glm =>
      [
        step(1, @settings.text(model.locale, GlmStepOne)),
        step(2, @settings.text(model.locale, CreateKey)),
        step(3, @settings.text(model.locale, GlmPasteKey)),
      ]
    OpenRouter =>
      [
        step(1, @settings.text(model.locale, OpenRouterStepOne)),
        step(2, @settings.text(model.locale, OpenRouterPasteKey)),
      ]
    Custom =>
      [
        step(1, @settings.text(model.locale, StartEndpoint)),
        step(2, @settings.text(model.locale, EnterEndpoint)),
        step(3, @settings.text(model.locale, OptionalEndpointKey)),
      ]
  }
  @html.div(
    class="setup-guide",
    [
      @html.p(@settings.text(model.locale, OwnProviderDescription)),
      @html.div(class="setup-guide-steps", steps),
      ..if provider is Deepseek {
        [
          provider_link(
            "https://platform.deepseek.com/api_keys",
            @settings.text(model.locale, DeepseekKeysLink),
          ),
        ]
      },
      ..if provider is Glm {
        [
          provider_link(
            "https://z.ai/manage-apikey/apikey-list",
            @settings.text(model.locale, GlmKeysLink),
          ),
        ]
      },
    ],
  )
}

///|
/// The API configuration rows shared by the Settings page and the API-setup
/// modal: the BYOK guide while the endpoint is unusable, the provider
/// selector, and the endpoint URL / API key fields that complete the setup.
/// The modal is this same section lifted out of the page, so setup happens
/// in place instead of a navigation.
fn api_settings_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let settings_loaded = model.host_settings_loaded()
  let ready = model.api_ready()
  let rows : Array[@html.Html] = [
    ..if !ready {
      [byok_setup_guide(dispatch, model)]
    },
    @settings.row(
      @settings.text(model.locale, ApiEndpoint),
      [
        ApiProviderMenu.setting_control(
          dispatch,
          model,
          id="api-provider-select",
          options=[
            {
              value: "deepseek",
              label: @settings.text(model.locale, DeepseekOfficial),
            },
            { value: "glm", label: @settings.text(model.locale, GlmOfficial), },
            { value: "openrouter", label: "OpenRouter", },
            { value: "custom", label: @settings.text(model.locale, CustomUrl), },
          ],
          selected=model.api_provider.wire(),
          aria_label=@settings.text(model.locale, ApiEndpoint),
          change=dispatch.map(value => ProviderChanged(value)),
          disabled=!settings_loaded,
        ),
      ],
      desc=provider_hint(model, model.api_provider),
    ),
  ]
  if model.api_provider is Custom {
    rows.push(
      @settings.row(
        @settings.text(model.locale, EndpointUrl),
        [
          @html.input(
            input_type=@html.InputType::Text,
            value=model.custom_api_url,
            placeholder="https://host/chat/completions",
            on_input=dispatch.map(value => CustomApiUrlChanged(value)),
            attrs=@html.Attrs::build()
              .aria_label(@settings.text(model.locale, EndpointUrl))
              .data_set("focus-owner", "")
              .disabled(!settings_loaded),
          ),
        ],
        stack=true,
      ),
    )
  }
  // The key lives on the host and is never echoed back — the page only
  // knows one is saved; saving a new one overwrites it.
  {
    let (key_label, key_saved) = match model.api_provider {
      Deepseek =>
        (@settings.text(model.locale, DeepseekApiKey), model.deepseek_key_saved)
      Glm => (@settings.text(model.locale, GlmApiKey), model.glm_key_saved)
      OpenRouter =>
        (@settings.text(model.locale, OpenRouterApiKey), model.custom_key_saved)
      Custom =>
        (@settings.text(model.locale, CustomApiKey), model.custom_key_saved)
    }
    rows.push(
      @settings.row(
        key_label,
        [
          @html.input(
            input_type=@html.InputType::Password,
            value=model.setup_api_key,
            placeholder=if key_saved {
              @settings.text(model.locale, SavedKey)
            } else {
              "sk-..."
            },
            on_input=dispatch.map(value => SetupApiKeyChanged(value)),
            attrs=@html.Attrs::build()
              .aria_label(@settings.text(model.locale, ApiKey))
              .data_set("focus-owner", "")
              .disabled(!settings_loaded),
          ),
          @html.button(
            // The id is layout only (grid placement); the fill is the
            // shared primary style.
            id="saveApiKey",
            class="button primary",
            disabled=!settings_loaded || model.setup_api_key.is_blank(),
            on_click=dispatch(SaveApiKey),
            @settings.text(model.locale, SaveApiKey),
          ),
        ],
        desc=@settings.text(model.locale, KeyStorageDescription),
        stack=true,
      ),
    )
  }
  rows
}

///|
/// The Settings page, shown in the main area in place of the conversation
/// (mirroring the Skills page — the sidebar is the way out, no Done button).
/// While the configured endpoint is unusable the BYOK guide leads the API
/// group, and the composer keeps Send disabled until a usable endpoint is
/// saved.
fn settings_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let locale = model.locale
  let settings_loaded = model.host_settings_loaded()
  let ready = model.api_ready()
  // All providers use the composer's model selector; API setup only chooses
  // the endpoint and credentials.
  let engine_rows : Array[@html.Html] = [
    @settings.row(
      @settings.text(locale, MaxSteps),
      [
        @html.input(
          input_type=@html.InputType::Number,
          value=model.max_steps,
          placeholder="1000",
          on_input=dispatch.map(value => MaxStepsChanged(value)),
          attrs=@html.Attrs::build()
            .aria_label(@settings.text(locale, MaxSteps))
            .data_set("focus-owner", ""),
        ),
      ],
      desc=@settings.text(locale, MaxStepsDescription),
    ),
  ]
  let api_rows : Array[@html.Html] = api_settings_rows(dispatch, model)
  let groups : Array[@html.Html] = [
    @settings.group(icon_sparkle, @settings.text(locale, Engine), engine_rows),
    @settings.group(icon_key, "API", api_rows),
    @settings.group(
      icon_extensions,
      "Codex",
      codex_account_rows(dispatch, model),
    ),
    @settings.group(icon_layout, @settings.text(locale, Interface), [
      @settings.row(
        @settings.text(locale, Language),
        [
          LanguageMenu.setting_control(
            dispatch,
            model,
            id="language-select",
            options=[
              { value: "system", label: @settings.text(locale, System), },
              { value: "en", label: "English", },
              { value: "zh-Hans", label: "简体中文", },
              { value: "zh-Hant", label: "繁體中文", },
              { value: "ja", label: "日本語", },
              { value: "es", label: "Español", },
            ],
            selected=model.language.wire(),
            aria_label=@settings.text(locale, Language),
            change=@cmd.Emit(value => {
              dispatch(LanguageChanged(value, browser_languages()))
            }),
          ),
        ],
        desc=@settings.text(locale, LanguageDescription),
      ),
      @settings.row(
        @settings.text(locale, Followup),
        [
          FollowupBehaviorMenu.setting_control(
            dispatch,
            model,
            id="followup-behavior-select",
            options=[
              { value: "steer", label: @settings.text(locale, Steer), },
              { value: "queue", label: @settings.text(locale, Queue), },
            ],
            selected=model.followup_behavior.wire(),
            aria_label=@settings.text(locale, Followup),
            change=dispatch.map(value => FollowupBehaviorChanged(value)),
            disabled=!settings_loaded,
          ),
        ],
        desc=@settings.text(locale, FollowupDescription),
      ),
      @settings.row(
        @settings.text(locale, Theme),
        [
          ThemeMenu.setting_control(
            dispatch,
            model,
            id="theme-select",
            options=[
              { value: "system", label: @settings.text(locale, System), },
              { value: "light", label: @settings.text(locale, Light), },
              { value: "dark", label: @settings.text(locale, Dark), },
            ],
            selected=model.theme.wire(),
            aria_label=@settings.text(locale, Theme),
            change=dispatch.map(value => ThemeChanged(value)),
          ),
        ],
        desc=@settings.text(locale, ThemeDescription),
      ),
      @settings.row(
        @settings.text(locale, FontSize),
        [
          FontSizeMenu.setting_control(
            dispatch,
            model,
            id="font-size-select",
            options=[
              { value: "12", label: "12px", },
              { value: "13", label: "13px", },
              { value: "14", label: "14px", },
              { value: "15", label: "15px", },
              { value: "16", label: "16px", },
              { value: "17", label: "17px", },
              { value: "18", label: "18px", },
            ],
            selected=model.app_font_size.wire(),
            aria_label=@settings.text(locale, FontSize),
            change=dispatch.map(value => FontSizeChanged(value)),
          ),
        ],
        desc=@settings.text(locale, FontSizeDescription),
      ),
      @settings.row(
        @settings.text(locale, NotificationCorner),
        [
          NotificationCornerMenu.setting_control(
            dispatch,
            model,
            id="notification-corner-select",
            options=[
              {
                value: "bottom-right",
                label: @settings.text(locale, BottomRight),
              },
              {
                value: "bottom-left",
                label: @settings.text(locale, BottomLeft),
              },
              { value: "top-right", label: @settings.text(locale, TopRight), },
              { value: "top-left", label: @settings.text(locale, TopLeft), },
            ],
            selected=model.notification_corner.wire(),
            aria_label=@settings.text(locale, NotificationCorner),
            change=dispatch.map(value => NotificationCornerChanged(value)),
          ),
        ],
        desc=@settings.text(locale, NotificationDescription),
      ),
      @settings.row(
        @settings.text(locale, FileTreeLayout),
        [
          TreeLayoutMenu.setting_control(
            dispatch,
            model,
            id="tree-layout-select",
            options=[
              {
                value: "right-sidebar",
                label: @settings.text(locale, RightSidebar),
              },
              {
                value: "bottom-panel",
                label: @settings.text(locale, BottomPanel),
              },
            ],
            selected=model.tree_layout.wire(),
            aria_label=@settings.text(locale, FileTreeLayout),
            change=dispatch.map(value => TreeLayoutChanged(value)),
          ),
        ],
        desc=@settings.text(locale, FileTreeDescription),
      ),
    ]),
  ]
  // Self-update swaps the bundle under the desktop process, and the relay
  // sign-in registers the machine the host runs on; from a browser both
  // sections could only break things for whoever is at the machine.
  if model.is_desktop {
    groups.push(
      @settings.group(
        @icons.icon_settings_gear,
        @settings.text(locale, Diagnostics),
        [
          @settings.row(
            @settings.text(locale, FpsOverlay),
            [
              @html.button(
                class="button secondary",
                attrs=@html.Attrs::build()
                  .role("switch")
                  .aria_label(@settings.text(locale, FpsOverlay))
                  .aria_checked(model.fps_overlay_enabled.to_string()),
                on_click=dispatch(FpsOverlayChanged(!model.fps_overlay_enabled)),
                if model.fps_overlay_enabled {
                  @settings.text(locale, On)
                } else {
                  @settings.text(locale, Off)
                },
              ),
            ],
            desc=@settings.text(locale, FpsDescription),
          ),
        ],
      ),
    )
    groups.push(
      @settings.group(
        icon_link_external,
        @settings.text(locale, RemoteAccess),
        remote_access_rows(dispatch, model),
      ),
    )
    groups.push(
      @settings.group(icon_sync, @settings.text(locale, Updates), [
        @settings.row(
          @settings.text(locale, CheckUpdates),
          update_check_controls(dispatch, model),
          desc=@settings.text(locale, CurrentVersion(model.app_version)),
        ),
      ]),
    )
  }
  @html.section(class="settings-page", [
    @html.div(class="settings-page-inner", [
      @html.div(class="settings-header", [
        @html.div(class="page-eyebrow", @settings.text(locale, Preferences)),
        @html.h1(@settings.text(locale, Settings)),
        @html.div(
          class="settings-subtitle",
          if !settings_loaded {
            @settings.text(locale, LoadingSettings)
          } else if ready {
            @settings.text(locale, RuntimeSettings)
          } else {
            match model.api_provider {
              Deepseek => @settings.text(locale, DeepseekKey)
              Glm => @settings.text(locale, GlmKey)
              OpenRouter => @settings.text(locale, OpenRouterKey)
              Custom => @settings.text(locale, CustomEndpoint)
            }
          },
        ),
      ]),
      @html.div(class="settings", groups),
    ]),
  ])
}

///|
fn run_indicator(model : Model, conv : Conversation) -> @html.Html {
  let status = model.display_status()
  let label = status.label(locale=model.locale)
  if conv.is_running() {
    @html.div(class="run-status accent", [
      @html.span(class="run-dot accent pulse", ""),
      @html.span(class="run-text", label),
    ])
  } else {
    @html.div(class="run-status", [
      @html.span(class="run-dot \{status.kind().css()}", ""),
      @html.span(class="run-text", label),
    ])
  }
}

///|
/// The workspace line appears once the host has reported it via `started`;
/// before the conversation's first run only the session id is known.
fn session_tooltip(model : Model, conv : Conversation) -> String {
  if model.conversation_root(conv) is Some(cwd) {
    dynamic_text(
      model.locale,
      DSessionWorkspace(conv.session_id.to_string(), cwd.path.to_string()),
    )
  } else {
    dynamic_text(model.locale, DSession(conv.session_id.to_string()))
  }
}

///|
/// The narrow layout always renders the minimal transcript: its titlebar has
/// no detail toggle, and a phone has no room for the detailed view. The
/// stored preference is preserved for the wide layout.
fn Model::minimal_transcript_effective(self : Model) -> Bool {
  self.narrow || self.minimal_transcript
}

///|
/// The telescope is on for detailed mode. Both conversation sources use the
/// inverse of the stored minimal preference, preserving existing choices.
/// This local preference has no connection or run-state gate. Neighboring
/// controls must clear their disabled state when Rabbita reuses their DOM
/// for this button (see the Codex topbar).
fn Model::detail_toggle(self : Model, dispatch : @cmd.Emit[Msg]) -> @html.Html {
  @html.button(
    class=if self.minimal_transcript {
      "panel-toggle"
    } else {
      "panel-toggle active"
    },
    title=if self.minimal_transcript {
      shell_text(self.locale, ShowDetailed)
    } else {
      shell_text(self.locale, ShowMinimal)
    },
    attrs=@html.Attrs::build()
      .aria_label(shell_text(self.locale, DetailedMode))
      .aria_pressed((!self.minimal_transcript).to_string()),
    on_click=dispatch(MinimalTranscriptChanged(!self.minimal_transcript)),
    icon(@icons.icon_telescope),
  )
}

///|
/// Top bar: conversation identity on the left (session id and workspace in
/// the tooltip), live run state and conversation controls on the right.
fn topbar_view(
  dispatch : @cmd.Emit[Msg],
  toggle_terminal : @cmd.Cmd,
  model : Model,
  conv : Conversation,
) -> @html.Html {
  let items : Array[@html.Html] = []
  items.push(
    @html.span(
      class="topbar-title",
      title=session_tooltip(model, conv),
      conversation_title(locale=model.locale, conv),
    ),
  )
  // The project this conversation works in. The git branch is not shown here
  // — it lives in the composer's status row.
  let workspace = conv.project()
  items.push(
    @html.span(class="topbar-workspace", title=workspace.path, [
      icon(icon_folder),
      @html.text(@resource.label(workspace)),
    ]),
  )
  items.push(run_indicator(model, conv))
  if conv.turn.usage_tokens > 0 {
    items.push(
      @html.span(
        class="pill",
        token_label(locale=model.locale, conv.turn.usage_tokens),
      ),
    )
  }
  // A phone's titlebar carries identity and run state only: the detail,
  // export, terminal, and right-panel controls all leave the narrow layout.
  if !model.narrow {
    items.push(model.detail_toggle(dispatch))
  }
  // Export is a native-window operation and the visualizer consumes durable
  // OpenSeek JSONL. Remote-device conversations and fresh drafts therefore do
  // not offer a button that their host cannot fulfill.
  if !model.narrow &&
    model.is_desktop &&
    conv.device is Local &&
    !conv.messages.is_empty() {
    items.push(
      @html.button(
        class="panel-toggle",
        title=shell_text(model.locale, ExportConversation),
        on_click=dispatch(
          OpenExport({
            session: conv.session_id,
            workspace: workspace.path,
            title: conversation_title(locale=model.locale, conv),
            archived: conv.is_archived_read_only(),
          }),
        ),
        icon(icon_chat_export),
      ),
    )
  }
  // A browser terminal is rendered locally but its PTY lives on the focused
  // remote device, reached through that device's WebSocket channel.
  if !model.narrow {
    items.push(
      @html.button(
        class=if model.terminal.is_open() {
          "panel-toggle active"
        } else {
          "panel-toggle"
        },
        title=if model.terminal.is_open() {
          shell_text(model.locale, HideTerminal)
        } else {
          shell_text(model.locale, ShowTerminal)
        },
        on_click=toggle_terminal,
        icon(icon_terminal),
      ),
    )
  }
  @html.div(class="topbar", items)
}

///|
/// The conversation column while no conversation is on screen. A chat happens
/// inside a project, so this is what the app shows before it knows of one:
/// while the host's registry is still in flight, and when no project is
/// attached at all. Attaching one is the only way out, so it is the only
/// action offered — the sidebar's own shell_text(model.locale, AddProject) opens the same picker.
fn onboarding_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let card : Array[@html.Html] = [
    @html.h2(shell_text(model.locale, OpenProject)),
  ]
  match (model.bridge_state(), model.focused_device()) {
    (Connected, Some(dev)) if dev.projects.is_empty() => {
      card.push(@html.p(shell_text(model.locale, ProjectOnboarding)))
      card.push(
        @html.button(
          class="button primary",
          type_="button",
          on_click=dispatch(PickProject(dev.channel)),
          shell_text(model.locale, AddProject),
        ),
      )
    }
    // A connected device with projects is between conversations: the session
    // rotation that opens one is a message away.
    (Connected, Some(_)) =>
      card.push(@html.p(shell_text(model.locale, OpeningChat)))
    // Until the bridge answers, this page knows nothing about the host's
    // projects. Offering to add one here would be a guess that the very next
    // message contradicts.
    _ => card.push(@html.p(shell_text(model.locale, ConnectingDevice)))
  }
  @html.section(class="onboarding", [@html.div(class="onboarding-card", card)])
}

///|
/// The console's full-screen gate. A missing `?device=` stops before sign-in;
/// authentication gets its own progress/retry states, and a signed-in page
/// stays here until its one query-selected device is available.
fn console_gate_view(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  console : ConsoleState,
) -> @html.Html {
  let card : Array[@html.Html] = []
  if console.page_device is Some(id) {
    match console.auth {
      AuthChecking => {
        card.push(
          @html.p(
            match console.notice {
              Some(notice) => notice
              None => shell_text(locale, CheckingSignIn)
            },
          ),
        )
        if console.notice is Some(_) {
          card.push(
            @html.button(
              class="button primary",
              on_click=dispatch(Console(RefreshClicked)),
              shell_text(locale, TryAgain),
            ),
          )
        }
      }
      AuthSignedOut => {
        card.push(@html.h2(shell_text(locale, SignInLabel)))
        card.push(@html.p(shell_text(locale, BrowserAccess)))
        card.push(
          @html.a(
            class="portal-button-link",
            href=console.login_url(),
            shell_text(locale, SignInGitHub),
          ),
        )
      }
      AuthSignedIn(..) =>
        match console.roster_sync {
          RosterLoading =>
            card.push(@html.p(shell_text(locale, CheckingDevice)))
          RosterFailed(message) => {
            card.push(@html.h2(shell_text(locale, CannotLoadDevice)))
            card.push(@html.p(message))
            card.push(
              @html.button(
                class="button primary",
                on_click=dispatch(Console(RefreshClicked)),
                shell_text(locale, TryAgain),
              ),
            )
          }
          RosterReady => {
            let selected = console.roster
              .iter()
              .find_first(meta => meta.id == id)
            if selected is Some(meta) {
              if meta.online {
                card.push(
                  @html.h2(
                    dynamic_text(locale, DConnecting(meta.name.to_string())),
                  ),
                )
                card.push(@html.p(shell_text(locale, WaitingConnection)))
              } else {
                card.push(@html.h2("\{meta.name} is offline"))
                card.push(@html.p(shell_text(locale, BringOnline)))
              }
            } else {
              card.push(@html.h2(shell_text(locale, DeviceUnavailable)))
              card.push(@html.p(shell_text(locale, DeviceNotInAccount)))
            }
            card.push(
              @html.button(
                class="button primary",
                on_click=dispatch(Console(RefreshClicked)),
                shell_text(locale, RefreshLabel),
              ),
            )
          }
        }
    }
  } else {
    card.push(@html.h2(shell_text(locale, DeviceLinkRequired)))
    card.push(@html.p(shell_text(locale, DeviceLinkDescription)))
  }
  // Every signed-in gate hides the sidebar's account controls. Keep the
  // account escape hatch here once, independent of why device access is gated.
  if console.auth is AuthSignedIn(..) {
    card.push(
      @html.button(
        class="button secondary",
        disabled=console.busy,
        on_click=dispatch(Console(SignOutClicked)),
        if console.busy {
          shell_text(locale, SigningOut)
        } else {
          shell_text(locale, SignOutLabel)
        },
      ),
    )
    if console.notice is Some(notice) {
      card.push(@html.p(notice))
    }
  }
  @html.section(class="portal", [
    @html.div(class="portal-inner", [
      @html.header(class="portal-header", [@html.h1("SeekMoon")]),
      @html.div(class="portal-card", card),
    ]),
  ])
}

///|
/// Native chrome geometry is owned by the window subscription, independently
/// of the application view's sidebar state.
fn app_shell_class(sidebar_open : Bool) -> String {
  let classes : Array[String] = ["app"]
  if !sidebar_open {
    classes.push("sidebar-collapsed")
  }
  classes.join(" ")
}

///|
/// Whether the root layout should expose its persistent terminal row. Page
/// navigation never closes terminal state or PTYs, but non-conversation pages
/// have no active workspace surface to place the panel under.
fn Model::terminal_panel_visible(self : Model) -> Bool {
  self.terminal.is_open() &&
  (
    self.screen is Chat ||
    (
      self.screen is Codex &&
      self.codex.active_placement(self.focused) is Some(_)
    )
  )
}

///|
/// A selected row is loaded only when the active transcript has the same
/// durable identity, including live-vs-archived placement and workspace.
fn Model::selected_conversation_loaded(self : Model) -> Bool {
  guard self.conversation_selection() is Some(selected) else { return true }
  guard self.active_conversation() is Some(active) else { return false }
  let record = if active.is_archived_read_only() {
    ArchivedRecord
  } else {
    LiveRecord
  }
  selected.channel == active.device &&
  selected.session == active.session_id &&
  selected.workspace == active.project() &&
  selected.record == record
}

///|
fn conversation_loading_view(locale? : @i18n.Locale = English) -> @html.Html {
  @html.div(
    class="conversation-load-state",
    shell_text(locale, LoadingConversation),
  )
}

///|
fn conversation_load_failed_view(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  message : String,
) -> @html.Html {
  @html.div(class="conversation-load-state failed", [
    @html.strong(shell_text(locale, CannotLoadConversation)),
    @html.span(class="conversation-load-state-message", message),
    @html.button(
      class="button secondary",
      type_="button",
      on_click=dispatch(RetrySelectedConversation),
      shell_text(locale, RetryLabel),
    ),
  ])
}

///|
fn view(
  dispatch : @cmd.Emit[Msg],
  toggle_terminal : @cmd.Cmd,
  toggle_right_panel : @cmd.Cmd,
  model : Model,
  terminal_html : @html.Html,
  transcript_html : @html.Html,
  right_panel_html : @html.Html,
  composer_html : @html.Html,
  codex_composer_html : @html.Html,
  sidebar_html : @html.Html,
  quick_open_and_context_menu : (@html.Html, @html.Html),
  skills_and_workspace_settings : (@html.Html, @html.Html),
) -> @html.Html {
  let (quick_open_html, context_menu_html) = quick_open_and_context_menu
  let (skills_html, workspace_settings_html) = skills_and_workspace_settings
  // Until the relay session and its device exist, the console frame —
  // sidebar, composer, overlays — stays unbuilt and inert Local cannot
  // receive UI work.
  if model.is_console_gated() {
    return console_gate_view(locale=model.locale, dispatch, model.console)
  }
  let file_panel_visible = model.file_panel_visible()
  let terminal_panel_visible = model.terminal_panel_visible()
  // Pages without their own topbar still paint beneath the native overlay.
  // Mark their main element so the document-level double-click gesture can
  // treat only its otherwise-empty top edge as window chrome.
  let window_titlebar_page = match model.screen {
    Chat => model.active_conversation() is None
    Skills | Schedules | Settings | WorkspaceSettings(..) => true
    Codex => false
  }
  let window_titlebar_drag_strip = window_titlebar_drag_strip_visible(
    window_titlebar_page,
    model.is_desktop,
  )
  let content = match model.screen {
    // `Model::chat_column` is the one fork that decides what the conversation
    // column is; the transcript component's lifetime follows the same value.
    Chat =>
      match model.chat_column() {
        LoadFailed(message~) =>
          [
            conversation_load_failed_view(
              locale=model.locale,
              dispatch,
              message,
            ),
          ]
        Loading => [conversation_loading_view(locale=model.locale)]
        Onboarding => [onboarding_view(dispatch, model)]
        Transcript(conversation=conv, ..) =>
          [
            topbar_view(dispatch, toggle_terminal, model, conv),
            transcript_html,
            if conv.is_archived_read_only() {
              conv.archived_read_only_view(locale=model.locale, dispatch)
            } else if model.scheduled_session_read_only(conv) {
              @html.div(class="composer archived-read-only", [
                @html.div(class="archived-read-only-bar", [
                  @html.span(
                    class="archived-read-only-text",
                    shell_text(model.locale, ScheduleReadOnly),
                  ),
                  @html.button(
                    class="archived-read-only-restore",
                    on_click=dispatch(OpenSchedules),
                    shell_text(model.locale, ViewTask),
                  ),
                ]),
              ])
            } else {
              composer_html
            },
          ]
      }
    Codex =>
      model.codex.page(
        locale=model.locale,
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        model.focused,
        terminal_open=terminal_panel_visible,
        narrow=model.narrow,
        @codex.PageActions::{
          toggle_terminal,
          workspace_label: workspace => @resource.label(workspace),
          transcript: transcript_html,
          composer: codex_composer_html,
          detail_toggle: model.detail_toggle(dispatch),
        },
      )
    Schedules => [schedules_page(dispatch, model)]
    Skills => [skills_html]
    Settings => [settings_page(dispatch, model)]
    WorkspaceSettings(..) => [workspace_settings_html]
  }
  // The app is `sidebar | content`; `content` itself splits into the
  // conversation (left) and the editor (right) as two independent parts, so
  // either side can be swapped out later. Files open over an OpenSeek or Codex
  // conversation with a real workspace; on the other pages the editor column
  // (and its viewer host) stays rendered so the attached viewer is never torn
  // down.
  let mut content_class = if file_panel_visible {
    "content panel-open"
  } else {
    "content"
  }
  if file_panel_visible && model.right_panel_expanded {
    content_class += " panel-expanded"
  }
  if terminal_panel_visible {
    content_class += " terminal-open"
  }
  let page_content = if window_titlebar_drag_strip {
    [@html.div(class="window-titlebar-drag-strip", @html.nothing), ..content]
  } else {
    content
  }
  let panel_available = model.screen is Chat ||
    (
      file_ctx(model).placement is Some(placement) &&
      placement.checkout_root() is Some(_)
    )
  let panel_toggle_visible = file_panel_visible ||
    (
      !model.narrow &&
      (
        model.screen is Codex ||
        (model.screen is Chat && model.active_conversation() is Some(_))
      )
    )
  let panel_toggle_label = if file_panel_visible {
    shell_text(model.locale, HidePanel)
  } else if model.screen is Codex {
    model.codex.files_toggle_label(locale=model.locale, model.focused)
  } else {
    shell_text(model.locale, ShowPanel)
  }
  let sidebar_toggle_label = if model.sidebar_open {
    @sidebar_messages.text(model.locale, HideSidebar)
  } else {
    @sidebar_messages.text(model.locale, ShowSidebar)
  }
  let children : Array[@html.Html] = [
    // Keep reading order aligned with the control's top-left position,
    // outside all animated content tracks.
    @html.button(
      class="sidebar-toggle",
      title=sidebar_toggle_label,
      on_click=dispatch(ToggleSidebar),
      attrs=@html.Attrs::build().aria_label(sidebar_toggle_label),
      icon(icon_layout_sidebar_left),
    ),
    sidebar_html,
    @html.div(class=content_class, [
      // One fixed control owns both states, outside the animated pane tracks.
      @html.button(
        class=if panel_toggle_visible {
          "panel-toggle right-panel-toggle"
        } else {
          "panel-toggle right-panel-toggle hidden"
        },
        title=panel_toggle_label,
        attrs=@html.Attrs::build()
          .aria_label(panel_toggle_label)
          .aria_expanded(file_panel_visible.to_string())
          .disabled(!panel_available),
        on_click=toggle_right_panel,
        icon(icon_layout_sidebar_right),
      ),
      @html.main_(
        class=if window_titlebar_drag_strip {
          "window-titlebar-page"
        } else {
          ""
        },
        page_content,
      ),
      right_panel_html,
      terminal_html,
    ]),
    // Keep the dialog before conditional overlays: replacing its DOM node
    // would lose showModal state during resize or a notification.
    model.export_dialog.view(
      locale=model.locale,
      dispatch.map(msg => ExportDialog(msg)),
    ),
  ]
  // On the narrow layout the sidebar's stable backdrop fades with the drawer;
  // keeping it mounted lets the closing transition finish before it becomes
  // inert. Appended after the stable shell children so toggling never re-keys
  // them.
  if model.narrow {
    children.push(
      @html.div(
        class=if model.sidebar_open {
          "sidebar-backdrop open"
        } else {
          "sidebar-backdrop"
        },
        on_click=dispatch(ToggleSidebar),
        @html.nothing,
      ),
    )
  }
  // The toast stack floats over everything (position: fixed), so appending
  // it last never shifts the layout; skipping it entirely while empty keeps
  // the corner clickable.
  if model.notifications.length() > 0 || model.github.checkout is Some(_) {
    children.push(notifications_view(dispatch, model))
  }
  children.push(
    @github.checkout_dialog(
      locale=model.locale,
      model.github,
      dispatch.map(msg => Github(msg)),
    ),
  )
  // The interrupt-confirmation modal floats the same way, above the toasts.
  if model.update_ux is ConfirmingRestart(version~) {
    children.push(update_confirm_modal(locale=model.locale, dispatch, version))
  }
  // The API-setup modal floats above the toasts like the other modals: it
  // owns the screen until the user answers it or a usable endpoint arrives.
  if model.api_setup_open {
    children.push(api_setup_modal(dispatch, model))
  }
  if model.project_picker is Some(picker) {
    children.push(
      @project_picker.view(
        locale=model.locale,
        dispatch.map(msg => ProjectPicker(msg)),
        picker,
      ),
    )
  }
  if model.archive_confirm is Some(confirm) {
    children.push(
      @composer.WorktreeArchiveDialog::{
        refusal: confirm.refusal,
        conversation_noun: "chat",
        cancel: dispatch(CancelArchiveDiscard),
        confirm: dispatch(ConfirmArchiveDiscard),
      }.render(locale=model.locale),
    )
  }
  if model.archived_delete_confirm is Some(confirm) {
    children.push(archived_delete_modal(locale=model.locale, dispatch, confirm))
  }
  if model.conversation_rename is Some(rename) {
    children.push(
      conversation_rename_dialog(locale=model.locale, dispatch, rename),
    )
  }
  // Rendered whether or not the palette is open — closed it is an empty
  // placeholder — so opening it never shifts the overlay children around it.
  children.push(quick_open_html)
  children.push(context_menu_html)
  // On the desktop a lost connection covers everything: with no event
  // stream and every API call failing, the app behind it can do nothing,
  // so an honest dead-end beats a half-broken UI. The console keeps its last
  // rendered device readable while its topbar and composer show reconnecting.
  if model.is_desktop && model.bridge_state() is BridgeLost(message) {
    children.push(bridge_lost_overlay(locale=model.locale, message))
  }
  @html.div(class=app_shell_class(model.sidebar_open), children)
}

///|
/// The full-screen card shown when the bridge is lost: a plain explanation
/// and what to do; the only action here is the instruction itself.
fn bridge_lost_overlay(
  locale? : @i18n.Locale = English,
  message : String,
) -> @html.Html {
  @html.div(class="bridge-lost-backdrop", [
    @html.div(class="bridge-lost-card", [
      @html.div(
        class="bridge-lost-title",
        shell_text(locale, DisconnectedLabel),
      ),
      @html.div(class="bridge-lost-body", message),
    ]),
  ])
}

///|
/// The modal shown when restarting into a staged update would cut running
/// conversations off: restarting tears the engine processes down mid-run.
/// The backdrop and the Cancel button both keep the current version running,
/// with the downloaded release parked for later.
fn update_confirm_modal(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  version : String,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelUpdateRestart), [
    @html.div(class="modal", [
      @html.div(
        class="modal-title",
        dynamic_text(locale, DRestartQuestion(version)),
      ),
      @html.div(class="modal-body", shell_text(locale, InterruptForUpdate)),
      @html.div(class="modal-actions", [
        @html.button(
          class="button secondary",
          on_click=dispatch(CancelUpdateRestart),
          shell_text(locale, KeepWorking),
        ),
        @html.button(
          class="button primary",
          on_click=dispatch(ConfirmUpdateRestart),
          shell_text(locale, RestartNow),
        ),
      ]),
    ]),
  ])
}

///|
/// The modal that owns the one truly blocking state a fresh install can be
/// in: SeekMoon is bring-your-own-key and no usable endpoint is configured.
/// It is the API settings section lifted out of the page — provider, URL,
/// and key are configured right here — so it opens over the chat, never
/// over the Settings form (which already shows the same section), and
/// disappears the moment a usable endpoint arrives. shell_text(model.locale, NotNow) dismisses for
/// the session; the composer's BYOK notice keeps the reminder — and the way
/// back here — visible. Clicks inside must not bubble to the backdrop, whose
/// click dismisses.
fn api_setup_modal(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let title = match model.api_provider {
    Deepseek => shell_text(model.locale, SetupDeepSeek)
    Glm => shell_text(model.locale, SetupGlm)
    OpenRouter => shell_text(model.locale, SetupOpenRouter)
    Custom => shell_text(model.locale, SetupEndpoint)
  }
  @html.div(class="modal-backdrop", on_click=dispatch(DismissApiSetup), [
    @html.div(
      class="modal setup-modal",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        @cmd.none
      }),
      [
        @html.div(class="modal-title", title),
        @html.div(class="setup-modal-form", api_settings_rows(dispatch, model)),
        @html.div(class="modal-actions", [
          @html.button(
            class="button secondary",
            on_click=dispatch(DismissApiSetup),
            shell_text(model.locale, NotNow),
          ),
        ]),
      ],
    ),
  ])
}

///|
/// The floating toast stack, fixed to the configured window corner. Each
/// toast dismisses on click; its timer handles the rest.
fn notifications_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let toasts : Array[@html.Html] = [
    @github.checkout_notification(
      locale=model.locale,
      model.github,
      dispatch.map(msg => Github(msg)),
    ),
  ]
  for toast in model.notifications {
    toasts.push(
      @html.div(
        class="notification",
        title=shell_text(model.locale, DismissLabel),
        on_click=dispatch(DismissNotification(toast.id)),
        toast.message,
      ),
    )
  }
  @html.div(
    class="notifications corner-\{model.notification_corner.wire()}",
    toasts,
  )
}

///|
test "archived families collapse while a live orphan child stays archivable" {
  let archived_model = test_model().with_dev(dev => {
    ..dev,
    archived: [archived_item("chat"), archived_item("chat-sr-1")],
  })
  let archived_sections = archived_model.sidebar_component_sections(
    archived_model.dev(),
  )
  let mut archived_entries : Array[@section.Entry] = []
  for section in archived_sections {
    if section.id().source() == "archived" {
      archived_entries = section.entries
    }
  }
  assert_eq(archived_entries.length(), 1)
  guard archived_entries[0] is @section.Conversation(archived) else {
    fail("expected archived parent conversation")
  }
  assert_eq(archived.id().conversation(), "chat")
  assert_true(
    archived.trailing is [@conversation.Restore(_), @conversation.Delete(_)],
  )
  let orphan_model = test_model().with_dev(dev => {
    ..dev,
    sessions: [placed_archived_item("chat-sr-1")],
  })
  let orphan_sections = orphan_model.sidebar_component_sections(
    orphan_model.dev(),
  )
  // Live rows hang under their project's folder row.
  let mut orphan : @conversation.Input? = None
  for section in orphan_sections {
    guard section.id().source() == "openseek.projects" else { continue }
    for entry in section.entries {
      guard entry is @section.Project(project) else { continue }
      for row in project.conversations {
        if row.id().conversation() == "chat-sr-1" {
          orphan = Some(row)
        }
      }
    }
  }
  guard orphan is Some(orphan) else {
    fail("expected live orphan conversation")
  }
  assert_eq(orphan.id().conversation(), "chat-sr-1")
  assert_true(orphan.trailing is [@conversation.Archive(_)])
}

///|
#warnings("-alert_unstable")
test "project component receives the complete conversation list" {
  let project = @interop.ChannelId::Local.test_resource("/work/alpha")
  let sessions : Array[@transcript.SessionListItem] = []
  for number = 1; number <= 6; number = number + 1 {
    sessions.push({
      id: "chat-\{number}",
      title: Some("Project chat \{number}"),
      workspace: project,
      workspace_name: "alpha",
      updated_at_ms: None,
    })
  }
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [project],
    sessions,
  })
  let sections = model.sidebar_component_sections(model.dev())
  let mut project : @project.Input? = None
  for section in sections {
    if section.id().source() == "openseek.projects" {
      for entry in section.entries {
        if entry is @section.Project(value) {
          project = Some(value)
        }
      }
    }
  }
  guard project is Some(project) else { fail("missing project input") }
  assert_eq(project.conversations.length(), 6)
  assert_eq(project.conversations[4].label, "Project chat 5")
  assert_eq(project.conversations[5].label, "Project chat 6")
}

///|
/// Durable identities are store-qualified, so one session id may hold a
/// record in two project stores at once. Both rows must survive the sidebar's
/// keyed container — colliding keys would silently drop one.
test "same-id records in two project stores keep distinct row keys" {
  let alpha = @interop.ChannelId::Local.test_resource("/alpha")
  let beta = @interop.ChannelId::Local.test_resource("/beta")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [alpha, beta],
    sessions: [
      {
        id: "desktop-shared",
        title: Some("alpha copy"),
        workspace: alpha,
        workspace_name: "alpha",
        updated_at_ms: None,
      },
      {
        id: "desktop-shared",
        title: Some("beta copy"),
        workspace: beta,
        workspace_name: "beta",
        updated_at_ms: None,
      },
    ],
  })
  let keys : Array[String] = []
  for section in model.sidebar_component_sections(model.dev()) {
    for entry in section.entries {
      match entry {
        @section.Project(project) =>
          for conversation in project.conversations {
            if conversation.id.conversation() == "desktop-shared" {
              keys.push(conversation.id.key())
            }
          }
        @section.Conversation(conversation) =>
          if conversation.id.conversation() == "desktop-shared" {
            keys.push(conversation.id.key())
          }
        _ => ()
      }
    }
  }
  assert_eq(keys.length(), 2)
  assert_true(keys[0] != keys[1])
}

///|
test "the token pill reads the same count as the composer's running row" {
  // Both render `usage_tokens`, and both can be on screen at once, so the
  // compaction has one owner (`@labels`) rather than a copy per view.
  inspect(token_label(12345), content="12.3k tokens")
}
