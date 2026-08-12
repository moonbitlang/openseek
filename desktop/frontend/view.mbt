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
/// The composer's model chip: this conversation's service tier, and the
/// control that changes it. One click flips to the other tier — the choice
/// is the conversation's, so a long refactor can sit on High while the chat
/// beside it stays on Low.
fn model_chip(dispatch : @cmd.Emit[Msg], conv : Conversation) -> @html.Html {
  let other = conv.engine_model.toggled()
  @html.button(
    class="composer-model",
    type_="button",
    title="Model: \{conv.engine_model.wire()} — click for \{other.label()}",
    on_click=dispatch(ToggleModel),
    [@html.span(conv.engine_model.label())],
  )
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
    "SeekMoon"
  } else {
    task
  }
}

///|
/// One sidebar row. A conversation with a turn in flight gets a pulsing dot,
/// so background work stays visible while another conversation is on screen.
/// A durable, idle row also carries a hover-revealed archive button; the row
/// itself is a div (not a button) so that control can nest inside it.
/// `subruns` is how many sub-run transcripts this conversation folded under
/// it: above zero the row leads with a twisty that shows or hides them
/// (`expanded` says which way it points). `subrun` marks the row as one of
/// those children — indented a step. Nested children have no independent
/// archive action because archiving their parent moves the whole family; a
/// legacy orphan that surfaces as a root row does get the action so old split
/// state remains repairable.
fn session_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  session_id : String,
  label : String,
  archivable? : Bool = false,
  nested? : Bool = false,
  worktree? : String,
  subruns? : Int = 0,
  expanded? : Bool = false,
  subrun? : Bool = false,
) -> @html.Html {
  // Session ids can collide across devices, so the accent pill needs the
  // channel to agree too.
  let active = channel == model.focused && session_id == model.active_session
  let conv = model.find_conversation(channel, session_id)
  let running = conv is Some(conv) && conv.is_running()
  // The row's status dot: pulsing while a run is in flight, then — when the
  // run finished off screen — settling into a solid dot (accent for success,
  // warn otherwise) until the conversation is opened (`Model::activate`
  // clears the mark).
  let dot = match conv {
    Some(conv) if conv.is_running() => Some("accent pulse")
    Some(conv) if conv.unseen_finish && !active =>
      // Success wears accent (continuity with the running pulse), any other
      // ending warn — the same success/other split `Status::kind` draws.
      Some(
        if conv.run is NoRun(ended=Some(RunFinished(Completed))) {
          "accent"
        } else {
          "warn"
        },
      )
    _ => None
  }
  // The shared row's trailing slot holds two right-aligned groups stacked in
  // one cell:
  // what the row *is* (status) and what can be done to it (actions). At
  // rest the status group shows; hovering a row that has actions swaps them
  // in. Sizing is content-driven — a row with neither group has no slot at
  // all, so idle rows carry no reserved gutter.
  let status : Array[@html.Html] = []
  // A worktree conversation wears a branch glyph — display only: the
  // environment lives and dies with the conversation; archiving removes it.
  // The name it stands for is on the row, not on the glyph: the pointer
  // that would rest on the glyph to read a tooltip is already hovering the
  // row, which swaps the glyph away.
  if worktree is Some(name) {
    status.push(
      @html.span(
        class="worktree-mark",
        attrs=@html.Attrs::build().aria_label("Runs in worktree \{name}"),
        icon(icon_worktree),
      ),
    )
  }
  // The dot goes last, so the rightmost glyph is always the run state.
  if dot is Some(kind) {
    status.push(@html.span(class="run-dot \{kind}", ""))
  }
  // Archiving a running conversation would pull the durable record out from
  // under its engine, so the button waits for the turn to end.
  let archive : @sidebar.ConversationArchive? = if archivable && !running {
    Some({
      title: "Archive — tuck this chat away; its files stay where they are",
      command: dispatch(ArchiveSession(channel, session_id)),
    })
  } else {
    None
  }
  // The row's own tooltip carries the worktree name, joined from the
  // registry (or the local binding while the first turn is still on its way
  // to the store). Anywhere on the row reaches it, including the half of
  // the row the archive button covers.
  let row_title = if worktree is Some(name) {
    "\{session_id}\nRuns in worktree \{name}; archiving removes its checkout but keeps the branch for Repair"
  } else {
    session_id
  }
  @sidebar.ConversationRow::{
    title: row_title,
    label,
    open: dispatch(OpenSession(channel, session_id)),
    nested,
    subrun,
    active,
    running,
    subruns: if subruns > 0 {
      @sidebar.Subruns(
        count=subruns,
        expanded~,
        toggle=dispatch(ToggleSubruns(channel, session_id)),
      )
    } else {
      @sidebar.NoSubruns
    },
    status,
    archive,
  }.render()
}

///|
/// Sidebar rows. Both the desktop window and browser console render only the
/// sections for one selected device channel. In the browser, `?device=` makes
/// that selection a page/tab boundary: another device belongs in another page,
/// not in this scroll box. Device identity and account controls stay outside it.
fn session_rows(dispatch : @cmd.Emit[Msg], model : Model) -> Array[@html.Html] {
  match model.console {
    None => {
      let dev = model
        .focused_device()
        .unwrap_or(empty_device_state(model.focused))
      device_section_rows(dispatch, model, dev)
    }
    Some(console) => console_session_rows(dispatch, model, console)
  }
}

///|
/// The console sidebar for this page/tab's query-selected device channel.
/// Roster loading and failure states only replace the sections when that
/// channel has no connected device state; an existing device remains usable
/// while a refresh is in flight.
fn console_session_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  console : ConsoleState,
) -> Array[@html.Html] {
  if model.focused_device() is Some(dev) {
    return device_section_rows(dispatch, model, dev)
  }
  let rows : Array[@html.Html] = []
  match console.roster_sync {
    RosterLoading => rows.push(dim_row("Loading device…"))
    RosterFailed(message) => rows.push(dim_row(message))
    RosterReady =>
      if console.roster.is_empty() {
        rows.push(
          dim_row(
            "No devices yet — open SeekMoon and sign in under Settings → Remote access.",
          ),
        )
      } else {
        rows.push(dim_row("No online device — reconnecting…"))
      }
  }
  rows
}

///|
fn dim_row(text : String) -> @html.Html {
  @html.div(class="conversation-row placeholder", [
    @html.span(class="sidebar-label", text),
  ])
}

///|
/// One device's sections: conversations that only exist in this app run (no
/// turn has reached the store yet) first, then the engine's durable
/// sessions, newest first. Rows stay clickable while runs are active —
/// switching between conversations mid-run is the point of keeping them
/// concurrent.
fn device_section_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dev : DeviceState,
) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  let listed = (id : String) => {
    for item in dev.sessions {
      if item.id == id {
        return true
      }
    }
    false
  }
  // An archived record has moved out of the live store, so the live list
  // normally cannot contain it; the filter covers the moment between the
  // archive reply and the list refetch that follows it.
  let archived = (id : String) => {
    for item in dev.archived {
      if item.id == id {
        return true
      }
    }
    false
  }
  // Two sections, matching the projects-then-chats shape chat apps settled
  // on: "Projects" lists each attached project as a folder row with its
  // conversations nested beneath, "Chats" holds the default store's loose
  // conversations. The section headings share one style; the ＋ on each adds
  // to that section (a project, or a Scratch chat).
  rows.push(
    @sidebar.Section::{
      label: "Projects",
      toggle: dispatch(ToggleProjectsSection),
      collapsed: model.projects_collapsed,
      action: Some({
        title: "Add a project",
        command: dispatch(PickProject(dev.channel)),
        disabled: false,
      }),
      selected: false,
    }.render(),
  )
  if !model.projects_collapsed {
    for path in dev.projects {
      rows.push(project_row(dispatch, model, dev, path))
      let before = rows.length()
      push_group_rows(
        rows,
        dispatch,
        model,
        dev,
        Some(path),
        listed~,
        archived~,
        nested=true,
      )
      if rows.length() == before {
        rows.push(
          @html.div(class="conversation-row nested placeholder", [
            @html.span(class="row-twisty spacer", ""),
            @html.span(class="sidebar-label", "No chats yet"),
          ]),
        )
      }
    }
  }
  rows.push(
    @sidebar.Section::{
      label: "Chats",
      toggle: dispatch(ToggleChatsSection),
      collapsed: model.chats_collapsed,
      action: Some({
        title: "New Scratch chat",
        command: dispatch(NewChatIn(dev.channel, None)),
        disabled: false,
      }),
      selected: false,
    }.render(),
  )
  if !model.chats_collapsed {
    push_group_rows(rows, dispatch, model, dev, None, listed~, archived~)
  }
  // Archived conversations fold behind a collapsed group at the end of the
  // list. Their records live in the store's `archived` twin, so they come
  // from the host's archived reply, not the live list; each row carries a
  // restore control instead of the archive one.
  let archived_rows : Array[@html.Html] = []
  for row in @transcript.session_tree(dev.archived) {
    // A parent and its archived sub-run records are one conversation. Restore
    // the root row and the host moves the complete family back together. An
    // old orphan child still owns a row and can therefore be restored.
    archived_rows.push(archived_row(dispatch, dev.channel, row.item))
  }
  if archived_rows.length() > 0 {
    rows.push(
      @html.details(class="sidebar-archived", [
        @html.summary(
          class="sidebar-heading archived-heading",
          "Archived (\{archived_rows.length()})",
        ),
        @html.div(class="archived-rows", archived_rows),
      ]),
    )
  }
  rows
}

///|
/// One store's conversation rows: the app-run-only (unlisted) conversations
/// newest first, then the store's durable sessions in list order — the same
/// ordering the flat sidebar always had, applied per group.
fn push_group_rows(
  rows : Array[@html.Html],
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dev : DeviceState,
  workspace : @common.Uri?,
  listed~ : (String) -> Bool,
  archived~ : (String) -> Bool,
  nested? : Bool = false,
) -> Unit {
  // Conversations worth keeping get a row, plus the one fresh "New chat" on
  // screen: it owns a row from the moment its ＋ was clicked, so the rotation
  // has visible feedback in the list; the row takes the real title at the
  // first send. Empty husks (a fresh chat the user navigated away from
  // without writing anything) stay hidden — but one holding an unsent draft
  // is kept precisely so it can be returned to, and a row is the only way
  // back to it.
  let composing = model.composing_new_chat()
  for conv in model.conversations.rev_iter() {
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
    if conv.worth_keeping() {
      rows.push(
        session_row(
          dispatch,
          model,
          dev.channel,
          conv.session_id,
          conversation_title(conv),
          nested~,
          worktree?,
        ),
      )
    } else if composing &&
      conv.device == model.focused &&
      conv.session_id == model.active_session {
      rows.push(
        session_row(
          dispatch,
          model,
          dev.channel,
          conv.session_id,
          "New chat",
          nested~,
          worktree?,
        ),
      )
    }
  }
  let durable : Array[@transcript.SessionListItem] = []
  for item in dev.sessions {
    if item.workspace != workspace || archived(item.id) {
      continue
    }
    durable.push(item)
  }
  // A conversation's label follows the live conversation while it is the one
  // on screen (its title settles at the first send), and otherwise comes from
  // the host's listing.
  fn label_of(item : @transcript.SessionListItem) -> String {
    if model.find_conversation(dev.channel, item.id) is Some(conv) &&
      dev.channel == model.focused &&
      item.id == model.active_session {
      conversation_title(conv)
    } else {
      session_item_label(item)
    }
  }

  // Sub-run transcripts fold under the conversation that launched them: they
  // are that turn's evidence, not conversations of their own, and one worker
  // sweep persists enough of them to bury the real chats. The parent row's
  // twisty shows them in place, the way a tree unfolds a directory.
  for row in @transcript.session_tree(durable) {
    let expanded = model.subruns_expanded(dev.channel, row.item.id)
    rows.push(
      session_row(
        dispatch,
        model,
        dev.channel,
        row.item.id,
        label_of(row.item),
        // Ordinary children are folded below a live parent and receive no
        // action. A child-shaped root is legacy split state (or belongs to a
        // parent in another store), so it remains independently archivable;
        // once beside its archived parent, family restore picks it up.
        archivable=true,
        nested~,
        worktree?=worktree_name_for(dev, workspace, row.item.id),
        subruns=row.children.length(),
        expanded~,
      ),
    )
    if expanded {
      for child in row.children {
        // The ordinal leads the row: it is what the transcript's sub-run
        // lines name, and it orders runs whose questions read alike. A child
        // that never got a question keeps the ordinal alone — its id would
        // only repeat the parent's.
        let question = match child.title {
          Some(title) if !title.is_blank() => Some(title)
          _ => None
        }
        let label = match (@transcript.subrun_label(child.id), question) {
          (Some(ordinal), Some(title)) => "\{ordinal} · \{title}"
          (Some(ordinal), None) => ordinal
          (None, _) => session_item_label(child)
        }
        rows.push(
          session_row(
            dispatch,
            model,
            dev.channel,
            child.id,
            label,
            nested~,
            subrun=true,
          ),
        )
      }
    }
  }
}

///|
/// One attached project: a folder row (full path in the tooltip) with its
/// conversations nested beneath it. Hover controls open the row's "…" menu
/// (workspace settings, detach) or start a new chat in the project. The
/// active project — where a plain "New chat" lands — reads as the darker
/// label.
fn project_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dev : DeviceState,
  path : @common.Uri,
) -> @html.Html {
  @sidebar.WorkspaceRow::{
    title: path.path,
    label: @resource.label(path),
    active: dev.channel == model.focused && dev.active_project == Some(path),
    menu: Some({
      title: "More actions",
      open: model.project_menu == Some({ channel: dev.channel, project: path }),
      toggle: dispatch(ToggleProjectMenu(dev.channel, path)),
      body: () => project_menu_body(dispatch, dev.channel, path),
    }),
    actions: [
      {
        title: "New chat in this project",
        command: dispatch(NewChatIn(dev.channel, Some(path))),
        image: icon_add,
      },
    ],
  }.render()
}

///|
/// The project row's "…" dropdown: the workspace settings page, and the
/// detach that used to ride the hover slot. A click away closes it (see
/// `dismiss_subscription`).
fn project_menu_body(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : @common.Uri,
) -> @html.Html {
  @html.div(class="workspace-menu", [
    @html.button(
      class="workspace-menu-item",
      type_="button",
      title="Defaults for new chats in this workspace",
      on_click=dispatch(OpenWorkspaceSettings(channel, path)),
      [icon(icon_settings_gear), @html.span("Workspace settings")],
    ),
    @html.button(
      class="workspace-menu-item",
      type_="button",
      title="Detach this project — its files and sessions stay",
      on_click=dispatch(RemoveProject(channel, path)),
      [icon(icon_close), @html.span("Detach project")],
    ),
  ])
}

///|
/// A sidebar entry's display label: its engine-reported title, or the
/// session id for a conversation with no user message yet (absent or blank
/// title).
fn session_item_label(item : @transcript.SessionListItem) -> String {
  if item.title is Some(title) && !title.is_blank() {
    title
  } else {
    item.id
  }
}

///|
/// One row of the Archived group: the conversation's title and a
/// hover-revealed restore button. The row is inert — an archived record is
/// invisible to `load_session` until it is restored, so the click that
/// brings it back is the unarchive control.
fn archived_row(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  item : @transcript.SessionListItem,
) -> @html.Html {
  @html.div(class="conversation-row archived", title=item.id, [
    @html.span(class="sidebar-label", session_item_label(item)),
    @html.button(
      class="row-archive",
      type_="button",
      title="Restore this conversation to the sidebar",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        dispatch(UnarchiveSession(channel, item.id))
      }),
      icon(icon_arrow_up),
    ),
  ])
}

///|
fn sidebar_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let sessions_section : Array[@html.Html] = []
  for row in session_rows(dispatch, model) {
    sessions_section.push(row)
  }
  // A 46px header matching the content column's topbar, so the sidebar
  // toggle rides the window's left edge here while the sidebar is open and
  // at the same screen position while it's closed — the topbar's left on
  // Chat, a floating button on Skills/Settings (see `page_with_toggle`) —
  // mirroring how the right-panel toggle stays put (topbar-right when
  // closed, breadcrumb-right when open). New chat rides the header's right
  // edge on every screen — rotating a session lands back on Chat regardless.
  let header_children : Array[@html.Html] = [
    @html.button(
      class="topbar-toggle",
      title="Hide sidebar",
      on_click=dispatch(ToggleSidebar),
      icon(icon_layout_sidebar_left),
    ),
  ]
  header_children.push(
    @html.button(
      class="topbar-toggle header-new-chat",
      title="New chat",
      on_click=dispatch(NewChat),
      icon(icon_add),
    ),
  )
  @html.aside([
    @html.div(class="sidebar-header", header_children),
    @html.div(class="sidebar-main", [
      @html.div(class="sidebar-section sessions", sessions_section),
    ]),
    @html.div(class="sidebar-footer", sidebar_footer_buttons(dispatch, model)),
  ])
}

///|
/// The sidebar footer: Skills and Settings, and — while an installable
/// release is on offer — the accent Update button above them, tracking the
/// download so its progress stays visible from any screen.
fn sidebar_footer_buttons(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let buttons : Array[@html.Html] = []
  let update_label : String? = match model.update_ux {
    UpdateAvailable(installable=true, ..) | ConfirmingRestart(..) =>
      Some("Update")
    DownloadingUpdate(progress~, ..) => Some(progress.sidebar_label())
    RestartingForUpdate(..) => Some("Restarting…")
    _ => None
  }
  if update_label is Some(label) {
    buttons.push(
      @html.button(
        class="sidebar-button primary",
        disabled=!(model.update_ux is UpdateAvailable(..)),
        on_click=dispatch(UpdateClicked),
        [
          @html.span(class="sidebar-icon", icon(icon_arrow_up)),
          @html.span(class="sidebar-label", label),
        ],
      ),
    )
  }
  buttons.push(
    @html.button(
      class=if model.screen is Skills {
        "sidebar-button active"
      } else {
        "sidebar-button"
      },
      on_click=dispatch(OpenSkills),
      [
        @html.span(class="sidebar-icon", icon(icon_extensions)),
        @html.span(class="sidebar-label", "Skills"),
      ],
    ),
  )
  buttons.push(
    @html.button(
      class=if model.screen is Settings {
        "sidebar-button active"
      } else {
        "sidebar-button"
      },
      on_click=dispatch(OpenSetup),
      [
        @html.span(class="sidebar-icon", icon(icon_settings_gear)),
        @html.span(class="sidebar-label", "Settings"),
      ],
    ),
  )
  // The console's account row: who is signed in, a roster refresh, and the
  // sign-out — with the last account-level failure inline beneath it.
  if model.console is Some(console) &&
    console.auth is AuthSignedIn(login~, avatar~) {
    let account : Array[@html.Html] = []
    if !avatar.is_empty() {
      account.push(@html.img(class="console-avatar", src=avatar, alt=login))
    }
    account.push(@html.span(class="console-login", "@\{login}"))
    account.push(
      @html.button(
        class="console-account-action",
        disabled=console.busy,
        title="Refresh the device list",
        on_click=dispatch(Console(RefreshClicked)),
        "Refresh",
      ),
    )
    account.push(
      @html.button(
        class="console-account-action",
        disabled=console.busy,
        on_click=dispatch(Console(SignOutClicked)),
        "Sign out",
      ),
    )
    buttons.push(@html.div(class="console-account", account))
    if console.notice is Some(notice) {
      buttons.push(@html.div(class="console-notice", notice))
    }
  }
  buttons
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
/// Composer key handling. While the completion menu is open it captures the
/// navigation keys — ↑/↓ move the highlight, Enter/Tab accept, Escape closes —
/// so they drive the menu instead of the textarea; everything else (and every
/// key with the menu closed) falls through to the normal submit shortcut.
fn task_attrs(dispatch : @cmd.Emit[Msg], menu_open : Bool) -> @html.Attrs {
  @html.Attrs::build().on_keydown(fn(event) {
    if menu_open {
      match event.key() {
        "ArrowDown" => {
          event.prevent_default()
          dispatch(CompletionMove(1))
        }
        "ArrowUp" => {
          event.prevent_default()
          dispatch(CompletionMove(-1))
        }
        "Tab" => {
          event.prevent_default()
          dispatch(CompletionAccept)
        }
        "Enter" =>
          if !event.shift_key() && !event.is_composing() {
            event.prevent_default()
            dispatch(CompletionAccept)
          } else {
            @cmd.none
          }
        "Escape" => {
          event.prevent_default()
          dispatch(CompletionDismiss)
        }
        _ => @cmd.none
      }
    } else if is_submit_shortcut(event) {
      event.prevent_default()
      dispatch(Send)
    } else {
      @cmd.none
    }
  })
}

///|
/// The completion menu floating above the composer: one row per match, the
/// highlighted row marked for the keyboard and clickable by mouse. A pointer
/// press accepts a row; `mousedown` (not `click`) is used so the textarea does
/// not blur the menu away before the selection registers.
fn completion_popup(
  dispatch : @cmd.Emit[Msg],
  completion : Completion,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for index, item in completion.items {
    let selected = index == completion.selected
    let row_class = if selected {
      "completion-item selected"
    } else {
      "completion-item"
    }
    rows.push(
      @html.div(
        class=row_class,
        attrs=@html.Attrs::build().on_mousedown(fn(event) {
          // Keep focus in the textarea; accept the row the press landed on.
          event.prevent_default()
          dispatch(CompletionPick(index))
        }),
        [
          @html.span(class="completion-label", item.label),
          @html.span(class="completion-detail", item.detail),
        ],
      ),
    )
  }
  // A `#` menu opens before its results arrive, so an empty list is a state to
  // narrate — searching, or genuinely nothing — not an empty box.
  if rows.is_empty() {
    let text = if completion.loading { "Searching…" } else { "No symbols" }
    rows.push(@html.div(class="completion-empty", text))
  }
  let hint = match completion.kind {
    SlashCommands => "Commands"
    SkillMentions => "Skills"
    Symbols => "Symbols"
  }
  @html.div(class="completion-menu", [
    @html.div(class="completion-hint", hint),
    @html.div(class="completion-list", rows),
  ])
}

///|
/// The chips above the textarea for the draft's mentions (`$` skills, `#`
/// symbols, `✎` editor comments), each removable by its `×`. Always rendered
/// (empty when there are no chips) so the textarea keeps a stable child index
/// and never loses focus when a chip comes or goes; CSS collapses the empty
/// tray to nothing. A chip with a resolved location is also clickable,
/// opening (or refocusing) the editor side-panel on that spot; a comment
/// chip's tooltip is the comment itself.
fn mention_tray(dispatch : @cmd.Emit[Msg], conv : Conversation) -> @html.Html {
  let chips : Array[@html.Html] = []
  for index, mention in conv.mentions {
    let glyph = @html.span(
      class="mention-glyph",
      @mention_context.glyph(mention.ref_),
    )
    let label = @html.span(
      class="mention-label",
      @mention_context.label(mention.ref_),
    )
    let body = if @mention_context.target(mention.ref_) is Some(target) {
      @html.button(
        class="mention-jump",
        type_="button",
        title=if mention.ref_ is Annotation(comment~, ..) {
          comment
        } else {
          "Jump to \{target.file}"
        },
        on_click=dispatch(JumpToMention(index)),
        [glyph, label],
      )
    } else {
      @html.span(class="mention-body", [glyph, label])
    }
    chips.push(
      @html.div(class="mention-chip", [
        body,
        @html.button(
          class="mention-remove",
          type_="button",
          title="Remove",
          on_click=dispatch(RemoveMention(index)),
          icon(icon_close),
        ),
      ]),
    )
  }
  @html.div(class="mention-tray", chips)
}

///|

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
fn composer_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let conv = model.active()
  let checkout = model.checkout_placement(conv)
  // Goal mode: `/goal` (or the banner's Edit) rebinds the composer's one
  // textarea to the goal draft for this conversation — the prompt draft
  // survives untouched underneath, and the same DOM node keeps focus.
  let goal_editor = conv.goal_edit
  let goal_mode = goal_editor is Some(_)
  let transcript_ready = conv.sync is Synced &&
    !conv.has_unresolved_run_tail_notice()
  let checkout_ready = checkout is Some(@interop.WorkspaceRoot) ||
    checkout is Some(@interop.Worktree(_))
  let has_input = model.bridge_state() is Connected(..) &&
    model.api_ready() &&
    transcript_ready &&
    checkout_ready &&
    conv.draft_sendable()
  // A compacting conversation cannot accept a prompt either: the serve
  // engine would queue it behind the compaction, where Stop cannot reach it.
  // Every unsettled phase — requested, queued, or running — holds the gate.
  let can_send = !conv.is_running() &&
    conv.compaction is NotCompacting &&
    has_input
  // The left status group: the conversation's model, then one git chip — the
  // branch's pull request, or the branch itself, tinted by CI — which opens
  // the rest (changes, base, links out) in a popover rather than spending the
  // row's remaining width on it.
  let status : Array[@html.Html] = [model_chip(dispatch, conv)]
  if git_chip(dispatch, model, conv) is Some(chip) {
    status.push(chip)
  }
  // The launch mode: a fresh workspace conversation chooses between the
  // workspace itself and a fresh host-named worktree (its 1:1 execution
  // environment) here, Codex-style, before its first prompt.
  if worktree_mode_chip(dispatch, model, conv) is Some(chip) {
    status.push(chip)
  }
  let controls : Array[@html.Html] = [
    @html.div(class="composer-status", status),
  ]
  if goal_editor is Some(editor) {
    // Goal mode replaces the send/steer cluster: the input edits the
    // standing goal, so the only action left here is Set — cancelling rides
    // the status group's lit chip, clearing rides the banner's ✕. No
    // run/compaction gate: a goal is welcome in every engine phase.
    controls.push(
      @html.button(
        id="goal-set",
        class="icon-button send-button",
        title="Set the standing goal (Enter)",
        disabled=editor.draft.is_blank(),
        on_click=dispatch(SubmitGoal),
        icon(icon_arrow_up),
      ),
    )
  } else if conv.is_running() {
    // One morphing button while this conversation's turn runs. It becomes a
    // steer submit only when the durable boundary is ready too; a draft must
    // never hide Stop behind a disabled Send during reload/reconciliation.
    let can_steer = has_input &&
      conv.run_durable_floor is Some(_) &&
      conv.run is Open(stage~, ..) &&
      !(stage is Cancelling)
    if !can_steer {
      controls.push(
        @html.button(
          id="stop",
          class="icon-button stop-button",
          title="Stop",
          disabled=!can_stop(conv),
          on_click=dispatch(Stop),
          icon(icon_debug_stop),
        ),
      )
    } else {
      controls.push(
        @html.button(
          id="send",
          class="icon-button send-button",
          title="Steer the running task",
          disabled=false,
          on_click=dispatch(Send),
          icon(icon_arrow_up),
        ),
      )
    }
  } else {
    controls.push(
      @html.button(
        id="send",
        class="icon-button send-button",
        title="Send",
        disabled=!can_send,
        on_click=dispatch(Send),
        icon(icon_arrow_up),
      ),
    )
  }
  // Keep every row above the input in one permanent context container. Beside
  // a tall terminal this is the only auxiliary vertical scroller, so plans and
  // notices yield space before the textarea or toolbar can disappear. Its
  // first two children remain permanent to preserve the plan panel's DOM state.
  let context : Array[@html.Html] = [
    connection_banner(model),
    @plan.panel(conv.visible_items()),
  ]
  if !conv.pending_steers().is_empty() {
    context.push(pending_steers_panel(conv))
  }
  // The requested phase reads as compacting already: the distinction (the
  // host may still be spawning the engine) is not the user's problem.
  match conv.compaction {
    Requested | Compacting =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(class="composer-notice-text", "Compacting context…"),
        ]),
      )
    Queued =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(
            class="composer-notice-text",
            "Compaction queued — starts when the current turn ends",
          ),
        ]),
      )
    NotCompacting => ()
  }
  // The conversation's execution environment vanished under it. The host
  // refuses to run it rather than silently falling back to the main
  // checkout, so the composer explains that and offers both ways out.
  match checkout {
    None =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(
            class="composer-notice-text",
            "Waiting for workspace placement…",
          ),
          @html.button(
            class="composer-notice-btn",
            type_="button",
            title="Request this workspace's worktree list again",
            on_click=dispatch(RetryWorktreePlacement),
            "Retry",
          ),
        ]),
      )
    Some(@interop.MissingWorktree(name~)) =>
      context.push(
        missing_worktree_notice(dispatch, conv.device, conv.session_id, name),
      )
    Some(_) => ()
  }
  // The goal row rides the same slot as the compaction notice: what the
  // composer is editing, or what stands. Pushed unconditionally — see
  // `goal_banner` for why it collapses instead of leaving.
  context.push(
    goal_banner(
      dispatch,
      conv.goal,
      editing=goal_editor,
      pending=conv.goal_pending.map(pending => pending.request),
    ),
  )
  let inner : Array[@html.Html] = [
    // This stable wrapper gives the textarea the height left by the permanent
    // mention tray. Only the textarea scrolls beside a tall terminal; the
    // toolbar and upward-opening menus stay outside it, and the textarea's
    // child index never changes as chips come and go.
    @html.div(class="composer-input", [
      mention_tray(dispatch, conv),
      @html.textarea(
        id="task",
        value=if goal_editor is Some(editor) { editor.draft } else { conv.task },
        placeholder=if goal_mode {
          "Describe the standing goal for this conversation — Enter sets it, Esc cancels."
        } else if conv.is_running() {
          "Steer the running task — your message joins it at the next step."
        } else {
          "Ask OpenSeek to inspect, edit, or explain this workspace."
        },
        on_input=dispatch.map(value => {
          if goal_mode {
            GoalDraftEdited(value)
          } else {
            TaskChanged(value)
          }
        }),
        attrs=(if goal_mode {
          goal_attrs(dispatch)
        } else {
          task_attrs(dispatch, model.completion is Some(_))
        }).data_set("focus-target", ""),
        "",
      ),
    ]),
    @html.div(class="composer-toolbar", [
      @html.div(class="composer-controls", controls),
    ]),
  ]
  // The menu floats above the composer via CSS, so its DOM position does not
  // affect layout. It is appended last (not inserted before the textarea) so
  // toggling it never shifts the input wrapper or toolbar — index-based vdom
  // diffing would otherwise rebuild the textarea subtree and drop its focus.
  if model.completion is Some(completion) {
    inner.push(completion_popup(dispatch, completion))
  }
  // The context and input wrappers are both permanent siblings. Conditional
  // rows can change inside the context without renumbering or rebuilding the
  // focus-holding textarea subtree.
  let children : Array[@html.Html] = [
    @html.div(class="composer-context", context),
    @html.div(
      class="composer-inner",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      inner,
    ),
  ]
  @html.section(class="composer", children)
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
  // authoritative read on this connection lands. An older host without
  // per-workspace settings never answers, and the select stays disabled
  // rather than pretending a choice would stick.
  let row = match model.device_state(channel) {
    Some(dev) => dev.workspace_settings_row(workspace)
    None => None
  }
  let worktree_mode = row is Some(row) && row.worktree_mode
  // Missing is the historical behavior, but the disabled control makes it
  // clear that no authoritative workspace snapshot has landed yet.
  let checkout_submodules = row is None ||
    (row is Some(row) && row.checkout_submodules)
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
test "settings, skills, and composer declare form focus ownership" {
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
  let composer_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(composer_view(dispatch, test_model()))
  })
  assert_true(composer_markup.contains("class=\"composer-inner\""))
  assert_true(composer_markup.contains("data-focus-owner=\"\""))
  assert_true(composer_markup.contains("data-focus-target=\"\""))
  let address_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @preview.toolbar_view(
        { url: None, input: "", title: "", loading: false, failure: None },
        {
          input: dispatch.map(value => TaskChanged(value)),
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
  for
    markup in [settings_markup, skills_markup, composer_markup, address_markup] {
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
      class=if model.terminal_open {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
      title=if model.terminal_open {
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
        composer_view(dispatch, model),
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
  if model.terminal_open {
    content_class = content_class + " terminal-open"
  }
  let children : Array[@html.Html] = [
    sidebar_view(dispatch, model),
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
#warnings("-alert_unstable")
test "archived families collapse while a live orphan child stays archivable" {
  let archived_model = test_model().with_dev(dev => {
    ..dev,
    archived: [archived_item("chat"), archived_item("chat-sr-1")],
  })
  let archived_dev = archived_model.dev()
  let archived_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @html.div(
        device_section_rows(test_dispatch(), archived_model, archived_dev),
      ),
    )
  })
  assert_true(archived_markup.contains("Archived (1)"))
  assert_true(archived_markup.contains("title=\"chat\""))
  assert_false(archived_markup.contains("chat-sr-1"))
  let orphan_model = test_model().with_dev(dev => {
    ..dev,
    sessions: [archived_item("chat-sr-1")],
  })
  let orphan_dev = orphan_model.dev()
  let orphan_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @html.div(device_section_rows(test_dispatch(), orphan_model, orphan_dev)),
    )
  })
  assert_true(orphan_markup.contains("chat-sr-1"))
  assert_true(orphan_markup.contains("Archive — tuck this chat away"))
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
