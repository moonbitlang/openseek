///|
/// Carried lexer state between lines, the `IState` of Monaco's tokenization
/// contract. An empty state is the canonical normal state; the persistent list
/// contains only open lexer modes. Stack edits share unchanged tails
/// while cached states remain isolated from later edits. Derived equality is
/// what callers use to detect re-tokenization convergence.
pub struct TokenizerState {
  priv modes : @list.List[Byte]
} derive(Eq)

///|
/// Creates the canonical normal tokenizer state.
pub fn TokenizerState::TokenizerState() -> TokenizerState {
  { modes: @list.new() }
}

///|
/// Top mode, or `None` for an empty state.
pub fn TokenizerState::last_mode(self : TokenizerState) -> Byte? {
  self.modes.head()
}

///|
/// Returns a new state with `mode` pushed. The receiver remains unchanged.
pub fn TokenizerState::push_mode(
  self : TokenizerState,
  mode : Byte,
) -> TokenizerState {
  { modes: self.modes.prepend(mode) }
}

///|
/// Returns a new state without its top mode. An empty state is returned as-is.
/// The receiver remains unchanged.
pub fn TokenizerState::pop_mode(self : TokenizerState) -> TokenizerState {
  match self.modes {
    More(_, tail~) => { modes: tail }
    Empty => self
  }
}

///|
/// Uses a compact bottom-first debug form, reversing the top-first list only
/// when diagnostics or snapshots request it.
pub impl Debug for TokenizerState with fn to_repr(self) {
  let encoded = StringBuilder()
  for mode in self.modes.rev() {
    encoded.write_char(mode.to_char())
  }
  Repr::ctor("TokenizerState", [(None, Repr(encoded.to_string()))])
}

///|
/// Highlight classification, widened toward Monaco's standard token
/// types. Existing tags and class names are stable for specs; new tags
/// extend the set for the per-language lexers.
pub(all) enum HighlightTag {
  Keyword
  Identifier
  String
  Number
  Comment
  Punctuation
  Plain
  Operator
  Delimiter
  Type
  Function
  Variable
  Constant
  StringEscape
  CommentDoc
  Regexp
  Tag
  Attribute
  Invalid
} derive(Eq, Debug)

///|
/// One highlighted span within a single line, in line-local UTF-16
/// code-unit offsets. Token ranges must never split a surrogate pair: the
/// viewer slices the document text at these offsets.
pub(all) struct LineToken {
  start : Int
  end : Int
  tag : HighlightTag
} derive(Eq, Debug)

///|
/// Line-at-a-time tokenization, Monaco's `ITokenizationSupport`: the
/// driver feeds lines in document order, threading the returned state
/// into the next call. Gaps between tokens render as plain text.
pub(open) trait LineTokenizer {
  fn initial_state(Self) -> TokenizerState
  fn tokenize_line(Self, line_text : StringView, state : TokenizerState) -> (
    Array[LineToken],
    TokenizerState,
  )
}

///|
/// Registration change notification, the ported subset of Monaco's
/// `ITokenizationSupportChangedEvent`
/// (`vscode/src/vs/editor/common/languages.ts:2503-2506`).
pub struct TokenizationChangedEvent {
  changed_languages : Array[String]
  changed_color_map : Bool
}

///|
priv struct TokenizationSupportEntry {
  id : Int
  tokenizer : &LineTokenizer
}

///|
/// Tokenization support keyed by language id, Monaco's
/// `TokenizationRegistry` (`common/languages.ts` /
/// `common/tokenizationRegistry.ts:12-113`). The process-wide instance is
/// `tokenization_registry` below; isolated instances remain constructible for
/// tests.
///
/// Deviation: Monaco stores `Color[] | null`; the viewer's existing styling
/// boundary consumes CSS expressions, so this package stores
/// `Array[String]?` without parsing, copying, or adding `Color` object
/// behavior. Lazy tokenization factories are not part of the synchronous
/// `LineTokenizer` API and are intentionally absent.
struct TokenizationRegistry {
  tokenizers : Map[String, TokenizationSupportEntry]
  next_id : Ref[Int]
  did_change : @base_common.Emitter[TokenizationChangedEvent]
  mut color_map : Array[String]?
}

///|
/// Creates an empty tokenization registry with no color map, matching
/// `vscode/src/vs/editor/common/tokenizationRegistry.ts:20-24`.
fn TokenizationRegistry::new_impl() -> TokenizationRegistry {
  {
    tokenizers: Map([]),
    next_id: Ref(0),
    did_change: Emitter(),
    color_map: None,
  }
}

///|
/// Announces tokenization changes for the exact supplied language ids.
/// Mirrors `TokenizationRegistry.handleChange`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:26-31`): a language
/// change never claims that the encoded-token color map changed.
fn TokenizationRegistry::handle_change_impl(
  self : TokenizationRegistry,
  language_ids : Array[String],
) -> Unit {
  self.did_change.fire({
    changed_languages: language_ids,
    changed_color_map: false,
  })
}

///|
/// Registers or replaces the tokenization support for a language id and
/// fires `on_did_change`. Mirrors `TokenizationRegistry.register`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:33-43`); disposing the
/// returned handle removes the support only if it is still the active
/// registration (Monaco's `=== support` identity check, kept as a registration
/// id so trait objects need no identity comparison).
pub fn TokenizationRegistry::register(
  self : TokenizationRegistry,
  language_id : String,
  tokenizer : &LineTokenizer,
) -> @base_common.Disposable {
  let id = self.next_id.val
  self.next_id.val = id + 1
  self.tokenizers[language_id] = { id, tokenizer }
  // The pinned source installs before notification; the disposer returns
  // immediately when a newer registration owns the key.
  self.handle_change_impl([language_id])
  @base_common.Disposable::from(() => {
    if self.tokenizers.get(language_id) is Some(entry) && entry.id == id {
      self.tokenizers.remove(language_id)
      self.handle_change_impl([language_id])
    }
  })
}

///|
/// The tokenization support for `language_id`, or `None` when unregistered
/// (Monaco's null tokenization fallback is the caller's choice). Mirrors
/// `TokenizationRegistry.get`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:45-47`).
pub fn TokenizationRegistry::get(
  self : TokenizationRegistry,
  language_id : String,
) -> &LineTokenizer? {
  self.tokenizers.get(language_id).map(entry => entry.tokenizer)
}

///|
/// Whether synchronous tokenization lookup for `language_id` is resolved.
/// Mirrors the two reachable branches of
/// `TokenizationRegistry.isResolved`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:81-93`). With no
/// lazy-factory API there is no pending state, so both registered and missing
/// languages are resolved.
fn TokenizationRegistry::is_resolved_impl(
  self : TokenizationRegistry,
  language_id : String,
) -> Bool {
  match self.get(language_id) {
    Some(_) => true
    None => true
  }
}

///|
/// Replaces the CSS color-expression map and announces the change for every
/// currently registered language in registry insertion order. This is the
/// reviewed `Color[]` to `Array[String]` reduction of
/// `TokenizationRegistry.setColorMap`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:95-101`).
fn TokenizationRegistry::set_color_map_impl(
  self : TokenizationRegistry,
  color_map : Array[String],
) -> Unit {
  self.color_map = Some(color_map)
  let changed_languages = [
    for language_id in self.tokenizers.keys() => language_id
  ]
  self.did_change.fire({ changed_languages, changed_color_map: true })
}

///|
/// Returns the retained CSS color-expression map, or `None` before one is set.
/// Mirrors `TokenizationRegistry.getColorMap`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:103-105`).
fn TokenizationRegistry::get_color_map_impl(
  self : TokenizationRegistry,
) -> Array[String]? {
  self.color_map
}

///|
/// Returns the CSS expression at Monaco's literal
/// `ColorId.DefaultBackground = 2`, but only when the map length exceeds that
/// index (`vscode/src/vs/editor/common/tokenizationRegistry.ts:107-112`).
fn TokenizationRegistry::get_default_background_impl(
  self : TokenizationRegistry,
) -> String? {
  match self.color_map {
    Some(color_map) if color_map.length() > 2 => Some(color_map[2])
    _ => None
  }
}

///|
/// Subscribes to registration changes. Mirrors
/// `TokenizationRegistry.onDidChange`
/// (`vscode/src/vs/editor/common/tokenizationRegistry.ts:17-18`).
pub fn TokenizationRegistry::on_did_change(
  self : TokenizationRegistry,
  listener : (TokenizationChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change.event(listener)
}

///|
/// The process-wide registry, Monaco's `export const TokenizationRegistry`
/// singleton (`common/languages.ts`). `Languages::set_tokens_provider`
/// (the `monaco.languages.setTokensProvider` analog) registers into it.
pub let tokenization_registry : TokenizationRegistry = TokenizationRegistry::new_impl()

///|
/// Whether `word` begins with an uppercase ASCII letter (`A`–`Z`), the shared
/// lexer heuristic for classifying an identifier as a type. Shared by the
/// language lexers (`lang_*`), which otherwise carry identical copies.
pub fn is_capitalized(word : StringView) -> Bool {
  let unit = word[0].to_int()
  65 <= unit && unit <= 90
}

///|
/// Append `start`..`end` tagged `tag`, coalescing it into the previous token
/// when that token carries the same tag and ends exactly where this one
/// begins. Contiguous same-tag lexemes therefore render as one span — a
/// quoted string arrives as quote, content, quote and leaves as a single
/// `String` token. Shared by the language lexers (`lang_*`), which otherwise
/// carry identical copies.
pub fn push_token(
  tokens : Array[LineToken],
  start : Int,
  end : Int,
  tag : HighlightTag,
) -> Unit {
  if tokens is [.., last] && last.tag == tag && last.end == start {
    tokens[tokens.length() - 1] = { start: last.start, end, tag }
    return
  }
  tokens.push({ start, end, tag })
}

///|

///|
#deprecated
pub extend HighlightTag with Debug::{to_repr}

///|
pub extend HighlightTag with Eq::{equal, not_equal}

///|
#deprecated
pub extend LineToken with Debug::{to_repr}

///|
pub extend LineToken with Eq::{equal, not_equal}

///|
#deprecated
pub extend TokenizerState with Debug::{to_repr}

///|
pub extend TokenizerState with Eq::{equal, not_equal}
