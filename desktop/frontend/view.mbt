///|
fn can_stop(conv : Conversation) -> Bool {
  conv.run is Open(..)
}

///|
fn token_label(tokens : Int) -> String {
  "\{@labels.compact_count(tokens)} tokens"
}

///|
/// One settings row: name and optional description on the left, the control
/// on the right. `stack=true` drops the control below the text at full
/// width instead, for free-form fields (URLs, keys) that a narrow right
/// column would squeeze.
fn setting_row(
  name : String,
  controls : Array[@html.Html],
  desc? : String,
  stack? : Bool = false,
) -> @html.Html {
  let text : Array[@html.Html] = [@html.div(class="setting-name", name)]
  if desc is Some(desc) && !desc.is_empty() {
    text.push(@html.div(class="setting-desc", desc))
  }
  @html.div(class=if stack { "setting-row stack" } else { "setting-row" }, [
    @html.div(class="setting-text", text),
    @html.div(class="setting-control", controls),
  ])
}

///|
/// A titled card of rows: an accent-tinted icon and heading above a bordered
/// surface, the design system's settings section. Shared with the Skills
/// page so the two pages read as siblings.
fn settings_group(
  icon_image : () -> @html.Html,
  title : String,
  rows : Array[@html.Html],
) -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(class="settings-group-head", [icon(icon_image), @html.h2(title)]),
    @html.div(class="settings-group-card", rows),
  ])
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
    open: model.select_menu == Some(self),
    toggle: dispatch(ToggleSelectMenu(self)),
    dismiss: dispatch(CloseSelectMenu),
    change,
    title: aria_label,
    aria_label,
    presentation: Setting,
  }.render()
}

///|
fn conversation_title(conv : Conversation) -> String {
  // Titles follow the committed user transcript.
  for item in conv.messages {
    if item.kind is User {
      // A prompt sent with chips titles by what was typed (or, chips alone,
      // by their labels) — never by the raw `<user_mentions>` envelope.
      let title = user_display_text(item.content).trim().to_owned()
      if !title.is_empty() {
        return title
      }
    }
  }
  let task = conv.task.trim().to_owned()
  if task.is_empty() {
    // The live draft text is component-local, so the root knows only that it
    // exists. Keep the row's pre-submit label truthful without mirroring the
    // text on every key; the durable User item supplies the real title.
    if conv.composer_draft_present {
      "New chat"
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
  // The row's status dot: pulsing while a run is in flight, then — when the
  // run finished off screen — settling into a solid dot (accent for success,
  // warn otherwise) until the conversation is opened (`Model::activate`
  // clears the mark).
  let run_mark = match conv {
    Some(conv) if conv.is_running() => @conversation.RunningMark
    Some(conv) if conv.unseen_finish && !active =>
      if conv.run is NoRun(ended=Some(RunFinished(Completed))) {
        @conversation.CompletedMark
      } else {
        @conversation.FailedMark
      }
    _ => @conversation.NoRunMark
  }
  // The row's own tooltip carries the worktree name, joined from the
  // registry (or the local binding while the first turn is still on its way
  // to the store).
  let title = if worktree is Some(name) {
    "\{session_id}\nRuns in worktree \{name}; archiving removes its checkout but keeps the branch for Repair"
  } else {
    session_id
  }
  {
    // The store placement rides in `root`: session ids may repeat across
    // project stores, and without it two same-id rows would collide on one
    // key in the sidebar's keyed container.
    id: @conversation.Id(
      source="openseek.live",
      channel=channel.uri_authority(),
      conversation=session_id,
      root?,
    ),
    title,
    label,
    nested,
    subrun,
    active,
    running,
    openable: true,
    worktree,
    // Archiving a running conversation would pull the durable record out
    // from under its engine, so the button waits for the turn to end.
    run_mark,
    trailing: if archivable && !running {
      [
        @conversation.Archive(
          title="Archive — tuck this chat away; its files stay where they are",
        ),
      ]
    } else {
      []
    },
    children,
  }
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
/// ordering the flat sidebar always had, applied per group. Conversations
/// worth keeping get a row, plus the one fresh "New chat" on screen; an empty
/// husk holding an unsent draft keeps its row because that row is the only
/// way back to the draft.
fn Model::push_group_component_inputs(
  self : Model,
  rows : Array[(RowStamp, @conversation.Input)],
  dev : DeviceState,
  workspace : @common.Uri,
  listed~ : (String) -> Bool,
  archived~ : (String) -> Bool,
) -> Unit {
  let composing = self.composing_new_chat()
  // Every row in this group shares the group's store placement; it becomes
  // the `root` half of each conversation's component id.
  let root = workspace.path
  for conv in self.conversations.rev_iter() {
    if conv.device != dev.channel ||
      conv.project() != workspace ||
      listed(conv.session_id) ||
      archived(conv.session_id) {
      continue
    }
    // A fresh worktree conversation knows its binding locally; once the
    // first turn is durable the registry mapping takes over.
    let worktree = if conv.worktree_name() is Some(name) {
      Some(name)
    } else {
      worktree_name_for(dev, workspace, conv.session_id)
    }
    let worth_keeping = conv.worth_keeping()
    let active = conv.device == self.focused &&
      conv.session_id == self.active_session
    if !worth_keeping && !(composing && active) {
      continue
    }
    rows.push(
      (
        // An in-memory conversation the durable listing does not hold yet is
        // this session's own work; it leads the stamped history below.
        ComposingNow,
        session_component_input(
          self,
          dev.channel,
          conv.session_id,
          if worth_keeping {
            conversation_title(conv)
          } else {
            "New chat"
          },
          nested=true,
          worktree?,
          root~,
        ),
      ),
    )
  }
  let durable : Array[@transcript.SessionListItem] = []
  for item in dev.sessions {
    if item.workspace == workspace && !archived(item.id) {
      durable.push(item)
    }
  }
  // Sub-run transcripts fold under the conversation that launched them: they
  // are that turn's evidence, not conversations of their own. They ride the
  // parent's component input, so their disclosure state lives in the
  // conversation component. A label follows the live conversation while it
  // is the one on screen (its title settles at the first send), and
  // otherwise comes from the host's listing.
  for tree in @transcript.session_tree(durable) {
    let parent_label = if self.find_conversation(dev.channel, tree.item.id)
      is Some(conv) &&
      dev.channel == self.focused &&
      tree.item.id == self.active_session {
      conversation_title(conv)
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
          nested=true,
          subrun=true,
          root~,
        ),
      )
    }
    let stamp = match tree.item.updated_at_ms {
      Some(ms) => ActiveAt(ms)
      None => Unstamped
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
          archivable=true,
          nested=true,
          worktree?=worktree_name_for(dev, workspace, tree.item.id),
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
  let keyed : Array[(Int, RowStamp, @conversation.Input)] = []
  for index, row in rows {
    keyed.push((index, row.0, row.1))
  }
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
  let listed = (id : String) => dev.sessions.iter().any(item => item.id == id)
  // An archived record has moved out of the live store, so the live list
  // normally cannot contain it; the filter covers the moment between the
  // archive reply and the list refetch that follows it.
  let archived = (id : String) => dev.archived.iter().any(item => item.id == id)
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
    let registered_projects : Array[String] = []
    for project in dev.projects {
      if @resource.path_for(project, dev.channel) is Some(path) {
        registered_projects.push(path)
      }
    }
    Some({
      channel: dev.channel,
      selected: self.screen is Codex,
      registered_projects,
    })
  } else {
    None
  }
  let projects : Array[@section.Entry] = []
  for path in dev.projects {
    let stamped : Array[(RowStamp, @conversation.Input)] = []
    self.push_group_component_inputs(stamped, dev, path, listed~, archived~)
    let mut codex_activation : String? = None
    if codex_context is Some(context) &&
      @resource.path_for(path, dev.channel) is Some(root) {
      if self.codex.project_draft(context, root) is Some(draft) {
        stamped.push((ComposingNow, draft))
      }
      for row in self.codex.project_conversations(context, root) {
        let stamp = match row.updated_at_ms {
          Some(ms) => ActiveAt(ms)
          None => Unstamped
        }
        stamped.push((stamp, row.input))
      }
      codex_activation = self.codex.project_activation(context, root)
    }
    let conversations = ordered_by_recency(stamped)
    let openseek_activation = activation(dev.active_project == Some(path))
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
        empty_label: Some("No chats yet"),
      }),
    )
  }
  if codex_context is Some(context) {
    // Codex threads in unregistered roots keep top-level rows at the end of
    // the section, as they did in the retired Codex section.
    for entry in self.codex.loose_entries(context) {
      projects.push(entry)
    }
  }
  let openseek_section_activation = activation(dev.active_project is Some(_))
  sections.push({
    id: @section.Id(source="openseek.projects", channel~),
    label: "Projects",
    initially_collapsed: false,
    activation: if openseek_section_activation is Some(_) {
      openseek_section_activation
    } else if codex_context is Some(context) && context.selected {
      self.codex.active_id()
    } else {
      None
    },
    action: Some({ title: "Add a project", disabled: false, }),
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
      @section.Conversation({
        id: @conversation.Id(
          source="openseek.archived",
          channel~,
          conversation=item.id,
          root=item.workspace.path,
        ),
        title: item.id,
        label: session_item_label(item),
        nested: false,
        subrun: false,
        active,
        running: false,
        openable: true,
        worktree: None,
        run_mark: @conversation.NoRunMark,
        trailing: [
          @conversation.Restore(
            title="Restore this conversation to the sidebar",
          ),
          @conversation.Delete(
            title="Permanently delete this archived conversation",
          ),
        ],
        children: [],
      }),
    )
  }
  if dev.channel == self.focused {
    for entry in self.codex.archived_sidebar_entries(dev.channel) {
      archived_entries.push(entry)
    }
  }
  sections.push({
    id: @section.Id(source="archived", channel~),
    label: if archived_entries.is_empty() {
      "Archived chats"
    } else {
      "Archived chats (\{archived_entries.length()})"
    },
    initially_collapsed: true,
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
    Some(dev) => self.sidebar_component_sections(dev)
    None => {
      match self.console {
        Some(console) =>
          match console.roster_sync {
            RosterLoading => notices.push("Loading device…")
            RosterFailed(message) => notices.push(message)
            RosterReady =>
              if console.roster.is_empty() {
                notices.push(
                  "No devices yet — open SeekMoon and sign in under Settings → Remote access.",
                )
              } else {
                notices.push("No online device — reconnecting…")
              }
          }
        None => ()
      }
      []
    }
  }
  // The footer's Update button tracks the download so its progress stays
  // visible from any screen.
  let update_label : String? = match self.update_ux {
    UpdateAvailable(installable=true, ..) | ConfirmingRestart(..) =>
      Some("Update")
    DownloadingUpdate(progress~, ..) => Some(progress.sidebar_label())
    RestartingForUpdate(..) => Some("Restarting…")
    _ => None
  }
  // The console's account row: who is signed in, a roster refresh, and the
  // sign-out — with the last account-level failure inline beneath it.
  let account : @sidebar.Account? = match self.console {
    Some(console) if console.auth is AuthSignedIn(login~, avatar~) =>
      Some({ login, avatar, busy: console.busy, notice: console.notice, })
    _ => None
  }
  {
    notices,
    sections,
    update_label,
    update_enabled: self.update_ux is UpdateAvailable(..),
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
  self : Conversation,
  dispatch : @cmd.Emit[Msg],
) -> @html.Html {
  @html.div(class="composer archived-read-only", [
    @html.div(class="archived-read-only-bar", [
      @html.span(
        class="archived-read-only-text",
        "Archived conversation · Read only",
      ),
      @html.button(
        class="archived-read-only-restore",
        type_="button",
        title="Restore this conversation before continuing it",
        on_click=dispatch(UnarchiveSession(self.device, self.session_id)),
        "Restore",
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
    setting_row(
      "Status",
      [],
      desc="\{codex.connection_label()} · \{codex.account_label()}",
    ),
  ]
  if codex.signed_in() {
    rows.push(
      setting_row(
        "Account",
        [
          @html.button(
            class="secondary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::logout())),
            "Sign out",
          ),
        ],
        desc="Signing out removes the ChatGPT credentials this desktop's Codex uses.",
      ),
    )
  } else if codex.sign_in_required() {
    rows.push(
      setting_row(
        "Sign in",
        [
          @html.button(
            class="primary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::login())),
            "Sign in with ChatGPT",
          ),
        ],
        desc="Codex conversations run with your ChatGPT account.",
      ),
    )
  }
  if codex.pending_auth_url() is Some(url) {
    rows.push(
      setting_row(
        "Sign-in page",
        [
          // The shared external-link listener keeps the desktop webview in
          // place and hands this URL to the system browser.
          @html.a(
            class="setting-link",
            href=url,
            target=Blank,
            rel="noopener noreferrer",
            [icon(icon_link_external), @html.span("Open")],
          ),
          @html.button(
            class="secondary",
            disabled=codex.is_busy(),
            on_click=dispatch(Codex(channel~, @codex.Msg::cancel_login())),
            "Cancel sign-in",
          ),
        ],
        desc="Finish signing in on the browser page, or cancel the attempt.",
      ),
    )
  }
  rows.push(
    setting_row(
      "Configuration",
      [
        @html.button(
          class="secondary",
          on_click=dispatch(OpenCodexConfig),
          "Open config.toml",
        ),
      ],
      desc="config.toml in this desktop's Codex home, created empty if missing. The app-server reads it at startup, so edits apply after the desktop restarts.",
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
  match model.remote_access {
    None =>
      rows.push(setting_row("Remote control", [], desc="Checking sign-in…"))
    Some(status) =>
      if status.managed_by_env {
        rows.push(
          setting_row(
            "Remote control",
            [],
            desc="Configured through the environment (OPENSEEK_RELAY_URL); sign-in is disabled.",
          ),
        )
      } else if status.user_login is Some(login) {
        let state = if status.connected {
          "online — reachable from your browser"
        } else {
          "connecting to the relay…"
        }
        rows.push(
          setting_row(
            "Signed in as",
            [
              @html.button(
                class="secondary",
                on_click=dispatch(RemoteDisconnectClicked),
                "Disconnect",
              ),
            ],
            desc="@\{login} — \{state}",
          ),
        )
        if status.device_url is Some(url) {
          let name = status.device_name.unwrap_or("this machine")
          rows.push(
            setting_row(
              "Device page",
              [
                // The shared external-link listener keeps the desktop webview
                // in place and hands this URL to the system browser.
                @html.a(
                  class="setting-link",
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  [icon(icon_link_external), @html.span("Open")],
                ),
              ],
              desc="\{name} — open \{url} in a signed-in browser.",
            ),
          )
        }
      } else {
        let target = match status.server_url {
          Some(server) =>
            "Registers this machine at \{server} so your browser can drive it."
          None =>
            "Registers this machine so your browser can drive it through the relay."
        }
        let controls : Array[@html.Html] = [
          @html.button(
            class="primary",
            disabled=model.remote_connecting,
            on_click=dispatch(RemoteConnectClicked),
            if model.remote_connecting {
              "Waiting for the browser…"
            } else {
              "Connect with GitHub"
            },
          ),
        ]
        // Appended after the stable Connect button, so its appearance
        // never re-seats that node.
        if model.remote_connecting {
          controls.push(
            @html.button(
              class="secondary",
              on_click=dispatch(RemoteCancelClicked),
              "Cancel",
            ),
          )
        }
        rows.push(setting_row("Sign in", controls, desc=target))
      }
  }
  if model.remote_error is Some(message) {
    rows.push(setting_row("Problem", [], desc=message))
  }
  rows
}

///|
#warnings("-alert_unstable")
test "remote access device page renders an external link" {
  let model = {
    ..test_model(),
    remote_access: Some({
      server_url: Some("https://relay.example"),
      connected: true,
      managed_by_env: false,
      user_login: Some("octocat"),
      device_name: Some("My Mac"),
      device_url: Some("https://relay.example/d/d_abc/"),
    }),
  }
  let rendered = @html.div(remote_access_rows(test_dispatch(), model))
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("href=\"https://relay.example/d/d_abc/\""))
  assert_true(markup.contains("target=\"_blank\""))
  assert_true(markup.contains("rel=\"noopener noreferrer\""))
  assert_true(markup.contains("class=\"setting-link\""))
  assert_true(markup.contains("<span>Open</span>"))
}

///|
/// The Settings check-for-updates row: the last check's outcome — status
/// text, or the accent Update button once an installable release is found —
/// on the left, the Check button on the right.
fn update_check_controls(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let controls : Array[@html.Html] = []
  match model.update_ux {
    UpdateUnknown => ()
    CheckingForUpdate =>
      controls.push(@html.span(class="update-status", "Checking…"))
    UpToDate =>
      controls.push(@html.span(class="update-status", "You are up to date."))
    UpdateAvailable(version~, installable~) =>
      if installable {
        controls.push(
          @html.button(
            class="primary",
            on_click=dispatch(UpdateClicked),
            "Update to \{version}",
          ),
        )
      } else {
        controls.push(
          @html.span(
            class="update-status",
            "\{version} is available, but this build cannot install updates.",
          ),
        )
      }
    ConfirmingRestart(version~) =>
      // The interrupt modal is up over this row; keep the button visible
      // behind it so the row does not blink while the user decides.
      controls.push(@html.button(class="primary", "Update to \{version}"))
    DownloadingUpdate(version~, progress~) => {
      let (fill_class, fill_style) = match progress.percentage() {
        Some(percent) =>
          ("update-progress-fill", ["--progress-width: \{percent}%"])
        None => ("update-progress-fill indeterminate", [])
      }
      controls.push(
        @html.div(class="update-progress", [
          @html.span(class="update-status", progress.status_text(version)),
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
        @html.span(class="update-status", "Restarting into \{version}…"),
      )
    UpdateCheckFailed(message~) =>
      controls.push(@html.span(class="update-status update-error", message))
  }
  controls.push(
    @html.button(
      class="secondary",
      disabled=model.update_ux
        is (CheckingForUpdate | DownloadingUpdate(..) | RestartingForUpdate(..)),
      on_click=dispatch(CheckForUpdates),
      "Check for updates",
    ),
  )
  controls
}

///|
fn provider_hint(provider : ApiProvider) -> String {
  match provider {
    Deepseek => "Requests go straight to api.deepseek.com with your key."
    Glm => "Requests go straight to api.z.ai with your key."
    Custom => "Any OpenAI-compatible chat-completions URL; key optional."
  }
}

///|
/// The bring-your-own-key guide shown at the top of the API group while the
/// configured endpoint is not usable. SeekMoon ships no hosted API: every
/// request goes straight from this machine to the user's own model
/// provider, so a key (official) or an endpoint URL (custom) must be
/// configured first. The steps follow the selected provider.
fn byok_setup_guide(provider : ApiProvider) -> @html.Html {
  let step = fn(index : Int, text : String) -> @html.Html {
    @html.div(class="setup-guide-step", [
      @html.span(class="setup-guide-index", index.to_string()),
      @html.span(class="setup-guide-text", text),
    ])
  }
  let steps : Array[@html.Html] = match provider {
    Deepseek =>
      [
        step(1, "Open platform.deepseek.com and sign in."),
        step(2, "Create an API key under API Keys."),
        step(3, "Paste it into the DeepSeek API key field below and save."),
      ]
    Glm =>
      [
        step(1, "Open z.ai and sign in."),
        step(2, "Create an API key under API Keys."),
        step(3, "Paste it into the GLM API key field below and save."),
      ]
    Custom =>
      [
        step(
          1, "Start an OpenAI-compatible endpoint (Ollama, LM Studio, a proxy…).",
        ),
        step(2, "Enter its chat-completions URL below."),
        step(3, "Add the endpoint's key if it requires one."),
      ]
  }
  @html.div(
    class="setup-guide",
    [
      @html.p(
        "SeekMoon does not provide a hosted API. Requests go straight from this machine to your own model provider, billed to your account. Your API key is stored only on this machine — SeekMoon never reads it.",
      ),
      @html.div(class="setup-guide-steps", steps),
      ..if provider is Deepseek {
        [
          @html.a(
            class="setting-link",
            href="https://platform.deepseek.com/api_keys",
            target=Blank,
            rel="noopener noreferrer",
            [
              icon(icon_link_external),
              @html.span("platform.deepseek.com → API Keys"),
            ],
          ),
        ]
      },
      ..if provider is Glm {
        [
          @html.a(
            class="setting-link",
            href="https://z.ai/manage-apikey/apikey-list",
            target=Blank,
            rel="noopener noreferrer",
            [icon(icon_link_external), @html.span("z.ai → API Keys")],
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
      [byok_setup_guide(model.api_provider)]
    },
    setting_row(
      "API endpoint",
      [
        ApiProviderMenu.setting_control(
          dispatch,
          model,
          id="api-provider-select",
          options=[
            { value: "deepseek", label: "DeepSeek official (your API key)", },
            { value: "glm", label: "Z.AI GLM (your API key)", },
            { value: "custom", label: "Custom URL", },
          ],
          selected=model.api_provider.wire(),
          aria_label="API endpoint",
          change=dispatch.map(value => ProviderChanged(value)),
          disabled=!settings_loaded,
        ),
      ],
      desc=provider_hint(model.api_provider),
    ),
  ]
  if model.api_provider is Custom {
    rows.push(
      setting_row(
        "Endpoint URL",
        [
          @html.input(
            input_type=@html.InputType::Text,
            value=model.custom_api_url,
            placeholder="https://host/chat/completions",
            on_input=dispatch.map(value => CustomApiUrlChanged(value)),
            attrs=@html.Attrs::build()
              .aria_label("Endpoint URL")
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
    let key_saved = match model.api_provider {
      Deepseek => model.deepseek_key_saved
      Glm => model.glm_key_saved
      Custom => model.custom_key_saved
    }
    rows.push(
      setting_row(
        match model.api_provider {
          Deepseek => "DeepSeek API key"
          Glm => "GLM API key"
          Custom => "Custom API key"
        },
        [
          @html.input(
            input_type=@html.InputType::Password,
            value=model.setup_api_key,
            placeholder=if key_saved {
              "saved — enter to replace"
            } else {
              "sk-..."
            },
            on_input=dispatch.map(value => SetupApiKeyChanged(value)),
            attrs=@html.Attrs::build()
              .aria_label("API key")
              .data_set("focus-owner", "")
              .disabled(!settings_loaded),
          ),
          @html.button(
            // The id is layout only (grid placement); the fill is the
            // shared primary style.
            id="saveApiKey",
            class="primary",
            disabled=!settings_loaded || model.setup_api_key.is_blank(),
            on_click=dispatch(SaveApiKey),
            "Save API key",
          ),
        ],
        desc="Stored on this machine and sent only with API requests. SeekMoon never reads it.",
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
  let settings_loaded = model.host_settings_loaded()
  let ready = model.api_ready()
  // The model is not here: it belongs to a conversation, not to the app, and
  // is picked on the composer's chip.
  let engine_rows : Array[@html.Html] = [
    setting_row(
      "Max steps",
      [
        @html.input(
          input_type=@html.InputType::Number,
          value=model.max_steps,
          placeholder="1000",
          on_input=dispatch.map(value => MaxStepsChanged(value)),
          attrs=@html.Attrs::build()
            .aria_label("Max steps")
            .data_set("focus-owner", ""),
        ),
      ],
      desc="How many agent steps one turn may take.",
    ),
  ]
  let api_rows : Array[@html.Html] = api_settings_rows(dispatch, model)
  let groups : Array[@html.Html] = [
    settings_group(icon_sparkle, "Engine", engine_rows),
    settings_group(icon_key, "API", api_rows),
    settings_group(
      icon_extensions,
      "Codex",
      codex_account_rows(dispatch, model),
    ),
    settings_group(icon_layout, "Interface", [
      setting_row(
        "Theme",
        [
          ThemeMenu.setting_control(
            dispatch,
            model,
            id="theme-select",
            options=[
              { value: "system", label: "System", },
              { value: "light", label: "Light", },
              { value: "dark", label: "Dark", },
            ],
            selected=model.theme.wire(),
            aria_label="Theme",
            change=dispatch.map(value => ThemeChanged(value)),
          ),
        ],
        desc="Used by the app, editor, and terminal. System follows the OS appearance.",
      ),
      setting_row(
        "Monospace font",
        [
          FontMenu.setting_control(
            dispatch,
            model,
            id="font-select",
            options=[
              { value: "system-mono", label: "System monospace", },
              { value: "geist-mono", label: "Geist Mono", },
              { value: "menlo", label: "Menlo", },
            ],
            selected=model.app_font.wire(),
            aria_label="Monospace font",
            change=dispatch.map(value => FontChanged(value)),
          ),
        ],
        desc="Used by code, the editor, and the terminal.",
      ),
      setting_row(
        "Font size",
        [
          FontSizeMenu.setting_control(
            dispatch,
            model,
            id="font-size-select",
            options=[
              { value: "small", label: "Small (13px)", },
              { value: "medium", label: "Medium (14px)", },
              { value: "large", label: "Large (15px)", },
            ],
            selected=model.app_font_size.wire(),
            aria_label="Font size",
            change=dispatch.map(value => FontSizeChanged(value)),
          ),
        ],
        desc="Scales app text; code uses a visually matched monospace size.",
      ),
      setting_row(
        "Notification corner",
        [
          NotificationCornerMenu.setting_control(
            dispatch,
            model,
            id="notification-corner-select",
            options=[
              { value: "bottom-right", label: "Bottom right", },
              { value: "bottom-left", label: "Bottom left", },
              { value: "top-right", label: "Top right", },
              { value: "top-left", label: "Top left", },
            ],
            selected=model.notification_corner.wire(),
            aria_label="Notification corner",
            change=dispatch.map(value => NotificationCornerChanged(value)),
          ),
        ],
        desc="Where error notifications pop up.",
      ),
      setting_row(
        "File tree layout",
        [
          TreeLayoutMenu.setting_control(
            dispatch,
            model,
            id="tree-layout-select",
            options=[
              { value: "right-sidebar", label: "Right sidebar", },
              { value: "bottom-panel", label: "Bottom panel", },
            ],
            selected=model.tree_layout.wire(),
            aria_label="File tree layout",
            change=dispatch.map(value => TreeLayoutChanged(value)),
          ),
        ],
        desc="Where the editor panel docks its file tree.",
      ),
    ]),
  ]
  // Self-update swaps the bundle under the desktop process, and the relay
  // sign-in registers the machine the host runs on; from a browser both
  // sections could only break things for whoever is at the machine.
  if model.is_desktop {
    groups.push(
      settings_group(
        icon_link_external,
        "Remote access",
        remote_access_rows(dispatch, model),
      ),
    )
    groups.push(
      settings_group(icon_sync, "Updates", [
        setting_row(
          "Check for updates",
          update_check_controls(dispatch, model),
          desc="Current version: \{model.app_version}.",
        ),
      ]),
    )
  }
  @html.section(class="settings-page", [
    @html.div(class="settings-page-inner", [
      @html.div(class="settings-header", [
        @html.div(class="page-eyebrow", "Preferences"),
        @html.h1("Settings"),
        @html.div(
          class="settings-subtitle",
          if !settings_loaded {
            "Loading runtime settings…"
          } else if ready {
            "Runtime settings for the SeekMoon engine."
          } else {
            match model.api_provider {
              Deepseek => "Enter a DeepSeek API key to start."
              Glm => "Enter a GLM API key to start."
              Custom => "Enter a chat-completions endpoint URL to start."
            }
          },
        ),
      ]),
      @html.div(class="settings", groups),
    ]),
  ])
}

///|
/// One workspace's settings page, shown in the main area like Settings and
/// reached from the project row's "…" menu. These settings affect future
/// worktree lifecycle operations; the composer's chip remains a per-chat
/// launch-mode override and never writes back here.
fn workspace_settings_page(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  workspace : @common.Uri,
) -> @html.Html {
  // The settings mirror for this workspace; absent until the first
  // authoritative read on this connection lands. Until then, the controls
  // stay disabled rather than pretending a choice would stick.
  let row = match model.device_state(channel) {
    Some(dev) => dev.workspace_settings_row(workspace)
    None => None
  }
  let worktree_mode = row is Some(row) && row.worktree_mode
  // Missing is the historical behavior, but the disabled control makes it
  // clear that no authoritative workspace snapshot has landed yet.
  let checkout_submodules = row is None ||
    (row is Some(row) && row.checkout_submodules)
  let submodule_checkout_timeout_seconds = match row {
    Some(row) => row.submodule_checkout_timeout_seconds
    None => DefaultWorkspaceSubmoduleCheckoutTimeoutSeconds
  }
  let conversation_rows : Array[@html.Html] = [
    setting_row(
      "New chats",
      [
        WorkspaceDefaultModeMenu.setting_control(
          dispatch,
          model,
          id="workspace-default-mode-select",
          options=[
            { value: "local", label: "Local", },
            { value: "worktree", label: "Worktree", },
          ],
          selected=if worktree_mode { "worktree" } else { "local" },
          aria_label="New chats",
          change=dispatch.map(value => {
            WorkspaceDefaultModeChosen(channel, workspace, value)
          }),
          disabled=row is None,
        ),
      ],
      desc="Where a new chat starts: the workspace itself, or a fresh git worktree bound to that chat. The composer's chip still changes a single chat.",
    ),
  ]
  let worktree_rows : Array[@html.Html] = [
    setting_row(
      "Submodules",
      [
        WorkspaceSubmodulesMenu.setting_control(
          dispatch,
          model,
          id="workspace-submodules-select",
          options=[
            { value: "checkout", label: "Initialize", },
            { value: "skip", label: "Leave uninitialized", },
          ],
          selected=if checkout_submodules { "checkout" } else { "skip" },
          aria_label="Submodules in worktrees",
          change=dispatch.map(value => {
            WorkspaceSubmodulesChosen(channel, workspace, value)
          }),
          disabled=row is None,
        ),
      ],
      desc="For new or repaired worktrees in this workspace, mirror the top-level submodules already initialized in its main checkout.",
    ),
    setting_row(
      "Checkout timeout",
      [
        WorkspaceSubmoduleTimeoutMenu.setting_control(
          dispatch,
          model,
          id="workspace-submodule-timeout-select",
          options=[
            { value: "5", label: "5 seconds", },
            { value: "10", label: "10 seconds", },
            { value: "30", label: "30 seconds", },
            { value: "60", label: "60 seconds", },
          ],
          selected=submodule_checkout_timeout_seconds.to_string(),
          aria_label="Submodule checkout timeout",
          change=dispatch.map(value => {
            WorkspaceSubmoduleTimeoutChosen(channel, workspace, value)
          }),
          disabled=row is None,
        ),
      ],
      desc="Stop initializing submodules if Git has not finished within this time.",
    ),
  ]
  @html.section(class="settings-page", [
    @html.div(class="settings-page-inner", [
      @html.div(class="settings-header", [
        @html.div(class="page-eyebrow", "Workspace"),
        @html.h1(@resource.label(workspace)),
        @html.div(class="settings-subtitle", workspace.path),
      ]),
      @html.div(class="settings", [
        settings_group(icon_worktree, "Conversations", conversation_rows),
        settings_group(icon_worktree, "Worktrees", worktree_rows),
      ]),
    ]),
  ])
}

///|
#warnings("-alert_unstable")
test "settings and the browser address bar declare form focus ownership" {
  let dispatch = test_dispatch()
  let settings_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(settings_page(dispatch, test_model()))
  })
  // Settings use the same app-owned button/listbox control as the composer;
  // no platform select may reintroduce a native popup on one page only.
  assert_false(settings_markup.contains("<select"))
  assert_true(
    settings_markup.contains("class=\"custom-select setting-select\""),
  )
  assert_true(settings_markup.contains("aria-haspopup=\"listbox\""))
  // Settings fields own their existing borders directly; there is no nested
  // target that could draw a second frame.
  assert_true(settings_markup.contains("data-focus-owner=\"\""))
  assert_false(settings_markup.contains("data-focus-target=\"\""))
  let address_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @preview.toolbar_view(
        { url: None, input: "", title: "", loading: false, failure: None, },
        {
          input: dispatch.map(value => BrowserAddressEdited(value)),
          submit: @cmd.none,
          back: @cmd.none,
          forward: @cmd.none,
          reload: @cmd.none,
          open_external: @cmd.none,
        },
      ),
    )
  })
  assert_true(address_markup.contains("class=\"browser-address\""))
  assert_true(address_markup.contains("data-focus-owner=\"\""))
  assert_false(address_markup.contains("data-focus-target=\"\""))
  // Every rendered form element must choose one side of the contract. A
  // composite also has a separate owner on its wrapper, which is why counting
  // markers alone would not prove that the nested control was marked.
  for markup in [settings_markup, address_markup] {
    for tag in ["<input", "<textarea"] {
      let parts = markup.split(tag).collect()
      for index, part in parts {
        if index > 0 {
          guard part.split_once(">") is Some((opening, _)) else {
            fail("unterminated form element in rendered markup")
          }
          assert_true(
            opening.contains("data-focus-owner") ||
            opening.contains("data-focus-target"),
          )
        }
      }
    }
  }
}

///|
#warnings("-alert_unstable")
test "workspace settings render only custom selects" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      workspace_settings_page(dispatch, test_model(), Local, workspace),
    )
  })
  assert_false(markup.contains("<select"))
  for
    id in [
      "workspace-default-mode-select", "workspace-submodules-select", "workspace-submodule-timeout-select",
    ] {
    assert_true(markup.contains("id=\"\{id}\""))
  }
}

///|
#warnings("-alert_unstable")
test "an archived transcript renders no live composer controls" {
  let dispatch = test_dispatch()
  let conv = { ..test_conversation(), record: ArchivedRecord, }
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(conv.archived_read_only_view(dispatch))
  })
  assert_true(markup.contains("Archived conversation · Read only"))
  assert_true(markup.contains(">Restore</button>"))
  assert_false(markup.contains("<textarea"))
  assert_false(markup.contains("id=\"send\""))
  assert_false(markup.contains("id=\"stop\""))
}

///|
#warnings("-alert_unstable")
test "the topbar exports only a durable local conversation" {
  let dispatch = test_dispatch()
  fn markup(model : Model, conv : Conversation) {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(
        topbar_view(dispatch, @cmd.none, @cmd.none, model, conv),
      )
    })
  }

  let model = { ..test_model(), is_desktop: true, }
  let empty = test_conversation()
  assert_false(markup(model, empty).contains("title=\"Export conversation\""))
  let durable = {
    ..empty,
    messages: [
      { kind: User, content: "Export me", ts: None, sequence: Some(1), },
    ],
  }
  assert_true(markup(model, durable).contains("title=\"Export conversation\""))
}

///|
/// The two halves of the top-level fork, from the model each one stands for.
#warnings("-alert_unstable")
test "onboarding stands in for the chat until a project holds one" {
  let dispatch = test_dispatch()
  fn markup(model : Model) {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(onboarding_view(dispatch, model))
    })
  }

  // Connected with no project: attaching one is the only way forward, so it
  // is the only thing offered.
  let empty = { ..test_model(), conversations: [], active_session: "", }
  let bare = empty.with_dev(dev => { ..dev, projects: [], worktrees: [], })
  assert_true(bare.active_conversation() is None)
  assert_true(markup(bare).contains("Add a project"))
  // Connected with projects but between conversations: the rotation that
  // opens one is a message away, and offering to add a project here would
  // answer a question the user did not ask.
  assert_true(empty.active_conversation() is None)
  assert_false(markup(empty).contains("Add a project"))
  // Before the bridge answers, this page knows nothing about the host's
  // projects and says only that.
  let connecting = bare.with_dev(dev => { ..dev, bridge: Connecting, })
  assert_true(markup(connecting).contains("Connecting"))
  assert_false(markup(connecting).contains("Add a project"))
  // With a conversation on screen the fork takes its other branch.
  assert_true(test_model().active_conversation() is Some(_))
}

///|
fn run_indicator(model : Model, conv : Conversation) -> @html.Html {
  let status = model.display_status()
  let label = status.label()
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
    "session \{conv.session_id}\nworkspace \{cwd.path}"
  } else {
    "session \{conv.session_id}"
  }
}

///|
/// Top bar: conversation identity on the left (session id and workspace in
/// the tooltip), live run state on the right — these are per-conversation
/// runtime facts, not settings, so they live here rather than in the
/// settings popup.
fn topbar_view(
  dispatch : @cmd.Emit[Msg],
  toggle_terminal : @cmd.Cmd,
  toggle_right_panel : @cmd.Cmd,
  model : Model,
  conv : Conversation,
) -> @html.Html {
  let items : Array[@html.Html] = []
  // The sidebar toggle rides the window's left edge. While the sidebar is open
  // it lives in the sidebar's own header; only when the sidebar is closed does
  // it fall back to the topbar's left, so it holds the same screen position
  // either way (the same trick the right-panel toggle uses on the right edge).
  if !model.sidebar_open {
    items.push(
      @html.button(
        class="topbar-toggle",
        title="Show sidebar",
        on_click=dispatch(ToggleSidebar),
        icon(icon_layout_sidebar_left),
      ),
    )
  }
  items.push(
    @html.span(
      class="topbar-title",
      title=session_tooltip(model, conv),
      conversation_title(conv),
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
    items.push(@html.span(class="pill", token_label(conv.turn.usage_tokens)))
  }
  if conv.watcher_status is Some(status) {
    items.push(@html.span(class="pill", "moon_check \{status}"))
  }
  // Export is a native-window operation and the visualizer consumes durable
  // OpenSeek JSONL. Remote-device conversations and fresh drafts therefore do
  // not offer a button that their host cannot fulfill.
  if model.is_desktop && conv.device is Local && !conv.messages.is_empty() {
    items.push(
      @html.button(
        class="panel-toggle",
        title="Export conversation",
        on_click=SessionExport::{
          channel: conv.device,
          session: conv.session_id,
          workspace,
          title: conversation_title(conv),
          archived: conv.is_archived_read_only(),
        }.command(dispatch),
        icon(icon_chat_export),
      ),
    )
  }
  // A browser terminal is rendered locally but its PTY lives on the focused
  // remote device, reached through that device's WebSocket channel.
  items.push(
    @html.button(
      class=if model.terminal.is_open() {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
      title=if model.terminal.is_open() {
        "Hide terminal (Ctrl+`)"
      } else {
        "Show terminal (Ctrl+`)"
      },
      on_click=toggle_terminal,
      icon(icon_terminal),
    ),
  )
  // Rightmost: the toggle for the whole right-hand panel — only while the
  // panel is closed; an open panel carries the toggle at the right edge of
  // its breadcrumb instead, keeping this bar uncrowded. Both spots hug the
  // window's right edge, so the toggle stays put as the panel opens/closes.
  if !model.right_panel_open {
    items.push(
      @html.button(
        class="panel-toggle",
        title="Show panel",
        on_click=toggle_right_panel,
        icon(icon_layout_sidebar_right),
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
/// action offered — the sidebar's own "Add a project" opens the same picker.
fn onboarding_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let card : Array[@html.Html] = [@html.h2("Open a project")]
  match (model.bridge_state(), model.focused_device()) {
    (Connected, Some(dev)) if dev.projects.is_empty() => {
      card.push(
        @html.p(
          "SeekMoon works inside a project directory. Add one and its first chat opens here.",
        ),
      )
      card.push(
        @html.button(
          class="primary",
          type_="button",
          on_click=dispatch(PickProject(dev.channel)),
          "Add a project",
        ),
      )
    }
    // A connected device with projects is between conversations: the session
    // rotation that opens one is a message away.
    (Connected, Some(_)) => card.push(@html.p("Opening a chat…"))
    // Until the bridge answers, this page knows nothing about the host's
    // projects. Offering to add one here would be a guess that the very next
    // message contradicts.
    _ => card.push(@html.p("Connecting to this device…"))
  }
  @html.section(class="onboarding", [@html.div(class="onboarding-card", card)])
}

///|
/// Skills and Settings have no topbar, so while the sidebar is closed they
/// float their own reopen button at the sidebar toggle's screen position —
/// without it the sidebar, their only way back to any other screen, would be
/// unrecoverable.
fn page_with_toggle(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  page : @html.Html,
) -> Array[@html.Html] {
  if model.sidebar_open {
    [page]
  } else {
    [
      @html.button(
        class="topbar-toggle page-sidebar-toggle",
        title="Show sidebar",
        on_click=dispatch(ToggleSidebar),
        icon(icon_layout_sidebar_left),
      ),
      page,
    ]
  }
}

///|
/// The console's full-screen gate. A missing `?device=` stops before sign-in;
/// authentication gets its own progress/retry states, and a signed-in page
/// stays here until its one query-selected device is available.
fn console_gate_view(
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
              None => "Checking sign-in…"
            },
          ),
        )
        if console.notice is Some(_) {
          card.push(
            @html.button(
              class="primary",
              on_click=dispatch(Console(RefreshClicked)),
              "Try again",
            ),
          )
        }
      }
      AuthSignedOut => {
        card.push(@html.h2("Sign in"))
        card.push(@html.p("Access this SeekMoon device from your browser."))
        card.push(
          @html.a(
            class="portal-button-link",
            href=console.login_url(),
            "Sign in with GitHub",
          ),
        )
      }
      AuthSignedIn(..) =>
        match console.roster_sync {
          RosterLoading => card.push(@html.p("Checking device…"))
          RosterFailed(message) => {
            card.push(@html.h2("Can't load device"))
            card.push(@html.p(message))
            card.push(
              @html.button(
                class="primary",
                on_click=dispatch(Console(RefreshClicked)),
                "Try again",
              ),
            )
          }
          RosterReady => {
            let mut selected : DeviceMeta? = None
            for meta in console.roster {
              if meta.id == id {
                selected = Some(meta)
                break
              }
            }
            if selected is Some(meta) {
              if meta.online {
                card.push(@html.h2("Connecting to \{meta.name}…"))
                card.push(@html.p("Waiting for this device's connection."))
              } else {
                card.push(@html.h2("\{meta.name} is offline"))
                card.push(@html.p("Bring this device online, then refresh."))
              }
            } else {
              card.push(@html.h2("Device unavailable"))
              card.push(
                @html.p(
                  "This device is not available to the signed-in account.",
                ),
              )
            }
            card.push(
              @html.button(
                class="primary",
                on_click=dispatch(Console(RefreshClicked)),
                "Refresh",
              ),
            )
          }
        }
    }
  } else {
    card.push(@html.h2("Device link required"))
    card.push(
      @html.p(
        "Open this page from Remote access in SeekMoon so the URL identifies one device.",
      ),
    )
  }
  // Every signed-in gate hides the sidebar's account controls. Keep the
  // account escape hatch here once, independent of why device access is gated.
  if console.auth is AuthSignedIn(..) {
    card.push(
      @html.button(
        class="secondary",
        disabled=console.busy,
        on_click=dispatch(Console(SignOutClicked)),
        if console.busy {
          "Signing out…"
        } else {
          "Sign out"
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
/// Root shell classes keep platform chrome geometry explicit in CSS. Only the
/// native Apple window uses Proton's left-side traffic-light overlay; browser
/// pages and non-Apple desktop shells retain the ordinary header insets.
fn app_shell_class(sidebar_open : Bool, native_apple_titlebar : Bool) -> String {
  let classes : Array[String] = ["app"]
  if !sidebar_open {
    classes.push("sidebar-collapsed")
  }
  if native_apple_titlebar {
    classes.push("native-apple-titlebar")
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
  quick_open_html : @html.Html,
  skills_html : @html.Html,
) -> @html.Html {
  // A browser page is gated on both its relay session and its required
  // query-selected device. Until both exist, the console frame — sidebar,
  // composer, overlays — stays unbuilt and inert Local cannot receive UI work.
  if model.console is Some(console) &&
    (
      console.page_device is None ||
      !(console.auth is AuthSignedIn(..)) ||
      model.focused_device() is None
    ) {
    return console_gate_view(dispatch, console)
  }
  let active_file_ctx = file_ctx(model)
  // Panel state survives page switches, but a Codex page only exposes it
  // after a real task supplies the identity (and, for files, a cwd) needed by
  // the host operation. Selecting a task makes an already-open panel reappear
  // in that task's workspace.
  let file_panel_visible = model.right_panel_open &&
    (
      model.screen is Chat ||
      (
        model.screen is Codex &&
        active_file_ctx.placement is Some(placement) &&
        placement.checkout_root() is Some(_)
      )
    )
  let terminal_panel_visible = model.terminal_panel_visible()
  // Pages without their own topbar still paint beneath the native overlay.
  // Mark their main element so the document-level double-click gesture can
  // treat only its otherwise-empty top edge as window chrome.
  let window_titlebar_page = match model.screen {
    Chat => model.active_conversation() is None
    Skills | Settings | WorkspaceSettings(..) => true
    Codex => false
  }
  let content = match model.screen {
    // The one fork that decides what the conversation column is. A chat needs
    // a conversation, and a conversation needs a project to work in, so with
    // none on screen — the registry has not arrived, or no project is
    // attached — the column is onboarding instead. Everything below this
    // point in the Chat branch has both.
    Chat =>
      match model.active_conversation() {
        None =>
          page_with_toggle(dispatch, model, onboarding_view(dispatch, model))
        Some(conv) =>
          [
            topbar_view(
              dispatch, toggle_terminal, toggle_right_panel, model, conv,
            ),
            transcript_html,
            if conv.is_archived_read_only() {
              conv.archived_read_only_view(dispatch)
            } else {
              composer_html
            },
          ]
      }
    Codex =>
      model.codex.page(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        model.focused,
        model.sidebar_open,
        terminal_panel_visible,
        file_panel_visible,
        @codex.PageActions::{
          toggle_sidebar: dispatch(ToggleSidebar),
          toggle_terminal,
          toggle_files: toggle_right_panel,
          workspace_label: workspace => @resource.label(workspace),
          transcript: transcript_html,
          composer: codex_composer_html,
        },
      )
    Skills => page_with_toggle(dispatch, model, skills_html)
    Settings =>
      page_with_toggle(dispatch, model, settings_page(dispatch, model))
    WorkspaceSettings(channel~, workspace~) =>
      page_with_toggle(
        dispatch,
        model,
        workspace_settings_page(dispatch, model, channel, workspace),
      )
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
  let children : Array[@html.Html] = [
    sidebar_html,
    @html.div(class=content_class, [
      @html.main_(
        class=if window_titlebar_page { "window-titlebar-page" } else { "" },
        content,
      ),
      right_panel_html,
      terminal_html,
    ]),
  ]
  // On the narrow layout the open sidebar is a drawer over the content; the
  // backdrop dims the page behind it and a tap there closes it. Appended
  // after the stable shell children so toggling never re-keys them.
  if model.narrow && model.sidebar_open {
    children.push(
      @html.div(
        class="sidebar-backdrop",
        on_click=dispatch(ToggleSidebar),
        @html.nothing,
      ),
    )
  }
  // The toast stack floats over everything (position: fixed), so appending
  // it last never shifts the layout; skipping it entirely while empty keeps
  // the corner clickable.
  if model.notifications.length() > 0 {
    children.push(notifications_view(dispatch, model))
  }
  // The interrupt-confirmation modal floats the same way, above the toasts.
  if model.update_ux is ConfirmingRestart(version~) {
    children.push(update_confirm_modal(dispatch, version))
  }
  // The API-setup modal floats above the toasts like the other modals: it
  // owns the screen until the user answers it or a usable endpoint arrives.
  if model.api_setup_open {
    children.push(api_setup_modal(dispatch, model))
  }
  if model.project_picker is Some(picker) {
    children.push(
      @project_picker.view(dispatch.map(msg => ProjectPicker(msg)), picker),
    )
  }
  if model.archive_confirm is Some(confirm) {
    children.push(
      @composer.WorktreeArchiveDialog::{
        refusal: confirm.refusal,
        conversation_noun: "chat",
        cancel: dispatch(CancelArchiveDiscard),
        confirm: dispatch(ConfirmArchiveDiscard),
      }.render(),
    )
  }
  if model.archived_delete_confirm is Some(confirm) {
    children.push(archived_delete_modal(dispatch, confirm))
  }
  // Rendered whether or not the palette is open — closed it is an empty
  // placeholder — so opening it never shifts the overlay children around it.
  children.push(quick_open_html)
  // On the desktop a lost connection covers everything: with no event
  // stream and every API call failing, the app behind it can do nothing,
  // so an honest dead-end beats a half-broken UI. The console keeps its last
  // rendered device readable while its topbar and composer show reconnecting.
  if model.is_desktop && model.bridge_state() is BridgeLost(message) {
    children.push(bridge_lost_overlay(message))
  }
  @html.div(
    class=app_shell_class(
      model.sidebar_open,
      model.is_desktop && app_shortcut_platform_is_apple(),
    ),
    children,
  )
}

///|
/// The full-screen card shown when the bridge is lost: a plain explanation
/// and what to do; the only action here is the instruction itself.
fn bridge_lost_overlay(message : String) -> @html.Html {
  @html.div(class="bridge-lost-backdrop", [
    @html.div(class="bridge-lost-card", [
      @html.div(class="bridge-lost-title", "Disconnected"),
      @html.div(class="bridge-lost-body", message),
    ]),
  ])
}

///|
/// The modal shown when updating would cut running conversations off:
/// restarting tears the engine processes down mid-run. The backdrop and the
/// Cancel button both keep the current version running.
fn update_confirm_modal(
  dispatch : @cmd.Emit[Msg],
  version : String,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelUpdateRestart), [
    @html.div(class="modal", [
      @html.div(class="modal-title", "Update to \{version}?"),
      @html.div(
        class="modal-body",
        "A conversation is still running. Updating restarts the app and interrupts it; the transcript so far is saved.",
      ),
      @html.div(class="modal-actions", [
        @html.button(on_click=dispatch(CancelUpdateRestart), "Keep working"),
        @html.button(
          class="primary",
          on_click=dispatch(ConfirmUpdateRestart),
          "Update and restart",
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
/// disappears the moment a usable endpoint arrives. "Not now" dismisses for
/// the session; the composer's BYOK notice keeps the reminder — and the way
/// back here — visible. Clicks inside must not bubble to the backdrop, whose
/// click dismisses.
fn api_setup_modal(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let title = match model.api_provider {
    Deepseek => "Set up your DeepSeek API key"
    Glm => "Set up your GLM API key"
    Custom => "Set your endpoint URL"
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
          @html.button(on_click=dispatch(DismissApiSetup), "Not now"),
        ]),
      ],
    ),
  ])
}

///|
/// The floating toast stack, fixed to the configured window corner. Each
/// toast dismisses on click; its timer handles the rest.
fn notifications_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let toasts : Array[@html.Html] = []
  for toast in model.notifications {
    toasts.push(
      @html.div(
        class="notification",
        title="Dismiss",
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
