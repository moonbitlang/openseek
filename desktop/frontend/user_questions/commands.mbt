// Transport effects live here; model updates and views only construct commands.

///|
pub fn fetch(channel : @interop.ChannelId, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      match result {
        Ok(snapshot) => emit(Snapshot(snapshot))
        Err(_) => @cmd.none
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.user_questions_list, NoPayload)
    },
  )
}

///|
fn answer(
  channel : @interop.ChannelId,
  payload : @protocol.UserQuestionAnswer,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      match result {
        Ok(snapshot) => emit(Snapshot(snapshot))
        Err(error) =>
          @cmd.batch([
            emit(
              Failed(
                request=payload.id,
                error=@interop.bridge_error_text(error),
              ),
            ),
            fetch(channel, emit),
          ])
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.user_questions_answer, payload)
    },
  )
}
