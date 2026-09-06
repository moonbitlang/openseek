///|
/// Browser-side document provider used by the workbench host. Opens are
/// correlated request/response through `protocol_request`; watches register a
/// URI-keyed listener that the websocket push branch feeds `DocumentChanged`
/// packets (and watch errors such as `FileNotFound`) into; closes are
/// fire-and-forget. The viewer never sees this provider directly.
priv struct RemoteDocumentProvider {}

///|
let document_provider : &@workspace.DocumentProvider = RemoteDocumentProvider::{
}

///|
/// Active document watches keyed by URI string; the push branch of the
/// protocol message handler routes document packets here.
let watch_listeners : Map[String, (@workspace.DocumentChange) -> Unit] = Map([])

///|
/// Watch request ids back to their URI, so `RemoteError` pushes (which
/// carry only a request id) can reach the watched document's listener.
let watch_request_uris : Map[String, String] = Map([])

///|
/// The active source lifecycle belongs to the workbench, not the viewer.
let active_document_uri : Ref[@base_common.Uri?] = Ref(None)

///|
let active_document_generation : Ref[Int] = Ref(0)

///|
let active_document_watch : Ref[@base_common.Disposable?] = Ref(None)

///|
impl @workspace.DocumentProvider for RemoteDocumentProvider with fn read(
  _self,
  uri,
) {
  read_remote_document(uri)
}

///|
/// Token-aware form used by Peek model resolution. The public workspace
/// provider contract remains token-free because the active-document source has
/// its own URI/generation freshness guard.
async fn read_remote_document(
  uri : @base_common.Uri,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @workspace.DocumentReadResult {
  let response = protocol_request(
    "open",
    id => OpenDocument({ id, uri, }),
    token~,
  )
  match response {
    DocumentLoaded(payload) => DocumentLoaded(payload.document)
    RemoteError(error) =>
      DocumentReadFailed(
        DocumentError(
          @workspace.FileSystemProviderErrorCode::from_string(
            error.provider_code,
          ),
          error.message,
          uri~,
        ),
      )
    _ =>
      DocumentReadFailed(
        DocumentError(
          Unavailable,
          "Unexpected protocol response for document open.",
          uri~,
        ),
      )
  }
}

///|
impl @workspace.DocumentProvider for RemoteDocumentProvider with fn watch(
  _self,
  uri,
  listener,
) {
  let key = uri.to_string()
  let id = next_request_id("watch")
  watch_listeners[key] = listener
  watch_request_uris[id] = key
  send_protocol_packet(WatchDocument({ id, uri, }))
  @base_common.Disposable::from(() => {
    watch_listeners.remove(key)
    watch_request_uris.remove(id)
  })
}

///|
impl @workspace.DocumentProvider for RemoteDocumentProvider with fn close(
  _self,
  uri,
) {
  send_protocol_packet(CloseDocument({ id: next_request_id("close"), uri, }))
}

///|
fn open_active_document_cmd(
  uri : @base_common.Uri,
  view_state : DocumentViewState,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    active_document_generation.val += 1
    let generation = active_document_generation.val
    close_active_document_source()
    active_document_uri.val = Some(uri)
    active_document_watch.val = Some(
      document_provider.watch(uri, change => {
        if is_active_document(uri, generation) {
          dispatch_workbench_msg(ActiveDocumentChanged(change))
        }
      }),
    )
    read_active_document(uri, generation, view_state)
  })
}

///|
fn reload_active_document_cmd(
  uri : @base_common.Uri,
  view_state : DocumentViewState,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    let generation = active_document_generation.val
    if is_active_document(uri, generation) {
      read_active_document(uri, generation, view_state)
    }
  })
}

///|
fn close_active_document_source() -> Unit {
  if active_document_watch.val is Some(watch) {
    watch.dispose()
  }
  active_document_watch.val = None
  if active_document_uri.val is Some(uri) &&
    !preview_resource_retains_remote_document(uri) {
    document_provider.close(uri)
  }
  active_document_uri.val = None
}

///|
fn is_active_document_resource(uri : @base_common.Uri) -> Bool {
  active_document_uri.val is Some(current) &&
  current.to_string() == uri.to_string()
}

///|
fn read_active_document(
  uri : @base_common.Uri,
  generation : Int,
  view_state : DocumentViewState,
) -> Unit {
  @js.async_run(() => {
    let result = document_provider.read(uri) catch {
      _ =>
        DocumentReadFailed(
          DocumentError(Unavailable, "Document open failed.", uri~),
        )
    }
    if is_active_document(uri, generation) {
      dispatch_workbench_msg(ActiveDocumentRead(result, view_state))
    }
  })
}

///|
fn is_active_document(uri : @base_common.Uri, generation : Int) -> Bool {
  generation == active_document_generation.val &&
  is_active_document_resource(uri)
}

///|
/// Routes an uncorrelated document push (the watch's initial load and
/// every later change) into the watcher of its URI. Pushes for URIs
/// nobody watches are dropped.
fn route_watched_document_cmd(
  payload : @remote_protocol.DocumentPayload,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    if watch_listeners.get(payload.document.uri.to_string()) is Some(listener) {
      listener(DocumentUpdated(payload.document))
    }
  })
}

///|
/// The watched URI a pushed `RemoteError` belongs to, if its request id
/// was minted by `watch_document`.
fn watched_uri_for_error(error : @remote_protocol.ProtocolError) -> String? {
  watch_request_uris.get(error.request_id)
}

///|
fn route_watched_error_cmd(
  uri_key : String,
  error : @remote_protocol.ProtocolError,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    match watch_listeners.get(uri_key) {
      Some(listener) => {
        let uri = Some(@base_common.Uri::parse(uri_key)) catch { _ => None }
        let document_uri = match uri {
          Some(uri) => uri
          None =>
            try! @base_common.Uri::from(
              scheme=@base_common.schemas_in_memory,
              authority="model",
              path="/\{uri_key}",
            )
        }
        let document_error = match uri {
          Some(uri) =>
            @workspace.DocumentError(
              @workspace.FileSystemProviderErrorCode::from_string(
                error.provider_code,
              ),
              error.message,
              uri~,
            )
          None =>
            DocumentError(
              @workspace.FileSystemProviderErrorCode::from_string(
                error.provider_code,
              ),
              error.message,
            )
        }
        listener(DocumentChangeFailed(uri=document_uri, error=document_error))
      }
      None => ()
    }
  })
}
