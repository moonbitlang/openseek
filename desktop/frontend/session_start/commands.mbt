///|
pub fn fetch(
  channel : @interop.ChannelId,
  session : String,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      match result {
        Ok(snapshot) => emit(Snapshot(snapshot))
        Err(error) =>
          emit(LoadFailed(session~, error=@interop.bridge_error_text(error)))
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.session_starts_list, {
        session,
      })
    },
  )
}

///|
fn decide(
  channel : @interop.ChannelId,
  payload : @protocol.SessionStartDecision,
  emit : @cmd.Emit[Msg],
  attempt~ : Int32,
) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      match result {
        Ok(snapshot) => emit(Snapshot(snapshot))
        Err(error) =>
          @cmd.batch([
            emit(
              Failed(
                session=payload.session,
                request=payload.request_id,
                attempt~,
                error=@interop.bridge_error_text(error),
              ),
            ),
            fetch(channel, payload.session, emit),
          ])
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.session_starts_decide, payload)
    },
  )
}
