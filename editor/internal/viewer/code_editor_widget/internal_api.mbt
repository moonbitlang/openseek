///|
pub fn CodeEditorServices::languages(
  self : CodeEditorServices,
) -> @languages.LanguageHandle {
  self.languages
}

///|
pub fn CodeEditorServices::marker_decorations(
  self : CodeEditorServices,
) -> @markers.MarkerDecorationsHandle {
  self.marker_decorations
}

///|
pub fn CodeEditorServices::agent_feedback(
  self : CodeEditorServices,
) -> @agent_feedback_api.AgentFeedbackHandle {
  self.agent_feedback
}

///|
pub fn CodeEditorServices::code_lens_command_executor(
  self : CodeEditorServices,
) -> @code_lens_api.CodeLensCommandExecutorHandle? {
  self.code_lens_command_executor
}

///|
pub fn CodeEditorServices::location_opener(
  self : CodeEditorServices,
) -> @navigation_api.LocationOpenerHandle? {
  self.location_opener
}

///|
pub fn CodeEditorServices::text_model_resolver(
  self : CodeEditorServices,
) -> @navigation_api.TextModelResolverHandle? {
  self.text_model_resolver
}

///|
pub fn CodeEditorServices::quick_diff(
  self : CodeEditorServices,
) -> @quick_diff_api.QuickDiffHandle {
  self.quick_diff
}

///|
pub fn CodeEditorServices::log_service(
  self : CodeEditorServices,
) -> @log.LogHandle {
  self.log_service
}

///|
/// Internal lifecycle fact used by composite widgets to verify that their
/// owned kernels have completed teardown. Public Viewer does not forward this
/// diagnostic surface.
pub fn CodeEditorWidget::is_disposed(self : CodeEditorWidget) -> Bool {
  self.disposed
}
