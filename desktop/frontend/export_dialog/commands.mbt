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
    @js.Promise::from_async(() => {
      let result = Ok(@interop.bridge_request(Local, command, payload)) catch {
        error => Err("\{failure}: \{@interop.bridge_error_text(error)}")
      }
      scheduler.add(emit(to_msg(result)))
    })
    |> ignore
  })
}

///|
fn Model::share(
  locale? : @i18n.Locale = English,
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  let generation = self.generation
  request(
    emit,
    @commands.session_share,
    source,
    failure=match locale {
      SimplifiedChinese => "分享失败"
      TraditionalChinese => "分享失敗"
      Japanese => "共有に失敗しました"
      English => "Could not share"
    },
    result => {
      Published(
        generation~,
        match result {
          Ok(reply) => reply
          Err(message) => @protocol.Failed(message~)
        },
      )
    },
  )
}

///|
fn Model::download(
  locale? : @i18n.Locale = English,
  self : Model,
  emit : @cmd.Emit[Msg],
  source : @protocol.SessionExportPayload,
) -> @cmd.Cmd {
  let generation = self.generation
  request(
    emit,
    @commands.session_export,
    source,
    failure=match locale {
      SimplifiedChinese => "下载失败"
      TraditionalChinese => "下載失敗"
      Japanese => "ダウンロードに失敗しました"
      English => "Could not download"
    },
    result => Downloaded(generation~, result),
  )
}

///|
/// Sign in to the selected OpenSeek server using the existing browser flow.
/// Returning to Ready requires another explicit Share click before upload.
fn Model::sign_in(
  locale? : @i18n.Locale = English,
  self : Model,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  let generation = self.generation
  request(
    emit,
    @commands.auth_connect,
    @protocol.NoPayload,
    failure=match locale {
      SimplifiedChinese => "登录失败"
      TraditionalChinese => "登入失敗"
      Japanese => "ログインに失敗しました"
      English => "Could not sign in"
    },
    result => SignedIn(generation~, result.map(_ => ())),
  )
}

///|
/// Abort the waiting sign-in. Its own auth.connect reply settles the dialog
/// that started it (already closed and ignoring that generation), so a
/// failure here has nothing left to report to.
fn cancel_sign_in() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request(
        Local,
        @commands.auth_cancel,
        @protocol.NoPayload,
      ) catch {
        _ => return
      }
    })
    |> ignore
  })
}
