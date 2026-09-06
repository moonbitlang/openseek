///|
/// Workbench-side language client: implements the `@language` provider
/// traits over the live protocol socket through `protocol_request`. The
/// workbench registers it with the viewer's selected language registry at
/// startup.
priv struct RemoteLanguageClient {
  log_service : @log.LogService
  freshness : RemoteLanguageFreshness
}

///|
/// Exact workbench-side identity for one document synchronization. The
/// caller-owned `version` remains part of the boundary record, while
/// `content_version` is the mutable TextModel freshness key.
priv struct RemoteDocumentStamp {
  generation : Int
  model : @model.TextModel
  model_identity : Int
  model_version : Int
  content_version : Int
  uri : String
  revision : String
}

///|
/// Subscriptions retained for the one model generation that may accept remote
/// hover and diagnostic results.
priv struct RemoteDocumentRegistration {
  stamp : RemoteDocumentStamp
  mut content_subscription : @base_common.Disposable?
  mut dispose_subscription : @base_common.Disposable?
}

///|
/// Workbench-owned remote result gate. Only a fresh document sync establishes a
/// generation; content mutation, replacement, or disposal clears owner `moon`
/// markers before retiring it.
priv struct RemoteLanguageFreshness {
  markers : @markers.MarkerService
  mut generation : Int
  mut current : RemoteDocumentRegistration?
}

///|
fn RemoteLanguageFreshness::RemoteLanguageFreshness(
  markers : @markers.MarkerService,
) -> RemoteLanguageFreshness {
  { markers, generation: 0, current: None, }
}

///|
fn RemoteDocumentStamp::matches_model(
  self : RemoteDocumentStamp,
  model : @model.TextModel,
) -> Bool {
  !model.is_disposed() &&
  model.same(self.model) &&
  model.identity() == self.model_identity &&
  model.version == self.model_version &&
  model.get_version_id() == self.content_version &&
  model.uri.to_string() == self.uri &&
  model.revision == self.revision
}

///|
fn RemoteLanguageFreshness::is_current(
  self : RemoteLanguageFreshness,
  stamp : RemoteDocumentStamp,
) -> Bool {
  self.current is Some(registration) &&
  registration.stamp.generation == stamp.generation &&
  registration.stamp.model.same(stamp.model) &&
  registration.stamp.model_identity == stamp.model_identity &&
  registration.stamp.model_version == stamp.model_version &&
  registration.stamp.content_version == stamp.content_version &&
  registration.stamp.uri == stamp.uri &&
  registration.stamp.revision == stamp.revision &&
  stamp.generation == self.generation &&
  stamp.matches_model(registration.stamp.model)
}

///|
fn RemoteLanguageFreshness::capture_model(
  self : RemoteLanguageFreshness,
  model : @model.TextModel,
) -> RemoteDocumentStamp? {
  guard self.current is Some(registration) else { return None }
  guard registration.stamp.matches_model(model) else { return None }
  Some(registration.stamp)
}

///|
fn RemoteLanguageFreshness::invalidate_generation(
  self : RemoteLanguageFreshness,
  generation : Int,
) -> Unit {
  if self.current is Some(registration) &&
    registration.stamp.generation == generation {
    self.invalidate()
  }
}

///|
fn RemoteLanguageFreshness::invalidate(self : RemoteLanguageFreshness) -> Unit {
  self.generation += 1
  guard self.current is Some(registration) else { return }
  self.current = None
  if registration.content_subscription is Some(subscription) {
    subscription.dispose()
  }
  if registration.dispose_subscription is Some(subscription) {
    subscription.dispose()
  }
  self.markers.remove_owner_resource("moon", registration.stamp.model.uri)
}

///|
/// Establishes the sole acceptable result generation before Viewer attachment,
/// so URI-keyed markers cannot seed the replacement model.
fn RemoteLanguageFreshness::note_document(
  self : RemoteLanguageFreshness,
  model : @model.TextModel,
) -> Unit {
  self.invalidate()
  // The incoming URI can retain markers from an older time it was active even
  // when it differs from the outgoing model.
  self.markers.remove_owner_resource("moon", model.uri)
  let stamp : RemoteDocumentStamp = {
    generation: self.generation,
    model,
    model_identity: model.identity(),
    model_version: model.version,
    content_version: model.get_version_id(),
    uri: model.uri.to_string(),
    revision: model.revision,
  }
  let registration : RemoteDocumentRegistration = {
    stamp,
    content_subscription: None,
    dispose_subscription: None,
  }
  self.current = Some(registration)
  registration.content_subscription = Some(
    model.on_did_change_content(_ => {
      self.invalidate_generation(stamp.generation)
    }),
  )
  registration.dispose_subscription = Some(
    model.on_will_dispose(() => self.invalidate_generation(stamp.generation)),
  )
}

///|
fn RemoteLanguageFreshness::prepare_diagnostics(
  self : RemoteLanguageFreshness,
  payload : @remote_protocol.DiagnosticsPayload,
) -> RemoteDocumentStamp? {
  guard self.current is Some(registration) else { return None }
  let stamp = registration.stamp
  guard stamp.uri == payload.uri.to_string() &&
    stamp.revision == payload.revision &&
    self.is_current(stamp) else {
    return None
  }
  Some(stamp)
}

///|
fn RemoteLanguageFreshness::apply_diagnostics(
  self : RemoteLanguageFreshness,
  stamp : RemoteDocumentStamp,
  payload : @remote_protocol.DiagnosticsPayload,
) -> Bool {
  if !self.is_current(stamp) ||
    stamp.uri != payload.uri.to_string() ||
    stamp.revision != payload.revision {
    return false
  }
  self.markers.set_diagnostics("moon", payload.uri, payload.diagnostics)
  true
}

///|
fn RemoteLanguageFreshness::accept_hover(
  self : RemoteLanguageFreshness,
  stamp : RemoteDocumentStamp,
  payload : @remote_protocol.HoverResultPayload,
) -> @language.Hover? {
  if self.is_current(stamp) &&
    payload.uri.to_string() == stamp.uri &&
    payload.revision == stamp.revision {
    payload.hover
  } else {
    None
  }
}

///|
fn register_remote_language_providers(services : WorkbenchServices) -> Unit {
  let client = RemoteLanguageClient::{
    log_service: services.log_service,
    freshness: services.remote_language,
  }
  let selector = @language.LanguageSelector::LanguageFilter(
    LanguageFilter(scheme="readonly-remote"),
  )
  services.languages.register_hover_provider(selector, client) |> ignore
  services.languages.register_definition_provider(selector, client) |> ignore
  services.languages.register_references_provider(selector, client) |> ignore
  services.languages.register_document_symbol_provider(selector, client)
  |> ignore
}

///|
fn RemoteLanguageClient::emit_remote_error(
  self : RemoteLanguageClient,
  operation : String,
  model : @model.TextModel,
  packet : @remote_protocol.ServerPacket,
) -> Unit {
  match packet {
    RemoteError(error) =>
      self.log_service.error(
        "language.protocol",
        "remote protocol provider error",
        details=[
          ("operation", operation),
          ("model", model.uri.to_string()),
          ("revision", model.revision),
          ("code", error.code.label()),
          ("providerCode", error.provider_code),
          ("message", error.message),
          ("requestId", error.request_id),
        ],
      )
    _ => ()
  }
}

///|
impl @language.HoverProvider for RemoteLanguageClient with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  guard self.freshness.capture_model(model) is Some(stamp) else { return None }
  if token.is_cancellation_requested() {
    return None
  }
  let offset = model.get_offset_at(position)
  let response = protocol_request(
    "hover",
    id => {
      Hover({ id, uri: model.uri, document_revision: model.revision, offset, })
    },
    token~,
  )
  if token.is_cancellation_requested() {
    return None
  }
  match response {
    HoverResult(payload) => self.freshness.accept_hover(stamp, payload)
    packet => {
      self.emit_remote_error("hover", model, packet)
      None
    }
  }
}

///|
impl @language.DefinitionProvider for RemoteLanguageClient with fn provide_definition(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  let offset = model.get_offset_at(position)
  let response = protocol_request(
    "definition",
    id => {
      Definition({
        id,
        uri: model.uri,
        document_revision: model.revision,
        offset,
      })
    },
    token~,
  )
  if token.is_cancellation_requested() {
    return []
  }
  match response {
    DefinitionResult(payload) => payload.locations
    packet => {
      self.emit_remote_error("definition", model, packet)
      []
    }
  }
}

///|
impl @language.ReferencesProvider for RemoteLanguageClient with fn provide_references(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  let offset = model.get_offset_at(position)
  let response = protocol_request(
    "references",
    id => {
      References({
        id,
        uri: model.uri,
        document_revision: model.revision,
        offset,
      })
    },
    token~,
  )
  if token.is_cancellation_requested() {
    return []
  }
  match response {
    ReferencesResult(payload) =>
      payload.references.map(item => {
        let location : @language.Location = {
          uri: item.uri,
          range: item.range,
        }
        location
      })
    packet => {
      self.emit_remote_error("references", model, packet)
      []
    }
  }
}

///|
/// Applies a server-pushed diagnostics packet to the marker service — the
/// sink for backend `moon check` pushes, Monaco's `setModelMarkers` path.
/// The marker-change event re-renders the viewer; no pull exists.
fn apply_remote_diagnostics_cmd(
  payload : @remote_protocol.DiagnosticsPayload,
) -> @rabbita.Cmd {
  let freshness = workbench_services().remote_language
  match freshness.prepare_diagnostics(payload) {
    Some(stamp) =>
      @cmd.custom_cmd(_ => freshness.apply_diagnostics(stamp, payload) |> ignore)
    None => @rabbita.none
  }
}

///|
impl @language.DocumentSymbolProvider for RemoteLanguageClient with fn provide_document_symbols(
  self,
  model,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  let response = protocol_request(
    "symbols",
    id => {
      DocumentSymbols({ id, uri: model.uri, document_revision: model.revision, })
    },
    token~,
  )
  if token.is_cancellation_requested() {
    return []
  }
  match response {
    DocumentSymbolsResult(payload) => payload.symbols
    packet => {
      self.emit_remote_error("documentSymbols", model, packet)
      []
    }
  }
}
