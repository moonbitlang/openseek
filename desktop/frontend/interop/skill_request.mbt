///|
/// Unwrap skill errors before callers render the host's original message.
pub async fn[Payload : ToJson, Reply : @json.FromJson] skill_request(
  channel : ChannelId,
  command : @commands.Command[Payload, @protocol.SkillCommandReply[Reply]],
  payload : Payload,
) -> Reply {
  match bridge_request(channel, command, payload) {
    SkillCommandSuccess(reply) => reply
    SkillCommandError(message) => raise BridgeRefused(message)
  }
}
