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
/// an install or uninstall in flight, keyed by the catalog entry's source
/// label or the installed entry's id; `notice` is the last failure to show.
struct State {
  catalog : Catalog
  query : String
  busy : Array[String]
  notice : String
  preview : Preview
  preview_cache : Map[String, String]
  list_scroll_top : Double
} derive(Eq)

///|
enum Preview {
  Closed
  Loading(target~ : PreviewTarget, request_id~ : String)
  Ready(target~ : PreviewTarget, content~ : String)
  Failed(target~ : PreviewTarget, message~ : String)
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
    notice: "",
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
  // Uninstall by library entry id; only registry installs get the button.
  Uninstall(String)
  // An install or uninstall settled: `key` is the busy entry to release, and
  // a non-empty `error` becomes the page's notice (a success reports the
  // library change to the root instead).
  ActionDone(channel~ : @interop.ChannelId, key~ : String, error~ : String)
  PreviewMarket(MarketItem)
  PreviewInstalled(InstalledItem)
  PreviewLoaded(request_id~ : String, content~ : String)
  PreviewFailed(request_id~ : String, message~ : String)
  BackToList
  SkillsScrolled(Double)
}

///|
/// Open the page. The catalog is fetched once per app run (and again after a
/// failure, a manual refresh, or a device switch during loading); a notice
/// left over from the previous visit is dropped. The installed library is
/// refreshed by the root, which owns it.
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
  (cmd, { ..self, catalog, notice: "", })
}

///|
/// Show a failure the page did not cause. The root-owned library refresh is
/// the only such source: the page has no other way to learn that the list
/// under "Installed" could not be read.
pub fn State::with_notice(self : State, message : String) -> State {
  { ..self, notice: message, }
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
          (@cmd.none, { ..self, preview: Ready(target~, content~), }, None)
        None => {
          let request_id = @uuid.mint()
          (
            fetch_content(emit, input.channel, request_id, target),
            { ..self, preview: Loading(target~, request_id~), },
            None,
          )
        }
      }
    }
    PreviewInstalled(item) => {
      let target = Installed(item)
      match self.preview_cache.get(preview_cache_key(target)) {
        Some(content) =>
          (@cmd.none, { ..self, preview: Ready(target~, content~), }, None)
        None => {
          let request_id = @uuid.mint()
          (
            fetch_installed_content(emit, input.channel, request_id, item),
            { ..self, preview: Loading(target~, request_id~), },
            None,
          )
        }
      }
    }
    PreviewLoaded(request_id~, content~) => {
      guard self.preview is Loading(request_id=current, target~) &&
        current == request_id else {
        return (@cmd.none, self, None)
      }
      let cache = self.preview_cache.copy()
      cache[preview_cache_key(target)] = content
      (
        @cmd.none,
        { ..self, preview: Ready(target~, content~), preview_cache: cache, },
        None,
      )
    }
    PreviewFailed(request_id~, message~) => {
      guard self.preview is Loading(request_id=current, target~) &&
        current == request_id else {
        return (@cmd.none, self, None)
      }
      (@cmd.none, { ..self, preview: Failed(target~, message~), }, None)
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
      let key = source_label(item)
      if self.busy.contains(key) {
        // A second click while the first install is in flight.
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(key)
        (
          install(emit, input.channel, item),
          { ..self, busy, notice: "", },
          None,
        )
      }
    }
    Uninstall(id) =>
      if self.busy.contains(id) {
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(id)
        (
          uninstall(emit, input.channel, id),
          { ..self, busy, notice: "", },
          None,
        )
      }
    ActionDone(channel~, key~, error~) => {
      let busy = self.busy.filter(entry => entry != key)
      // A result that outlived a focus switch belongs to its old host: it
      // releases its busy entry, but it neither refreshes the library on
      // screen nor speaks for the page's notice. That host refetches when it
      // is focused again.
      guard channel == input.channel else {
        return (@cmd.none, { ..self, busy, }, None)
      }
      if error.is_empty() {
        // The library changed; what the page shows must come from disk, not
        // from a client-side guess.
        (@cmd.none, { ..self, busy, }, Some(LibraryChanged(channel~)))
      } else {
        (@cmd.none, { ..self, busy, notice: error, }, None)
      }
    }
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
