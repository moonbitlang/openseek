///|
/// Opaque service capabilities shared by the embeddable CodeEditorWidget and its
/// feature controllers. Concrete host backings never cross this root facade.
///
/// The hover participant registry is *not* held here: it is a free global in
/// `internal/viewer/contrib/hover` populated by that feature's contribution,
/// mirroring Monaco's `HoverParticipantRegistry`. `CodeEditorWidget::request_hover`
/// projects these services into a `@hover.HoverParticipantServices` when it
/// builds a hover computer.
struct CodeEditorServices {
  languages : @languages.LanguageHandle
  marker_decorations : @markers.MarkerDecorationsHandle
  agent_feedback : @agent_feedback_api.AgentFeedbackHandle
  code_lens_command_executor : @code_lens_api.CodeLensCommandExecutorHandle?
  location_opener : @navigation_api.LocationOpenerHandle?
  text_model_resolver : @navigation_api.TextModelResolverHandle?
  quick_diff : @quick_diff_api.QuickDiffHandle
  log_service : @log.LogHandle
  /// Concrete defaults owned by this exact bundle. Caller-supplied handles
  /// never appear here and therefore can never be disposed by the bundle.
  owned_marker_decorations : @markers.MarkerDecorationsService?
  owned_markers : @markers.MarkerService?
  owned_agent_feedback : @agent_feedback.AgentFeedbackService?
  mut disposed : Bool
}

///|
/// Creates a service bundle. Passing the returned value explicitly to a
/// CodeEditorWidget keeps ownership with the caller, allowing multiple Viewers to share
/// model registrations and host state. Omitting the CodeEditorWidget constructor's
/// `services` argument creates the same shape internally and transfers only
/// that internal bundle's lifetime to the CodeEditorWidget.
pub fn CodeEditorServices::CodeEditorServices(
  languages? : @languages.LanguageHandle,
  markers? : @markers.MarkerDecorationsSource,
  agent_feedback? : @agent_feedback_api.AgentFeedbackHandle,
  code_lens_command_executor? : @code_lens_api.CodeLensCommandExecutorHandle,
  location_opener? : @navigation_api.LocationOpenerHandle,
  text_model_resolver? : @navigation_api.TextModelResolverHandle,
  quick_diff? : @quick_diff_api.QuickDiffHandle,
  log_service? : @log.LogHandle,
) -> CodeEditorServices {
  let log_service = match log_service {
    Some(handle) => handle
    None => @log.LogService().log_handle()
  }
  let languages = match languages {
    Some(handle) => handle
    None => @languages.default_languages().language_handle(log_service)
  }
  let (marker_decorations, owned_marker_decorations, owned_markers) = match
    markers {
    None => {
      // The change event merges same-tick updates on a real microtask here
      // (Monaco's `MicrotaskEmitter`); headless tests use the sync default.
      let store = @markers.MarkerService(schedule=@base_browser.queue_microtask)
      let decorations = @markers.MarkerDecorationsService(
        store.marker_service_handle(),
      )
      (decorations.marker_decorations_handle(), Some(decorations), Some(store))
    }
    Some(MarkerStore(store)) => {
      let decorations = @markers.MarkerDecorationsService(store)
      (decorations.marker_decorations_handle(), Some(decorations), None)
    }
    Some(Decorations(decorations)) => (decorations, None, None)
  }
  let (agent_feedback, owned_agent_feedback) = match agent_feedback {
    Some(handle) => (handle, None)
    None => {
      let service = @agent_feedback.AgentFeedbackService()
      (service.agent_feedback_handle(), Some(service))
    }
  }
  let quick_diff = match quick_diff {
    Some(handle) => handle
    None => @quick_diff.QuickDiffService().quick_diff_handle()
  }
  {
    languages,
    marker_decorations,
    agent_feedback,
    code_lens_command_executor,
    location_opener,
    text_model_resolver,
    quick_diff,
    log_service,
    owned_marker_decorations,
    owned_markers,
    owned_agent_feedback,
    disposed: false,
  }
}

///|
/// Releases only backings created by this bundle, in the fixed
/// marker-decorations → marker-store → feedback order. The operation is
/// idempotent and never disposes a caller-supplied handle or captured backing.
pub fn CodeEditorServices::dispose(self : CodeEditorServices) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.owned_marker_decorations {
    Some(service) => service.dispose()
    None => ()
  }
  match self.owned_markers {
    Some(service) => service.dispose()
    None => ()
  }
  match self.owned_agent_feedback {
    Some(service) => service.dispose()
    None => ()
  }
}
