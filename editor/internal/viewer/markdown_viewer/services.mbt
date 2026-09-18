///|
/// The service capabilities used by the standalone Markdown surface. This
/// package owns no CodeEditorWidget and does not import its service façade.
struct MarkdownViewerServices {
  localization : @localization.Localization
  languages : @languages.LanguageHandle
  marker_decorations : @markers.MarkerDecorationsHandle
  location_opener : @navigation_api.LocationOpenerHandle?
  text_model_resolver : @navigation_api.TextModelResolverHandle?
  resource_path_label : (@base_common.Uri) -> String?
  preview_factory : @references_browser.ReferencesPeekPreviewFactory?
  launch_async_task : (async () -> Unit noraise) -> Unit
  log_service : @log.LogHandle
  owned_marker_decorations : @markers.MarkerDecorationsService?
  owned_markers : @markers.MarkerService?
  mut disposed : Bool
}

///|
/// Builds a Markdown-only service bundle. Supplied handles remain caller-owned;
/// omitted marker services are created and released by this bundle.
pub fn MarkdownViewerServices::MarkdownViewerServices(
  localization? : @localization.Localization = Localization(),
  languages? : @languages.LanguageHandle,
  markers? : @markers.MarkerDecorationsSource,
  location_opener? : @navigation_api.LocationOpenerHandle,
  text_model_resolver? : @navigation_api.TextModelResolverHandle,
  resource_path_label? : (@base_common.Uri) -> String? = _ => None,
  preview_factory? : @references_browser.ReferencesPeekPreviewFactory,
  launch_async_task? : (async () -> Unit noraise) -> Unit = task => {
    @js.async_run(task)
  },
  log_service? : @log.LogHandle,
) -> MarkdownViewerServices {
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
  {
    localization,
    languages,
    marker_decorations,
    location_opener,
    text_model_resolver,
    resource_path_label,
    preview_factory,
    launch_async_task,
    log_service,
    owned_marker_decorations,
    owned_markers,
    disposed: false,
  }
}

///|
pub fn MarkdownViewerServices::languages(
  self : MarkdownViewerServices,
) -> @languages.LanguageHandle {
  self.languages
}

///|
pub fn MarkdownViewerServices::marker_decorations(
  self : MarkdownViewerServices,
) -> @markers.MarkerDecorationsHandle {
  self.marker_decorations
}

///|
pub fn MarkdownViewerServices::location_opener(
  self : MarkdownViewerServices,
) -> @navigation_api.LocationOpenerHandle? {
  self.location_opener
}

///|
pub fn MarkdownViewerServices::text_model_resolver(
  self : MarkdownViewerServices,
) -> @navigation_api.TextModelResolverHandle? {
  self.text_model_resolver
}

///|
pub fn MarkdownViewerServices::preview_factory(
  self : MarkdownViewerServices,
) -> @references_browser.ReferencesPeekPreviewFactory? {
  self.preview_factory
}

///|
pub fn MarkdownViewerServices::launch_async_task(
  self : MarkdownViewerServices,
  task : async () -> Unit noraise,
) -> Unit {
  (self.launch_async_task)(task)
}

///|
pub fn MarkdownViewerServices::log_service(
  self : MarkdownViewerServices,
) -> @log.LogHandle {
  self.log_service
}

///|
pub fn MarkdownViewerServices::dispose(self : MarkdownViewerServices) -> Unit {
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
}
