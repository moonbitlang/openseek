///|
/// Resolve file references with the conversation's project and checkout roots.
/// scratch/artifact paths belong to the durable session; other paths belong
/// to its current checkout. The host performs the ordinary rooted file read.
pub fn file_target(
  workspace : @common.Uri?,
  checkout : @common.Uri?,
  session : String,
  archived : Bool,
  path : String,
) -> (@common.Uri, String)? {
  guard @workspace_file_ref.parse(
      @workspace_file_ref.FenceLanguage,
      path,
      closed=true,
    )
    is Some(file) else {
    return None
  }
  if @workspace_file_ref.artifact_path(file.path) is Some(relative) {
    guard workspace is Some(root) &&
      !session.is_empty() &&
      session != "." &&
      session != ".." &&
      !session.contains("/") &&
      !session.contains("\\") else {
      return None
    }
    let store = if archived { ".openseek/archived" } else { ".openseek" }
    return Some(
      (root, "\{store}/sessions/\{session}/scratch/artifact/\{relative}"),
    )
  }
  checkout.map(root => (root, file.path))
}
