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
/// an install or uninstall in flight, retaining its source even after the
/// library changes; notices retain the scope of each failure.
struct State {
  catalog : Catalog
  query : String
  busy : Array[PendingSkillAction]
  notices : Array[Notice]
  preview : Preview
  preview_cache : Map[String, String]
  list_scroll_top : Double
} derive(Eq)

///|
priv enum Notice {
  SkillActionFailed(action~ : PendingSkillAction, message~ : String)
  LibraryLoadFailed(String)
} derive(Eq)

///|
fn Notice::belongs_to(self : Notice, source : String) -> Bool {
  match self {
    SkillActionFailed(action~, ..) => action.source() == source
    LibraryLoadFailed(_) => false
  }
}

///|
/// Retain the source until the request settles, even if a library notification
/// replaces the action or removes the installed entry first.
pub(all) enum PendingSkillAction {
  Installing(source~ : String)
  Uninstalling(source~ : String, id~ : String)
} derive(Eq)

///|
pub extend PendingSkillAction with Eq::{equal, not_equal}

///|
fn PendingSkillAction::source(self : PendingSkillAction) -> String {
  match self {
    Installing(source~) | Uninstalling(source~, ..) => source
  }
}

///|
fn State::pending_action(self : State, source : String) -> PendingSkillAction? {
  for action in self.busy {
    if action.source() == source {
      return Some(action)
    }
  }
  None
}

///|
enum Preview {
  Closed
  Loading(target~ : PreviewTarget, request~ : Int)
  Ready(target~ : PreviewTarget, request~ : Int, content~ : String)
  Failed(target~ : PreviewTarget, request~ : Int, message~ : String)
} derive(Eq)

///|
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
  // An install or uninstall settled: `action` is the operation to release, and
  // an `error` becomes a notice for that skill (a success reports the
  // library change to the root instead).
  ActionDone(
    channel~ : @interop.ChannelId,
    action~ : PendingSkillAction,
    error~ : String?
  )
  PreviewMarket(MarketItem)
  PreviewInstalled(InstalledItem)
  PreviewLoaded(request~ : Int, target~ : PreviewTarget, content~ : String)
  PreviewFailed(request~ : Int, target~ : PreviewTarget, message~ : String)
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
  let notices = self.notices.filter(notice => notice is SkillActionFailed(..))
  (cmd, { ..self, catalog, notices, })
}

///|
/// Show a failure the page did not cause. The root-owned library refresh is
/// the only such source: the page has no other way to learn that the list
/// under "Installed" could not be read.
pub fn State::with_library_error(self : State, message : String) -> State {
  let notices = self.notices.filter(notice => notice is SkillActionFailed(..))
  notices.push(LibraryLoadFailed(message))
  { ..self, notices, }
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
      match self.preview_cache.get(preview_cache_key(target)) {
        Some(content) =>
          (
            @cmd.none,
            { ..self, preview: Ready(target~, request=0, content~), },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_content(emit, input.channel, request, target),
            { ..self, preview: Loading(target~, request~), },
            None,
          )
        }
      }
    }
    PreviewInstalled(item) => {
      let target = Installed(item)
      match self.preview_cache.get(preview_cache_key(target)) {
        Some(content) =>
          (
            @cmd.none,
            { ..self, preview: Ready(target~, request=0, content~), },
            None,
          )
        None => {
          let request = preview_request_id(self.preview) + 1
          (
            fetch_installed_content(emit, input.channel, request, item),
            { ..self, preview: Loading(target~, request~), },
            None,
          )
        }
      }
    }
    PreviewLoaded(request~, target~, content~) => {
      guard self.preview is Loading(request=current, target=current_target) &&
        current == request &&
        current_target == target else {
        return (@cmd.none, self, None)
      }
      let cache = self.preview_cache.copy()
      cache[preview_cache_key(target)] = content
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
    PreviewFailed(request~, target~, message~) => {
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
        { ..self, preview: Closed, },
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
    Install(item) => {
      let source = source_label(item)
      if self.pending_action(source) is Some(_) {
        // Block either direction while an operation on this source is in flight.
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(Installing(source~))
        (
          install(emit, input.channel, item),
          {
            ..self,
            busy,
            notices: self.notices.filter(notice => !notice.belongs_to(source)),
          },
          None,
        )
      }
    }
    Uninstall(item) =>
      if item.source.is_empty() || self.pending_action(item.source) is Some(_) {
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(Uninstalling(source=item.source, id=item.id))
        (
          uninstall(emit, input.channel, item),
          {
            ..self,
            busy,
            notices: self.notices.filter(notice => {
              !notice.belongs_to(item.source)
            }),
          },
          None,
        )
      }
    ActionDone(channel~, action~, error~) => {
      let busy = self.busy.filter(entry => entry != action)
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
            !notice.belongs_to(action.source())
          })
          notices.push(SkillActionFailed(action~, message~))
          (@cmd.none, { ..self, busy, notices, }, None)
        }
      }
    }
  }
}

///|
fn preview_request_id(preview : Preview) -> Int {
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
    Installed(item) => "installed:\{item.id}"
  }
}

///|
fn preview_target_for_market(
  installed : Array[InstalledItem],
  item : MarketItem,
) -> PreviewTarget {
  for skill in installed {
    if !skill.source.is_empty() && skill.source == source_label(item) {
      return Installed(skill)
    }
  }
  Market(item)
}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend Preview with Eq::{equal, not_equal}

///|
pub extend PreviewTarget with Eq::{equal, not_equal}
