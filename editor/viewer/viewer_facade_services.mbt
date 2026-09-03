///|
/// Public service bundle shared by standalone code viewers and host-owned
/// Markdown viewers. Ownership remains in the single internal bundle so the
/// façade cannot double-dispose default services.
struct ViewerServices {
  inner : @code_widget.CodeEditorServices
}

///|
pub fn ViewerServices::ViewerServices(
  languages? : @languages.LanguageHandle,
  markers? : @markers.MarkerDecorationsSource,
  agent_feedback? : @agent_feedback_api.AgentFeedbackHandle,
  code_lens_command_executor? : @code_lens_api.CodeLensCommandExecutorHandle,
  location_opener? : @navigation_api.LocationOpenerHandle,
  text_model_resolver? : @navigation_api.TextModelResolverHandle,
  quick_diff? : @quick_diff_api.QuickDiffHandle,
  log_service? : @log.LogHandle,
) -> ViewerServices {
  {
    inner: CodeEditorServices(
      languages?,
      markers?,
      agent_feedback?,
      code_lens_command_executor?,
      location_opener?,
      text_model_resolver?,
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
