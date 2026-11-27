///|
fn ApiState::preview_tool(self : ApiState, account? : String) -> @mcp.Tool {
  @preview_open.tool((session, path) => {
    let request : @protocol.PreviewOpenRequest = match account {
      Some(account) => {
        guard self.auth.account().map(a => a.user.user_id) == Some(account) else {
          raise @mcp.ToolError("Cloud preview account is no longer signed in")
        }
        Cloud(account~, session~, path~)
      }
      None => {
        guard @work_dir.session_cwd(session) is Some(workspace) else {
          raise @mcp.ToolError("this conversation has no available workspace")
        }
        Local(session~, workspace=workspace.resource_path(), path~)
      }
    }
    // TODO: retain requests while the desktop page is disconnected. Opening
    // acknowledges host acceptance; it does not confirm UI delivery/rendering.
    self.publish(PreviewOpen(request))
  })
}
