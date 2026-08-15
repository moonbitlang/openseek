///|
fn can_stop(conv : Conversation) -> Bool {
  conv.run is Open(..)
}

///|
fn token_label(tokens : Int) -> String {
  "\{compact_count(tokens)} tokens"
}

///|
/// A count compacted for a pill: exact under a thousand, otherwise one
/// decimal of k/M with a whole value's ".0" dropped — 999 → "999",
/// 12_345 → "12.3k", 10_000 → "10k", 1_230_000 → "1.2M".
fn compact_count(value : Int) -> String {
  fn scaled(tenths : Int, unit : String) -> String {
    if tenths % 10 == 0 {
      "\{tenths / 10}\{unit}"
    } else {
      "\{tenths / 10}.\{tenths % 10}\{unit}"
    }
  }

  if value < 1000 {
    value.to_string()
  } else if value < 999_950 {
    // Rounded tenths of a thousand; the cap keeps the k form from rounding
    // up to "1000k" — beyond it the M form takes over.
    scaled((value + 50) / 100, "k")
  } else {
    scaled((value + 50_000) / 100_000, "M")
  }
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
/// A native select with the Settings page's own chevron. The browser-drawn
/// indicator ignores the control's right padding, so it cannot line up with
/// the selected text's left inset reliably across desktop webviews.
fn setting_select(control : @html.Html) -> @html.Html {
  @html.div(class="setting-select", [
    control,
    @html.span(class="setting-select-chevron", icon(icon_chevron_down)),
  ])
}

///|
/// The composer's model selector. OpenSeek supplies its model wire values and
/// labels; the reusable composer package owns the control's geometry.
fn EngineModel::composer_select(
  self : EngineModel,
  dispatch : @cmd.Emit[Msg],
) -> @html.Html {
  let options : Array[@composer.ModelOption] = [
    { value: High.wire(), label: High.label() },
    { value: Low.wire(), label: Low.label() },
  ]
  if self is Other(name) {
    options.push({ value: name, label: name })
  }
  @composer.ModelSelect::{
    options,
    selected: self.wire(),
    disabled: false,
    change: dispatch.map(value => EngineModelChanged(value)),
    title: "Model: \{self.wire()}",
  }.render()
}

///|
fn conversation_title(conv : Conversation) -> String {
  // Titles follow the committed user transcript. Client-local failure notices
  // are visible too but never qualify as a title.
  for item in conv.visible_items() {
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
    // Scratch and project stores, and without it two same-id rows would
    // collide on one key in the sidebar's keyed container.
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
  rows : Array[@conversation.Input],
  dev : DeviceState,
  workspace : @common.Uri?,
  listed~ : (String) -> Bool,
  archived~ : (String) -> Bool,
  nested? : Bool = false,
) -> Unit {
  let composing = self.composing_new_chat()
  // Every row in this group shares the group's store placement; it becomes
  // the `root` half of each conversation's component id.
  let root = workspace.map(workspace => workspace.path)
  for conv in self.conversations.rev_iter() {
    if conv.device != dev.channel ||
      conv.workspace.project() != workspace ||
      listed(conv.session_id) ||
      archived(conv.session_id) {
      continue
    }
    // A fresh worktree conversation knows its binding locally; once the
    // first turn is durable the registry mapping takes over.
    let worktree = if conv.workspace.worktree_name() is Some(name) {
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
      session_component_input(
        self,
        dev.channel,
        conv.session_id,
        if worth_keeping {
          conversation_title(conv)
        } else {
          "New chat"
        },
        nested~,
        worktree?,
        root?,
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
          nested~,
          subrun=true,
          root?,
        ),
      )
    }
    rows.push(
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
        nested~,
        worktree?=worktree_name_for(dev, workspace, tree.item.id),
        root?,
        children~,
      ),
    )
  }
}

///|
/// One device's sections: each attached project as a folder row with its
/// conversations nested beneath it, the default store's loose chats, and the
/// archived group at the tail. Rows stay clickable while runs are active —
/// switching between conversations mid-run is the point of keeping them
/// concurrent.
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
  let projects : Array[@section.Entry] = []
  for path in dev.projects {
    let conversations : Array[@conversation.Input] = []
    self.push_group_component_inputs(
      conversations,
      dev,
      Some(path),
      listed~,
      archived~,
      nested=true,
    )
    projects.push(
      @section.Project({
        id: @project.Id(source="openseek.projects", channel~, root=path.path),
        title: path.path,
        label: @resource.label(path),
        activation: activation(dev.active_project == Some(path)),
        can_start: true,
        managed: true,
        conversations,
        empty_label: Some("No chats yet"),
      }),
    )
  }
  sections.push({
    id: @section.Id(source="openseek.projects", channel~),
    label: "Projects",
    initially_collapsed: false,
    activation: activation(dev.active_project is Some(_)),
    action: Some({ title: "Add a project", disabled: false }),
    entries: projects,
  })
  let chats : Array[@conversation.Input] = []
  self.push_group_component_inputs(chats, dev, None, listed~, archived~)
  sections.push({
    id: @section.Id(source="openseek.chats", channel~),
    label: "Chats",
    initially_collapsed: false,
    activation: activation(dev.active_project is None),
    action: Some({ title: "New Scratch chat", disabled: false }),
    entries: chats.map(chat => @section.Conversation(chat)),
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
          root?=item.workspace.map(workspace => workspace.path),
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
      Some({ login, avatar, busy: console.busy, notice: console.notice })
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
/// Steering input the engine has not settled yet, shown as a panel docked
/// above the composer: the submission is acknowledged immediately, but it
/// only joins the transcript when the engine folds it into the turn
/// (`steer_applied` commits it as a real user message).
fn pending_steers_panel(conv : Conversation) -> @html.Html {
  let rows : Array[@html.Html] = []
  for text in conv.pending_steers() {
    let shown = user_display_text(text)
    rows.push(
      @html.div(class="pending-steer-row", title=shown, [
        @html.span(class="pending-steer-icon", "⤷"),
        @html.span(class="pending-steer-text", shown),
        @html.span(class="pending-steer-state", "steering…"),
      ]),
    )
  }
  @html.div(class="pending-steers", rows)
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
/// The console's connection banner: a permanent first child of the composer's
/// context row whose class flips visibility. Keeping that row stable preserves
/// the plan panel's DOM state while the connection changes. Desktop keeps the
/// full-screen overlay instead and renders this hidden.
fn connection_banner(model : Model) -> @html.Html {
  let visible = model.console is Some(_) &&
    model.bridge_state() is BridgeLost(_)
  if visible {
    @html.div(
      class="composer-banner",
      "Can't reach \{model.focused_device_name()} — reconnecting…",
    )
  } else {
    @html.div(class="composer-banner hidden", "")
  }
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
fn provider_select(
  dispatch : @cmd.Emit[Msg],
  selected : ApiProvider,
  disabled~ : Bool,
) -> @html.Html {
  let control = @html.select(
    disabled~,
    on_change=dispatch.map(value => ProviderChanged(value)),
    attrs=@html.Attrs::build()
      .aria_label("API endpoint")
      .data_set("focus-owner", ""),
    [
      @html.option(
        value="openseek",
        selected=selected is Openseek,
        "OpenSeek (default, no API key)",
      ),
      @html.option(
        value="openseek-staging",
        selected=selected is OpenseekStaging,
        "OpenSeek staging (testing)",
      ),
      @html.option(
        value="deepseek",
        selected=selected is Deepseek,
        "DeepSeek official (your API key)",
      ),
      @html.option(value="custom", selected=selected is Custom, "Custom URL"),
    ],
  )
  setting_select(control)
}

///|
fn corner_select(
  dispatch : @cmd.Emit[Msg],
  selected : NotificationCorner,
) -> @html.Html {
  let control = @html.select(
    on_change=dispatch.map(value => NotificationCornerChanged(value)),
    attrs=@html.Attrs::build()
      .aria_label("Notification corner")
      .data_set("focus-owner", ""),
    [
      @html.option(
        value="bottom-right",
        selected=selected is BottomRight,
        "Bottom right",
      ),
      @html.option(
        value="bottom-left",
        selected=selected is BottomLeft,
        "Bottom left",
      ),
      @html.option(
        value="top-right",
        selected=selected is TopRight,
        "Top right",
      ),
      @html.option(value="top-left", selected=selected is TopLeft, "Top left"),
    ],
  )
  setting_select(control)
}

///|
fn tree_layout_select(
  dispatch : @cmd.Emit[Msg],
  selected : @fileeditor.TreeLayout,
) -> @html.Html {
  let control = @html.select(
    on_change=dispatch.map(value => TreeLayoutChanged(value)),
    attrs=@html.Attrs::build()
      .aria_label("File tree layout")
      .data_set("focus-owner", ""),
    [
      @html.option(
        value="right-sidebar",
        selected=selected is RightSidebar,
        "Right sidebar",
      ),
      @html.option(
        value="bottom-panel",
        selected=selected is BottomPanel,
        "Bottom panel",
      ),
    ],
  )
  setting_select(control)
}

///|
/// The Remote access group's rows: sign-in state against the selected
/// OpenSeek server, or why there is nothing to sign in to.
fn remote_access_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  // A pending connect bypasses the guard: switching the endpoint mid-flow
  // must not hide the Cancel button while the sign-in still runs against
  // the server it started with.
  if !(model.api_provider is (Openseek | OpenseekStaging)) &&
    !(model.remote_access is Some({ user_login: Some(_), .. })) &&
    !model.remote_connecting {
    rows.push(
      setting_row(
        "Remote control",
        [],
        desc="Needs the OpenSeek server — select it under API endpoint.",
      ),
    )
    return rows
  }
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
    Openseek => "Requests go through the OpenSeek service; no key needed."
    OpenseekStaging =>
      "The OpenSeek staging server: pre-release service and staging updates."
    Deepseek => "Requests go straight to api.deepseek.com with your key."
    Custom => "Any DeepSeek-compatible chat-completions URL; key optional."
  }
}

///|
/// The Settings page, shown in the main area in place of the conversation
/// (mirroring the Skills page — the sidebar is the way out, no Done button).
/// While the configured endpoint is unusable the page takes over on its own,
/// and the composer keeps Send disabled until a usable endpoint is saved.
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
  let api_rows : Array[@html.Html] = [
    setting_row(
      "API endpoint",
      [provider_select(dispatch, model.api_provider, disabled=!settings_loaded)],
      desc=provider_hint(model.api_provider),
    ),
  ]
  if model.api_provider is Custom {
    api_rows.push(
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
  // The OpenSeek proxy ignores keys, so the key field only appears for the
  // endpoints that can use one. The key lives on the host and is never
  // echoed back — the page only knows one is saved; saving a new one
  // overwrites it.
  if !(model.api_provider is Openseek) {
    let key_saved = if model.api_provider is Custom {
      model.custom_key_saved
    } else {
      model.deepseek_key_saved
    }
    api_rows.push(
      setting_row(
        if model.api_provider is Custom {
          "Custom API key"
        } else {
          "DeepSeek API key"
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
        desc="Stored on the OpenSeek host machine and sent only with API requests.",
        stack=true,
      ),
    )
  }
  let groups : Array[@html.Html] = [
    settings_group(icon_sparkle, "Engine", engine_rows),
    settings_group(icon_key, "API", api_rows),
    settings_group(icon_layout, "Interface", [
      setting_row(
        "Theme",
        [
          setting_select(
            @html.select(
              on_change=dispatch.map(value => ThemeChanged(value)),
              attrs=@html.Attrs::build()
                .aria_label("Theme")
                .data_set("focus-owner", ""),
              [
                @html.option(
                  value="system",
                  selected=model.theme is System,
                  "System",
                ),
                @html.option(
                  value="light",
                  selected=model.theme is Light,
                  "Light",
                ),
                @html.option(value="dark", selected=model.theme is Dark, "Dark"),
              ],
            ),
          ),
        ],
        desc="Used by the app, editor, and terminal. System follows the OS appearance.",
      ),
      setting_row(
        "Font",
        [
          setting_select(
            @html.select(
              on_change=dispatch.map(value => FontChanged(value)),
              attrs=@html.Attrs::build()
                .aria_label("Font")
                .data_set("focus-owner", ""),
              [
                @html.option(
                  value="geist-mono",
                  selected=model.app_font is GeistMono,
                  "Geist Mono",
                ),
                @html.option(
                  value="system-mono",
                  selected=model.app_font is SystemMono,
                  "System monospace",
                ),
                @html.option(
                  value="menlo",
                  selected=model.app_font is Menlo,
                  "Menlo",
                ),
              ],
            ),
          ),
        ],
        desc="Used by the app, editor, and terminal.",
      ),
      setting_row(
        "Font size",
        [
          setting_select(
            @html.select(
              on_change=dispatch.map(value => FontSizeChanged(value)),
              attrs=@html.Attrs::build()
                .aria_label("Font size")
                .data_set("focus-owner", ""),
              [
                @html.option(
                  value="small",
                  selected=model.app_font_size is Small,
                  "Small (12px)",
                ),
                @html.option(
                  value="medium",
                  selected=model.app_font_size is Medium,
                  "Medium (13px)",
                ),
                @html.option(
                  value="large",
                  selected=model.app_font_size is Large,
                  "Large (14px)",
                ),
              ],
            ),
          ),
        ],
        desc="Scales text in the app, editor, and terminal.",
      ),
      setting_row(
        "Notification corner",
        [corner_select(dispatch, model.notification_corner)],
        desc="Where error notifications pop up.",
      ),
      setting_row(
        "File tree layout",
        [tree_layout_select(dispatch, model.tree_layout)],
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
          desc="Current version: \{model.app_version}. The staging server serves staging builds.",
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
            "Runtime settings for the OpenSeek engine."
          } else if model.api_provider is Custom {
            "Enter a chat-completions endpoint URL to start."
          } else {
            "Enter a DeepSeek API key to start."
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
        setting_select(
          @html.select(
            on_change=dispatch.map(value => {
              WorkspaceDefaultModeChosen(channel, workspace, value)
            }),
            attrs=@html.Attrs::build()
              .aria_label("New chats")
              .data_set("focus-owner", "")
              .disabled(row is None),
            [
              @html.option(value="local", selected=!worktree_mode, "Local"),
              @html.option(value="worktree", selected=worktree_mode, "Worktree"),
            ],
          ),
        ),
      ],
      desc="Where a new chat starts: the workspace itself, or a fresh git worktree bound to that chat. The composer's chip still changes a single chat.",
    ),
  ]
  let worktree_rows : Array[@html.Html] = [
    setting_row(
      "Submodules",
      [
        setting_select(
          @html.select(
            on_change=dispatch.map(value => {
              WorkspaceSubmodulesChosen(channel, workspace, value)
            }),
            attrs=@html.Attrs::build()
              .aria_label("Submodules in worktrees")
              .data_set("focus-owner", "")
              .disabled(row is None),
            [
              @html.option(
                value="checkout",
                selected=checkout_submodules,
                "Initialize",
              ),
              @html.option(
                value="skip",
                selected=!checkout_submodules,
                "Leave uninitialized",
              ),
            ],
          ),
        ),
      ],
      desc="For new or repaired worktrees in this workspace, mirror the top-level submodules already initialized in its main checkout.",
    ),
    setting_row(
      "Checkout timeout",
      [
        setting_select(
          @html.select(
            on_change=dispatch.map(value => {
              WorkspaceSubmoduleTimeoutChosen(channel, workspace, value)
            }),
            attrs=@html.Attrs::build()
              .aria_label("Submodule checkout timeout")
              .data_set("focus-owner", "")
              .disabled(row is None),
            [
              @html.option(
                value="5",
                selected=submodule_checkout_timeout_seconds == 5,
                "5 seconds",
              ),
              @html.option(
                value="10",
                selected=submodule_checkout_timeout_seconds == 10,
                "10 seconds",
              ),
              @html.option(
                value="30",
                selected=submodule_checkout_timeout_seconds == 30,
                "30 seconds",
              ),
              @html.option(
                value="60",
                selected=submodule_checkout_timeout_seconds == 60,
                "60 seconds",
              ),
            ],
          ),
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
/// One local-library row: name, description, and — for registry installs
/// only — the source tag and the uninstall button. Hand-written skills are
/// listed so the user sees everything the engine advertises, but the app
/// never offers to delete them.
fn installed_skill_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  skill : @transcript.InstalledSkillItem,
) -> @html.Html {
  let info : Array[@html.Html] = [@html.div(class="skill-name", skill.name)]
  if !skill.description.is_blank() {
    info.push(@html.div(class="skill-desc", skill.description))
  }
  info.push(
    @html.div(
      class="skill-meta",
      if skill.source.is_empty() {
        "hand-written"
      } else {
        skill.source
      },
    ),
  )
  let children : Array[@html.Html] = [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
  ]
  if skill.source.is_empty() {
    children.push(@html.span(class="skill-check ok", "✓"))
  } else {
    let busy = model.skills_busy.contains(skill.id)
    children.push(
      @html.button(
        class="secondary skill-action",
        disabled=busy,
        on_click=dispatch(UninstallSkill(skill.id)),
        if busy {
          "Removing…"
        } else {
          "Uninstall"
        },
      ),
    )
  }
  @html.div(class="skill-row", children)
}

///|
/// One catalog row. The action button morphs: already installed at this
/// exact version reads as a disabled "Installed" (an older install keeps
/// the button alive as the upgrade path), an install in flight reads as
/// "Installing…".
fn market_skill_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  item : @transcript.MarketSkillItem,
) -> @html.Html {
  let source = @transcript.market_source_label(item)
  let busy = model.skills_busy.contains(source)
  let installed = model.skill_installed(source)
  let info : Array[@html.Html] = [@html.div(class="skill-name", item.name)]
  if !item.description.is_blank() {
    info.push(@html.div(class="skill-desc", item.description))
  }
  let meta = if item.author.is_empty() {
    "v\{item.version}"
  } else {
    "v\{item.version} · \{item.author}"
  }
  info.push(@html.div(class="skill-meta", meta))
  let action = if installed {
    @html.span(class="skill-check ok", "✓ Installed")
  } else {
    @html.button(
      class="secondary skill-action",
      disabled=busy,
      on_click=dispatch(InstallSkill(item)),
      if busy {
        "Installing…"
      } else {
        "Install"
      },
    )
  }
  @html.div(class="skill-row", title=item.repository, [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
    action,
  ])
}

///|
/// Whether a skill row survives the page's search filter: a blank query
/// keeps everything, otherwise any listed field must contain it
/// (case-insensitive).
fn skill_matches(query : String, fields : Array[String]) -> Bool {
  let query = query.trim().to_owned().to_lower()
  if query.is_empty() {
    return true
  }
  for field in fields {
    if field.to_lower().contains(query) {
      return true
    }
  }
  false
}

///|
/// The Skills page, shown in the main area in place of the conversation:
/// header, search, the local library, then the mooncakes.io catalog.
fn skills_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let sections : Array[@html.Html] = [
    @html.div(class="skills-header", [
      @html.div(class="page-eyebrow", "Library"),
      @html.h1("Skills"),
      @html.div(
        class="skills-subtitle",
        "Playbooks the agent reads when a task matches. Skills apply to new chats.",
      ),
    ]),
    @html.div(
      class="skills-search",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        icon(icon_search),
        @html.input(
          input_type=@html.InputType::Search,
          value=model.skills_query,
          placeholder="Search skills…",
          on_input=dispatch.map(value => SkillsQueryChanged(value)),
          attrs=@html.Attrs::build().data_set("focus-target", ""),
        ),
      ],
    ),
  ]
  if !model.skills_notice.is_empty() {
    sections.push(@html.div(class="skills-notice danger", model.skills_notice))
  }
  let installed_rows : Array[@html.Html] = []
  for skill in model.installed_skills {
    if skill_matches(model.skills_query, [
        skill.name,
        skill.description,
        skill.source,
      ]) {
      installed_rows.push(installed_skill_row(dispatch, model, skill))
    }
  }
  if installed_rows.is_empty() {
    installed_rows.push(
      @html.div(
        class="skills-empty",
        if model.installed_skills.is_empty() {
          "No skills installed yet."
        } else {
          "No installed skill matches the search."
        },
      ),
    )
  }
  sections.push(settings_group(icon_extensions, "Installed", installed_rows))
  let market_rows : Array[@html.Html] = []
  match model.skills_catalog {
    CatalogIdle | CatalogLoading =>
      market_rows.push(
        @html.div(class="skills-empty", "Loading the skill catalog…"),
      )
    CatalogFailed(message) =>
      market_rows.push(@html.div(class="skills-empty danger", message))
    CatalogReady(items) => {
      for item in items {
        if skill_matches(model.skills_query, [
            item.name,
            item.description,
            item.author,
          ]) {
          market_rows.push(market_skill_row(dispatch, model, item))
        }
      }
      if market_rows.is_empty() {
        market_rows.push(
          @html.div(
            class="skills-empty",
            if items.is_empty() {
              "The registry lists no installable skills yet."
            } else {
              "No registry skill matches the search."
            },
          ),
        )
      }
    }
  }
  sections.push(settings_group(icon_package, "Mooncakes registry", market_rows))
  @html.section(class="skills-page", [
    @html.div(class="skills-page-inner", sections),
  ])
}

///|
#warnings("-alert_unstable")
test "settings and skills declare form focus ownership" {
  let dispatch = test_dispatch()
  let settings_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(settings_page(dispatch, test_model()))
  })
  // Settings fields own their existing borders directly; there is no nested
  // target that could draw a second frame.
  assert_true(settings_markup.contains("data-focus-owner=\"\""))
  assert_false(settings_markup.contains("data-focus-target=\"\""))
  let skills_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(skills_page(dispatch, test_model()))
  })
  assert_true(skills_markup.contains("class=\"skills-search\""))
  assert_true(skills_markup.contains("data-focus-owner=\"\""))
  assert_true(skills_markup.contains("data-focus-target=\"\""))
  let address_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @preview.toolbar_view(
        { url: None, input: "", title: "", loading: false, failure: None },
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
  for markup in [settings_markup, skills_markup, address_markup] {
    for tag in ["<input", "<textarea", "<select"] {
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
test "an archived transcript renders no live composer controls" {
  let dispatch = test_dispatch()
  let conv = { ..test_conversation(), record: ArchivedRecord }
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
fn run_indicator(model : Model) -> @html.Html {
  let status = model.display_status()
  let label = status.label()
  if model.active().is_running() {
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
/// The first letter of an app name, for the icon fallback when the host could
/// not extract a real icon.
fn app_initial(name : String) -> String {
  if name.iter().next() is Some(c) {
    "\{c.to_ascii_uppercase()}"
  } else {
    "?"
  }
}

///|
/// The launcher dropdown's rows: a real icon (or letter fallback) and the app
/// name, each launching the app on the active workspace. Falls back to a
/// loading / error / empty notice when there is nothing to list.
fn launcher_menu(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  match model.launcher.apps {
    AppsFailed(message) =>
      rows.push(@html.div(class="launcher-empty danger", message))
    AppsNotFetched | AppsLoading =>
      rows.push(@html.div(class="launcher-empty", "Finding apps…"))
    AppsFetched([]) =>
      rows.push(@html.div(class="launcher-empty", "No apps found"))
    AppsFetched(apps) =>
      for app in apps {
        let icon = if app.icon.is_empty() {
          @html.span(class="launcher-icon letter", app_initial(app.name))
        } else {
          @html.img(
            class="launcher-icon",
            src=app.icon,
            alt=app.name,
            width=24,
            height=24,
          )
        }
        rows.push(
          @html.button(
            class="launcher-item",
            type_="button",
            on_click=dispatch(LaunchApp(app.id)),
            [icon, @html.span(class="launcher-name", app.name)],
          ),
        )
      }
  }
  @html.div(class="launcher-menu", rows)
}

///|
/// The topbar app launcher: a button that opens a dropdown of installed apps,
/// each opening the active conversation's workspace. A click away closes it
/// (see `dismiss_subscription`).
fn launcher_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  // A conversation's workspace exists only once it has run; a fresh chat with
  // no turn yet has nothing to open, so the launcher is disabled until then.
  let conv = model.active()
  let ready = !conv.visible_items().is_empty() || conv.is_running()
  let children : Array[@html.Html] = [
    @html.button(
      class=if model.launcher.open {
        "launcher-button open"
      } else {
        "launcher-button"
      },
      type_="button",
      disabled=!ready,
      title=if ready {
        "Open this workspace in an app"
      } else {
        "Send a message to create this chat's workspace"
      },
      on_click=dispatch(ToggleLauncher),
      [
        @html.span(class="launcher-glyph", icon(icon_link_external)),
        @html.span(class="launcher-caret", icon(icon_chevron_down)),
      ],
    ),
  ]
  if ready && model.launcher.open {
    // No backdrop element: dismissal rides on `dismiss_subscription`, which
    // does not consume the click that closes it.
    children.push(launcher_menu(dispatch, model))
  }
  @html.div(class="launcher", children)
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
) -> @html.Html {
  let conv = model.active()
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
  // The conversation's attached project; a scratch conversation has no chip.
  // The git branch is not shown here — it lives in the composer's status row.
  if conv.workspace.project() is Some(workspace) {
    items.push(
      @html.span(class="topbar-workspace", title=workspace.path, [
        icon(icon_folder),
        @html.text(@resource.label(workspace)),
      ]),
    )
  }
  items.push(run_indicator(model))
  if conv.usage_tokens > 0 {
    items.push(@html.span(class="pill", token_label(conv.usage_tokens)))
  }
  if !conv.watcher_status.is_empty() {
    items.push(@html.span(class="pill", "moon_check \{conv.watcher_status}"))
  }
  // The launcher opens GUI apps on the host machine, which only means
  // something when the page IS that machine's desktop window; from a remote
  // browser the launched app would appear on a screen the user is not at.
  if model.is_desktop {
    items.push(launcher_view(dispatch, model))
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
        card.push(@html.p("Access this OpenSeek device from your browser."))
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
      @html.header(class="portal-header", [@html.h1("OpenSeek")]),
      @html.div(class="portal-card", card),
    ]),
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
  sidebar_html : @html.Html,
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
  let content = match model.screen {
    Chat =>
      [
        topbar_view(dispatch, toggle_terminal, toggle_right_panel, model),
        transcript_html,
        if model.active().is_archived_read_only() {
          model.active().archived_read_only_view(dispatch)
        } else {
          composer_html
        },
      ]
    Skills => page_with_toggle(dispatch, model, skills_page(dispatch, model))
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
  // either side can be swapped out later. The files panel only opens over the
  // chat; on the Skills page it stays collapsed, but the editor column (and the
  // viewer host inside it) is still rendered so the attached viewer is never
  // torn down.
  let panel_open = model.right_panel_open && model.screen is Chat
  let mut content_class = if panel_open {
    "content panel-open"
  } else {
    "content"
  }
  if model.terminal.is_open() {
    content_class = content_class + " terminal-open"
  }
  let children : Array[@html.Html] = [
    sidebar_html,
    @html.div(class=content_class, [
      @html.main_(content),
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
  if model.project_picker is Some(picker) {
    children.push(project_picker_modal(dispatch, picker))
  }
  if model.archive_confirm is Some(confirm) {
    children.push(archive_discard_modal(dispatch, confirm))
  }
  if model.archived_delete_confirm is Some(confirm) {
    children.push(archived_delete_modal(dispatch, confirm))
  }
  if model.quick_open is Some(open) {
    children.push(quick_open_view(dispatch, open))
  }
  // On the desktop a lost connection covers everything: with no event
  // stream and every API call failing, the app behind it can do nothing,
  // so an honest dead-end beats a half-broken UI. The console keeps its last
  // rendered device readable while its topbar and composer show reconnecting.
  if model.is_desktop && model.bridge_state() is BridgeLost(message) {
    children.push(bridge_lost_overlay(message))
  }
  @html.div(
    class=if model.sidebar_open { "app" } else { "app sidebar-collapsed" },
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
/// The in-app folder picker behind the sidebar's "Add a project", shaped
/// like a system chooser: a clickable breadcrumb for the current directory
/// (each segment navigates up to that level — there is no ".." row) and a
/// folder list that navigates on click. The keyboard surface lives in the
/// document-level capture pair (`project_picker_keys.mbt`): Enter adds the
/// browsed directory, Escape closes, and a pasted path jumps straight to
/// that location (a path that names no directory pops a toast). It renders
/// the host machine's directories whichever gateway serves the page, so
/// desktop and browser share the one flow. Clicks inside must not bubble
/// to the backdrop, whose click closes the picker.
fn project_picker_modal(
  dispatch : @cmd.Emit[Msg],
  picker : ProjectPicker,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for name in picker.entries {
    let target = match picker.path {
      Some(path) => path.picker_child_path(name)
      None => name
    }
    rows.push(
      @html.div(
        class="picker-row",
        on_click=dispatch(ProjectPickerNavigate(target)),
        [
          @html.span(class="picker-row-icon", icon(icon_folder)),
          @html.span(class="picker-row-name", name),
        ],
      ),
    )
  }
  if picker.entries.length() == 0 {
    rows.push(
      @html.div(
        class="picker-empty",
        if picker.loading {
          "Loading…"
        } else {
          "No subfolders"
        },
      ),
    )
  }
  let children : Array[@html.Html] = [
    @html.div(class="modal-title", "Add a project"),
    picker_breadcrumbs(dispatch, picker),
  ]
  children.push(@html.div(class="picker-list", rows))
  children.push(
    @html.div(class="modal-actions", [
      @html.button(on_click=dispatch(ProjectPickerClose), "Cancel"),
      @html.button(
        class="primary",
        // While a navigation is in flight the shown listing is stale;
        // update refuses the confirm too, this just says so visually.
        disabled=picker.loading,
        on_click=dispatch(ProjectPickerConfirm),
        match picker.path {
          None => "Add this folder"
          Some(path) => "Add \u{201c}\{@resource.label(path)}\u{201d}"
        },
      ),
    ]),
  )
  @html.div(class="modal-backdrop", on_click=dispatch(ProjectPickerClose), [
    @html.div(
      class="modal picker-modal",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        @cmd.none
      }),
      children,
    ),
  ])
}

///|
/// The current directory as a clickable trail: every ancestor is a button
/// that navigates back up to it, the way a system chooser's path bar works.
/// Windows resource paths keep `/C:/` as their drive root; POSIX paths root
/// at `/`. UNC never reaches this UI because the backend rejects it.
fn picker_breadcrumbs(
  dispatch : @cmd.Emit[Msg],
  picker : ProjectPicker,
) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  guard picker.path is Some(resource) else {
    return @html.div(class="picker-crumbs", crumbs)
  }
  let path = resource.path

  let segments : Array[String] = []
  for part in path.split("/") {
    if !part.is_empty() {
      segments.push("\{part}")
    }
  }
  let drive_root = match segments {
    [drive, ..] if drive.length() == 2 && drive.has_suffix(":") => Some(drive)
    _ => None
  }
  if drive_root is None {
    crumbs.push(
      @html.button(
        class=if segments.length() == 0 {
          "picker-crumb current"
        } else {
          "picker-crumb"
        },
        on_click=dispatch(ProjectPickerNavigate("/")),
        "/",
      ),
    )
  }
  let mut prefix = ""
  for index, segment in segments {
    prefix = if drive_root is Some(_) && index == 0 {
      "/" + segment + "/"
    } else if prefix.has_suffix("/") {
      prefix + segment
    } else {
      prefix + "/" + segment
    }
    if crumbs.length() > 0 {
      crumbs.push(@html.span(class="picker-crumb-sep", "›"))
    }
    crumbs.push(
      @html.button(
        class=if index == segments.length() - 1 {
          "picker-crumb current"
        } else {
          "picker-crumb"
        },
        on_click=dispatch(ProjectPickerNavigate(prefix)),
        segment,
      ),
    )
  }
  @html.div(class="picker-crumbs", crumbs)
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
    sessions: [archived_item("chat-sr-1")],
  })
  let orphan_sections = orphan_model.sidebar_component_sections(
    orphan_model.dev(),
  )
  let mut orphan_entries : Array[@section.Entry] = []
  for section in orphan_sections {
    if section.id().source() == "openseek.chats" {
      orphan_entries = section.entries
    }
  }
  let mut orphan : @conversation.Input? = None
  for entry in orphan_entries {
    if entry is @section.Conversation(row) &&
      row.id().conversation() == "chat-sr-1" {
      orphan = Some(row)
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
      workspace: Some(project),
      workspace_name: "alpha",
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
/// record in Scratch and in a project store at once. Both rows must survive
/// the sidebar's keyed container — colliding keys would silently drop one.
test "same-id records in Scratch and a project store keep distinct row keys" {
  let project = @interop.ChannelId::Local.test_resource("/work/alpha")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [project],
    sessions: [
      {
        id: "desktop-shared",
        title: Some("project copy"),
        workspace: Some(project),
        workspace_name: "alpha",
      },
      {
        id: "desktop-shared",
        title: Some("scratch copy"),
        workspace: None,
        workspace_name: "",
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
test "token counts compact to k/M with whole values undotted" {
  inspect(compact_count(0), content="0")
  inspect(compact_count(999), content="999")
  inspect(compact_count(1000), content="1k")
  inspect(compact_count(1049), content="1k")
  inspect(compact_count(1050), content="1.1k")
  inspect(compact_count(12345), content="12.3k")
  inspect(compact_count(999_949), content="999.9k")
  inspect(compact_count(999_950), content="1M")
  inspect(compact_count(1_230_000), content="1.2M")
  inspect(token_label(12345), content="12.3k tokens")
}
