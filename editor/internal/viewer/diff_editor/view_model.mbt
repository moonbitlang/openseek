///|
/// The two caller-owned models compared by the diff ViewModel. The ViewModel
/// only retains and observes them; it never disposes either model.
pub(all) struct DiffEditorModelData {
  original : @model.TextModel
  modified : @model.TextModel
}

///|
pub(all) enum DiffEditorViewModelState {
  NoModel
  Pending
  Ready
  Failed
} derive(Eq, Debug)

///|
/// Internal diagnostic for the otherwise intentionally coarse public
/// `Failed` state. Keeping it private distinguishes provider execution from
/// rejected provider output without widening the DiffEditor API.
priv enum DiffEditorViewModelFailure {
  ProviderError
  ValidationRejected
}

///|
/// DOM-free owner of one model pair and its synchronous provider result.
/// Browser timing is injected through RunOnceScheduler so white-box tests can
/// drive the 0/200ms lanes without sleeping.
pub struct DiffEditorViewModel {
  mut provider : &@diff.DocumentDiffProvider
  mut provider_subscription : @base_common.Disposable?
  mut model : DiffEditorModelData?
  model_subscriptions : Array[@base_common.Disposable]
  mut options : @diff.DocumentDiffOptions
  mut state : DiffEditorViewModelState
  mut current_diff : @diff.DocumentDiff?
  priv mut failure : DiffEditorViewModelFailure?
  mut generation : Int
  immediate : @base_browser.RunOnceScheduler
  content_debounce : @base_browser.RunOnceScheduler
  did_change_model : @base_common.Emitter[Unit]
  did_update : @base_common.Emitter[Unit]
  mut disposed : Bool
}

///|
pub fn DiffEditorViewModel::DiffEditorViewModel(
  provider : &@diff.DocumentDiffProvider,
  options? : @diff.DocumentDiffOptions = { ignore_trim_whitespace: true, },
  schedule_timeout? : (() -> Unit, Int) -> @base_common.Disposable = @base_browser.schedule_timeout,
) -> DiffEditorViewModel {
  let self : DiffEditorViewModel = {
    provider,
    provider_subscription: None,
    model: None,
    model_subscriptions: [],
    options,
    state: NoModel,
    current_diff: None,
    failure: None,
    generation: 0,
    immediate: @base_browser.RunOnceScheduler::new_with_timer(
      0, schedule_timeout,
    ),
    content_debounce: @base_browser.RunOnceScheduler::new_with_timer(
      200, schedule_timeout,
    ),
    did_change_model: Emitter(),
    did_update: Emitter(),
    disposed: false,
  }
  self.install_provider_subscription()
  self
}

///|
fn DiffEditorViewModel::install_provider_subscription(
  self : DiffEditorViewModel,
) -> Unit {
  match self.provider_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  self.provider_subscription = Some(
    self.provider.on_did_change(() => self.invalidate_immediately()),
  )
}

///|
fn same_model_pair(
  left : DiffEditorModelData?,
  right : DiffEditorModelData?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) =>
      left.original.same(right.original) && left.modified.same(right.modified)
    _ => false
  }
}

///|
pub fn DiffEditorViewModel::set_model(
  self : DiffEditorViewModel,
  model : DiffEditorModelData?,
) -> DiffEditorModelData? {
  let previous = self.model
  // The return value is an ownership-transfer seam for hosts: every returned
  // pair is already detached and may be disposed immediately. Returning the
  // still-installed pair for a no-op would violate that contract.
  if self.disposed || same_model_pair(previous, model) {
    return None
  }
  self.generation += 1
  self.immediate.cancel()
  self.content_debounce.cancel()
  self.dispose_model_subscriptions()
  self.model = model
  self.current_diff = None
  self.failure = None
  match model {
    None => self.state = NoModel
    Some(model) => {
      self.state = Pending
      let original_identity = model.original.identity()
      let modified_identity = model.modified.identity()
      let invalidate_content = () => {
        self.invalidate_content_for_model_pair(
          original_identity, modified_identity,
        )
      }
      let clear_pair = () => {
        self.clear_model_pair_on_will_dispose(
          original_identity, modified_identity,
        )
      }
      self.model_subscriptions.push(
        model.original.on_did_change_content(_ => invalidate_content()),
      )
      self.model_subscriptions.push(
        model.modified.on_did_change_content(_ => invalidate_content()),
      )
      self.model_subscriptions.push(model.original.on_will_dispose(clear_pair))
      self.model_subscriptions.push(model.modified.on_will_dispose(clear_pair))
      self.schedule_immediate_compute()
    }
  }
  // The model event is a synchronous transaction boundary. DiffEditorWidget
  // mirrors the already-committed pair into both kernels before the ordinary
  // diff update event can reconcile decorations, zones, and overview state.
  self.did_change_model.fire(())
  self.did_update.fire(())
  previous
}

///|
fn DiffEditorViewModel::clear_model_pair_on_will_dispose(
  self : DiffEditorViewModel,
  original_identity : Int,
  modified_identity : Int,
) -> Unit {
  if self.disposed {
    return
  }
  guard self.model is Some(current) &&
    current.original.identity() == original_identity &&
    current.modified.identity() == modified_identity else {
    // A detached model can finish disposal after a replacement. Its callback
    // must never clear the newly installed pair.
    return
  }
  self.generation += 1
  self.immediate.cancel()
  self.content_debounce.cancel()
  self.dispose_model_subscriptions()
  self.model = None
  self.current_diff = None
  self.failure = None
  self.state = NoModel
  // Models are caller-owned. The disposing member and its still-live sibling
  // are only detached here; neither is disposed and no ownership transfer is
  // synthesized for an external lifecycle invalidation.
  self.did_change_model.fire(())
  self.did_update.fire(())
}

///|
fn DiffEditorViewModel::dispose_model_subscriptions(
  self : DiffEditorViewModel,
) -> Unit {
  for subscription in self.model_subscriptions {
    subscription.dispose()
  }
  self.model_subscriptions.clear()
}

///|
pub fn DiffEditorViewModel::set_provider(
  self : DiffEditorViewModel,
  provider : &@diff.DocumentDiffProvider,
) -> Unit {
  if self.disposed {
    return
  }
  self.provider = provider
  self.install_provider_subscription()
  self.invalidate_immediately()
}

///|
pub fn DiffEditorViewModel::update_options(
  self : DiffEditorViewModel,
  options : @diff.DocumentDiffOptions,
) -> Unit {
  if self.disposed || self.options == options {
    return
  }
  self.options = options
  self.invalidate_immediately()
}

///|
fn DiffEditorViewModel::begin_pending(self : DiffEditorViewModel) -> Unit {
  self.generation += 1
  self.current_diff = None
  self.failure = None
  self.state = if self.model is Some(_) { Pending } else { NoModel }
  self.did_update.fire(())
}

///|
fn DiffEditorViewModel::invalidate_immediately(
  self : DiffEditorViewModel,
) -> Unit {
  if self.disposed {
    return
  }
  self.begin_pending()
  self.content_debounce.cancel()
  self.schedule_immediate_compute()
}

///|
fn DiffEditorViewModel::invalidate_content(self : DiffEditorViewModel) -> Unit {
  if self.disposed {
    return
  }
  self.begin_pending()
  self.immediate.cancel()
  let generation = self.generation
  self.content_debounce.schedule(() => self.compute_generation(generation))
}

///|
fn DiffEditorViewModel::invalidate_content_for_model_pair(
  self : DiffEditorViewModel,
  original_identity : Int,
  modified_identity : Int,
) -> Unit {
  guard self.model is Some(current) &&
    current.original.identity() == original_identity &&
    current.modified.identity() == modified_identity else {
    return
  }
  self.invalidate_content()
}

///|
fn DiffEditorViewModel::schedule_immediate_compute(
  self : DiffEditorViewModel,
) -> Unit {
  if self.model is Some(_) {
    let generation = self.generation
    self.immediate.schedule(() => self.compute_generation(generation))
  }
}

///|
fn DiffEditorViewModel::compute_generation(
  self : DiffEditorViewModel,
  generation : Int,
) -> Unit {
  if !self.disposed && self.generation == generation {
    self.compute_current()
  }
}

///|
fn DiffEditorViewModel::compute_current(self : DiffEditorViewModel) -> Unit {
  if self.disposed {
    return
  }
  guard self.model is Some(model) else {
    self.state = NoModel
    self.current_diff = None
    self.failure = None
    return
  }
  let generation = self.generation
  let original_identity = model.original.identity()
  let modified_identity = model.modified.identity()
  let original_version = model.original.get_version_id()
  let modified_version = model.modified.get_version_id()
  let original = model.original.snapshot()
  let modified = model.modified.snapshot()
  let computed = Some(
    self.provider.compute_diff(original, modified, self.options),
  ) catch {
    _ => None
  }
  if self.disposed || self.generation != generation {
    return
  }
  guard self.model is Some(current) &&
    current.original.identity() == original_identity &&
    current.modified.identity() == modified_identity &&
    current.original.get_version_id() == original_version &&
    current.modified.get_version_id() == modified_version else {
    return
  }
  match computed {
    Some(result) =>
      match
        @diff.normalize_and_validate_document_diff(result, original, modified) {
        Some(result) => {
          self.current_diff = Some(result)
          self.failure = None
          self.state = Ready
        }
        None => {
          self.current_diff = None
          self.failure = Some(ValidationRejected)
          self.state = Failed
          self.did_update.fire(())
          return
        }
      }
    _ => {
      self.current_diff = None
      self.failure = Some(ProviderError)
      self.state = Failed
    }
  }
  self.did_update.fire(())
}

///|
/// Internal-package failure detail for diagnostics. The public Viewer facade
/// keeps its coarse `Failed` state and does not forward this accessor.
pub fn DiffEditorViewModel::get_failure_diagnostic(
  self : DiffEditorViewModel,
) -> String? {
  match self.failure {
    Some(ProviderError) => Some("provider error")
    Some(ValidationRejected) => Some("validator rejection")
    None => None
  }
}

///|
pub fn DiffEditorViewModel::get_model(
  self : DiffEditorViewModel,
) -> DiffEditorModelData? {
  self.model
}

///|
pub fn DiffEditorViewModel::get_state(
  self : DiffEditorViewModel,
) -> DiffEditorViewModelState {
  self.state
}

///|
pub fn DiffEditorViewModel::get_diff(
  self : DiffEditorViewModel,
) -> @diff.DocumentDiff? {
  self.current_diff
}

///|
pub fn DiffEditorViewModel::is_diff_up_to_date(
  self : DiffEditorViewModel,
) -> Bool {
  self.state is Ready
}

///|
pub fn DiffEditorViewModel::on_did_update_diff(
  self : DiffEditorViewModel,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_update.event(_ => listener())
}

///|
fn DiffEditorViewModel::on_did_change_model(
  self : DiffEditorViewModel,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_change_model.event(_ => listener())
}

///|
pub fn DiffEditorViewModel::dispose(self : DiffEditorViewModel) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.generation += 1
  self.immediate.dispose()
  self.content_debounce.dispose()
  self.dispose_model_subscriptions()
  match self.provider_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  self.provider_subscription = None
  self.model = None
  self.current_diff = None
  self.failure = None
  self.state = NoModel
  self.did_change_model.dispose()
  self.did_update.dispose()
}

///|
pub extend DiffEditorViewModelState with Eq::{equal, not_equal}

///|
pub extend DiffEditorViewModelState with Debug::{to_repr}
