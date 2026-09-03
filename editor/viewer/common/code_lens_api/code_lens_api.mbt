///|
/// One host execution request originating from a rendered CodeLens command.
/// The Viewer supplies its stable id, current resource, tracked lens range,
/// and the provider's complete command value; workspace and command-routing
/// policy remain entirely host-owned.
pub(all) struct CodeLensCommandRequest {
  source_viewer_id : String
  resource : @base_common.Uri
  range : @base_common.Range
  command : @language.CodeLensCommand
} derive(Debug)

///|
/// Minimal host-owned capability for executing a CodeLens command. `true`
/// means the host accepted and handled the request.
struct CodeLensCommandExecutorHandle {
  execute_callback : async (CodeLensCommandRequest) -> Bool noraise
}

///|
/// Constructs an executor without transferring ownership of its captured
/// backing or lifecycle to the handle or ViewerServices.
pub fn CodeLensCommandExecutorHandle::CodeLensCommandExecutorHandle(
  execute~ : async (CodeLensCommandRequest) -> Bool noraise,
) -> CodeLensCommandExecutorHandle {
  { execute_callback: execute, }
}

///|
/// Forwards one complete command request to the host.
pub async fn CodeLensCommandExecutorHandle::execute(
  self : CodeLensCommandExecutorHandle,
  request : CodeLensCommandRequest,
) -> Bool noraise {
  (self.execute_callback)(request)
}

///|
pub extend CodeLensCommandRequest with Debug::{to_repr}
