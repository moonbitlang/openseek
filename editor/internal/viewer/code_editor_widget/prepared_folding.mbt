///|
/// Structural ranges belong to the model/version, never to a view's mutable
/// collapse flags. Model disposal removes the entry and its listener.
priv struct PreparedFolding {
  version : Int
  language_id : String
  rules : @languages.FoldingRules?
  tab_size : Int
  limit : Int
  provider : Array[@worker_protocol.PreparedFoldRange]
  outlined : Array[@worker_protocol.PreparedFoldRange]
  subscription : @base_common.Disposable
}

///|
let prepared_folding : Map[Int, PreparedFolding] = Map([])

///|
fn CodeEditorWidget::prepared_folding(
  self : CodeEditorWidget,
  model : @model.TextModel,
) -> PreparedFolding? {
  let rules = self.services.languages.get_language_configuration(
      model.get_language_id(),
    ).folding_rules
  match prepared_folding.get(model.identity()) {
    Some(cached) if cached.version == model.get_version_id() &&
      cached.language_id == model.get_language_id() &&
      cached.tab_size == self.get_options().tab_size &&
      cached.limit == self.get_options().folding_maximum_regions &&
      same_folding_rules(cached.rules, rules) => Some(cached)
    _ => None
  }
}

///|
/// Pure entry shared by the browser worker and synchronous compatibility
/// path. No widget, DOM or collapse state is constructed in the worker.
pub fn compute_prepared_folding(
  text : String,
  language_id : String,
  off_side : Bool,
  tab_size : Int,
  limit : Int,
  outline : Bool,
) -> (@folding_browser.FoldingRegions, @folding_browser.FoldingRegions) {
  let model = @model.TextModel(
    @base_common.Uri::from(scheme="inmemory", path="/folding-worker") catch {
      _ => abort("invalid constant URI")
    },
    "folding-worker",
    language_id,
    1,
    "1",
    text,
  )
  defer model.dispose()
  let ranges = @folding_browser.compute_ranges(model, off_side, tab_size~, folding_ranges_limit={
    limit: () => limit,
    update: (_, _) => (),
  })
  let outlined = if outline && language_id == "moonbit" {
    moonbit_outline_folding_regions(model.snapshot, ranges, limit)
  } else {
    ranges
  }
  (ranges, outlined)
}

///|
fn CodeEditorWidget::store_prepared_folding(
  self : CodeEditorWidget,
  model : @model.TextModel,
  provider : Array[@worker_protocol.PreparedFoldRange],
  outlined : Array[@worker_protocol.PreparedFoldRange],
) -> Unit {
  let identity = model.identity()
  match prepared_folding.get(identity) {
    Some(previous) => previous.subscription.dispose()
    None => ()
  }
  let subscription = model.on_will_dispose(() => {
    match prepared_folding.get(identity) {
      Some(cached) => cached.subscription.dispose()
      None => ()
    }
    prepared_folding.remove(identity)
  })
  prepared_folding[identity] = {
    version: model.get_version_id(),
    language_id: model.get_language_id(),
    rules: self.services.languages.get_language_configuration(
      model.get_language_id(),
    ).folding_rules,
    tab_size: self.get_options().tab_size,
    limit: self.get_options().folding_maximum_regions,
    provider,
    outlined,
    subscription,
  }
}

///|
/// Prepare before the host's atomic set_model/restore/fold/paint transaction.
/// Small inputs and arbitrary folding-marker closures keep the synchronous
/// compatibility path; large built-in indentation/outline work is cancelable.
/// A canceled or stale job never publishes ranges or calls ready.
pub fn CodeEditorWidget::prepare_model(
  self : CodeEditorWidget,
  model : @model.TextModel,
  ready : (Result[Unit, @code_worker.CodeWorkerFailure]) -> Unit,
) -> @base_common.Disposable {
  if self.disposed || model.is_disposed() {
    ready(Err(Unavailable))
    return @base_common.Disposable::from(() => ())
  }
  if !self.get_options().folding ||
    model.is_too_large_for_tokenization() ||
    self.prepared_folding(model) is Some(_) ||
    (model.snapshot.line_count() < 2000 && model.get_value().length() < 65536) {
    ready(Ok(()))
    return @base_common.Disposable::from(() => ())
  }
  let rules = self.services.languages.get_language_configuration(
      model.get_language_id(),
    ).folding_rules
  if rules is Some({ markers: Some(_), .. }) {
    ready(Ok(()))
    return @base_common.Disposable::from(() => ())
  }
  let version = model.get_version_id()
  let tab_size = self.get_options().tab_size
  let limit = self.get_options().folding_maximum_regions
  let request = @worker_protocol.CodeWorkerRequest::Folding(
    text=model.get_value(),
    language_id=model.get_language_id(),
    off_side=rules is Some({ off_side: true, .. }),
    tab_size~,
    limit~,
    outline=true,
  )
  let job = @code_worker.compute(
    request,
    result => {
      if self.disposed || model.is_disposed() {
        return
      }
      let current_rules = self.services.languages.get_language_configuration(
          model.get_language_id(),
        ).folding_rules
      if model.get_version_id() != version ||
        self.get_options().tab_size != tab_size ||
        self.get_options().folding_maximum_regions != limit ||
        !same_folding_rules(rules, current_rules) {
        ready(Err(InvalidResponse))
        return
      }
      match result {
        Ok(Folding(provider, outlined)) => {
          self.store_prepared_folding(
            model,
            provider,
            outlined.unwrap_or(provider),
          )
          ready(Ok(()))
        }
        Ok(_) => ready(Err(InvalidResponse))
        Err(error) => ready(Err(error))
      }
    },
    max_time_ms=5000,
  )
  match job {
    None => {
      ready(Ok(()))
      @base_common.Disposable::from(() => ())
    }
    Some(job) => {
      let disposal = model.on_will_dispose(() => job.dispose())
      let widget_disposal = self.did_dispose.event(_ => job.dispose())
      @base_common.Disposable::from(() => {
        disposal.dispose()
        widget_disposal.dispose()
        job.dispose()
      })
    }
  }
}

///|
fn same_folding_rules(
  a : @languages.FoldingRules?,
  b : @languages.FoldingRules?,
) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}
