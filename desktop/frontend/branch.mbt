// The topbar's branch chip: ask the host for the git branch of a
// conversation's workspace through the `workspace_branch` op. Probed when a
// run starts (the workspace is created lazily on the first one), when a
// stored session opens, and when a run finishes (the agent may have created
// the repository or switched branches mid-turn). Any failure just reads as
// "no branch" — the chip hides.

///|
fn fetch_branch(
  dispatch : @cmd.Emit[Msg],
  session : String,
  cwd : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["cwd"] = cwd
      let reply = bridge_request("workspace_branch", payload.to_value()) catch {
        _ => {
          scheduler.add(dispatch(BranchLoaded(session~, branch="")))
          return
        }
      }
      scheduler.add(
        dispatch(
          BranchLoaded(session~, branch=decode_branch(reply_json_text(reply))),
        ),
      )
    })
  })
}

///|
fn decode_branch(text : String) -> String {
  let json = @json.parse(text) catch { _ => return "" }
  guard json is Object(reply) else { return "" }
  guard reply.get("branch") is Some(String(branch)) else { return "" }
  branch
}
