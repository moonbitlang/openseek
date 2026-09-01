// The terminal panel's public state machine: a set of terminal tabs, each
// backed by one PTY session on the host and one emulator instance in the
// DOM (see host.mbt). Tabs are grouped by device channel and workspace — the
// panel shows only the active conversation's group, and every group's shells
// stay alive while the user looks elsewhere.

///|
/// Which device/workspace a tab belongs to. A terminal UUID identifies the
/// host session, while the channel retains the connection that owns and can
/// operate that PTY.
/// Main-checkout conversations in the same registered project directory on
/// one device share a group. A worktree is a separate group keyed by its
/// registered project and worktree name, while a scratch group is keyed by
/// its conversation. This prevents a worktree chat from ever displaying or
/// driving a shell whose cwd belongs to the main checkout.
priv enum WorkspaceKey {
  Project(@interop.ChannelId, @common.Uri)
  Worktree(@interop.ChannelId, @common.Uri, String)
  Scratch(@interop.ChannelId, String)
} derive(Eq)

///|
fn WorkspaceKey::channel(self : WorkspaceKey) -> @interop.ChannelId {
  match self {
    Project(channel, _) | Worktree(channel, _, _) | Scratch(channel, _) =>
      channel
  }
}

///|
priv enum TabStatus {
  /// `terminal_open` is in flight.
  TabOpening
  TabRunning
  /// Opening or driving the session failed.
  TabFailed(message~ : String)
} derive(Eq)

///|
/// One terminal tab. `key` is the panel's own stable handle (the emulator
/// instance is keyed by it, and it exists before the host names the
/// session); `id` is the host's session id once `terminal_open` replies.
/// `session`/`workspace_path` are the binding the tab was opened with —
/// restarts reuse them, so a tab never migrates between workspaces.
priv struct Tab {
  key : Int
  id : String?
  workspace : WorkspaceKey
  workspace_label : String
  session : String
  workspace_path : @common.Uri?
  status : TabStatus
} derive(Eq)

///|
pub struct State {
  priv open : Bool
  priv next_key : Int
  priv tabs : Array[Tab]
  /// The remembered active tab per workspace group, as an association list
  /// (small; a workspace rarely has more than a handful of tabs).
  priv active : Array[(WorkspaceKey, Int)]
  /// The tab whose emulator element is currently displayed (`None` while
  /// the panel is closed). Mirrors imperative DOM state so `sync` can tell
  /// when a conversation switch must re-aim the display — the switch itself
  /// produces no terminal message.
  priv shown : Int?
  /// Channel/session ids whose exit event beat their `terminal_open` reply.
  /// The reply is the first event that identifies the opening tab, so it
  /// consumes the pair and retires that tab instead of reviving an
  /// already-dead session.
  priv exited_before_open : Array[(@interop.ChannelId, String)]
  /// The color scheme last applied to every mounted emulator. Keeping this in
  /// model state lets `sync` refresh existing xterm instances exactly once
  /// when the application switches between light and dark mode.
  priv synced_dark_mode : Bool?
  /// Root-owned input snapshot used to retire dead channels. Keeping it
  /// beside the tabs makes input reconciliation a normal state transition.
  priv live_channels : Array[@interop.ChannelId]
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    open: false,
    next_key: 1,
    tabs: [],
    active: [],
    shown: None,
    exited_before_open: [],
    synced_dark_mode: None,
    live_channels: [],
  }
}

///|
/// Whether the shell grid should reserve the terminal row.
pub fn State::is_open(self : State) -> Bool {
  self.open
}

///|
/// The terminal package's view of the active conversation, recomputed per
/// dispatch by the main package (mirrors `@fileeditor.Ctx`).
pub struct Ctx {
  /// The host connection that owns every terminal opened from this context.
  channel : @interop.ChannelId
  session : String
  /// `None` until the host has identified this conversation's placement on
  /// the current connection. The value supplies both the registered project
  /// for host resolution and the concrete checkout for readiness checks.
  placement : @interop.CheckoutPlacement?
  dark_mode : Bool
  /// False from the first WebSocket loss until that channel reports ready
  /// again. The old connection's PTYs are already gone, so `sync` must not
  /// create their replacements on the dead transport.
  connected : Bool
} derive(Eq)

///|
/// Construct the terminal's read-only view of the active conversation.
pub fn Ctx::Ctx(
  channel~ : @interop.ChannelId,
  session~ : String,
  placement~ : @interop.CheckoutPlacement?,
  dark_mode~ : Bool,
  connected~ : Bool,
) -> Ctx {
  { channel, session, placement, dark_mode, connected, }
}

///|
/// The workspace group the active conversation belongs to, once its placement
/// has loaded. Returning `None` keeps an unresolved worktree conversation out
/// of the project-root group.
fn workspace_key(ctx : Ctx) -> WorkspaceKey? {
  guard ctx.placement is Some(placement) else { return None }
  match placement {
    @interop.Scratch(..) => Some(Scratch(ctx.channel, ctx.session))
    @interop.WorkspaceRoot(root~) => Some(Project(ctx.channel, root))
    @interop.Worktree(project~, name~, ..)
    | @interop.MissingWorktree(project~, name~) =>
      Some(Worktree(ctx.channel, project, name))
  }
}

///|
/// The tabs of the active conversation's workspace group, in creation order.
fn State::visible_tabs(self : State, ctx : Ctx) -> Array[Tab] {
  guard ctx.placement is Some(placement) &&
    placement.is_ready() &&
    workspace_key(ctx) is Some(key) else {
    return []
  }
  self.tabs.filter(tab => tab.workspace == key)
}

///|
/// The tab the panel should show for the active conversation's workspace:
/// the remembered choice while it still exists, else the group's newest tab.
fn State::active_tab(self : State, ctx : Ctx) -> Tab? {
  let visible = self.visible_tabs(ctx)
  guard !visible.is_empty() else { return None }
  guard workspace_key(ctx) is Some(group) else { return None }
  for entry in self.active {
    if entry.0 == group {
      for tab in visible {
        if tab.key == entry.1 {
          return Some(tab)
        }
      }
    }
  }
  visible.get(visible.length() - 1)
}

///|
fn State::tab_by_key(self : State, key : Int) -> Tab? {
  for tab in self.tabs {
    if tab.key == key {
      return Some(tab)
    }
  }
  None
}

///|
fn State::tab_by_id(
  self : State,
  channel : @interop.ChannelId,
  id : String,
) -> Tab? {
  for tab in self.tabs {
    if tab.workspace.channel() == channel &&
      tab.id is Some(tab_id) &&
      tab_id == id {
      return Some(tab)
    }
  }
  None
}

///|
/// Replace one tab (matched by key) with an updated copy.
fn State::replace_tab(self : State, updated : Tab) -> State {
  {
    ..self,
    tabs: self.tabs.map(tab => {
      if tab.key == updated.key {
        updated
      } else {
        tab
      }
    }),
  }
}

///|
/// Remember `key` as the workspace group's active tab.
fn State::remember_active(
  self : State,
  group : WorkspaceKey,
  key : Int,
) -> State {
  let active = self.active.filter(entry => entry.0 != group)
  active.push((group, key))
  { ..self, active, }
}

///|
pub(all) enum Msg {
  /// Show/hide the panel (every shell keeps running while hidden).
  ToggleTerminal
  /// `terminal_exit` event: the shell ended, so its tab retires.
  SessionExited(channel~ : @interop.ChannelId, id~ : String, code~ : Int)
  /// Open one more terminal in the active conversation's workspace.
  NewTerminal
  TabSelected(key~ : Int)
  /// Close a tab: its shell is torn down, its emulator disposed.
  TabClosed(key~ : Int)
  /// The tab's emulator is mounted, fitted, and reports its grid size.
  EmulatorReady(key~ : Int, cols~ : Int, rows~ : Int)
  /// `terminal_open` replied for the tab. The channel is retained because the
  /// tab may have been closed or the UI may have switched devices meanwhile.
  Opened(channel~ : @interop.ChannelId, key~ : Int, id~ : String)
  OpenFailed(key~ : Int, message~ : String)
  /// Keystrokes from one tab's emulator.
  UserInput(key~ : Int, data~ : String)
  /// A web URL activated through xterm's link addon. The main frontend routes
  /// it through the same dock/system-browser policy as conversation anchors.
  LinkActivated(url~ : String)
  /// xterm's `onBinary` payload, encoded as base64 so each JS character code
  /// reaches the PTY as exactly one byte instead of being UTF-8 re-encoded.
  BinaryInput(key~ : Int, data~ : String)
  /// `terminal_input` failed for the tab: the keystrokes were lost. The
  /// main package surfaces the message as an error toast (the panel has no
  /// toast rail of its own); the tab's status is untouched — a lost
  /// keystroke does not make the session failed.
  InputFailed(message~ : String)
  /// One tab's emulator re-fit to a new grid size.
  ViewportResized(key~ : Int, cols~ : Int, rows~ : Int)
}

///|
pub extend Ctx with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}
