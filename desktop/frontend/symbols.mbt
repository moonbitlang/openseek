// Root-shell routing for the shared workspace-symbol package. OpenSeek keeps
// owner/generation identity in its own Msg; wire projection and transport live
// in `frontend/symbols`.

///|
type WorkspaceSymbol = @symbols.Symbol

///|
/// Which root-shell surface owns a workspace-symbol request. Each surface
/// carries its own generation so an overtaken response cannot settle a newer
/// query.
priv enum SymbolRequest {
  QuickOpenSymbolRequest(Int)
}

///|
/// Search `query` and route the reply back to the exact owning surface. The
/// shared symbols package owns transport; this method only projects its reply
/// into the root shell's two message shapes.
fn SymbolRequest::search(
  self : SymbolRequest,
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  query : String,
  root~ : @common.Uri?,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  let loaded = items => {
    dispatch(
      match self {
        QuickOpenSymbolRequest(generation) =>
          QuickOpenSymbolsLoaded(owner~, query~, generation~, items~)
      },
    )
  }
  let failed = dispatch(
    match self {
      QuickOpenSymbolRequest(generation) =>
        QuickOpenSymbolsRequestFailed(owner~, query~, generation~)
    },
  )
  @symbols.search(owner.channel, query, root~, loaded~, failed~)
}
