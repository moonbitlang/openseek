// The Skills page's state machine. Every transition is pure: the host calls
// live in `requests.mbt` and reach the page back as `Msg` values.

///|
/// The mooncakes.io skill catalog as the page sees it. One enum, so
/// "loading", "loaded empty" and "failed" cannot be conflated.
priv enum Catalog {
  Idle
  Loading
  Ready(Array[MarketItem])
  Failed(String)
} derive(Eq)

///|
/// Everything the page alone can see. The catalog is fetched when the page
/// opens and kept for the app run; `busy` holds the entries with an
/// install or uninstall in flight, keyed by the catalog entry's source label
/// or the installed entry's id; `notice` is the last failure to show.
struct State {
  catalog : Catalog
  query : String
  busy : Array[String]
  notice : String
} derive(Eq)

///|
/// A page that has never been opened: no catalog, no filter, nothing in
/// flight.
pub fn State::empty() -> State {
  { catalog: Idle, query: "", busy: [], notice: "" }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
  CatalogLoaded(Array[MarketItem])
  CatalogFailed(String)
  Install(MarketItem)
  // Uninstall by library entry id; only registry installs get the button.
  Uninstall(String)
  // An install or uninstall settled: `key` is the busy entry to release, and
  // a non-empty `error` becomes the page's notice (a success reports the
  // library change to the root instead).
  ActionDone(channel~ : @interop.ChannelId, key~ : String, error~ : String)
}

///|
/// Open the page. The catalog is fetched once per app run (and again after a
/// failure); a notice left over from the previous visit is dropped. The
/// installed library is refreshed by the root, which owns it.
pub fn State::opening(
  self : State,
  emit : @cmd.Emit[Msg],
  input : Input,
) -> (@cmd.Cmd, State) {
  let (cmd, catalog) = match self.catalog {
    Idle | Failed(_) => (fetch_catalog(emit, input.channel), Loading)
    current => (@cmd.none, current)
  }
  (cmd, { ..self, catalog, notice: "" })
}

///|
/// Show a failure the page did not cause. The root-owned library refresh is
/// the only such source: the page has no other way to learn that the list
/// under "Installed" could not be read.
pub fn State::with_notice(self : State, message : String) -> State {
  { ..self, notice: message }
}

///|
pub fn State::handle(
  self : State,
  emit : @cmd.Emit[Msg],
  msg : Msg,
  input : Input,
) -> (@cmd.Cmd, State, Outcome?) {
  match msg {
    QueryChanged(value) => (@cmd.none, { ..self, query: value }, None)
    CatalogLoaded(items) => (@cmd.none, { ..self, catalog: Ready(items) }, None)
    CatalogFailed(message) =>
      (@cmd.none, { ..self, catalog: Failed(message) }, None)
    Install(item) => {
      let key = source_label(item)
      if self.busy.contains(key) {
        // A second click while the first install is in flight.
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(key)
        (install(emit, input.channel, item), { ..self, busy, notice: "" }, None)
      }
    }
    Uninstall(id) =>
      if self.busy.contains(id) {
        (@cmd.none, self, None)
      } else {
        let busy = self.busy.copy()
        busy.push(id)
        (uninstall(emit, input.channel, id), { ..self, busy, notice: "" }, None)
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
        (@cmd.none, { ..self, busy, notice: error }, None)
      }
    }
  }
}

///|
pub extend State with Eq::{equal, not_equal}
