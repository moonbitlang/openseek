///|
fn ApiState::preview_tool(self : ApiState, account? : String) -> @mcp.Tool {
  {
    name: "preview_open",
    description: "Show a generated workspace file to the user in this conversation's SeekMoon file/preview panel. Supply a workspace-relative path using forward slashes. Reuses the existing HTML/HTM, PDF, image, Office, code and text viewers. This presents a file to the user; it does not read file contents for the agent or open an external website (use browser_open for URLs). An opening result only acknowledges that the open request was accepted, not that the file exists, has loaded, or has finished rendering. Background conversation requests stay with that conversation and open when the user returns, without changing chat focus.",
    input_schema: {
      "type": "object",
      "additionalProperties": false,
      "required": ["path"],
      "properties": {
        "path": {
          "type": "string",
          "description": "Path of the generated file relative to this conversation's workspace.",
        },
      },
    },
    call: call => {
      let args : @protocol.PreviewOpenArgs = @json.from_json(call.arguments)
      let request : @protocol.PreviewOpenRequest = match account {
        Some(account) => {
          guard self.auth.account().map(a => a.user.user_id) == Some(account) else {
            raise @mcp.ToolError("Cloud preview account is no longer signed in")
          }
          Cloud(account~, session=call.session, path=args.path)
        }
        None => {
          guard @work_dir.session_cwd(call.session) is Some(workspace) else {
            raise @mcp.ToolError("this conversation has no available workspace")
          }
          Local(
            session=call.session,
            workspace=workspace.resource_path(),
            path=args.path,
          )
        }
      }
      // TODO: retain requests while the desktop page is disconnected. Opening
      // acknowledges host acceptance; it does not confirm UI delivery/rendering.
      self.publish(PreviewOpen(request))
      let result : Json = { "status": "opening", "path": Json(args.path) }
      [Text(result.stringify())]
    },
  }
}
