///|
/// Parsed remote workspace path or protocol-shaped URI validation error.
pub(all) enum RemotePathResult {
  ParsedRemotePath(@workspace.SourcePath)
  RemotePathError(@remote_protocol.ProtocolError)
} derive(Debug)

///|
/// Native host file-read result returned to the remote server policy layer.
pub(all) enum ServerHostReadResult {
  ServerHostReadOk(@workspace.DocumentContent)
  ServerHostReadError(@workspace.FileSystemProviderErrorCode, String)
} derive(Debug)

///|
/// One resolved directory level: child stats with provider-minted URIs and
/// `children: None` (unresolved), the `IFileService.resolve` contract.
pub(all) enum ServerHostResolveResult {
  ServerHostResolveOk(Array[@workspace.WorkspaceStat])
  ServerHostResolveError(@workspace.FileSystemProviderErrorCode, String)
} derive(Debug)

///|
/// Disposable watch handle owned by the remote server.
pub struct ServerWatch {
  priv dispose : () -> Unit
}

///|
/// Native-effect boundary for the remote server. Paths are root-relative
/// `SourcePath`s under `workspace_root`; the host owns filesystem and watcher
/// details.
pub(open) trait ServerHost {
  async fn read_directory(Self, String, String) -> ServerHostResolveResult
  async fn read_text_file(Self, String, @workspace.SourcePath) -> ServerHostReadResult
  fn watch_text_file(
    Self,
    String,
    @workspace.SourcePath,
    async (@workspace.FileChangeType) -> Unit,
    (async () -> Unit) -> Unit,
  ) -> ServerWatch
}

///|
/// Reference remote workspace server: protocol policy, document cache, watches,
/// and language-provider routing without direct native effects.
pub struct RemoteServer {
  priv workspace_root : String
  priv host : &ServerHost
  priv hover_provider : &@language.HoverProvider
  priv definition_provider : &@language.DefinitionProvider
  priv references_provider : &@language.ReferencesProvider
  priv document_symbol_provider : &@language.DocumentSymbolProvider
  priv documents : Map[String, @workspace.DocumentSnapshot]
  priv watches : Map[String, ServerWatch]
  priv document_sync_listener : Ref[((@workspace.DocumentSnapshot) -> Unit)?]
}

///|
/// Builds a server watch from a host disposer.
pub fn ServerWatch::ServerWatch(dispose : () -> Unit) -> ServerWatch {
  { dispose, }
}

///|
/// Stops the host watch.
pub fn ServerWatch::dispose(self : ServerWatch) -> Unit {
  (self.dispose)()
}

///|
/// Creates a remote server with explicit semantic feature providers.
pub fn RemoteServer::with_language_providers(
  workspace_root : String,
  host : &ServerHost,
  hover_provider : &@language.HoverProvider,
  definition_provider : &@language.DefinitionProvider,
  references_provider : &@language.ReferencesProvider,
  document_symbol_provider : &@language.DocumentSymbolProvider,
) -> RemoteServer {
  {
    workspace_root: normalize_workspace_root(workspace_root),
    host,
    hover_provider,
    definition_provider,
    references_provider,
    document_symbol_provider,
    documents: Default::default(),
    watches: Default::default(),
    document_sync_listener: Ref(None),
  }
}

///|
/// Creates one connection-scoped server session. Host/provider services and
/// document-sync delivery remain server-scoped, while cached documents and
/// watches are owned exclusively by the new connection.
pub fn RemoteServer::new_session(self : RemoteServer) -> RemoteServer {
  {
    workspace_root: self.workspace_root,
    host: self.host,
    hover_provider: self.hover_provider,
    definition_provider: self.definition_provider,
    references_provider: self.references_provider,
    document_symbol_provider: self.document_symbol_provider,
    documents: Default::default(),
    watches: Default::default(),
    document_sync_listener: self.document_sync_listener,
  }
}

///|
/// Installs a listener notified whenever the server caches a fresh document
/// snapshot (open or watch update). The native host uses it to schedule a
/// `moon check` run without waiting for a feature request, so diagnostics are
/// published as soon as content is known.
pub fn RemoteServer::set_document_sync_listener(
  self : RemoteServer,
  listener : ((@workspace.DocumentSnapshot) -> Unit)?,
) -> Unit {
  self.document_sync_listener.val = listener
}

///|
fn RemoteServer::notify_document_cached(
  self : RemoteServer,
  document : @workspace.DocumentSnapshot,
) -> Unit {
  match self.document_sync_listener.val {
    Some(listener) => listener(document)
    None => ()
  }
}

///|
/// Converts a root-relative source path into the remote workspace URI scheme.
pub fn remote_document_uri(raw_path : String) -> @base_common.Uri? {
  match @workspace.SourcePath::normalize_root_relative_path(raw_path) {
    ParsedSourcePath(path) =>
      Some(
        @base_common.Uri::parse(
          "readonly-remote://workspace/" + path.to_string(),
        ),
      ) catch {
        _ => None
      }
    SourcePathError(_) => None
  }
}

///|
/// Resolves a `readonly-remote://workspace/...` document URI into a safe
/// root-relative source path.
pub fn resolve_remote_document_uri(
  uri : @base_common.Uri,
  request_id? : String = "",
) -> RemotePathResult {
  let raw = uri.to_string()
  let prefix = "readonly-remote://workspace/"
  if !raw.has_prefix(prefix) {
    return RemotePathError(
      ProtocolError(
        ProtocolInvalidUri,
        "Remote URI must use readonly-remote://workspace/.",
        request_id~,
      ),
    )
  }
  match
    @workspace.SourcePath::normalize_root_relative_path(
      raw[prefix.length():].to_owned(),
    ) {
    ParsedSourcePath(path) => ParsedRemotePath(path)
    SourcePathError(error) =>
      RemotePathError(
        ProtocolError(
          ProtocolInvalidUri,
          "Invalid remote workspace path " + error.to_string(),
          request_id~,
        ),
      )
  }
}

///|
/// Parsed remote directory URI. The root uses an empty path and display name
/// `workspace`.
pub(all) enum RemoteDirectoryResult {
  /// Root-relative directory path ("" for the workspace root itself) plus
  /// the directory's display name.
  ParsedRemoteDirectory(String, String)
  RemoteDirectoryError(@remote_protocol.ProtocolError)
} derive(Debug)

///|
/// Resolves a directory URI to its root-relative path. Accepts the bare
/// `readonly-remote://workspace` root, which `resolve_remote_document_uri`
/// rejects because documents always carry a path.
pub fn resolve_remote_directory_uri(
  uri : @base_common.Uri,
  request_id? : String = "",
) -> RemoteDirectoryResult {
  if uri.to_string() == "readonly-remote://workspace" {
    return ParsedRemoteDirectory("", "workspace")
  }
  match resolve_remote_document_uri(uri, request_id~) {
    ParsedRemotePath(path) =>
      ParsedRemoteDirectory(path.to_string(), directory_name(path.to_string()))
    RemotePathError(error) => RemoteDirectoryError(error)
  }
}

///|
fn directory_name(path : String) -> String {
  match path.rev_after("/") {
    Some(name) => name.to_owned()
    None => path
  }
}

///|
/// Dispatches one decoded client packet and returns immediate response packets.
/// Watch callbacks emit later packets through `emit`.
pub async fn RemoteServer::handle_client_packet(
  self : RemoteServer,
  packet : @remote_protocol.ClientPacket,
  emit : async (@remote_protocol.ServerPacket) -> Unit,
  spawn_watch : (async () -> Unit) -> Unit,
) -> Array[@remote_protocol.ServerPacket] {
  match packet {
    ResolveDirectory(request) => [self.resolve_directory(request)]
    OpenDocument(request) => [self.open_document(request)]
    WatchDocument(request) => [self.watch_document(request, emit, spawn_watch)]
    CloseDocument(request) => {
      self.close_document(request)
      []
    }
    Hover(request) => [self.hover(request)]
    Definition(request) => [self.definition(request)]
    References(request) => [self.references(request)]
    DocumentSymbols(request) => [self.document_symbols(request)]
  }
}

///|
/// Resolves one directory level: the stat for the requested URI with its
/// immediate children attached. The workspace root resolves through the
/// bare `readonly-remote://workspace` URI.
pub async fn RemoteServer::resolve_directory(
  self : RemoteServer,
  request : @remote_protocol.DocumentRequest,
) -> @remote_protocol.ServerPacket {
  match resolve_remote_directory_uri(request.uri, request_id=request.id) {
    ParsedRemoteDirectory(relative, name) =>
      match self.host.read_directory(self.workspace_root, relative) {
        ServerHostResolveOk(children) =>
          DirectoryResolved({
            id: request.id,
            stat: {
              uri: request.uri,
              name,
              kind: Directory,
              children: Some(children),
            },
          })
        ServerHostResolveError(code, message) =>
          RemoteError(
            @remote_protocol.ProtocolError::from_file_system_error(
              FileSystemProviderError(code, message, uri=request.uri),
              request_id=request.id,
            ),
          )
      }
    RemoteDirectoryError(error) => RemoteError(error)
  }
}

///|
/// Opens, caches, and returns a remote document.
pub async fn RemoteServer::open_document(
  self : RemoteServer,
  request : @remote_protocol.DocumentRequest,
) -> @remote_protocol.ServerPacket {
  match self.read_remote_document(request.id, request.uri) {
    DocumentLoaded(document) => {
      let document = self.tracked_document(document)
      self.documents.set(request.uri.to_string(), document)
      self.notify_document_cached(document)
      DocumentLoaded({ id: request.id, document })
    }
    DocumentNotFound(uri) =>
      RemoteError(
        @remote_protocol.ProtocolError::from_file_system_error(
          FileSystemProviderError(
            FileNotFound,
            "Source file does not exist.",
            uri~,
          ),
          request_id=request.id,
        ),
      )
    DocumentReadFailed(error) =>
      RemoteError(
        @remote_protocol.ProtocolError::from_file_system_error(
          error.to_file_system_error(),
          request_id=request.id,
        ),
      )
  }
}

///|
/// Starts or replaces a remote document watch, then returns the current document
/// payload as the initial watch value.
pub async fn RemoteServer::watch_document(
  self : RemoteServer,
  request : @remote_protocol.DocumentRequest,
  emit : async (@remote_protocol.ServerPacket) -> Unit,
  spawn_watch : (async () -> Unit) -> Unit,
) -> @remote_protocol.ServerPacket {
  match resolve_remote_document_uri(request.uri, request_id=request.id) {
    ParsedRemotePath(path) => {
      let key = request.uri.to_string()
      match self.watches.get(key) {
        Some(existing) => existing.dispose()
        None => ()
      }
      let watch = self.host.watch_text_file(
        self.workspace_root,
        path,
        change_type => {
          self.handle_watch_event(request.id, request.uri, change_type, emit)
        },
        spawn_watch,
      )
      self.watches.set(key, watch)
      self.open_document(request)
    }
    RemotePathError(error) => RemoteError(error)
  }
}

///|
/// Closes a document and disposes its active watch if present.
pub fn RemoteServer::close_document(
  self : RemoteServer,
  request : @remote_protocol.DocumentRequest,
) -> Unit {
  let key = request.uri.to_string()
  match self.watches.get(key) {
    Some(watch) => {
      watch.dispose()
      self.watches.remove(key)
    }
    None => ()
  }
  self.documents.remove(key)
}

///|
/// Disposes every active document watch.
pub fn RemoteServer::dispose_watches(self : RemoteServer) -> Unit {
  let keys : Array[String] = []
  for key, _watch in self.watches {
    keys.push(key)
  }
  for key in keys {
    match self.watches.get(key) {
      Some(watch) => watch.dispose()
      None => ()
    }
    self.watches.remove(key)
  }
}

///|
/// Routes a hover request only when the cached document URI/revision still
/// matches the request.
pub async fn RemoteServer::hover(
  self : RemoteServer,
  request : @remote_protocol.DocumentPositionRequest,
) -> @remote_protocol.ServerPacket {
  match
    self.cached_document(request.uri, request.document_revision, request.id) {
    Some(document) => {
      let model = text_model_from_document(document)
      HoverResult({
        id: request.id,
        uri: request.uri,
        revision: document.revision,
        hover: self.hover_provider.provide_hover(
          model,
          model.get_position_at(request.offset),
          @language.CancellationToken::none(),
        ),
      })
    }
    None => self.missing_cached_document_error(request.id)
  }
}

///|
/// Routes a definition request only when the cached document URI/revision still
/// matches the request.
pub async fn RemoteServer::definition(
  self : RemoteServer,
  request : @remote_protocol.DocumentPositionRequest,
) -> @remote_protocol.ServerPacket {
  match
    self.cached_document(request.uri, request.document_revision, request.id) {
    Some(document) => {
      let model = text_model_from_document(document)
      DefinitionResult({
        id: request.id,
        uri: request.uri,
        revision: document.revision,
        location: self.definition_provider.provide_definition(
          model,
          model.get_position_at(request.offset),
          @language.CancellationToken::none(),
        ),
      })
    }
    None => self.missing_cached_document_error(request.id)
  }
}

///|
/// Routes a references request and enriches locations with preview line data.
pub async fn RemoteServer::references(
  self : RemoteServer,
  request : @remote_protocol.DocumentPositionRequest,
) -> @remote_protocol.ServerPacket {
  match
    self.cached_document(request.uri, request.document_revision, request.id) {
    Some(document) => {
      let model = text_model_from_document(document)
      let locations = self.references_provider.provide_references(
        model,
        model.get_position_at(request.offset),
        @language.CancellationToken::none(),
      )
      let references = []
      for location in locations {
        references.push(self.enrich_reference(document, location))
      }
      ReferencesResult({
        id: request.id,
        uri: request.uri,
        revision: document.revision,
        references,
      })
    }
    None => self.missing_cached_document_error(request.id)
  }
}

///|
/// Builds a `ReferenceItem` with one-based line/column and the text of the
/// containing line. Same-document references read the cached snapshot;
/// cross-file references read the file through the host and degrade to an
/// empty preview when the file cannot be read.
async fn RemoteServer::enrich_reference(
  self : RemoteServer,
  requested : @workspace.DocumentSnapshot,
  location : @language.Location,
) -> @remote_protocol.ReferenceItem {
  let snapshot = if location.uri.to_string() == requested.uri.to_string() {
    Some(requested)
  } else {
    match resolve_remote_document_uri(location.uri) {
      ParsedRemotePath(path) =>
        match self.host.read_text_file(self.workspace_root, path) {
          ServerHostReadOk(content) =>
            Some(
              @workspace.DocumentSnapshot::from_content(location.uri, content),
            )
          _ => None
        }
      RemotePathError(_) => None
    }
  }
  match snapshot {
    Some(snapshot) =>
      // `location.range` is already 1-based line/column, so the display fields
      // read straight off it; only `line_text` needs a 0-based line index.
      {
        uri: location.uri,
        range: location.range,
        line: location.range.start_line_number,
        column: location.range.start_column,
        line_text: snapshot.line_text(location.range.start_line_number - 1),
      }
    None =>
      {
        uri: location.uri,
        range: location.range,
        line: 0,
        column: 0,
        line_text: "",
      }
  }
}

///|
/// Routes a document-symbol request for the cached document revision.
pub async fn RemoteServer::document_symbols(
  self : RemoteServer,
  request : @remote_protocol.DocumentRevisionRequest,
) -> @remote_protocol.ServerPacket {
  match
    self.cached_document(request.uri, request.document_revision, request.id) {
    Some(document) => {
      let model = text_model_from_document(document)
      DocumentSymbolsResult({
        id: request.id,
        uri: request.uri,
        revision: document.revision,
        symbols: self.document_symbol_provider.provide_document_symbols(
          model,
          @language.CancellationToken::none(),
        ),
      })
    }
    None => self.missing_cached_document_error(request.id)
  }
}

///|
async fn RemoteServer::read_remote_document(
  self : RemoteServer,
  request_id : String,
  uri : @base_common.Uri,
) -> @workspace.DocumentReadResult {
  match resolve_remote_document_uri(uri, request_id~) {
    ParsedRemotePath(path) =>
      match self.host.read_text_file(self.workspace_root, path) {
        ServerHostReadOk(content) =>
          DocumentLoaded(
            @workspace.DocumentSnapshot::from_content(uri, content),
          )
        ServerHostReadError(code, message) =>
          if code == FileNotFound {
            DocumentNotFound(uri)
          } else {
            DocumentReadFailed(DocumentError(code, message, uri~))
          }
      }
    RemotePathError(error) =>
      DocumentReadFailed(DocumentError(InvalidUri, error.message, uri~))
  }
}

///|
async fn RemoteServer::handle_watch_event(
  self : RemoteServer,
  request_id : String,
  uri : @base_common.Uri,
  change_type : @workspace.FileChangeType,
  emit : async (@remote_protocol.ServerPacket) -> Unit,
) -> Unit {
  match change_type {
    Deleted => {
      self.documents.remove(uri.to_string())
      emit(
        RemoteError(
          ProtocolError(
            ProtocolProviderError,
            "Watched source file was deleted.",
            request_id~,
            provider_code="FileNotFound",
          ),
        ),
      )
    }
    _ =>
      match self.read_remote_document(request_id, uri) {
        DocumentLoaded(document) => {
          let document = self.tracked_document(document)
          self.documents.set(uri.to_string(), document)
          self.notify_document_cached(document)
          emit(DocumentChanged({ id: request_id, document }))
        }
        DocumentNotFound(uri) =>
          emit(
            RemoteError(
              @remote_protocol.ProtocolError::from_file_system_error(
                FileSystemProviderError(
                  FileNotFound,
                  "Source file does not exist.",
                  uri~,
                ),
                request_id~,
              ),
            ),
          )
        DocumentReadFailed(error) =>
          emit(
            RemoteError(
              @remote_protocol.ProtocolError::from_file_system_error(
                error.to_file_system_error(),
                request_id~,
              ),
            ),
          )
      }
  }
}

///|
fn RemoteServer::tracked_document(
  self : RemoteServer,
  document : @workspace.DocumentSnapshot,
) -> @workspace.DocumentSnapshot {
  match self.documents.get(document.uri.to_string()) {
    Some(previous) =>
      if previous.revision == document.revision {
        previous
      } else {
        document
      }
    None => document
  }
}

///|
fn RemoteServer::cached_document(
  self : RemoteServer,
  uri : @base_common.Uri,
  expected_revision : String,
  request_id : String,
) -> @workspace.DocumentSnapshot? {
  ignore(request_id)
  match self.documents.get(uri.to_string()) {
    Some(document) =>
      if expected_revision == "" || document.revision == expected_revision {
        Some(document)
      } else {
        None
      }
    None => None
  }
}

///|
fn RemoteServer::missing_cached_document_error(
  _self : RemoteServer,
  request_id : String,
) -> @remote_protocol.ServerPacket {
  RemoteError(
    ProtocolError(
      ProtocolInvalidPacket,
      "No matching loaded document is available for this request.",
      request_id~,
    ),
  )
}

///|
fn normalize_workspace_root(root : String) -> String {
  let normalized = root.replace_all(old="\\", new="/")
  if normalized.has_suffix("/") && normalized.length() > 1 {
    normalized[0:normalized.length() - 1].to_owned()
  } else {
    normalized
  }
}
