// The Skills page's state machine. Every transition is pure: the host calls
// live in `requests.mbt` and reach the page back as `Msg` values.

///|
/// The mooncakes.io skill catalog as the page sees it. One enum, so
/// "loading", "loaded empty" and "failed" cannot be conflated. Loading keeps
/// the source device so opening the page on another device starts its own
/// request instead of inheriting an in-flight request it cannot settle.
#derive(Eq)
priv enum Catalog {
  Idle
  Loading(channel~ : @interop.ChannelId)
  Ready(Array[MarketItem])
  Failed(String)
}

///|
/// Everything the page alone can see. The catalog is fetched when the page
/// opens and kept until the user refreshes it; `busy` holds the entries with
/// an operation in flight, keyed by host and version-independent identity;
/// notices retain the scope of each failure.
#derive(Eq)
struct State {
  catalog : Catalog
  query : String
  busy : Array[PendingOperation]
  notices : Array[Notice]
  preview : Preview
  preview_cache : Map[(@interop.ChannelId, String), String]
  preview_channel : @interop.ChannelId?
  list_scroll_top : Double
}

///|
#derive(Eq)
priv enum Notice {
  SkillActionFailed(operation~ : PendingOperation, message~ : String)
  LibraryLoadFailed(String)
  BuiltinSyncFailed(
    channel~ : @interop.ChannelId,
    error~ : @protocol.BuiltinSkillError
  )
}

///|
#derive(Eq)
priv struct PendingOperation {
  channel : @interop.ChannelId
  identity : PendingTarget
  action : PendingSkillAction
}

///|
/// Installation and enablement are independent operations. Registry actions
/// follow the package identity; switches follow the installed library entry.
#derive(Eq)
priv enum PendingTarget {
  Registry((String, String))
  LibraryEntry(String)
}

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
#derive(Eq)
pub(all) enum PendingSkillAction {
  Installing(source~ : String)
  Uninstalling(source~ : String, id~ : String)
  Updating(source~ : String)
  SettingEnabled(source~ : String, id~ : String, enabled~ : Bool)
}

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
#derive(Eq)
enum Preview {
  Closed
  Loading(target~ : PreviewTarget, request~ : Int32)
  Ready(target~ : PreviewTarget, request~ : Int32, content~ : String)
  Failed(target~ : PreviewTarget, request~ : Int32, message~ : String)
}

///|
/// The subject a preview was opened for. For `Installed`, this is the snapshot
/// the read was issued against: an enablement-only library change deliberately
/// leaves it untouched so the outstanding read can still settle. Its `enabled`
/// is therefore historical; render live state from `Input.installed`, as
/// `detail_action_target` does.
#derive(Eq)
enum PreviewTarget {
  Market(MarketItem)
  Installed(InstalledItem)
}

///|
pub fn State::detail_open(self : State, channel : @interop.ChannelId) -> Bool {
  self.preview_channel == Some(channel) && !(self.preview is Closed)
}

///|
/// Initial state: no catalog, no filter, nothing in flight.
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

///|
fn test_skill(enabled~ : Bool, name~ : String = "widget") -> InstalledItem {
  {
    id: "acme-widget",
    name,
    description: "",
    source: "acme/widget@1.0.0",
    registry: Some({ module_name: "acme/widget", package_path: "", }),
    builtin: false,
    enabled,
  }
}

///|
fn test_input(installed~ : Array[InstalledItem]) -> Input {
  { channel: @interop.ChannelId::Local, installed, }
}

///|
fn test_emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
/// The request number of the read a preview is waiting on.
fn test_pending_request(preview : Preview) -> Int32 raise {
  match preview {
    Loading(request~, ..) => request
    _ => fail("expected a pending preview read")
  }
}

///|
fn test_market(version~ : String = "1.0.0") -> MarketItem {
  {
    name: "widget",
    module_name: "acme/widget",
    package_path: "",
    version,
    description: "Build widgets",
    author: "acme",
    repository: "",
  }
}

///|
fn test_step(
  state : State,
  msg : Msg,
  input : Input,
) -> (State, Outcome?) raise {
  let (_, next, outcome) = state.handle(test_emit(), msg, input)
  let (_, repeated, repeated_outcome) = state.handle(test_emit(), msg, input)
  assert_true(next == repeated)
  assert_true(outcome == repeated_outcome)
  (next, outcome)
}

///|
fn test_ready(state : State, input : Input) -> State raise {
  guard state.preview is Loading(target~, request~) else {
    fail("expected a content read")
  }
  test_step(
    state,
    PreviewLoaded(
      channel=input.channel,
      target~,
      request~,
      content="Skill body",
    ),
    input,
  ).0
}

///|
test "one catalog detail installs, reports uninstall failure, and retries removal" {
  let market = test_market()
  let skill = test_skill(enabled=true)
  let empty = test_input(installed=[])
  let installed = test_input(installed=[skill])
  let (catalog, _) = test_step(
    State::empty(),
    CatalogLoaded(channel=empty.channel, items=[market]),
    empty,
  )
  let (loading, _) = test_step(catalog, PreviewMarket(market), empty)
  let detail = test_ready(loading, empty)
  let (installing, _) = test_step(detail, Install(market), empty)
  assert_true(
    installing.busy is [{ action: Installing(source="acme/widget@1.0.0"), .. }],
  )
  let (done, outcome) = test_step(
    installing,
    ActionDone(
      channel=empty.channel,
      action=Installing(source=skill.source),
      error=None,
    ),
    empty,
  )
  assert_true(outcome is Some(LibraryChanged(channel=Local)))
  let (_, loading) = done.sync_library(test_emit(), installed)
  let detail = test_ready(loading, installed)
  assert_true(
    detail_action_target(Market(market), detail, installed) ==
    Some(Installed(skill)),
  )
  let (removing, _) = test_step(detail, Uninstall(skill), installed)
  let action = Uninstalling(source=skill.source, id=skill.id)
  assert_true(removing.busy is [{ action: pending, .. }] && pending == action)
  let (failed, outcome) = test_step(
    removing,
    ActionDone(
      channel=installed.channel,
      action~,
      error=Some("Cannot remove skill: permission denied"),
    ),
    installed,
  )
  assert_true(outcome is None)
  assert_true(failed.busy.is_empty())
  assert_eq(notice_messages(failed, installed, Some(Installed(skill))), [
    "Cannot remove skill: permission denied",
  ])
  assert_true(
    detail_action_target(Market(market), failed, installed) ==
    Some(Installed(skill)),
  )
  let (retry, _) = test_step(failed, Uninstall(skill), installed)
  assert_true(retry.notices.is_empty())
  let (removed, outcome) = test_step(
    retry,
    ActionDone(channel=installed.channel, action~, error=None),
    empty,
  )
  assert_true(outcome is Some(LibraryChanged(channel=Local)))
  assert_true(removed.detail_open(empty.channel))
  assert_true(
    detail_action_target(Installed(skill), removed, empty) ==
    Some(Market(market)),
  )
  assert_true(removed.busy.is_empty())
  assert_true(removed.notices.is_empty())
}

///|
test "late skill errors retain their targets across cached navigation and retry" {
  let skill = test_skill(enabled=true)
  let input = test_input(installed=[skill])
  let other = { ..test_market(), name: "other", module_name: "acme/other", }
  let (loading, _) = test_step(State::empty(), PreviewInstalled(skill), input)
  let ready = test_ready(loading, input)
  let (removing, _) = test_step(ready, Uninstall(skill), input)
  let removal = Uninstalling(source=skill.source, id=skill.id)
  let (list, _) = test_step(removing, BackToList, input)
  let (loading, _) = test_step(list, PreviewMarket(other), input)
  let ready = test_ready(loading, input)
  let (installing, _) = test_step(ready, Install(other), input)
  let (other_failed, _) = test_step(
    installing,
    ActionDone(
      channel=input.channel,
      action=Installing(source=source_label(other)),
      error=Some("Other install failed"),
    ),
    input,
  )
  let (both_failed, _) = test_step(
    other_failed,
    ActionDone(
      channel=input.channel,
      action=removal,
      error=Some("Removal failed after navigation"),
    ),
    input,
  )
  assert_eq(notice_messages(both_failed, input, Some(Market(other))), [
    "Other install failed",
  ])
  let (list, _) = test_step(both_failed, BackToList, input)
  assert_eq(notice_messages(list, input, None), [
    "acme/other@1.0.0: Other install failed", "acme/widget@1.0.0: Removal failed after navigation",
  ])
  let (cached_other, _) = test_step(list, PreviewMarket(other), input)
  assert_true(cached_other.preview is Ready(target=Market(_), request=0, ..))
  assert_eq(notice_messages(cached_other, input, Some(Market(other))), [
    "Other install failed",
  ])
  let (list, _) = test_step(cached_other, BackToList, input)
  let (cached_skill, _) = test_step(list, PreviewInstalled(skill), input)
  assert_true(cached_skill.preview is Ready(target=Installed(_), request=0, ..))
  assert_eq(notice_messages(cached_skill, input, Some(Installed(skill))), [
    "Removal failed after navigation",
  ])
  let (retry, _) = test_step(cached_skill, Uninstall(skill), input)
  assert_true(notice_messages(retry, input, Some(Installed(skill))).is_empty())
  let (done, outcome) = test_step(
    retry,
    ActionDone(channel=input.channel, action=removal, error=None),
    test_input(installed=[]),
  )
  assert_true(outcome is Some(LibraryChanged(channel=Local)))
  assert_eq(notice_messages(done, input, None), [
    "acme/other@1.0.0: Other install failed",
  ])
}

///|
test "handwritten enablement failure keeps the host value and retries the same operation" {
  let skill = {
    ..test_skill(enabled=true),
    id: "My notes",
    name: "My notes",
    source: "",
    registry: None,
  }
  let input = test_input(installed=[skill])
  let (loading, _) = test_step(State::empty(), PreviewInstalled(skill), input)
  let ready = test_ready(loading, input)
  let (sending, _) = test_step(ready, ToggleEnabled(skill.id), input)
  let action = SettingEnabled(source="My notes", id=skill.id, enabled=false)
  assert_true(sending.busy is [{ action: pending, .. }] && pending == action)
  assert_true(
    detail_action_target(Installed(skill), sending, input) ==
    Some(Installed(skill)),
  )
  let (failed, outcome) = test_step(
    sending,
    ActionDone(
      channel=input.channel,
      action~,
      error=Some("Cannot move skill: permission denied"),
    ),
    input,
  )
  assert_true(outcome is None)
  assert_false(failed.pending_enabled(input.channel, skill.id))
  assert_eq(notice_messages(failed, input, Some(Installed(skill))), [
    "Cannot move skill: permission denied",
  ])
  let (retry, _) = test_step(failed, ToggleEnabled(skill.id), input)
  assert_true(retry.busy is [{ action: pending, .. }] && pending == action)
  assert_true(retry.notices.is_empty())
  let (done, outcome) = test_step(
    retry,
    ActionDone(channel=input.channel, action~, error=None),
    input,
  )
  assert_true(outcome is Some(LibraryChanged(channel=Local)))
  let disabled = { ..skill, enabled: false, }
  let input = test_input(installed=[disabled])
  let (_, refreshed) = done.sync_library(test_emit(), input)
  assert_true(refreshed.preview == ready.preview)
  assert_true(
    detail_action_target(Installed(skill), refreshed, input) ==
    Some(Installed(disabled)),
  )
  assert_true(refreshed.notices.is_empty())
}

///|
test "updating and enablement settle independently and reload content only for a new version" {
  for enabled in [true, false] {
    let skill = test_skill(enabled~)
    let input = test_input(installed=[skill])
    let market = test_market(version="1.0.1")
    let (loading, _) = test_step(State::empty(), PreviewInstalled(skill), input)
    let ready = test_ready(loading, input)
    let (updating, _) = test_step(ready, Update(market), input)
    let update : PendingSkillAction = Updating(source=source_label(market))
    assert_true(
      updating.pending_action(input.channel, market.identity()) == Some(update),
    )
    assert_false(update.blocks_enablement())
    let (both, _) = test_step(updating, ToggleEnabled(skill.id), input)
    let toggle = SettingEnabled(
      source=skill.source,
      id=skill.id,
      enabled=!enabled,
    )
    assert_eq(both.busy.length(), 2)
    assert_true(both.busy.any(operation => operation.action == toggle))
    let (duplicate, _) = test_step(both, ToggleEnabled(skill.id), input)
    assert_true(duplicate == both)
    let (toggled, outcome) = test_step(
      both,
      ActionDone(channel=input.channel, action=toggle, error=None),
      input,
    )
    assert_true(outcome is Some(LibraryChanged(channel=Local)))
    let changed = { ..skill, enabled: !enabled, }
    let changed_input = test_input(installed=[changed])
    let (_, refreshed) = toggled.sync_library(test_emit(), changed_input)
    assert_true(refreshed.preview == ready.preview)
    assert_true(
      refreshed.pending_action(input.channel, market.identity()) == Some(update),
    )
    assert_false(refreshed.pending_enabled(input.channel, skill.id))
    let (done, outcome) = test_step(
      refreshed,
      ActionDone(channel=input.channel, action=update, error=None),
      changed_input,
    )
    assert_true(outcome is Some(LibraryChanged(channel=Local)))
    let upgraded = { ..changed, source: source_label(market), }
    let upgraded_input = test_input(installed=[upgraded])
    let (_, reloading) = done.sync_library(test_emit(), upgraded_input)
    assert_eq(
      test_pending_request(reloading.preview),
      preview_request_id(ready.preview) + 1,
    )
    let loaded = test_ready(reloading, upgraded_input)
    assert_true(loaded.busy.is_empty())
    assert_true(
      detail_action_target(Installed(skill), loaded, upgraded_input) ==
      Some(Installed(upgraded)),
    )
  }
}

///|
test "empty-library builtin failure survives catalog retry until host refresh confirms installation" {
  let input = test_input(installed=[])
  let market = test_market()
  let error : @protocol.BuiltinSkillError = {
    registry: {
      module_name: market.module_name,
      package_path: market.package_path,
    },
    message: "Startup sync failed: registry offline",
  }
  let initial = State::empty().with_builtin_errors(input.channel, [error])
  let (failed, _) = test_step(
    initial,
    CatalogFailed(channel=input.channel, message="Catalog unavailable"),
    input,
  )
  assert_true(failed.catalog is Failed("Catalog unavailable"))
  let (refreshing, _) = test_step(failed, RefreshCatalog, input)
  assert_true(refreshing.catalog is Loading(channel=Local))
  let (catalog, _) = test_step(
    refreshing,
    CatalogLoaded(channel=input.channel, items=[market]),
    input,
  )
  let (loading, _) = test_step(catalog, PreviewMarket(market), input)
  let ready = test_ready(loading, input)
  assert_eq(notice_messages(ready, input, Some(Market(market))), [
    "acme/widget: Startup sync failed: registry offline",
  ])
  let (installing, _) = test_step(ready, Install(market), input)
  let skill = { ..test_skill(enabled=true), builtin: true, }
  let installed = test_input(installed=[skill])
  let invalidated = installing.with_builtin_errors(input.channel, [])
  let (_, loading) = invalidated.sync_library(test_emit(), installed)
  let confirmed = test_ready(loading, installed)
  assert_true(confirmed.notices.is_empty())
  assert_true(
    confirmed.pending_action(input.channel, market.identity())
    is Some(Installing(..)),
  )
  assert_true(
    detail_action_target(Market(market), confirmed, installed) ==
    Some(Installed(skill)),
  )
  let (done, outcome) = test_step(
    confirmed,
    ActionDone(
      channel=input.channel,
      action=Installing(source=skill.source),
      error=None,
    ),
    installed,
  )
  assert_true(outcome is Some(LibraryChanged(channel=Local)))
  assert_true(done.busy.is_empty())
  let (unchanged, _) = test_step(done, Uninstall(skill), installed)
  assert_true(unchanged == done)
  let (list, _) = test_step(unchanged, BackToList, installed)
  assert_true(notice_messages(list, installed, None).is_empty())
}
