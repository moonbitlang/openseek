///|
priv struct LanguageFeatureRegistry[T] {
  entries : Array[LanguageFeatureEntry[T]]
  mut clock : Int
}

///|
priv struct LanguageFeatureEntry[T] {
  selector : @language.LanguageSelector
  provider : T
  active : Ref[Bool]
  registration_time : Int
}

///|
/// One request-start snapshot entry. `entry` is a value copy whose `active`
/// reference remains shared with the live registration, so an async request
/// never indexes the mutable registry after suspension while still being able
/// to reject a result from a registration disposed during the await.
priv struct LanguageFeatureSnapshot[T] {
  entry : LanguageFeatureEntry[T]
  provider_index : Int
  score : Int
}

///|
fn[T] LanguageFeatureRegistry::LanguageFeatureRegistry() -> LanguageFeatureRegistry[
  T,
] {
  { entries: [], clock: 0, }
}

///|
fn[T] LanguageFeatureRegistry::register(
  self : LanguageFeatureRegistry[T],
  selector : @language.LanguageSelector,
  provider : T,
) -> @base_common.Disposable {
  let active = Ref(true)
  let registration_time = self.clock
  self.clock += 1
  let entry : LanguageFeatureEntry[T] = {
    selector,
    provider,
    active,
    registration_time,
  }
  self.entries.push(entry)
  @base_common.Disposable::from(() => {
    active.val = false
    self.entries.retain(item => item.active.val)
  })
}

///|
/// Captures the matching, currently active registrations in Monaco registry
/// priority: selector score descending, then registration time descending.
/// The returned array is independent of later registry compaction; each
/// captured entry retains the registration's shared liveness reference.
fn[T] LanguageFeatureRegistry::snapshot_matching(
  self : LanguageFeatureRegistry[T],
  model : @model.TextModel,
) -> Array[LanguageFeatureSnapshot[T]] {
  let result : Array[LanguageFeatureSnapshot[T]] = []
  for entry in self.entries {
    let score = entry.selector.score(model)
    if entry.active.val && score > 0 {
      result.push({ entry, provider_index: entry.registration_time, score, })
    }
  }
  result.sort_by((left, right) => {
    let score_order = right.score - left.score
    if score_order != 0 {
      score_order
    } else {
      right.entry.registration_time - left.entry.registration_time
    }
  })
  result
}

///|
priv struct RegisteredMarkdownCommentProvider {
  provider : &@language.MarkdownCommentProvider
  foldable : Bool
}

///|
/// Raw result plus the registration-level presentation capability captured
/// from the same winning provider entry.
pub struct MarkdownCommentProviderResult {
  blocks : Array[@language.MarkdownCommentBlock]
  foldable : Bool
}

///|
/// Public language registry for tokenization and language-feature providers.
/// Hosts normally use the process-wide `@languages.languages` value; tests and
/// embedded viewers that need isolation can create a fresh registry and pass it
/// through `ViewerServices(languages~)`.
struct Languages {
  hover_provider : LanguageFeatureRegistry[&@language.HoverProvider]
  definition_provider : LanguageFeatureRegistry[&@language.DefinitionProvider]
  references_provider : LanguageFeatureRegistry[&@language.ReferencesProvider]
  document_symbol_provider : LanguageFeatureRegistry[
    &@language.DocumentSymbolProvider,
  ]
  markdown_comment_provider : LanguageFeatureRegistry[
    RegisteredMarkdownCommentProvider,
  ]
  /// Per-language comment/folding configuration — the viewer's stand-in for
  /// Monaco's `ILanguageConfigurationService` registrations.
  language_configurations : Map[String, LanguageConfiguration]
}

///|
/// Opaque production-language capability used by Viewer contributions. The
/// logging policy is prebound when the handle is derived, so consumers cannot
/// recover either the mutable registry or its concrete LogService.
struct LanguageHandle {
  get_language_configuration_callback : (String) -> LanguageConfiguration
  markdown_comment_provider_result_callback : (@model.TextModel) -> MarkdownCommentProviderResult?
  hover_at_callback : async (@model.TextModel, Int, @language.CancellationToken) -> @language.Hover? noraise
  definition_at_callback : async (
    @model.TextModel,
    Int,
    @language.CancellationToken,
    async (Array[async () -> Unit]) -> Unit,
  ) -> Array[@language.Location] noraise
  has_definition_provider_callback : (@model.TextModel) -> Bool
  references_at_callback : async (
    @model.TextModel,
    Int,
    @language.CancellationToken,
    async (Array[async () -> Unit]) -> Unit,
  ) -> Array[@language.Location] noraise
  has_references_provider_callback : (@model.TextModel) -> Bool
}

///|
/// Creates an isolated language registry.
pub fn Languages::Languages() -> Languages {
  {
    hover_provider: LanguageFeatureRegistry(),
    definition_provider: LanguageFeatureRegistry(),
    references_provider: LanguageFeatureRegistry(),
    document_symbol_provider: LanguageFeatureRegistry(),
    markdown_comment_provider: LanguageFeatureRegistry(),
    language_configurations: Map([]),
  }
}

///|
/// Derives the minimal language capability used by folding, Markdown comments,
/// and hover. The handle owns no registry or logging state; its callbacks retain
/// the selected backings for as long as the host retains the handle.
pub fn Languages::language_handle(
  self : Languages,
  log_service : @log.LogHandle,
) -> LanguageHandle {
  {
    get_language_configuration_callback: language_id => {
      self.get_language_configuration(language_id)
    },
    markdown_comment_provider_result_callback: model => {
      self.markdown_comment_provider_result_with_log_handle(model, log_service)
    },
    hover_at_callback: (model, offset, token) => {
      self.hover_at_with_log_handle(model, offset, log_service, token~)
    },
    definition_at_callback: (model, offset, token, run_tasks) => {
      self.definition_at_with_log_handle(
        model,
        offset,
        log_service,
        token~,
        run_tasks~,
      )
    },
    has_definition_provider_callback: model => {
      self.has_definition_provider(model)
    },
    references_at_callback: (model, offset, token, run_tasks) => {
      self.references_at_with_log_handle(
        model,
        offset,
        log_service,
        token~,
        run_tasks~,
      )
    },
    has_references_provider_callback: model => {
      self.has_references_provider(model)
    },
  }
}

///|
/// Returns the first matching provider's blocks and registration-level
/// foldability from one captured registry entry.
pub fn LanguageHandle::markdown_comment_provider_render_result(
  self : LanguageHandle,
  model : @model.TextModel,
) -> MarkdownCommentProviderResult? {
  (self.markdown_comment_provider_result_callback)(model)
}

///|
pub fn LanguageHandle::get_language_configuration(
  self : LanguageHandle,
  language_id : String,
) -> LanguageConfiguration {
  (self.get_language_configuration_callback)(language_id)
}

///|
pub async fn LanguageHandle::hover_at(
  self : LanguageHandle,
  model : @model.TextModel,
  offset : Int,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.Hover? noraise {
  (self.hover_at_callback)(model, offset, token)
}

///|
/// Resolves definitions through every matching provider and concatenates their
/// live results in Monaco registry priority (selector score, then newest
/// registration). An injected runner must return only after every task has
/// terminated.
pub async fn LanguageHandle::definition_at(
  self : LanguageHandle,
  model : @model.TextModel,
  offset : Int,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  (self.definition_at_callback)(model, offset, token, run_tasks)
}

///|
/// Reports whether the model currently has a matching live definition
/// provider registration.
pub fn LanguageHandle::has_definition_provider(
  self : LanguageHandle,
  model : @model.TextModel,
) -> Bool {
  (self.has_definition_provider_callback)(model)
}

///|
/// Resolves references through every matching provider and concatenates their
/// live results in Monaco registry priority (selector score, then newest
/// registration). An injected runner must return only after every task has
/// terminated.
pub async fn LanguageHandle::references_at(
  self : LanguageHandle,
  model : @model.TextModel,
  offset : Int,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  (self.references_at_callback)(model, offset, token, run_tasks)
}

///|
/// Reports whether the model currently has a matching live references
/// provider registration.
pub fn LanguageHandle::has_references_provider(
  self : LanguageHandle,
  model : @model.TextModel,
) -> Bool {
  (self.has_references_provider_callback)(model)
}

///|
/// Default process-wide language registry used by `ViewerServices()`.
pub let languages : Languages = Languages()

///|
pub fn default_languages() -> Languages {
  languages
}

///|
/// Registers or replaces the tokenizer for `language_id` in the process-wide
/// `@syntax.tokenization_registry`, exactly monaco-editor's standalone
/// `monaco.languages.setTokensProvider` forwarding into
/// `TokenizationRegistry.register`. Tokenizers are global even for isolated
/// `Languages` instances, as in Monaco; disposing the returned handle clears
/// the provider only if it is still the active registration.
pub fn Languages::set_tokens_provider(
  _self : Languages,
  language_id : String,
  tokenizer : &@syntax.LineTokenizer,
) -> @base_common.Disposable {
  @syntax.tokenization_registry.register(language_id, tokenizer)
}

///|
/// Registers an ordered hover provider.
pub fn Languages::register_hover_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.HoverProvider,
) -> @base_common.Disposable {
  self.hover_provider.register(selector, provider)
}

///|
/// Registers an ordered definition provider.
pub fn Languages::register_definition_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.DefinitionProvider,
) -> @base_common.Disposable {
  self.definition_provider.register(selector, provider)
}

///|
/// Registers an ordered references provider.
pub fn Languages::register_references_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.ReferencesProvider,
) -> @base_common.Disposable {
  self.references_provider.register(selector, provider)
}

///|
/// Registers an ordered document-symbol provider.
pub fn Languages::register_document_symbol_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.DocumentSymbolProvider,
) -> @base_common.Disposable {
  self.document_symbol_provider.register(selector, provider)
}

///|
/// Registers an ordered whole-line Markdown-comment provider.
pub fn Languages::register_markdown_comment_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.MarkdownCommentProvider,
  foldable? : Bool = false,
) -> @base_common.Disposable {
  self.markdown_comment_provider.register(selector, { provider, foldable, })
}

///|
fn Languages::markdown_comment_provider_result_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  log_service : @log.LogHandle,
) -> MarkdownCommentProviderResult? {
  let providers = self.markdown_comment_provider.snapshot_matching(model)
  guard providers is [captured, ..] else { return None }
  let blocks = captured.entry.provider.provider.provide_markdown_comments(model) catch {
    _ => {
      log_provider_failure(
        log_service,
        "language.markdownComments",
        model,
        captured.provider_index,
      )
      []
    }
  }
  Some({ blocks, foldable: captured.entry.provider.foldable, })
}

///|
async fn Languages::hover_at_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.Hover? noraise {
  if token.is_cancellation_requested() {
    return None
  }
  let position = model.get_position_at(offset)
  let providers = self.hover_provider.snapshot_matching(model)
  for captured in providers {
    if token.is_cancellation_requested() {
      return None
    }
    let entry = captured.entry
    if !entry.active.val {
      continue
    }
    let hover = entry.provider.provide_hover(model, position, token) catch {
      _ => {
        if !token.is_cancellation_requested() {
          log_provider_failure(
            log_service,
            "language.hover",
            model,
            captured.provider_index,
          )
        }
        None
      }
    }
    if hover is Some(hover) {
      if token.is_cancellation_requested() {
        return None
      } else if entry.active.val && hover.contents.length() > 0 {
        return Some(hover)
      }
    }
  }
  None
}

///|
/// Shared body of `definition_at_with_log_handle` and
/// `references_at_with_log_handle`: fans one position out to every matching
/// live provider, then concatenates the surviving results in registry order.
async fn[T] locations_at_with_log_handle(
  registry : LanguageFeatureRegistry[T],
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  category : String,
  token : @language.CancellationToken,
  run_tasks : async (Array[async () -> Unit]) -> Unit,
  provide : async (
    T,
    @model.TextModel,
    @base_common.Position,
    @language.CancellationToken,
  ) -> Array[@language.Location],
) -> Array[@language.Location] noraise {
  if token.is_cancellation_requested() {
    return []
  }
  let position = model.get_position_at(offset)
  let providers = registry.snapshot_matching(model)
  let provider_results : Array[Array[@language.Location]?] = [
    for _ in 0..<providers.length() => None
  ]
  let tasks : Array[async () -> Unit] = []
  for result_index, captured in providers {
    tasks.push(() => {
      let entry = captured.entry
      if token.is_cancellation_requested() || !entry.active.val {
        return
      }
      let result = provide(entry.provider, model, position, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              category,
              model,
              captured.provider_index,
            )
          }
          []
        }
      }
      provider_results[result_index] = Some(result)
    })
  }
  run_tasks(tasks) catch {
    _ => ()
  }
  if token.is_cancellation_requested() {
    return []
  }
  let locations : Array[@language.Location] = []
  for index, result in provider_results {
    if result is Some(result) && providers[index].entry.active.val {
      locations.append(result)
    }
  }
  locations
}

///|
async fn Languages::definition_at_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  locations_at_with_log_handle(
    self.definition_provider,
    model,
    offset,
    log_service,
    "language.definition",
    token,
    run_tasks,
    (provider, model, position, token) => {
      provider.provide_definition(model, position, token)
    },
  )
}

///|
/// Reports whether the model currently has a matching live definition
/// provider registration.
fn Languages::has_definition_provider(
  self : Languages,
  model : @model.TextModel,
) -> Bool {
  !self.definition_provider.snapshot_matching(model).is_empty()
}

///|
async fn Languages::references_at_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  locations_at_with_log_handle(
    self.references_provider,
    model,
    offset,
    log_service,
    "language.references",
    token,
    run_tasks,
    (provider, model, position, token) => {
      provider.provide_references(model, position, token)
    },
  )
}

///|
/// Reports whether the model currently has a matching live references
/// provider registration.
fn Languages::has_references_provider(
  self : Languages,
  model : @model.TextModel,
) -> Bool {
  !self.references_provider.snapshot_matching(model).is_empty()
}

///|
fn log_provider_failure(
  log_service : @log.LogHandle,
  category : String,
  model : @model.TextModel,
  index : Int,
) -> Unit {
  log_service.warn(category, "provider failed", details=[
    ("model", model.uri.to_string()),
    ("revision", model.revision),
    ("providerIndex", index.to_string()),
  ])
}
