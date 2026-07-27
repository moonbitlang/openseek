///|
/// All concrete services Desktop owns for its embedded Viewer. Keeping them
/// together makes their shared lifetime explicit without changing editor's
/// public API.
priv struct DesktopViewerServices {
  viewer_services : @viewer.ViewerServices
  markers : @markers.MarkerService
  feedback : @feedback.DesktopFeedbackService
}

///|
fn DesktopViewerServices::DesktopViewerServices() -> DesktopViewerServices {
  let markers = @markers.MarkerService(schedule=@base_browser.queue_microtask)
  let feedback = @feedback.DesktopFeedbackService()
  let viewer_services = @viewer.ViewerServices(
    markers=@markers.MarkerStore(markers.marker_service_handle()),
    agent_feedback=feedback.agent_feedback_handle(),
  )
  { viewer_services, markers, feedback }
}
