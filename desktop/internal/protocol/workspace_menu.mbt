// Typed contract for the native workspace-row popup. The selected workspace
// stays in frontend state; the native host needs only presentation coordinates.

///|
pub(all) enum WorkspaceMenuAction {
  OpenWorkspaceSettings
  DetachWorkspace
} derive(Debug, Eq)

///|
pub fn WorkspaceMenuAction::wire(self : WorkspaceMenuAction) -> String {
  match self {
    OpenWorkspaceSettings => "workspace.settings"
    DetachWorkspace => "workspace.detach"
  }
}

///|
pub fn WorkspaceMenuAction::parse(value : String) -> WorkspaceMenuAction? {
  match value {
    "workspace.settings" => Some(OpenWorkspaceSettings)
    "workspace.detach" => Some(DetachWorkspace)
    _ => None
  }
}

///|
pub(all) struct WorkspaceMenuPayload {
  x : Int
  y : Int
} derive(Debug, Eq)

///|
pub impl FromJson for WorkspaceMenuPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "workspace menu payload")
  { x: object.required_int("x"), y: object.required_int("y"), }
}

///|
pub impl ToJson for WorkspaceMenuPayload with fn to_json(self) {
  { "x": self.x, "y": self.y }
}

///|
pub extend WorkspaceMenuPayload with FromJson::{from_json}

///|
pub extend WorkspaceMenuPayload with ToJson::{to_json}

///|
pub extend WorkspaceMenuAction with Debug::{to_repr}

///|
pub extend WorkspaceMenuAction with Eq::{equal, not_equal}

///|
pub extend WorkspaceMenuPayload with Debug::{to_repr}

///|
pub extend WorkspaceMenuPayload with Eq::{equal, not_equal}
