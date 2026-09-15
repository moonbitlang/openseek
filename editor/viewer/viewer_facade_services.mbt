///|
/// Public service bundle shared by standalone code viewers and host-owned
/// Markdown viewers. Ownership remains in the single internal bundle so the
/// façade cannot double-dispose default services.
struct ViewerServices {
  inner : @code_widget.CodeEditorServices
}

///|
/// Creates shared viewer services. `resource_path_label` returns a host-relative
/// file path for Peek labels, or `None` to retain the default resource label.
/// It is evaluated when results render so hosts can consult the live workspace.
pub fn ViewerServices::ViewerServices(
  languages? : @languages.LanguageHandle,
  markers? : @markers.MarkerDecorationsSource,
  agent_feedback? : @agent_feedback_api.AgentFeedbackHandle,
  location_opener? : @navigation_api.LocationOpenerHandle,
  text_model_resolver? : @navigation_api.TextModelResolverHandle,
  resource_path_label? : (@base_common.Uri) -> String? = _ => None,
  quick_diff? : @quick_diff_api.QuickDiffHandle,
  log_service? : @log.LogHandle,
) -> ViewerServices {
  {
    inner: CodeEditorServices(
      languages?,
      markers?,
      agent_feedback?,
      location_opener?,
      text_model_resolver?,
      resource_path_label~,
      quick_diff?,
      log_service?,
    ),
  }
}

///|
pub fn ViewerServices::dispose(self : ViewerServices) -> Unit {
  self.inner.dispose()
}

///|
fn ViewerServices::code_services(
  self : ViewerServices,
) -> @code_widget.CodeEditorServices {
  self.inner
}

///|
fn ViewerServices::languages(
  self : ViewerServices,
) -> @languages.LanguageHandle {
  self.inner.languages()
}

///|
fn ViewerServices::marker_decorations(
  self : ViewerServices,
) -> @markers.MarkerDecorationsHandle {
  self.inner.marker_decorations()
}

///|
fn ViewerServices::location_opener(
  self : ViewerServices,
) -> @navigation_api.LocationOpenerHandle? {
  self.inner.location_opener()
}

///|
fn ViewerServices::text_model_resolver(
  self : ViewerServices,
) -> @navigation_api.TextModelResolverHandle? {
  self.inner.text_model_resolver()
}

///|
fn ViewerServices::log_service(self : ViewerServices) -> @log.LogHandle {
  self.inner.log_service()
}
