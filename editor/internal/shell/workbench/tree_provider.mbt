///|
/// Browser-side workspace tree provider: implements
/// `@workspace.WorkspaceTreeProvider` over the protocol client with
/// correlated `ResolveDirectory` requests.
priv struct RemoteWorkspaceTreeProvider {}

///|
let workspace_tree_provider : &@workspace.WorkspaceTreeProvider = RemoteWorkspaceTreeProvider::{
}

///|
impl @workspace.WorkspaceTreeProvider for RemoteWorkspaceTreeProvider with fn root(
  _self,
) {
  try! @base_common.Uri::parse("readonly-remote://workspace")
}

///|
impl @workspace.WorkspaceTreeProvider for RemoteWorkspaceTreeProvider with fn resolve(
  _self,
  uri,
) {
  let response = protocol_request("resolve", id => {
    ResolveDirectory({ id, uri, })
  })
  match response {
    DirectoryResolved(payload) => WorkspaceResolved(payload.stat)
    RemoteError(error) =>
      WorkspaceResolveError(
        FileSystemProviderError(
          @workspace.FileSystemProviderErrorCode::from_string(
            error.provider_code,
          ),
          error.message,
          uri~,
        ),
      )
    _ =>
      WorkspaceResolveError(
        FileSystemProviderError(
          Unavailable,
          "Unexpected protocol response for directory resolve.",
          uri~,
        ),
      )
  }
}

///|
/// The explorer widget instance, created on first use so the protocol
/// dispatch hooks installed at mount are already in place.
let file_tree_cell : Ref[@file_tree.FileTree?] = Ref(None)

///|
fn workspace_file_tree() -> @file_tree.FileTree {
  match file_tree_cell.val {
    Some(tree) => tree
    None => {
      let tree = @file_tree.FileTree(workspace_tree_provider, on_open=uri => {
        dispatch_workbench_msg(SelectWorkspace(uri))
      })
      file_tree_cell.val = Some(tree)
      tree
    }
  }
}

///|
/// Auto-open policy (app policy, not widget behavior): a bounded
/// depth-first resolve walk that opens the first `.mbt` file, falling back
/// to the first file of any kind; `set_active` then reveals it in the tree
/// once the document renders.
fn auto_open_first_file_cmd(emit : @rabbita.Emit[WorkbenchMsg]) -> @rabbita.Cmd {
  @cmd.perform(result => emit(AutoOpenResolved(result)), async fn() noraise {
    find_first_workspace_file() catch {
      _ => None
    }
  })
}

///|
let auto_open_max_resolves = 32

///|
let auto_open_max_depth = 6

///|
async fn find_first_workspace_file() -> @base_common.Uri? {
  let first_file : Ref[@base_common.Uri?] = Ref(None)
  let budget : Ref[Int] = Ref(auto_open_max_resolves)
  match
    first_moonbit_file(workspace_tree_provider.root(), budget, 0, first_file) {
    Some(uri) => Some(uri)
    None => first_file.val
  }
}

///|
async fn first_moonbit_file(
  uri : @base_common.Uri,
  budget : Ref[Int],
  depth : Int,
  first_file : Ref[@base_common.Uri?],
) -> @base_common.Uri? {
  if budget.val <= 0 || depth > auto_open_max_depth {
    return None
  }
  budget.val -= 1
  guard workspace_tree_provider.resolve(uri)
    is WorkspaceResolved({ children: Some(children), .. }) else {
    return None
  }
  for child in children {
    if child.kind == File {
      if child.name.has_suffix(".mbt") {
        return Some(child.uri)
      }
      if first_file.val is None {
        first_file.val = Some(child.uri)
      }
    }
  }
  for child in children {
    if child.kind == Directory &&
      first_moonbit_file(child.uri, budget, depth + 1, first_file)
      is Some(found) {
      return Some(found)
    }
  }
  None
}
