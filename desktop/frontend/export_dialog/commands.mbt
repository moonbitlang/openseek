///|
/// These effects bind the existing typed Proton command channel. HTTP and
/// credentials remain native; updates only construct commands and hold data.
fn Model::share(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        Local,
        @commands.session_share,
        source,
      ) catch {
        error =>
          @protocol.Failed(
            message="Could not share: \{@interop.bridge_error_text(error)}",
          )
      }
      scheduler.add(emit(Published(generation=self.generation, reply)))
    })
  })
}

///|
fn Model::download(
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = Ok(
        @interop.bridge_request(Local, @commands.session_export, source),
      ) catch {
        error => Err("Could not download: \{@interop.bridge_error_text(error)}")
      }
      scheduler.add(emit(Downloaded(generation=self.generation, reply)))
    })
  })
}

///|
/// Sign in to the selected OpenSeek server using the existing browser flow.
/// Returning to Ready requires another explicit Share click before upload.
fn Model::sign_in(self : Model, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result = try {
        let _ = @interop.bridge_request(
          Local,
          @commands.auth_connect,
          @protocol.NoPayload,
        )
        Ok(())
      } catch {
        error => Err("Could not sign in: \{@interop.bridge_error_text(error)}")
      }
      scheduler.add(emit(SignedIn(generation=self.generation, result)))
    })
  })
}
