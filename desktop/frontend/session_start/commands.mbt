///|
pub fn fetch(
  channel : @interop.ChannelId,
  source : Source,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    result => {
      match result {
        Ok(snapshot) => emit(Snapshot(snapshot))
        Err(error) =>
          emit(LoadFailed(source~, error=@interop.bridge_error_text(error)))
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.session_starts_list, {
        session: source.session,
        workspace: source.workspace,
        archived: Some(source.archived),
      })
    },
  )
}

///|
fn decide(
  channel : @interop.ChannelId,
  payload : @protocol.SessionStartDecision,
  source : Source,
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
                source~,
                request=payload.request_id,
                attempt~,
                error=@interop.bridge_error_text(error),
              ),
            ),
            fetch(channel, source, emit),
          ])
      }
    },
    () => {
      @interop.bridge_request(channel, @commands.session_starts_decide, payload)
    },
  )
}
