// The Skills page's state machine. Every transition is pure: the host calls
// live in `requests.mbt` and reach the page back as `Msg` values.

///|
/// The mooncakes.io skill catalog as the page sees it. One enum, so
/// "loading", "loaded empty" and "failed" cannot be conflated. Loading keeps
/// the source device so opening the page on another device starts its own
/// request instead of inheriting an in-flight request it cannot settle.
priv enum Catalog {
  Idle
  Loading(channel~ : @interop.ChannelId)
  Ready(Array[MarketItem])
  Failed(String)
} derive(Eq)

///|
/// Everything the page alone can see. The catalog is fetched when the page
/// opens and kept until the user refreshes it; `busy` holds the entries with
/// an operation in flight, keyed by host and version-independent identity;
/// notices retain the scope of each failure.
struct State {
  catalog : Catalog
  query : String
  busy : Array[PendingOperation]
  notices : Array[Notice]
  preview : Preview
  preview_cache : Map[(@interop.ChannelId, String), String]
  preview_channel : @interop.ChannelId?
  list_scroll_top : Double
} derive(Eq)

///|
priv enum Notice {
  SkillActionFailed(operation~ : PendingOperation, message~ : String)
  LibraryLoadFailed(String)
  BuiltinSyncFailed(
    channel~ : @interop.ChannelId,
    error~ : @protocol.BuiltinSkillError
  )
} derive(Eq)

///|
priv struct PendingOperation {
  channel : @interop.ChannelId
  identity : PendingTarget
  action : PendingSkillAction
} derive(Eq)

///|
/// Installation and enablement are independent operations. Registry actions
/// follow the package identity; switches follow the installed library entry.
priv enum PendingTarget {
  Registry((String, String))
  LibraryEntry(String)
} derive(Eq)

///|
fn Notice::belongs_to(
  self : Notice,
  channel : @interop.ChannelId,
  identity : PendingTarget,
) -> Bool {
  match self {
    SkillActionFailed(operation~, ..) =>
      operation.channel == channel && operation.identity == identity
    LibraryLoadFailed(_) | BuiltinSyncFailed(..) => false
  }
}

///|
pub(all) enum PendingSkillAction {
  Installing(source~ : String)
  Uninstalling(source~ : String, id~ : String)
  Updating(source~ : String)
  SettingEnabled(source~ : String, id~ : String, enabled~ : Bool)
} derive(Eq)

///|
pub extend PendingSkillAction with Eq::{equal, not_equal}

///|
fn PendingSkillAction::source(self : PendingSkillAction) -> String {
  match self {
    Installing(source~)
    | Uninstalling(source~, ..)
    | Updating(source~)
    | SettingEnabled(source~, ..) => source
  }
}

///|
/// Whether this operation decides the entry's lifecycle, so the enable switch
/// must not race it. Updating keeps the entry in place and leaves the switch
/// usable; a pending enablement is handled by the switch's own pending state.
fn PendingSkillAction::blocks_enablement(self : PendingSkillAction) -> Bool {
  match self {
    Installing(..) | Uninstalling(..) => true
    Updating(..) | SettingEnabled(..) => false
  }
}

///|
fn State::pending_action(
  self : State,
  channel : @interop.ChannelId,
  identity : (String, String),
) -> PendingSkillAction? {
  for operation in self.busy {
    guard operation.channel == channel &&
      operation.identity == PendingTarget::Registry(identity) else {
      continue
    }
    return Some(operation.action)
  }
  None
}

///|
fn State::pending_enabled(
  self : State,
  channel : @interop.ChannelId,
  id : String,
) -> Bool {
  self.busy
  .iter()
  .any(operation => {
    operation.channel == channel &&
    operation.identity == PendingTarget::LibraryEntry(id)
  })
}

///|
fn State::start_action(
  self : State,
  channel : @interop.ChannelId,
  identity : PendingTarget,
  action : PendingSkillAction,
  cmd : @cmd.Cmd,
) -> (@cmd.Cmd, State, Outcome?) {
  guard !self.busy
    .iter()
    .any(operation => {
      operation.channel == channel && operation.identity == identity
    }) else {
    return (@cmd.none, self, None)
  }
  let busy = self.busy.copy()
  busy.push({ channel, identity, action, })
  (
    cmd,
    {
      ..self,
      busy,
      notices: self.notices.filter(notice => {
        !notice.belongs_to(channel, identity)
      }),
    },
    None,
  )
}

///|
fn State::update_candidate(self : State, item : InstalledItem) -> MarketItem? {
  guard item.registry is Some(registry) else { return None }
  guard self.catalog is Ready(items) else { return None }
  for candidate in items {
    guard candidate.identity() == (registry.module_name, registry.package_path) &&
      source_label(candidate) != item.source else {
      continue
    }
    return Some(candidate)
  }
  None
}

///|
enum Preview {
  Closed
  Loading(target~ : PreviewTarget, request~ : Int32)
  Ready(target~ : PreviewTarget, request~ : Int32, content~ : String)
  Failed(target~ : PreviewTarget, request~ : Int32, message~ : String)
} derive(Eq)

///|
/// The subject a preview was opened for. For `Installed`, this is the snapshot
/// the read was issued against: an enablement-only library change deliberately
/// leaves it untouched so the outstanding read can still settle. Its `enabled`
/// is therefore historical; render live state from `Input.installed`, as
/// `detail_action_target` does.
enum PreviewTarget {
  Market(MarketItem)
  Installed(InstalledItem)
} derive(Eq)

///|
/// A page that has never been opened: no catalog, no filter, nothing in
/// flight.
pub fn State::empty() -> State {
  {
    catalog: Idle,
    query: "",
    busy: [],
    notices: [],
    preview: Closed,
    preview_cache: Map([]),
    preview_channel: None,
    list_scroll_top: 0.0,
  }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  RefreshCatalog
  CatalogLoaded(channel~ : @interop.ChannelId, items~ : Array[MarketItem])
  CatalogFailed(channel~ : @interop.ChannelId, message~ : String)
  Install(MarketItem)
  // Capture the source alongside the library id before the entry disappears.
  Uninstall(InstalledItem)
  Update(MarketItem)
  ToggleEnabled(String)
  // A skill operation settled: `action` is the operation to release, and
  // an `error` becomes a notice for that skill (a success reports the
  // library change to the root instead).
  ActionDone(
    channel~ : @interop.ChannelId,
    action~ : PendingSkillAction,
    error~ : String?
  )
  PreviewMarket(MarketItem)
  PreviewInstalled(InstalledItem)
  PreviewLoaded(
    channel~ : @interop.ChannelId,
    request~ : Int32,
    target~ : PreviewTarget,
    content~ : String
  )
  PreviewFailed(
    channel~ : @interop.ChannelId,
    request~ : Int32,
    target~ : PreviewTarget,
    message~ : String
  )
  BackToList
  SkillsScrolled(Double)
}

///|
/// Open the page. The catalog is fetched once per app run (and again after a
/// failure, a manual refresh, or a device switch during loading). Only the
/// library loading error is cleared: operation errors belong to their skills.
/// The installed library is refreshed by the root, which owns it.
pub fn State::opening(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
) -> (@cmd.Cmd, State) {
  let (cmd, catalog) = match self.catalog {
    Idle | Failed(_) =>
      (
        fetch_catalog(emit, input.channel),
        Catalog::Loading(channel=input.channel),
      )
    Loading(channel~) =>
      if channel == input.channel {
        (@cmd.none, self.catalog)
      } else {
        (fetch_catalog(emit, input.channel), Loading(channel=input.channel))
      }
    current => (@cmd.none, current)
  }
  let notices = self.notices.filter(notice => !(notice is LibraryLoadFailed(_)))
  (cmd, { ..self, catalog, notices, })
}

///|
/// Show a failure the page did not cause. The root-owned library refresh is
/// the only such source: the page has no other way to learn that the list
/// under "Installed" could not be read.
pub fn State::with_library_error(self : State, message : String) -> State {
  let notices = self.notices.filter(notice => !(notice is LibraryLoadFailed(_)))
  notices.push(LibraryLoadFailed(message))
  { ..self, notices, }
}

///|
/// Replace startup-sync failures with the focused host's authoritative reply.
/// Errors can identify a missing builtin, so they are independent of the list.
pub fn State::with_builtin_errors(
  self : State,
  channel : @interop.ChannelId,
  errors : Array[@protocol.BuiltinSkillError],
) -> State {
  let notices = self.notices.filter(notice => !(notice is BuiltinSyncFailed(..)))
  for error in errors {
    notices.push(BuiltinSyncFailed(channel~, error~))
  }
  { ..self, notices, }
}

///|
/// The root calls this after refreshing its installed mirror, including
/// changes announced by another client. Reload an open document when its
/// installation changes; versioned cache keys keep old instructions separate.
pub fn State::sync_library(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
) -> (@cmd.Cmd, State) {
  guard self.preview_channel == Some(input.channel) else {
    return (@cmd.none, { ..self, preview: Closed, preview_channel: None, })
  }
  let target = match self.preview {
    Closed => return (@cmd.none, self)
    Loading(target~, ..) | Ready(target~, ..) | Failed(target~, ..) => target
  }
  let current = match target {
    Market(item) => preview_target_for_market(input.installed, item)
    Installed(item) => {
      guard input.installed.iter().find_first(skill => skill.id == item.id)
        is Some(current) else {
        return (@cmd.none, self)
      }
      Installed(current)
    }
  }
  let document_changed = match (target, current) {
    (Installed(previous), Installed(current)) =>
      { ..previous, enabled: current.enabled, } != current
    _ => current != target
  }
  // Enablement comes from the live input. Keep the document snapshot so an
  // outstanding read can still settle against the target it was issued for;
  // its `enabled` stays historical until the document itself changes.
  guard document_changed else { return (@cmd.none, self) }
  let request = preview_request_id(self.preview) + 1
  (
    fetch_content(emit, input.channel, request, current),
    { ..self, preview: Loading(target=current, request~), },
  )
}

///|
/// Return from a detail to the list, restoring its scroll position. `None`
/// means the page is already at the list and the shell owns the next return.
pub fn State::back(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
) -> (@cmd.Cmd, State)? {
  match self.preview {
    Closed => None
    _ => {
      let (cmd, state, _) = self.handle(emit, BackToList, input)
      Some((cmd, state))
    }
  }
}

///|
pub fn State::handle(
  self : State,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  input : Input,
) -> (@cmd.Cmd, State, Outcome?) {
  match msg {
    QueryChanged(value) => (@cmd.none, { ..self, query: value, }, None)
    PreviewMarket(item) => {
      let target = preview_target_for_market(input.installed, item)
      match self.preview_cache.get((input.channel, preview_cache_key(target))) {
        Some(content) =>
          (
            @cmd.none,
            {
              ..self,
              preview: Ready(target~, request=0, content~),
              preview_channel: Some(input.channel),
            },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_content(emit, input.channel, request, target),
            {
              ..self,
              preview: Loading(target~, request~),
              preview_channel: Some(input.channel),
            },
            None,
          )
        }
      }
    }
    PreviewInstalled(item) => {
      let target = Installed(item)
      match self.preview_cache.get((input.channel, preview_cache_key(target))) {
        Some(content) =>
          (
            @cmd.none,
            {
              ..self,
              preview: Ready(target~, request=0, content~),
              preview_channel: Some(input.channel),
            },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_installed_content(emit, input.channel, request, item),
            {
              ..self,
              preview: Loading(target~, request~),
              preview_channel: Some(input.channel),
            },
            None,
          )
        }
      }
    }
    PreviewLoaded(channel~, request~, target~, content~) => {
      guard channel == input.channel && self.preview_channel == Some(channel) else {
        return (@cmd.none, self, None)
      }
      guard self.preview is Loading(request=current, target=current_target) &&
        current == request &&
        current_target == target else {
        return (@cmd.none, self, None)
      }
      let cache = self.preview_cache.copy()
      cache[(channel, preview_cache_key(target))] = content
      (
        @cmd.none,
        {
          ..self,
          preview: Ready(target~, request~, content~),
          preview_cache: cache,
        },
        None,
      )
    }
    PreviewFailed(channel~, request~, target~, message~) => {
      guard channel == input.channel && self.preview_channel == Some(channel) else {
        return (@cmd.none, self, None)
      }
      guard self.preview is Loading(request=current, target=current_target) &&
        current == request &&
        current_target == target else {
        return (@cmd.none, self, None)
      }
      (
        @cmd.none,
        { ..self, preview: Failed(target~, request~, message~), },
        None,
      )
    }
    BackToList =>
      (
        restore_list_scroll(self.list_scroll_top),
        { ..self, preview: Closed, preview_channel: None, },
        None,
      )
    SkillsScrolled(scroll_top) =>
      (@cmd.none, { ..self, list_scroll_top: scroll_top, }, None)
    RefreshCatalog =>
      match self.catalog {
        // The rendered button is disabled while loading, and this guard also
        // makes programmatic duplicate messages harmless.
        Loading(channel~) if channel == input.channel => (@cmd.none, self, None)
        _ =>
          (
            fetch_catalog(emit, input.channel),
            { ..self, catalog: Loading(channel=input.channel), },
            None,
          )
      }
    CatalogLoaded(channel~, items~) => {
      // Catalog requests belong to the device that issued them. A completion
      // that outlived a focus switch must not overwrite the focused device's
      // catalog or its newer in-flight request.
      guard channel == input.channel else { return (@cmd.none, self, None) }
      (@cmd.none, { ..self, catalog: Ready(items), }, None)
    }
    CatalogFailed(channel~, message~) => {
      guard channel == input.channel else { return (@cmd.none, self, None) }
      (@cmd.none, { ..self, catalog: Failed(message), }, None)
    }
    ToggleEnabled(id) => {
      guard input.installed.iter().find_first(item => item.id == id)
        is Some(item) else {
        return (@cmd.none, self, None)
      }
      let payload : @protocol.SetSkillEnabledPayload = {
        id,
        enabled: !item.enabled,
      }
      let action = SettingEnabled(
        source=if item.source.is_empty() { item.name } else { item.source },
        id~,
        enabled=payload.enabled,
      )
      self.start_action(
        input.channel,
        PendingTarget::LibraryEntry(id),
        action,
        set_enabled(emit, input.channel, payload, action),
      )
    }
    Install(item) | Update(item) => {
      let source = source_label(item)
      let action : PendingSkillAction = {
        guard msg is Update(_) else { Installing(source~) }
        Updating(source~)
      }
      self.start_action(
        input.channel,
        PendingTarget::Registry(item.identity()),
        action,
        install(emit, input.channel, item, action),
      )
    }
    Uninstall(item) => {
      guard !item.builtin &&
        !input.installed
        .iter()
        .any(current => current.id == item.id && current.builtin) &&
        item.identity() is Some(identity) else {
        return (@cmd.none, self, None)
      }
      self.start_action(
        input.channel,
        PendingTarget::Registry(identity),
        Uninstalling(source=item.source, id=item.id),
        uninstall(emit, input.channel, item),
      )
    }
    ActionDone(channel~, action~, error~) => {
      let operation = self.busy
        .iter()
        .find_first(operation => {
          operation.channel == channel && operation.action == action
        })
      guard operation is Some(operation) else { return (@cmd.none, self, None) }
      let busy = self.busy.filter(operation => {
        !(operation.channel == channel && operation.action == action)
      })
      // A result that outlived a focus switch belongs to its old host: it
      // releases its busy entry, but it neither refreshes the library on
      // screen nor speaks for the page's notice. That host refetches when it
      // is focused again.
      guard channel == input.channel else {
        return (@cmd.none, { ..self, busy, }, None)
      }
      match error {
        None =>
          // The library changed; what the page shows must come from disk.
          (@cmd.none, { ..self, busy, }, Some(LibraryChanged(channel~)))
        Some(message) => {
          let notices = self.notices.filter(notice => {
            !notice.belongs_to(channel, operation.identity)
          })
          notices.push(SkillActionFailed(operation~, message~))
          (@cmd.none, { ..self, busy, notices, }, None)
        }
      }
    }
  }
}

///|
fn preview_request_id(preview : Preview) -> Int32 {
  match preview {
    Closed => 0
    Loading(request~, ..) | Ready(request~, ..) | Failed(request~, ..) =>
      request
  }
}

///|
fn preview_cache_key(target : PreviewTarget) -> String {
  match target {
    Market(item) => "market:\{source_label(item)}"
    Installed(item) => "installed:\{item.id}:\{item.source}"
  }
}

///|
fn preview_target_for_market(
  installed : Array[InstalledItem],
  item : MarketItem,
) -> PreviewTarget {
  for skill in installed {
    guard skill.identity() == Some(item.identity()) else { continue }
    return Installed(skill)
  }
  Market(item)
}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend Preview with Eq::{equal, not_equal}

///|
pub extend PreviewTarget with Eq::{equal, not_equal}
