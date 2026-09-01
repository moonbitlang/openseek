// Unified Quick Open for the native desktop and the browser console. This is
// Workbench chrome: the package owns provider-prefix state, result navigation,
// and the Host file-search cache session. The shell owns the global shortcut
// that opens it, the modal exclusions that decide whether it may open at all,
// and the editor path that an accepted row reaches.

///|
/// Which provider owns the palette. Files are the default provider; a leading
/// `#` in the visible input selects workspace symbols.
pub(all) enum Provider {
  Files
  Symbols
} derive(Eq)

///|
fn Provider::prefix(self : Provider) -> String {
  match self {
    Files => ""
    Symbols => "#"
  }
}

///|
/// One selectable row. File rows open without a range; symbol rows retain the
/// precise range returned by MoonIDE.
priv enum Item {
  FileRow(@files.Match)
  SymbolRow(@symbols.Symbol)
} derive(Eq)

///|
/// File and symbol queries wait briefly while the user types. `Ready`
/// deliberately includes an empty result; `Failed` is reserved for
/// bridge/request failure. The two waiting arms carry the UUID of the one
/// thing armed for the run — a debounce timer, or one Host request — and
/// every id is armed at most once, so a reply identifies exactly the request
/// it answers and leaving the arm is itself the fence.
priv enum Phase {
  Debouncing(request_id~ : String)
  Loading(request_id~ : String)
  Ready
  Failed
} derive(Eq)

///|
/// One open palette run. `value` is the exact text shown in the input,
/// including the `#` provider prefix when symbols are active. `owner` and
/// `root` are the conversation identity captured when the run started, so
/// `reconcile` can tell a shell change from a no-op. `phase` carries whatever
/// the run is waiting for.
priv struct Open {
  owner : @interop.ConversationKey
  root : @common.Uri?
  value : String
  items : Array[Item]
  selected : Int
  phase : Phase
} derive(Eq)

///|
/// Frontend half of VS Code's FileQueryCacheState. `active_key` remains usable
/// while `loading_key` warms a replacement for the same root, so a failed
/// replacement cannot evict the last good cache. It outlives one palette run:
/// reopening reuses a compatible warm cache instead of paying for it again.
priv struct FileQueryCache {
  owner : @interop.ConversationKey?
  root : @common.Uri?
  active_key : String?
  loading_key : String?
} derive(Eq)

///|
/// The palette's whole state. The shell holds this value but cannot read into
/// it; every transition goes through `open`, `handle`, or `reconcile`.
pub struct State {
  priv open : Open?
  priv cache : FileQueryCache
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    open: None,
    cache: { owner: None, root: None, active_key: None, loading_key: None, },
  }
}

///|
/// Whether the palette is drawn. The shell needs this for its overlay/z-order
/// bookkeeping: native browser views sit above all HTML and must be hidden
/// while the palette covers them.
pub fn State::is_open(self : State) -> Bool {
  self.open is Some(_)
}

///|
/// The shell data one palette run reads. Rebuilt every render, so a change of
/// conversation, root, or open editor tabs reaches the palette without the
/// package knowing how the application derives any of it.
struct Input {
  owner : @interop.ConversationKey
  root : @common.Uri?
  /// Open editor tabs that still name usable files, ranked ahead of the Host
  /// index. Deleted tabs remain bookmarks in the editor strip and must not
  /// become Quick Open results, so the shell filters them out.
  open_files : Array[@pathx.Relative]
  active_file : @pathx.Relative?
} derive(Eq)

///|
pub fn Input::Input(
  owner~ : @interop.ConversationKey,
  root~ : @common.Uri?,
  open_files~ : Array[@pathx.Relative],
  active_file~ : @pathx.Relative?,
) -> Input {
  { owner, root, open_files, active_file, }
}

///|
/// A row the user accepted. The palette has already closed itself by the time
/// this is returned; opening the target is the shell's transition, in the same
/// root update, so panel reconciliation still sees one message.
pub(all) struct Accepted {
  path : String
  range : @common.Range?
} derive(Eq, @debug.Debug)

///|
pub(all) enum Msg {
  ValueChanged(String)
  FilesDue(request_id~ : String)
  FileCacheLoaded(cache_key~ : String)
  FileCacheRequestFailed(cache_key~ : String)
  FilesLoaded(request_id~ : String, files~ : Array[@pathx.Relative])
  FilesRequestFailed(request_id~ : String)
  SymbolsDue(request_id~ : String)
  SymbolsLoaded(request_id~ : String, items~ : Array[@symbols.Symbol])
  SymbolsRequestFailed(request_id~ : String)
  Move(Int)
  Select(Int)
  Pick(Int)
  Dismiss
}

///|
/// Which provider the visible input currently selects.
fn Open::provider(self : Open) -> Provider {
  if self.value.has_prefix("#") {
    Symbols
  } else {
    Files
  }
}

///|
/// Provider-local query: file input verbatim, symbol input without exactly one
/// leading `#`.
fn Open::query(self : Open) -> String {
  match self.provider() {
    Files => self.value
    Symbols => self.value[1:].to_owned()
  }
}

///|
fn Open::current(self : Open) -> Item? {
  self.items.get(self.selected)
}

///|
/// Rewrite only the provider prefix, preserving the visible query suffix.
fn value_for_provider(value : String, provider : Provider) -> String {
  let suffix = if value.has_prefix("#") { value[1:].to_owned() } else { value }
  provider.prefix() + suffix
}

///|
fn Item::name(self : Item) -> String {
  match self {
    FileRow(file) => file.name
    SymbolRow(symbol) => symbol.name
  }
}

///|
fn Item::detail(self : Item) -> String {
  match self {
    FileRow(file) => file.path.0
    SymbolRow(symbol) => symbol.detail()
  }
}

///|
fn Item::accepted(self : Item) -> Accepted {
  match self {
    FileRow(file) => { path: file.path.0, range: None, }
    SymbolRow(symbol) => { path: symbol.path, range: Some(symbol.range), }
  }
}

///|
pub extend Accepted with Debug::{to_repr}

///|
pub extend Accepted with Eq::{equal, not_equal}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Provider with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}
