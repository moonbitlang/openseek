///|
/// These effects bind the existing typed Proton command channel. HTTP and
/// credentials remain native; updates only construct commands and hold data.
/// A bridge failure is reported under `failure` with the transport's text.
fn[Payload : ToJson, Reply : @json.FromJson] request(
  emit : @cmd.Emit[Msg],
  command : @commands.Command[Payload, Reply],
  payload : Payload,
  failure~ : String,
  to_msg : (Result[Reply, String]) -> Msg,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result = Ok(@interop.bridge_request(Local, command, payload)) catch {
        error => Err("\{failure}: \{@interop.bridge_error_text(error)}")
      }
      scheduler.add(emit(to_msg(result)))
    })
  })
}

///|
fn Model::share(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  let generation = self.generation
  request(emit, @commands.session_share, source, failure="Could not share", result => {
    Published(
      generation~,
      match result {
        Ok(reply) => reply
        Err(message) => Failed(message~)
      },
    )
  })
}

///|
fn Model::download(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  let generation = self.generation
  request(
    emit,
    @commands.session_export,
    source,
    failure="Could not download",
    result => Downloaded(generation~, result),
  )
}

///|
/// Sign in to the selected OpenSeek server using the existing browser flow.
/// Returning to Ready requires another explicit Share click before upload.
fn Model::sign_in(self : Model, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  let generation = self.generation
  request(
    emit,
    @commands.auth_connect,
    NoPayload,
    failure="Could not sign in",
    result => SignedIn(generation~, result.map(_ => ())),
  )
}

///|
/// Abort the waiting sign-in. Its own auth.connect reply settles the dialog
/// that started it (already closed and ignoring that generation), so a
/// failure here has nothing left to report to.
fn cancel_sign_in() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.async_run(() => {
      let _ = @interop.bridge_request(Local, @commands.auth_cancel, NoPayload) catch {
        _ => return
      }
    })
  })
}
