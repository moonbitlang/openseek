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
  Loading(library~ : Library)
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
  preview_cache : Map[(String, String), String]
  preview_library : Library?
  list_scroll_top : Double
}

///|
#derive(Eq)
priv enum Notice {
  SkillActionFailed(operation~ : PendingOperation, message~ : String)
  LibraryLoadFailed(String)
  BuiltinSyncFailed(library~ : Library, error~ : @protocol.BuiltinSkillError)
}

///|
#derive(Eq)
priv struct PendingOperation {
  library : Library
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
  library : Library,
  identity : PendingTarget,
) -> Bool {
  match self {
    SkillActionFailed(operation~, ..) =>
      operation.library == library && operation.identity == identity
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
  library : Library,
  identity : (String, String),
) -> PendingSkillAction? {
  for operation in self.busy {
    guard operation.library == library &&
      operation.identity == PendingTarget::Registry(identity) else {
      continue
    }
    return Some(operation.action)
  }
  None
}

///|
fn State::pending_enabled(self : State, library : Library, id : String) -> Bool {
  self.busy
  .iter()
  .any(operation => {
    operation.library == library &&
    operation.identity == PendingTarget::LibraryEntry(id)
  })
}

///|
fn State::start_action(
  self : State,
  library : Library,
  identity : PendingTarget,
  action : PendingSkillAction,
  cmd : @cmd.Cmd,
) -> (@cmd.Cmd, State, Outcome?) {
  guard !self.busy
    .iter()
    .any(operation => {
      operation.library == library && operation.identity == identity
    }) else {
    return (@cmd.none, self, None)
  }
  let busy = self.busy.copy()
  busy.push({ library, identity, action, })
  (
    cmd,
    {
      ..self,
      busy,
      notices: self.notices.filter(notice => {
        !notice.belongs_to(library, identity)
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
pub fn State::detail_open(self : State, library : Library) -> Bool {
  self.preview_library == Some(library) && !(self.preview is Closed)
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
    preview_library: None,
    list_scroll_top: 0.0,
  }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  RefreshCatalog
  CatalogLoaded(library~ : Library, items~ : Array[MarketItem])
  CatalogFailed(library~ : Library, message~ : String)
  Install(MarketItem)
  // Capture the source alongside the library id before the entry disappears.
  Uninstall(InstalledItem)
  Update(MarketItem)
  ToggleEnabled(String)
  // A skill operation settled: `action` is the operation to release, and
  // an `error` becomes a notice for that skill (a success reports the
  // library change to the root instead).
  ActionDone(library~ : Library, action~ : PendingSkillAction, error~ : String?)
  PreviewMarket(MarketItem)
  PreviewInstalled(InstalledItem)
  PreviewLoaded(
    library~ : Library,
    request~ : Int32,
    target~ : PreviewTarget,
    content~ : String
  )
  PreviewFailed(
    library~ : Library,
    request~ : Int32,
    target~ : PreviewTarget,
    message~ : String
  )
  BackToList
  SkillsScrolled(Double)
  // The library switch: the root decides what the page shows next.
  SelectLibrary(LibraryKind)
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
        fetch_catalog(emit, input.library),
        Catalog::Loading(library=input.library),
      )
    Loading(library~) =>
      if library == input.library {
        (@cmd.none, self.catalog)
      } else {
        (fetch_catalog(emit, input.library), Loading(library=input.library))
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
  library : Library,
  errors : Array[@protocol.BuiltinSkillError],
) -> State {
  let notices = self.notices.filter(notice => !(notice is BuiltinSyncFailed(..)))
  for error in errors {
    notices.push(BuiltinSyncFailed(library~, error~))
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
  guard self.preview_library == Some(input.library) else {
    return (@cmd.none, { ..self, preview: Closed, preview_library: None, })
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
    fetch_content(emit, input.library, request, current),
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
      match
        self.preview_cache.get((input.library.key(), preview_cache_key(target))) {
        Some(content) =>
          (
            @cmd.none,
            {
              ..self,
              preview: Ready(target~, request=0, content~),
              preview_library: Some(input.library),
            },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_content(emit, input.library, request, target),
            {
              ..self,
              preview: Loading(target~, request~),
              preview_library: Some(input.library),
            },
            None,
          )
        }
      }
    }
    PreviewInstalled(item) => {
      let target = Installed(item)
      match
        self.preview_cache.get((input.library.key(), preview_cache_key(target))) {
        Some(content) =>
          (
            @cmd.none,
            {
              ..self,
              preview: Ready(target~, request=0, content~),
              preview_library: Some(input.library),
            },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_installed_content(emit, input.library, request, item),
            {
              ..self,
              preview: Loading(target~, request~),
              preview_library: Some(input.library),
            },
            None,
          )
        }
      }
    }
    PreviewLoaded(library~, request~, target~, content~) => {
      guard library == input.library && self.preview_library == Some(library) else {
        return (@cmd.none, self, None)
      }
      guard self.preview is Loading(request=current, target=current_target) &&
        current == request &&
        current_target == target else {
        return (@cmd.none, self, None)
      }
      let cache = self.preview_cache.copy()
      cache[(library.key(), preview_cache_key(target))] = content
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
    PreviewFailed(library~, request~, target~, message~) => {
      guard library == input.library && self.preview_library == Some(library) else {
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
        { ..self, preview: Closed, preview_library: None, },
        None,
      )
    SkillsScrolled(scroll_top) =>
      (@cmd.none, { ..self, list_scroll_top: scroll_top, }, None)
    SelectLibrary(kind) =>
      if input.switchable && kind != input.library.kind() {
        (@cmd.none, self, Some(LibrarySelected(kind)))
      } else {
        (@cmd.none, self, None)
      }
    RefreshCatalog =>
      match self.catalog {
        // The rendered button is disabled while loading, and this guard also
        // makes programmatic duplicate messages harmless.
        Loading(library~) if library == input.library => (@cmd.none, self, None)
        _ =>
          (
            fetch_catalog(emit, input.library),
            { ..self, catalog: Loading(library=input.library), },
            None,
          )
      }
    CatalogLoaded(library~, items~) => {
      // Catalog requests belong to the device that issued them. A completion
      // that outlived a focus switch must not overwrite the focused device's
      // catalog or its newer in-flight request.
      guard library == input.library else { return (@cmd.none, self, None) }
      (@cmd.none, { ..self, catalog: Ready(items), }, None)
    }
    CatalogFailed(library~, message~) => {
      guard library == input.library else { return (@cmd.none, self, None) }
      (@cmd.none, { ..self, catalog: Failed(message), }, None)
    }
    ToggleEnabled(id) => {
      guard input.installed.iter().find_first(item => item.id == id)
        is Some(item) &&
        !(item.builtin && input.library.locks_builtins()) else {
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
        input.library,
        PendingTarget::LibraryEntry(id),
        action,
        set_enabled(emit, input.library, payload, action),
      )
    }
    Install(item) | Update(item) => {
      guard !(input.library.locks_builtins() &&
        input.installed.any(current => {
          current.builtin && current.identity() == Some(item.identity())
        })) else {
        return (@cmd.none, self, None)
      }
      let source = source_label(item)
      let action : PendingSkillAction = {
        guard msg is Update(_) else { Installing(source~) }
        Updating(source~)
      }
      self.start_action(
        input.library,
        PendingTarget::Registry(item.identity()),
        action,
        install(emit, input.library, item, action),
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
        input.library,
        PendingTarget::Registry(identity),
        Uninstalling(source=item.source, id=item.id),
        uninstall(emit, input.library, item),
      )
    }
    ActionDone(library~, action~, error~) => {
      let operation = self.busy
        .iter()
        .find_first(operation => {
          operation.library == library && operation.action == action
        })
      guard operation is Some(operation) else { return (@cmd.none, self, None) }
      let busy = self.busy.filter(operation => {
        !(operation.library == library && operation.action == action)
      })
      // A result that outlived a focus switch belongs to its old host: it
      // releases its busy entry, but it neither refreshes the library on
      // screen nor speaks for the page's notice. That host refetches when it
      // is focused again.
      guard library == input.library else {
        return (@cmd.none, { ..self, busy, }, None)
      }
      match error {
        None =>
          // The library changed; what the page shows must come from disk.
          (@cmd.none, { ..self, busy, }, Some(LibraryChanged(library~)))
        Some(message) => {
          let notices = self.notices.filter(notice => {
            !notice.belongs_to(library, operation.identity)
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
