///|
/// Extract only losslessly recoverable source bytes from the existing cache.
/// Text is the original UTF-8 source, not the editor's normalized text model.
/// Office previews retain parsed documents, so they must use the raw endpoint.
fn Doc::download_cache(self : Doc) -> (String, Bytes)? {
  let (etag, bytes) = match self.state {
    TabLoaded(content~, sig~) => (sig, @utf8.encode(content))
    TabPdf(document~, sig~) => (sig, document.bytes)
    TabImage(url~, sig~) => {
      guard url.has_prefix("data:") &&
        url.split_once(";base64,") is Some((_, data)) else {
        return None
      }
      let bytes = @base64.decode(data) catch { _ => return None }
      (sig, bytes)
    }
    _ => return None
  }
  guard !etag.is_empty() else { return None }
  Some((etag, bytes))
}

///|
fn accepts_download(
  state : State,
  ctx : Ctx,
  owner : @interop.ConversationIdentity,
  auth_epoch : Int32,
  generation : Int32,
  path : @common.Uri,
) -> Bool {
  ctx.owner == owner &&
  state.owner == Some(owner) &&
  ctx.cloud_files is Some({ epoch: current, .. }) &&
  current == auth_epoch &&
  state.download_generation == generation &&
  state.download == Some(path)
}

///|
fn start_download(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @common.Uri,
  desktop~ : Bool,
) -> (@cmd.Cmd, State) {
  guard ctx.owner is @interop.Cloud(account~, session~) &&
    state.owner == Some(ctx.owner) &&
    ctx.cloud_files is Some(access) &&
    ctx.relative(path) is Some(relative) &&
    state.download is None else {
    return (@cmd.none, state)
  }
  let owner = ctx.owner
  let auth_epoch = access.epoch
  let generation = state.download_generation + 1
  let cached = state.docs.get(path).bind(doc => doc.download_cache())
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result = try {
        if desktop {
          let reply = @interop.bridge_request(
            Local,
            @commands.cloud_file_download,
            {
              account,
              session,
              path: relative.0,
              cached: cached.map(cache => {
                etag: cache.0,
                data_base64: @base64.encode(cache.1),
              }),
            },
          )
          match reply {
            Saved(revealed=true, ..) => ()
            Saved(path=local_path, revealed=false) =>
              raise SourceError(
                "Saved to \{local_path}, but could not show the downloaded file.",
              )
            Failed(message~) => raise SourceError(message)
          }
        } else {
          let bytes = if cached is Some((etag, bytes)) &&
            @cloud.file_unchanged(access.token, session, relative.0, etag) {
            bytes
          } else {
            @cloud_client.download_file(access.token, session, relative.0)
          }
          scheduler.add(
            dispatch(
              FileDownloadReady(owner~, auth_epoch~, generation~, path~, bytes~),
            ),
          )
          return
        }
        Ok(())
      } catch {
        @cloud.RequestError::RequestError(failure) => Err(failure.label())
        SourceError(message) => Err(message)
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(
        dispatch(
          FileDownloaded(owner~, auth_epoch~, generation~, path~, result~),
        ),
      )
    })
    |> ignore
  })
  (command, { ..state, download: Some(path), download_generation: generation, })
}

///|
/// Use the same Blob/anchor handoff as conversation exports. This runs only
/// after the update loop has checked the account that owns the fetched bytes.
pub fn browser_download(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationIdentity,
  auth_epoch : Int32,
  generation : Int32,
  path : @common.Uri,
  bytes : Bytes,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let result = try {
      @js.Error_::wrap(
        () => {
          let blob = @dom.Blob::from_bytes(bytes, "application/octet-stream")
          let urls : @js.Value = @js.globalThis.get_with_string("URL")
          let url : String = urls.apply_with_string("createObjectURL", [
            @js.Value::cast_from(blob),
          ])
          let anchor = @dom.document().create_element("a")
          anchor.set_attribute("href", url)
          anchor.set_attribute("download", basename(path.path))
          let element = anchor.to_html_element().unwrap()
          @base_browser.schedule_timeout(
            () => {
              let _ : Unit = urls.apply_with_string("revokeObjectURL", [
                @js.Value::cast_from(url),
              ])
            },
            1000,
          )
          |> ignore
          element.click()
          @js.Value::cast_from(url)
        },
        map_ok=_ => (),
      )
      Ok(())
    } catch {
      _ => Err("Could not start the browser download.")
    }
    scheduler.add(
      dispatch(FileDownloaded(owner~, auth_epoch~, generation~, path~, result~)),
    )
  })
}

///|
fn download_button(
  locale~ : @i18n.Locale,
  dispatch : @cmd.Emit[Msg],
  state : State,
  path : @common.Uri,
  desktop~ : Bool,
) -> @html.Html {
  let pending = state.download is Some(_)
  let label = ui(
    locale,
    if pending {
      DownloadingFile
    } else {
      DownloadToLocal
    },
  )
  @html.button(
    type_="button",
    class="file-reveal-button",
    title=label,
    disabled=pending,
    on_click=dispatch(DownloadFile(desktop~, path~)),
    attrs=@html.Attrs::build().aria_label(label).aria_busy(pending.to_string()),
    [@icons.icon_arrow_down(), @html.text(label)],
  )
}
