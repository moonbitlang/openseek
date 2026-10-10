///|
/// Allocate a page-local request namespace outside the pure update function.
pub fn initialize(ready : @cmd.Emit[String]) -> @cmd.Cmd {
  @cmd.perform(value => ready(value), () => @uuid.mint())
}

///|
/// Run a typed auxiliary request. Reply identity is owned by the caller.
pub fn request(
  owner : @interop.ConversationKey,
  request_id : String,
  source_sequence : Int,
  settled : @cmd.Emit[Result[@protocol.PredictionReply, String]],
) -> @cmd.Cmd {
  @cmd.attempt(result => settled(result.map_err(@interop.bridge_error_text)), () => {
    @interop.bridge_request(owner.channel, @commands.agent_predict, {
      session: owner.session,
      request_id,
      source_sequence,
    })
  })
}

///|
/// Best-effort cancellation; stale response rejection remains mandatory.
pub fn cancel(
  owner : @interop.ConversationKey,
  request_id : String,
  source_sequence : Int,
) -> @cmd.Cmd {
  @cmd.attempt(_ => @cmd.none, () => {
    @interop.bridge_request(owner.channel, @commands.agent_cancel_prediction, {
      session: owner.session,
      request_id,
      source_sequence,
    })
  })
}
