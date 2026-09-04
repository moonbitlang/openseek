///|
/// All concrete services Desktop owns for its embedded Viewer. Keeping them
/// together makes their shared lifetime explicit without changing editor's
/// public API.
priv struct DesktopViewerServices {
  viewer_services : @viewer.ViewerServices
  markers : @markers.MarkerService
  feedback : @feedback.DesktopFeedbackService
  // Caller-owned baseline store behind the Viewer's public QuickDiffHandle.
  // Changed-file opens push HEAD content here; ordinary opens clear it for
  // the resource they show.
  quick_diff : DesktopQuickDiffService
  // Retaining the registry handles keeps ownership explicit. The desktop
  // mounts exactly one Viewer for the page lifetime; a future page teardown
  // can dispose these without reaching into the process-wide registry.
  _navigation_registrations : Array[@common.Disposable]
  _code_lens_registration : @common.Disposable
}

///|
fn DesktopViewerServices::DesktopViewerServices(
  location_opener : @navigation_api.LocationOpenerHandle,
  text_model_resolver : @navigation_api.TextModelResolverHandle,
  on_navigation_error : (@interop.ConversationKey, String) -> Unit,
) -> DesktopViewerServices {
  let markers = @markers.MarkerService(schedule=@base_browser.queue_microtask)
  let feedback = @feedback.DesktopFeedbackService()
  let quick_diff = DesktopQuickDiffService()
  let navigation_registrations = register_moon_ide_navigation_providers(
    on_navigation_error,
  )
  let code_lens_registration = register_moon_ide_code_lens_provider()
  let viewer_services = @viewer.ViewerServices(
    markers=@markers.MarkerStore(markers.marker_service_handle()),
    agent_feedback=feedback.agent_feedback_handle(),
    location_opener~,
    text_model_resolver~,
    quick_diff=quick_diff.quick_diff_handle(),
    code_lens_command_executor=moon_ide_code_lens_executor(on_navigation_error),
  )
  {
    viewer_services,
    markers,
    feedback,
    quick_diff,
    _navigation_registrations: navigation_registrations,
    _code_lens_registration: code_lens_registration,
  }
}
