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
    let retained = self.entries.filter(item => item.active.val)
    self.entries.clear()
    self.entries.append(retained)
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
priv struct RegisteredCodeLensProvider {
  provider : &@language.CodeLensProvider
  resolver : &@language.CodeLensResolver?
}

///|
/// Opaque result row returned through `LanguageHandle`. It keeps the provider
/// registration identity needed for later lazy resolution without exposing
/// the mutable registry to Viewer contributions.
struct CodeLensItem {
  lens_value : @language.CodeLens
  resolver : &@language.CodeLensResolver?
  active : Ref[Bool]
  provider_rank : Int
  provider_index : Int
  result_index : Int
}

///|
/// The provider-produced lens value captured for this result row.
pub fn CodeLensItem::lens(self : CodeLensItem) -> @language.CodeLens {
  self.lens_value
}

///|
/// Whether this row's registration supplied a lazy resolver.
pub fn CodeLensItem::has_resolver(self : CodeLensItem) -> Bool {
  self.resolver is Some(_)
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
  code_lens_provider : LanguageFeatureRegistry[RegisteredCodeLensProvider]
  code_lens_did_change : @base_common.Emitter[Unit]
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
  code_lenses_callback : async (
    @model.TextModel,
    @language.CancellationToken,
    async (Array[async () -> Unit]) -> Unit,
  ) -> Array[CodeLensItem] noraise
  resolve_code_lens_callback : async (
    @model.TextModel,
    CodeLensItem,
    @language.CodeLens,
    @language.CancellationToken,
  ) -> @language.CodeLens? noraise
  has_code_lens_provider_callback : (@model.TextModel) -> Bool
  on_did_change_code_lenses_callback : (() -> Unit) -> @base_common.Disposable
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
    code_lens_provider: LanguageFeatureRegistry(),
    code_lens_did_change: Emitter(),
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
    code_lenses_callback: (model, token, run_tasks) => {
      self.code_lenses_with_log_handle(model, log_service, token~, run_tasks~)
    },
    resolve_code_lens_callback: (model, item, lens, token) => {
      self.resolve_code_lens_with_log_handle(
        model,
        item,
        lens,
        log_service,
        token~,
      )
    },
    has_code_lens_provider_callback: model => self.has_code_lens_provider(model),
    on_did_change_code_lenses_callback: listener => {
      self.code_lens_did_change.event(_ => listener())
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
/// Resolves every matching CodeLens provider and returns rows sorted by source
/// line, provider priority, source column, and provider result order. Browser
/// callers inject a concurrent runner; the host-neutral default is sequential.
pub async fn LanguageHandle::code_lenses(
  self : LanguageHandle,
  model : @model.TextModel,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[CodeLensItem] noraise {
  (self.code_lenses_callback)(model, token, run_tasks)
}

///|
/// Lazily resolves one captured CodeLens row against its original live
/// registration. A disposed registration or cancelled request yields `None`.
pub async fn LanguageHandle::resolve_code_lens(
  self : LanguageHandle,
  model : @model.TextModel,
  item : CodeLensItem,
  lens : @language.CodeLens,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.CodeLens? noraise {
  (self.resolve_code_lens_callback)(model, item, lens, token)
}

///|
/// Reports whether the model currently has a matching live CodeLens provider.
pub fn LanguageHandle::has_code_lens_provider(
  self : LanguageHandle,
  model : @model.TextModel,
) -> Bool {
  (self.has_code_lens_provider_callback)(model)
}

///|
/// Fires when CodeLens registrations or a provider-owned invalidation event
/// change the result set that a Viewer should request.
pub fn LanguageHandle::on_did_change_code_lenses(
  self : LanguageHandle,
  listener : () -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_code_lenses_callback)(listener)
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
/// Registers an ordered CodeLens provider plus its optional lazy resolver and
/// provider-owned change event. The returned disposable retires all three as
/// one registration and announces both registration and disposal changes.
pub fn Languages::register_code_lens_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.CodeLensProvider,
  resolver? : &@language.CodeLensResolver,
  on_did_change? : (() -> Unit) -> @base_common.Disposable,
) -> @base_common.Disposable {
  let registration = self.code_lens_provider.register(selector, {
    provider,
    resolver,
  })
  let provider_subscription = match on_did_change {
    Some(subscribe) => Some(subscribe(() => self.code_lens_did_change.fire(())))
    None => None
  }
  self.code_lens_did_change.fire(())
  @base_common.Disposable::from(() => {
    match provider_subscription {
      Some(subscription) => subscription.dispose()
      None => ()
    }
    registration.dispose()
    self.code_lens_did_change.fire(())
  })
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
    match
      (entry.provider.provide_hover(model, position, token) catch {
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
      }) {
      Some(hover) =>
        if token.is_cancellation_requested() {
          return None
        } else if entry.active.val && hover.contents.length() > 0 {
          return Some(hover)
        }
      None => ()
    }
  }
  None
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
  if token.is_cancellation_requested() {
    return []
  }
  let position = model.get_position_at(offset)
  let providers = self.definition_provider.snapshot_matching(model)
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
      let result = entry.provider.provide_definition(model, position, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              "language.definition",
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
    match result {
      Some(result) =>
        if providers[index].entry.active.val {
          locations.append(result)
        }
      None => ()
    }
  }
  locations
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
  if token.is_cancellation_requested() {
    return []
  }
  let position = model.get_position_at(offset)
  let providers = self.references_provider.snapshot_matching(model)
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
      let result = entry.provider.provide_references(model, position, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              "language.references",
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
    match result {
      Some(result) =>
        if providers[index].entry.active.val {
          locations.append(result)
        }
      None => ()
    }
  }
  locations
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
async fn Languages::code_lenses_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[CodeLensItem] noraise {
  if token.is_cancellation_requested() {
    return []
  }
  let providers = self.code_lens_provider.snapshot_matching(model)
  let provider_results : Array[Array[CodeLensItem]?] = [
    for _ in 0..<providers.length() => None
  ]
  let tasks : Array[async () -> Unit] = []
  for provider_rank, captured in providers {
    tasks.push(() => {
      let entry = captured.entry
      if token.is_cancellation_requested() || !entry.active.val {
        return
      }
      let lenses = entry.provider.provider.provide_code_lenses(model, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              "language.codeLens",
              model,
              captured.provider_index,
            )
          }
          []
        }
      }
      if token.is_cancellation_requested() || !entry.active.val {
        return
      }
      let items : Array[CodeLensItem] = []
      for result_index, lens in lenses {
        items.push({
          lens_value: lens,
          resolver: entry.provider.resolver,
          active: entry.active,
          provider_rank,
          provider_index: captured.provider_index,
          result_index,
        })
      }
      provider_results[provider_rank] = Some(items)
    })
  }
  run_tasks(tasks) catch {
    _ => ()
  }
  if token.is_cancellation_requested() {
    return []
  }
  let items : Array[CodeLensItem] = []
  for provider_rank, result in provider_results {
    match result {
      Some(result) if providers[provider_rank].entry.active.val =>
        items.append(result)
      _ => ()
    }
  }
  items.sort_by(compare_code_lens_items)
  items
}

///|
fn compare_code_lens_items(left : CodeLensItem, right : CodeLensItem) -> Int {
  let left_range = left.lens_value.range
  let right_range = right.lens_value.range
  if left_range.start_line_number != right_range.start_line_number {
    left_range.start_line_number - right_range.start_line_number
  } else if left.provider_rank != right.provider_rank {
    left.provider_rank - right.provider_rank
  } else if left_range.start_column != right_range.start_column {
    left_range.start_column - right_range.start_column
  } else {
    left.result_index - right.result_index
  }
}

///|
async fn Languages::resolve_code_lens_with_log_handle(
  _self : Languages,
  model : @model.TextModel,
  item : CodeLensItem,
  lens : @language.CodeLens,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.CodeLens? noraise {
  if token.is_cancellation_requested() || !item.active.val {
    return None
  }
  guard item.resolver is Some(resolver) else { return Some(lens) }
  let resolved = resolver.resolve_code_lens(model, lens, token) catch {
    _ => {
      if !token.is_cancellation_requested() {
        log_provider_failure(
          log_service,
          "language.codeLens.resolve",
          model,
          item.provider_index,
        )
      }
      None
    }
  }
  if token.is_cancellation_requested() || !item.active.val {
    None
  } else {
    resolved
  }
}

///|
fn Languages::has_code_lens_provider(
  self : Languages,
  model : @model.TextModel,
) -> Bool {
  !self.code_lens_provider.snapshot_matching(model).is_empty()
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
