///|
/// Kind of a workspace tree entry, in place of `IFileStat`'s
/// `isFile`/`isDirectory` booleans.
pub(all) enum WorkspaceEntryKind {
  File
  Directory
} derive(Eq, Debug)

///|
/// One node of the workspace tree, mirroring VS Code's `IFileStat`: every
/// stat carries its full provider-minted `uri`, and `children` is `None`
/// until a provider resolves that directory level (the
/// `IFileStat.children: undefined` convention). Depth is tree structure,
/// not an annotation.
pub(all) struct WorkspaceStat {
  uri : @base_common.Uri
  name : String
  kind : WorkspaceEntryKind
  children : Array[WorkspaceStat]?
} derive(Debug)

///|
/// Result of resolving a workspace tree node through a tree provider.
pub(all) enum WorkspaceResolveResult {
  WorkspaceResolved(WorkspaceStat)
  WorkspaceResolveError(FileSystemProviderError)
} derive(Debug)

///|
/// The `IFileService.resolve` analog. `root` names the workspace root URI;
/// `resolve` returns the stat for a directory URI with exactly one level
/// of `children` resolved. Requests are pull-based; providers never push
/// tree data.
pub(open) trait WorkspaceTreeProvider {
  fn root(Self) -> @base_common.Uri
  async fn resolve(Self, @base_common.Uri) -> WorkspaceResolveResult
}

///|
/// Wire label for workspace tree entry kinds.
pub fn WorkspaceEntryKind::to_string(self : WorkspaceEntryKind) -> String {
  match self {
    File => "file"
    Directory => "directory"
  }
}

///|
/// Decodes a workspace tree entry kind from its wire label.
pub fn WorkspaceEntryKind::from_string(kind : String) -> WorkspaceEntryKind? {
  match kind {
    "file" => Some(File)
    "directory" => Some(Directory)
    _ => None
  }
}

///|
pub extend WorkspaceEntryKind with Debug::{to_repr}

///|
pub extend WorkspaceEntryKind with Eq::{equal, not_equal}

///|
pub extend WorkspaceResolveResult with Debug::{to_repr}

///|
pub extend WorkspaceStat with Debug::{to_repr}
