///|
/// Immutable semantic origin for one symbol-navigation request. Surface
/// adapters reduce DOM/cursor input to this value before shared actions see
/// it; the original TextModel remains the only provider input.
struct SymbolNavigationAnchor {
  model : @model.TextModel
  position : @base_common.Position
  range : @base_common.Range
  model_identity : Int
  model_version_id : Int
  surface_generation : Int
}

///|
pub fn SymbolNavigationAnchor::from_model(
  model : @model.TextModel,
  position : @base_common.Position,
  range : @base_common.Range,
  surface_generation : Int,
) -> SymbolNavigationAnchor {
  let position = model.validate_position(position)
  {
    model,
    position,
    range: model.validate_range(range),
    model_identity: model.identity(),
    model_version_id: model.get_version_id(),
    surface_generation,
  }
}

///|
pub fn SymbolNavigationAnchor::model(
  self : SymbolNavigationAnchor,
) -> @model.TextModel {
  self.model
}

///|
pub fn SymbolNavigationAnchor::position(
  self : SymbolNavigationAnchor,
) -> @base_common.Position {
  self.position
}

///|
pub fn SymbolNavigationAnchor::range(
  self : SymbolNavigationAnchor,
) -> @base_common.Range {
  self.range
}

///|
pub fn SymbolNavigationAnchor::surface_generation(
  self : SymbolNavigationAnchor,
) -> Int {
  self.surface_generation
}

///|
/// Snapshot-only half of request freshness. The surface host separately
/// validates attachment/projection identity through `is_anchor_current`.
pub fn SymbolNavigationAnchor::model_is_current(
  self : SymbolNavigationAnchor,
) -> Bool {
  !self.model.is_disposed() &&
  self.model.identity() == self.model_identity &&
  self.model.get_version_id() == self.model_version_id
}

///|
pub fn SymbolNavigationAnchor::same_snapshot(
  self : SymbolNavigationAnchor,
  other : SymbolNavigationAnchor,
) -> Bool {
  self.model_identity == other.model_identity &&
  self.model_version_id == other.model_version_id &&
  self.surface_generation == other.surface_generation &&
  self.position == other.position &&
  self.range == other.range
}

///|
/// Shared command identity and presentation. Surface adapters render these
/// descriptors in their native command/menu infrastructure; command ids,
/// labels, keybinding labels, and provider enablement stay centralized here.
pub(all) enum SymbolNavigationCommand {
  RevealDefinition
  PeekDefinition
  GoToReferences
  PeekReferences
} derive(Eq, Debug)

///|
pub fn SymbolNavigationCommand::id(self : SymbolNavigationCommand) -> String {
  match self {
    RevealDefinition => "editor.action.revealDefinition"
    PeekDefinition => "editor.action.peekDefinition"
    GoToReferences => "editor.action.goToReferences"
    PeekReferences => "editor.action.referenceSearch.trigger"
  }
}

///|
pub fn SymbolNavigationCommand::title(self : SymbolNavigationCommand) -> String {
  match self {
    RevealDefinition => "Go to Definition"
    PeekDefinition => "Peek Definition"
    GoToReferences => "Go to References"
    PeekReferences => "Peek References"
  }
}

///|
pub fn SymbolNavigationCommand::keybinding_label(
  self : SymbolNavigationCommand,
) -> String? {
  match self {
    RevealDefinition => Some("F12")
    PeekDefinition =>
      Some(if @base_common.is_macintosh { "\u{2325}F12" } else { "Alt+F12" })
    GoToReferences =>
      Some(if @base_common.is_macintosh { "\u{21e7}F12" } else { "Shift+F12" })
    PeekReferences => None
  }
}

///|
pub fn SymbolNavigationCommand::from_id(
  id : String,
) -> SymbolNavigationCommand? {
  match id {
    "editor.action.revealDefinition" => Some(RevealDefinition)
    "editor.action.peekDefinition" => Some(PeekDefinition)
    "editor.action.goToReferences" => Some(GoToReferences)
    "editor.action.referenceSearch.trigger" => Some(PeekReferences)
    _ => None
  }
}

///|
pub fn SymbolNavigationCommand::is_available(
  self : SymbolNavigationCommand,
  languages : @languages.LanguageHandle,
  model : @model.TextModel,
  peek_available : Bool,
) -> Bool {
  match self {
    RevealDefinition => languages.has_definition_provider(model)
    PeekDefinition => peek_available && languages.has_definition_provider(model)
    GoToReferences => languages.has_references_provider(model)
    PeekReferences => peek_available && languages.has_references_provider(model)
  }
}

///|
pub fn symbol_navigation_context_commands(
  languages : @languages.LanguageHandle,
  model : @model.TextModel,
  peek_available : Bool,
) -> Array[SymbolNavigationCommand] {
  [RevealDefinition, PeekDefinition, GoToReferences, PeekReferences].filter(command => {
    command.is_available(languages, model, peek_available)
  })
}

///|
pub(all) struct SymbolNavigationActionConfig {
  open_to_side : Bool
  open_in_peek : Bool
  mute_message : Bool
}

///|
pub fn SymbolNavigationActionConfig::goto() -> SymbolNavigationActionConfig {
  { open_to_side: false, open_in_peek: false, mute_message: false, }
}

///|
pub fn SymbolNavigationActionConfig::peek() -> SymbolNavigationActionConfig {
  { open_to_side: false, open_in_peek: true, mute_message: false, }
}

///|
pub fn SymbolNavigationActionConfig::link() -> SymbolNavigationActionConfig {
  { open_to_side: false, open_in_peek: false, mute_message: true, }
}

///|
/// Narrow surface contract used by DefinitionAction and ReferencesAction.
/// It intentionally contains no CodeEditorWidget, MarkdownDocumentView, DOM,
/// ViewZone, or overlay type.
pub(all) struct SymbolNavigationActionHost {
  prepare_navigation : () -> Unit
  is_anchor_current : (SymbolNavigationAnchor) -> Bool
  open_location : async (
    SymbolNavigationAnchor,
    @language.Location,
    @navigation_api.OpenLocationMode,
    String,
  ) -> Bool noraise
  open_in_peek : (
    SymbolNavigationAnchor,
    @references.ReferencesPeekMode,
    Array[@language.Location],
  ) -> Bool
  show_message : (SymbolNavigationAnchor, String) -> Unit
}

///|
priv enum SymbolNavigationQueryKind {
  DefinitionQuery
  ReferencesQuery
}

///|
/// Shared cancellation, provider-query, normalization, and result-policy
/// owner. DefinitionAction and ReferencesAction are typed views over this one
/// mutually-cancelling request stream.
struct SymbolNavigationAction {
  languages : @languages.LanguageHandle
  host : SymbolNavigationActionHost
  run_provider_tasks : async (Array[async () -> Unit]) -> Unit
  mut generation : Int
  mut source : @language.CancellationTokenSource?
  mut disposed : Bool
}

///|
pub fn SymbolNavigationAction::SymbolNavigationAction(
  languages : @languages.LanguageHandle,
  host : SymbolNavigationActionHost,
  run_provider_tasks : async (Array[async () -> Unit]) -> Unit,
) -> SymbolNavigationAction {
  {
    languages,
    host,
    run_provider_tasks,
    generation: 0,
    source: None,
    disposed: false,
  }
}

///|
pub fn SymbolNavigationAction::cancel(self : SymbolNavigationAction) -> Unit {
  self.generation += 1
  let source = self.source
  self.source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
pub fn SymbolNavigationAction::dispose(self : SymbolNavigationAction) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel()
}

///|
fn SymbolNavigationAction::request_is_current(
  self : SymbolNavigationAction,
  generation : Int,
  source : @language.CancellationTokenSource,
  anchor : SymbolNavigationAnchor,
) -> Bool {
  !self.disposed &&
  self.generation == generation &&
  self.source is Some(current) &&
  physical_equal(current, source) &&
  !source.token().is_cancellation_requested() &&
  anchor.model_is_current() &&
  (self.host.is_anchor_current)(anchor)
}

///|
fn SymbolNavigationAction::result_is_current(
  self : SymbolNavigationAction,
  generation : Int,
  anchor : SymbolNavigationAnchor,
) -> Bool {
  !self.disposed &&
  self.generation == generation &&
  anchor.model_is_current() &&
  (self.host.is_anchor_current)(anchor)
}

///|
fn SymbolNavigationAction::retire_source(
  self : SymbolNavigationAction,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.source {
    Some(current) if physical_equal(current, source) => {
      self.source = None
      source.dispose(cancel~)
    }
    _ => source.dispose(cancel~)
  }
}

///|
async fn SymbolNavigationAction::query(
  self : SymbolNavigationAction,
  kind : SymbolNavigationQueryKind,
  anchor : SymbolNavigationAnchor,
  token : @language.CancellationToken,
) -> Array[@language.Location] noraise {
  let model = anchor.model()
  let offset = model.get_offset_at(anchor.position())
  match kind {
    DefinitionQuery =>
      self.languages.definition_at(
        model,
        offset,
        token~,
        run_tasks=self.run_provider_tasks,
      )
    ReferencesQuery =>
      self.languages.references_at(
        model,
        offset,
        token~,
        run_tasks=self.run_provider_tasks,
      )
  }
}

///|
fn normalize_symbol_locations(
  locations : Array[@language.Location],
) -> Array[@language.Location] {
  let normalized : Array[@language.Location] = []
  for candidate in locations {
    if !normalized.any(existing => {
        existing.uri.to_string() == candidate.uri.to_string() &&
        existing.range == candidate.range
      }) {
      normalized.push(candidate)
    }
  }
  normalized
}

///|
/// Shared provider-query owner for modifier-hover Definition links. Surfaces
/// retain only hit testing and projected-decoration work.
struct DefinitionLinkResolver {
  languages : @languages.LanguageHandle
  is_anchor_current : (SymbolNavigationAnchor) -> Bool
  run_provider_tasks : async (Array[async () -> Unit]) -> Unit
  mut generation : Int
  mut source : @language.CancellationTokenSource?
  mut disposed : Bool
}

///|
pub fn DefinitionLinkResolver::DefinitionLinkResolver(
  languages : @languages.LanguageHandle,
  is_anchor_current~ : (SymbolNavigationAnchor) -> Bool,
  run_provider_tasks : async (Array[async () -> Unit]) -> Unit,
) -> DefinitionLinkResolver {
  {
    languages,
    is_anchor_current,
    run_provider_tasks,
    generation: 0,
    source: None,
    disposed: false,
  }
}

///|
pub fn DefinitionLinkResolver::cancel(self : DefinitionLinkResolver) -> Unit {
  self.generation += 1
  let source = self.source
  self.source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
pub fn DefinitionLinkResolver::begin(
  self : DefinitionLinkResolver,
  anchor : SymbolNavigationAnchor,
) -> Int? {
  guard !self.disposed &&
    anchor.model_is_current() &&
    (self.is_anchor_current)(anchor) else {
    return None
  }
  self.cancel()
  self.generation += 1
  Some(self.generation)
}

///|
pub async fn DefinitionLinkResolver::resolve_reserved(
  self : DefinitionLinkResolver,
  anchor : SymbolNavigationAnchor,
  generation : Int,
) -> Array[@language.Location] noraise {
  guard !self.disposed &&
    self.generation == generation &&
    anchor.model_is_current() &&
    (self.is_anchor_current)(anchor) else {
    return []
  }
  let source = @language.CancellationTokenSource()
  self.source = Some(source)
  let model = anchor.model()
  let locations = self.languages.definition_at(
    model,
    model.get_offset_at(anchor.position()),
    token=source.token(),
    run_tasks=self.run_provider_tasks,
  )
  let current = !self.disposed &&
    self.generation == generation &&
    self.source is Some(current_source) &&
    physical_equal(current_source, source) &&
    !source.token().is_cancellation_requested() &&
    anchor.model_is_current() &&
    (self.is_anchor_current)(anchor)
  if !current {
    match self.source {
      Some(current_source) if physical_equal(current_source, source) =>
        self.source = None
      _ => ()
    }
    source.dispose(cancel=true)
    return []
  }
  self.source = None
  source.dispose()
  normalize_symbol_locations(locations)
}

///|
pub fn DefinitionLinkResolver::dispose(self : DefinitionLinkResolver) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel()
}

///|
fn symbol_navigation_no_result_message(
  kind : SymbolNavigationQueryKind,
  anchor : SymbolNavigationAnchor,
) -> String {
  let word = anchor.model().get_word_at_position(anchor.position())
  match (kind, word) {
    (DefinitionQuery, Some(word)) if !word.word.is_empty() =>
      "No definition found for '\{word.word}'"
    (ReferencesQuery, Some(word)) if !word.word.is_empty() =>
      "No references found for '\{word.word}'"
    (DefinitionQuery, _) => "No definition found"
    (ReferencesQuery, _) => "No references found"
  }
}

///|
fn symbol_navigation_open_failure_message(
  kind : SymbolNavigationQueryKind,
) -> String {
  match kind {
    DefinitionQuery => "Unable to open definition"
    ReferencesQuery => "Unable to open reference"
  }
}

///|
fn symbol_navigation_open_source(kind : SymbolNavigationQueryKind) -> String {
  match kind {
    DefinitionQuery => "gotoDefinition"
    ReferencesQuery => "showReferences"
  }
}

///|
fn symbol_navigation_peek_mode(
  kind : SymbolNavigationQueryKind,
) -> @references.ReferencesPeekMode {
  match kind {
    DefinitionQuery => Definitions
    ReferencesQuery => References
  }
}

///|
fn SymbolNavigationAction::begin(
  self : SymbolNavigationAction,
  anchor : SymbolNavigationAnchor,
) -> Int? {
  guard !self.disposed && anchor.model_is_current() else { return None }
  self.cancel()
  self.generation += 1
  let generation = self.generation
  (self.host.prepare_navigation)()
  if self.result_is_current(generation, anchor) {
    Some(generation)
  } else {
    None
  }
}

///|
async fn SymbolNavigationAction::run_reserved(
  self : SymbolNavigationAction,
  kind : SymbolNavigationQueryKind,
  anchor : SymbolNavigationAnchor,
  config : SymbolNavigationActionConfig,
  generation : Int,
) -> Unit noraise {
  guard self.result_is_current(generation, anchor) else { return }
  let source = @language.CancellationTokenSource()
  self.source = Some(source)
  let locations = self.query(kind, anchor, source.token())
  if !self.request_is_current(generation, source, anchor) {
    self.retire_source(source, cancel=true)
    return
  }
  self.source = None
  source.dispose()
  let locations = normalize_symbol_locations(locations)
  if locations.is_empty() {
    if !config.mute_message && self.result_is_current(generation, anchor) {
      (self.host.show_message)(
        anchor,
        symbol_navigation_no_result_message(kind, anchor),
      )
    }
    return
  }
  let wants_peek = config.open_in_peek || locations.length() > 1
  if wants_peek && self.result_is_current(generation, anchor) {
    let opened = (self.host.open_in_peek)(
      anchor,
      symbol_navigation_peek_mode(kind),
      locations,
    )
    if opened {
      return
    }
    if config.open_in_peek {
      if !config.mute_message && self.result_is_current(generation, anchor) {
        (self.host.show_message)(anchor, "No preview available")
      }
      return
    }
  }
  guard self.result_is_current(generation, anchor) else { return }
  let accepted = (self.host.open_location)(
    anchor,
    locations[0],
    if config.open_to_side {
      Side
    } else {
      Current
    },
    symbol_navigation_open_source(kind),
  )
  if !accepted &&
    !config.mute_message &&
    self.result_is_current(generation, anchor) {
    (self.host.show_message)(
      anchor,
      symbol_navigation_open_failure_message(kind),
    )
  }
}

///|
struct DefinitionAction {
  action : SymbolNavigationAction
}

///|
pub fn DefinitionAction::DefinitionAction(
  action : SymbolNavigationAction,
) -> DefinitionAction {
  { action, }
}

///|
pub fn DefinitionAction::begin(
  self : DefinitionAction,
  anchor : SymbolNavigationAnchor,
) -> Int? {
  self.action.begin(anchor)
}

///|
pub async fn DefinitionAction::run_reserved(
  self : DefinitionAction,
  anchor : SymbolNavigationAnchor,
  config : SymbolNavigationActionConfig,
  generation : Int,
) -> Unit noraise {
  self.action.run_reserved(DefinitionQuery, anchor, config, generation)
}

///|
pub async fn DefinitionAction::run(
  self : DefinitionAction,
  anchor : SymbolNavigationAnchor,
  config : SymbolNavigationActionConfig,
) -> Unit noraise {
  guard self.begin(anchor) is Some(generation) else { return }
  self.run_reserved(anchor, config, generation)
}

///|
struct ReferencesAction {
  action : SymbolNavigationAction
}

///|
pub fn ReferencesAction::ReferencesAction(
  action : SymbolNavigationAction,
) -> ReferencesAction {
  { action, }
}

///|
pub fn ReferencesAction::begin(
  self : ReferencesAction,
  anchor : SymbolNavigationAnchor,
) -> Int? {
  self.action.begin(anchor)
}

///|
pub async fn ReferencesAction::run_reserved(
  self : ReferencesAction,
  anchor : SymbolNavigationAnchor,
  config : SymbolNavigationActionConfig,
  generation : Int,
) -> Unit noraise {
  self.action.run_reserved(ReferencesQuery, anchor, config, generation)
}

///|
pub async fn ReferencesAction::run(
  self : ReferencesAction,
  anchor : SymbolNavigationAnchor,
  config : SymbolNavigationActionConfig,
) -> Unit noraise {
  guard self.begin(anchor) is Some(generation) else { return }
  self.run_reserved(anchor, config, generation)
}

///|
pub extend SymbolNavigationCommand with Debug::{to_repr}

///|
pub extend SymbolNavigationCommand with Eq::{equal, not_equal}
