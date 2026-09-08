///|
/// Current client/server protocol version. Both sides reject packets carrying a
/// different version.
fn protocol_version_impl() -> Int {
  6
}

///|
/// Structured error categories used on the wire.
pub(all) enum ProtocolErrorCode {
  ProtocolInvalidJson
  ProtocolUnsupportedVersion
  ProtocolUnknownPacket
  ProtocolInvalidPacket
  ProtocolInvalidUri
  ProtocolProviderError
} derive(Eq, Debug)

///|
/// Debug label that keeps the local enum prefix visible.
pub fn ProtocolErrorCode::label(self : ProtocolErrorCode) -> String {
  match self {
    ProtocolInvalidJson => "ProtocolInvalidJson"
    ProtocolUnsupportedVersion => "ProtocolUnsupportedVersion"
    ProtocolUnknownPacket => "ProtocolUnknownPacket"
    ProtocolInvalidPacket => "ProtocolInvalidPacket"
    ProtocolInvalidUri => "ProtocolInvalidUri"
    ProtocolProviderError => "ProtocolProviderError"
  }
}

///|
/// Remote protocol error packet payload. `request_id` correlates failures to a
/// request; `provider_code` preserves lower-level filesystem/provider
/// categories.
pub struct ProtocolError {
  code : ProtocolErrorCode
  message : String
  request_id : String
  provider_code : String
} derive(Debug)

///|
/// Request addressed only by document URI.
pub(all) struct DocumentRequest {
  id : String
  uri : @base_common.Uri
} derive(Debug)

///|
/// Request addressed by URI, expected document revision, and UTF-16 offset.
/// Servers use the revision to drop stale feature requests.
pub(all) struct DocumentPositionRequest {
  id : String
  uri : @base_common.Uri
  document_revision : String
  offset : Int
} derive(Debug)

///|
/// Request addressed by URI and expected document revision, for whole-document
/// feature refreshes.
pub(all) struct DocumentRevisionRequest {
  id : String
  uri : @base_common.Uri
  document_revision : String
} derive(Debug)

///|
/// Browser-to-server request packet variants.
pub(all) enum ClientPacket {
  ResolveDirectory(DocumentRequest)
  OpenDocument(DocumentRequest)
  WatchDocument(DocumentRequest)
  CloseDocument(DocumentRequest)
  Hover(DocumentPositionRequest)
  Definition(DocumentPositionRequest)
  References(DocumentPositionRequest)
  DocumentSymbols(DocumentRevisionRequest)
  ListHostDirectory(HostPathRequest)
  SwitchWorkspace(HostPathRequest)
} derive(Debug)

///|
/// Loaded or changed document payload from the remote server.
pub(all) struct DocumentPayload {
  id : String
  document : @workspace.DocumentSnapshot
} derive(Debug)

///|
/// One stat for the requested directory URI with exactly one level of
/// `children` resolved; nested directories arrive with `children: None`.
pub(all) struct DirectoryResolvedPayload {
  id : String
  stat : @workspace.WorkspaceStat
} derive(Debug)

///|
/// Server-initiated diagnostics push for a URI at a document revision. The
/// backend publishes these from `moon check` runs, so the packet carries no
/// request id.
pub(all) struct DiagnosticsPayload {
  uri : @base_common.Uri
  revision : String
  diagnostics : Array[@language.Diagnostic]
} derive(Debug)

///|
/// Hover response for a specific URI, document revision, and request id.
pub(all) struct HoverResultPayload {
  id : String
  uri : @base_common.Uri
  revision : String
  hover : @language.Hover?
} derive(Debug)

///|
/// Definition response for a specific URI, document revision, and request id.
pub(all) struct DefinitionResultPayload {
  id : String
  uri : @base_common.Uri
  revision : String
  locations : Array[@language.Location]
} derive(Debug)

///|
/// A reference location enriched by the server with one-based line/column
/// and the text of the containing line, so clients can list cross-file
/// references without fetching file contents.
pub(all) struct ReferenceItem {
  uri : @base_common.Uri
  range : @base_common.Range
  line : Int
  column : Int
  line_text : String
} derive(Debug)

///|
/// References response for a specific URI and document revision.
pub(all) struct ReferencesResultPayload {
  id : String
  uri : @base_common.Uri
  revision : String
  references : Array[ReferenceItem]
} derive(Debug)

///|
/// Document symbols response for a specific URI and document revision.
pub(all) struct DocumentSymbolsResultPayload {
  id : String
  uri : @base_common.Uri
  revision : String
  symbols : Array[@language.DocumentSymbol]
} derive(Debug)

///|
/// Server-to-browser response, event, and error packet variants.
pub(all) enum ServerPacket {
  DirectoryResolved(DirectoryResolvedPayload)
  DocumentLoaded(DocumentPayload)
  DocumentChanged(DocumentPayload)
  Diagnostics(DiagnosticsPayload)
  HoverResult(HoverResultPayload)
  DefinitionResult(DefinitionResultPayload)
  ReferencesResult(ReferencesResultPayload)
  DocumentSymbolsResult(DocumentSymbolsResultPayload)
  HostDirectoryListed(HostDirectoryListedPayload)
  WorkspaceSwitched(WorkspaceSwitchedPayload)
  RemoteError(ProtocolError)
} derive(Debug)

///|
/// Client-packet decode result that preserves structured protocol errors.
pub enum ClientPacketDecodeResult {
  DecodedClientPacket(ClientPacket)
  ClientPacketDecodeError(ProtocolError)
} derive(Debug)

///|
/// Server-packet decode result that preserves structured protocol errors.
pub enum ServerPacketDecodeResult {
  DecodedServerPacket(ServerPacket)
  ServerPacketDecodeError(ProtocolError)
} derive(Debug)

///|
/// Version-negotiation result used before opening a long-lived connection.
pub enum ProtocolNegotiation {
  ProtocolAccepted(Int)
  ProtocolRejected(ProtocolError)
} derive(Debug)

///|
/// Builds a protocol error, defaulting an empty message to the wire code.
pub fn ProtocolError::ProtocolError(
  code : ProtocolErrorCode,
  message : String,
  request_id? : String = "",
  provider_code? : String = "",
) -> ProtocolError {
  let message = if message == "" { code.to_string() } else { message }
  { code, message, request_id, provider_code, }
}

///|
/// Converts a filesystem-provider failure into a protocol error without losing
/// the provider error code.
pub fn ProtocolError::from_file_system_error(
  error : @workspace.FileSystemProviderError,
  request_id? : String = "",
) -> ProtocolError {
  ProtocolError(
    ProtocolProviderError,
    error.message,
    request_id~,
    provider_code=error.code.to_string(),
  )
}

///|
/// Stable compact code used in JSON payloads.
pub fn ProtocolErrorCode::to_string(self : ProtocolErrorCode) -> String {
  match self {
    ProtocolInvalidJson => "InvalidJson"
    ProtocolUnsupportedVersion => "UnsupportedVersion"
    ProtocolUnknownPacket => "UnknownPacket"
    ProtocolInvalidPacket => "InvalidPacket"
    ProtocolInvalidUri => "InvalidUri"
    ProtocolProviderError => "ProviderError"
  }
}

///|
/// Decodes a wire error code, failing closed to `InvalidPacket` for unknown
/// values.
pub fn ProtocolErrorCode::from_string(code : String) -> ProtocolErrorCode {
  match code {
    "InvalidJson" => ProtocolInvalidJson
    "UnsupportedVersion" => ProtocolUnsupportedVersion
    "UnknownPacket" => ProtocolUnknownPacket
    "InvalidPacket" => ProtocolInvalidPacket
    "InvalidUri" => ProtocolInvalidUri
    "ProviderError" => ProtocolProviderError
    _ => ProtocolInvalidPacket
  }
}

///|
/// Accepts only the exact current protocol version.
fn negotiate_protocol_version_impl(version : Int) -> ProtocolNegotiation {
  if version == protocol_version() {
    ProtocolAccepted(version)
  } else {
    ProtocolRejected(
      ProtocolError(
        ProtocolUnsupportedVersion,
        "Unsupported remote protocol version \{version.to_string()}",
      ),
    )
  }
}

///|
/// Serializes client requests to the MoonBit-owned remote protocol JSON shape.
pub impl ToJson for ClientPacket with fn to_json(self) {
  match self {
    ResolveDirectory(request) =>
      document_request_json("ResolveDirectory", request)
    OpenDocument(request) => document_request_json("OpenDocument", request)
    WatchDocument(request) => document_request_json("WatchDocument", request)
    CloseDocument(request) => document_request_json("CloseDocument", request)
    Hover(request) => position_request_json("Hover", request)
    Definition(request) => position_request_json("Definition", request)
    References(request) => position_request_json("References", request)
    DocumentSymbols(request) =>
      revision_request_json("DocumentSymbols", request)
    ListHostDirectory(request) =>
      host_path_request_json("ListHostDirectory", request)
    SwitchWorkspace(request) =>
      host_path_request_json("SwitchWorkspace", request)
  }
}

///|
/// Serializes server responses and events to the remote protocol JSON shape.
pub impl ToJson for ServerPacket with fn to_json(self) {
  match self {
    DirectoryResolved(payload) => directory_resolved_json(payload)
    DocumentLoaded(payload) => document_payload_json("DocumentLoaded", payload)
    DocumentChanged(payload) =>
      document_payload_json("DocumentChanged", payload)
    Diagnostics(payload) => diagnostics_payload_json(payload)
    HoverResult(payload) => hover_result_json(payload)
    DefinitionResult(payload) => definition_result_json(payload)
    ReferencesResult(payload) => references_result_json(payload)
    DocumentSymbolsResult(payload) => document_symbols_result_json(payload)
    HostDirectoryListed(payload) => host_directory_listed_json(payload)
    WorkspaceSwitched(payload) => workspace_switched_json(payload)
    RemoteError(error) => error_packet_json(error)
  }
}

///|
/// Decodes and validates a client packet, returning structured errors instead
/// of raising on malformed JSON or packet shape.
pub fn decode_client_packet(raw : String) -> ClientPacketDecodeResult {
  match parse_packet_object(raw) {
    Some(packet) =>
      match validate_packet_version(packet) {
        Some(error) => ClientPacketDecodeError(error)
        None =>
          match json_string_field(packet, "type") {
            Some("ResolveDirectory") =>
              decode_document_client(packet, request_id(packet), request => {
                ResolveDirectory(request)
              })
            Some("OpenDocument") =>
              decode_document_client(packet, request_id(packet), request => {
                OpenDocument(request)
              })
            Some("WatchDocument") =>
              decode_document_client(packet, request_id(packet), request => {
                WatchDocument(request)
              })
            Some("CloseDocument") =>
              decode_document_client(packet, request_id(packet), request => {
                CloseDocument(request)
              })
            Some("Hover") =>
              decode_position_client(packet, request_id(packet), request => {
                Hover(request)
              })
            Some("Definition") =>
              decode_position_client(packet, request_id(packet), request => {
                Definition(request)
              })
            Some("References") =>
              decode_position_client(packet, request_id(packet), request => {
                References(request)
              })
            Some("DocumentSymbols") =>
              decode_version_client(packet, request_id(packet), request => {
                DocumentSymbols(request)
              })
            Some("ListHostDirectory") =>
              decode_host_path_client(packet, request_id(packet), request => {
                ListHostDirectory(request)
              })
            Some("SwitchWorkspace") =>
              decode_host_path_client(packet, request_id(packet), request => {
                SwitchWorkspace(request)
              })
            Some(kind) =>
              ClientPacketDecodeError(
                ProtocolError(
                  ProtocolUnknownPacket,
                  "Unknown client packet type \{kind}",
                  request_id=request_id(packet),
                ),
              )
            None =>
              ClientPacketDecodeError(
                ProtocolError(
                  ProtocolInvalidPacket,
                  "Remote protocol packet is missing a type.",
                  request_id=request_id(packet),
                ),
              )
          }
      }
    None =>
      ClientPacketDecodeError(
        ProtocolError(ProtocolInvalidJson, "Invalid remote protocol JSON."),
      )
  }
}

///|
/// Decodes and validates a server packet, returning structured errors instead
/// of raising on malformed JSON or packet shape.
pub fn decode_server_packet(raw : String) -> ServerPacketDecodeResult {
  match parse_packet_object(raw) {
    Some(packet) =>
      match validate_packet_version(packet) {
        Some(error) => ServerPacketDecodeError(error)
        None =>
          match json_string_field(packet, "type") {
            Some("DirectoryResolved") =>
              decode_directory_resolved_payload(packet, request_id(packet))
            Some("DocumentLoaded") =>
              decode_document_server(packet, request_id(packet), payload => {
                DocumentLoaded(payload)
              })
            Some("DocumentChanged") =>
              decode_document_server(packet, request_id(packet), payload => {
                DocumentChanged(payload)
              })
            Some("Diagnostics") => decode_diagnostics_payload(packet)
            Some("HoverResult") =>
              decode_hover_result_payload(packet, request_id(packet))
            Some("DefinitionResult") =>
              decode_definition_result_payload(packet, request_id(packet))
            Some("ReferencesResult") =>
              decode_references_result_payload(packet, request_id(packet))
            Some("DocumentSymbolsResult") =>
              decode_document_symbols_result_payload(packet, request_id(packet))
            Some("HostDirectoryListed") =>
              decode_host_directory_listed_payload(packet, request_id(packet))
            Some("WorkspaceSwitched") =>
              decode_workspace_switched_payload(packet, request_id(packet))
            Some("Error") => decode_error_payload(packet, request_id(packet))
            Some(kind) =>
              ServerPacketDecodeError(
                ProtocolError(
                  ProtocolUnknownPacket,
                  "Unknown server packet type \{kind}",
                  request_id=request_id(packet),
                ),
              )
            None =>
              ServerPacketDecodeError(
                ProtocolError(
                  ProtocolInvalidPacket,
                  "Remote protocol packet is missing a type.",
                  request_id=request_id(packet),
                ),
              )
          }
      }
    None =>
      ServerPacketDecodeError(
        ProtocolError(ProtocolInvalidJson, "Invalid remote protocol JSON."),
      )
  }
}

///|
fn decode_document_client(
  packet : Json,
  id : String,
  build : (DocumentRequest) -> ClientPacket,
) -> ClientPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) => DecodedClientPacket(build({ id, uri, }))
    ProtocolUriError(error) => ClientPacketDecodeError(error)
  }
}

///|
fn decode_position_client(
  packet : Json,
  id : String,
  build : (DocumentPositionRequest) -> ClientPacket,
) -> ClientPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedClientPacket(
        build({
          id,
          uri,
          document_revision: json_string_field(packet, "documentRevision").unwrap_or(
            "",
          ),
          offset: json_int_field(packet, "offset").unwrap_or(0),
        }),
      )
    ProtocolUriError(error) => ClientPacketDecodeError(error)
  }
}

///|
fn decode_version_client(
  packet : Json,
  id : String,
  build : (DocumentRevisionRequest) -> ClientPacket,
) -> ClientPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedClientPacket(
        build({
          id,
          uri,
          document_revision: json_string_field(packet, "documentRevision").unwrap_or(
            "",
          ),
        }),
      )
    ProtocolUriError(error) => ClientPacketDecodeError(error)
  }
}

///|
fn decode_document_server(
  packet : Json,
  id : String,
  build : (DocumentPayload) -> ServerPacket,
) -> ServerPacketDecodeResult {
  match json_field(packet, "document") {
    Some(document_json) =>
      match parse_source_document(document_json, id) {
        ParsedProtocolDocument(document) =>
          DecodedServerPacket(build({ id, document, }))
        ProtocolDocumentError(error) => ServerPacketDecodeError(error)
      }
    None =>
      ServerPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Document packet is missing a document.",
          request_id=id,
        ),
      )
  }
}

///|
fn decode_directory_resolved_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match json_field(packet, "stat") {
    Some(stat_json) =>
      match parse_workspace_stat(stat_json) {
        Some(stat) => DecodedServerPacket(DirectoryResolved({ id, stat, }))
        None =>
          ServerPacketDecodeError(
            ProtocolError(
              ProtocolInvalidPacket,
              "Directory resolved packet carries an invalid stat.",
              request_id=id,
            ),
          )
      }
    None =>
      ServerPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Directory resolved packet is missing a stat.",
          request_id=id,
        ),
      )
  }
}

///|
fn decode_diagnostics_payload(packet : Json) -> ServerPacketDecodeResult {
  match parse_uri_field(packet, "uri", "") {
    ParsedProtocolUri(uri) =>
      DecodedServerPacket(
        Diagnostics({
          uri,
          revision: json_string_field(packet, "documentRevision").unwrap_or(""),
          diagnostics: json_array_field(packet, "diagnostics", parse_diagnostic),
        }),
      )
    ProtocolUriError(error) => ServerPacketDecodeError(error)
  }
}

///|
fn decode_hover_result_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedServerPacket(
        HoverResult({
          id,
          uri,
          revision: json_string_field(packet, "documentRevision").unwrap_or(""),
          hover: json_field(packet, "hover").bind(parse_hover),
        }),
      )
    ProtocolUriError(error) => ServerPacketDecodeError(error)
  }
}

///|
fn decode_definition_result_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedServerPacket(
        DefinitionResult({
          id,
          uri,
          revision: json_string_field(packet, "documentRevision").unwrap_or(""),
          locations: json_array_field(packet, "locations", parse_location),
        }),
      )
    ProtocolUriError(error) => ServerPacketDecodeError(error)
  }
}

///|
fn decode_references_result_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedServerPacket(
        ReferencesResult({
          id,
          uri,
          revision: json_string_field(packet, "documentRevision").unwrap_or(""),
          references: json_array_field(
            packet, "references", parse_reference_item,
          ),
        }),
      )
    ProtocolUriError(error) => ServerPacketDecodeError(error)
  }
}

///|
fn decode_document_symbols_result_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match parse_uri_field(packet, "uri", id) {
    ParsedProtocolUri(uri) =>
      DecodedServerPacket(
        DocumentSymbolsResult({
          id,
          uri,
          revision: json_string_field(packet, "documentRevision").unwrap_or(""),
          symbols: json_array_field(packet, "symbols", parse_document_symbol),
        }),
      )
    ProtocolUriError(error) => ServerPacketDecodeError(error)
  }
}

///|
fn decode_error_payload(packet : Json, id : String) -> ServerPacketDecodeResult {
  match json_field(packet, "error") {
    Some(error) =>
      DecodedServerPacket(
        RemoteError(
          ProtocolError(
            ProtocolErrorCode::from_string(
              json_string_field(error, "code").unwrap_or("InvalidPacket"),
            ),
            json_string_field(error, "message").unwrap_or("Remote error."),
            request_id=json_string_field(error, "requestId").unwrap_or(id),
            provider_code=json_string_field(error, "providerCode").unwrap_or(""),
          ),
        ),
      )
    None =>
      ServerPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Error packet is missing an error object.",
          request_id=id,
        ),
      )
  }
}

///|
fn parse_packet_object(raw : String) -> Json? {
  match parse_json(raw) {
    Some(Object(_)) as parsed => parsed
    _ => None
  }
}

///|
fn validate_packet_version(packet : Json) -> ProtocolError? {
  let version = json_int_field(packet, "version").unwrap_or(0)
  if version == protocol_version() {
    None
  } else {
    Some(
      ProtocolError(
        ProtocolUnsupportedVersion,
        "Unsupported remote protocol version \{version.to_string()}",
        request_id=request_id(packet),
      ),
    )
  }
}

///|
fn request_id(packet : Json) -> String {
  json_string_field(packet, "id").unwrap_or("")
}

///|
priv enum ProtocolUriResult {
  ParsedProtocolUri(@base_common.Uri)
  ProtocolUriError(ProtocolError)
}

///|
/// `Uri::parse` raises `UriError` (D6); the protocol keeps its own error
/// mapping, so decode failures collapse to `None` here. Strict mode keeps
/// the old contract of rejecting scheme-less strings — the protocol only
/// ever transports `to_string()` output, which always carries a scheme.
fn try_parse_uri(raw : String) -> @base_common.Uri? {
  Some(@base_common.Uri::parse(raw, strict=true)) catch {
    _ => None
  }
}

///|
fn parse_uri_field(
  packet : Json,
  key : String,
  id : String,
) -> ProtocolUriResult {
  match json_string_field(packet, key) {
    Some(raw) =>
      match try_parse_uri(raw) {
        Some(uri) => ParsedProtocolUri(uri)
        None =>
          ProtocolUriError(
            ProtocolError(
              ProtocolInvalidUri,
              "Invalid document URI \{raw}",
              request_id=id,
            ),
          )
      }
    None =>
      ProtocolUriError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Remote protocol packet is missing \{key}.",
          request_id=id,
        ),
      )
  }
}

///|
priv enum ProtocolDocumentResult {
  ParsedProtocolDocument(@workspace.DocumentSnapshot)
  ProtocolDocumentError(ProtocolError)
}

///|
fn parse_source_document(value : Json, id : String) -> ProtocolDocumentResult {
  match value {
    Object(_) =>
      match json_string_field(value, "uri") {
        Some(raw_uri) =>
          match try_parse_uri(raw_uri) {
            Some(uri) =>
              ParsedProtocolDocument(
                DocumentSnapshot(
                  uri,
                  json_string_field(value, "displayName").unwrap_or(""),
                  json_string_field(value, "languageId").unwrap_or(""),
                  json_string_field(value, "revision").unwrap_or(""),
                  json_string_field(value, "text").unwrap_or(""),
                ),
              )
            None =>
              ProtocolDocumentError(
                ProtocolError(
                  ProtocolInvalidUri,
                  "Invalid document URI \{raw_uri}",
                  request_id=id,
                ),
              )
          }
        None =>
          ProtocolDocumentError(
            ProtocolError(
              ProtocolInvalidPacket,
              "Source document is missing uri.",
              request_id=id,
            ),
          )
      }
    _ =>
      ProtocolDocumentError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Document payload must be an object.",
          request_id=id,
        ),
      )
  }
}

///|
fn document_request_json(kind : String, request : DocumentRequest) -> Json {
  let fields = packet_fields(kind, request.id)
  fields["uri"] = request.uri.to_string().to_json()
  Json(fields)
}

///|
fn position_request_json(
  kind : String,
  request : DocumentPositionRequest,
) -> Json {
  let fields = packet_fields(kind, request.id)
  fields["uri"] = request.uri.to_string().to_json()
  fields["documentRevision"] = request.document_revision.to_json()
  fields["offset"] = request.offset.to_json()
  Json(fields)
}

///|
fn revision_request_json(
  kind : String,
  request : DocumentRevisionRequest,
) -> Json {
  let fields = packet_fields(kind, request.id)
  fields["uri"] = request.uri.to_string().to_json()
  fields["documentRevision"] = request.document_revision.to_json()
  Json(fields)
}

///|
fn document_payload_json(kind : String, payload : DocumentPayload) -> Json {
  let fields = packet_fields(kind, payload.id)
  fields["document"] = payload.document.to_json()
  Json(fields)
}

///|
fn directory_resolved_json(payload : DirectoryResolvedPayload) -> Json {
  let fields = packet_fields("DirectoryResolved", payload.id)
  fields["stat"] = workspace_stat_json(payload.stat)
  Json(fields)
}

///|
/// Kind crosses the wire as a string; unresolved `children` is omitted so
/// the decoder can tell "not resolved" (`None`) from "empty" (`[]`).
fn workspace_stat_json(stat : @workspace.WorkspaceStat) -> Json {
  let fields : Map[String, Json] = {
    "uri": stat.uri.to_string().to_json(),
    "name": stat.name.to_json(),
    "kind": stat.kind.to_string().to_json(),
  }
  if stat.children is Some(children) {
    fields["children"] = Json(children.map(workspace_stat_json))
  }
  Json(fields)
}

///|
fn parse_workspace_stat(value : Json) -> @workspace.WorkspaceStat? {
  guard value is Object(_) else { return None }
  guard json_string_field(value, "uri") is Some(raw_uri) else { return None }
  guard try_parse_uri(raw_uri) is Some(uri) else { return None }
  guard json_string_field(value, "kind") is Some(raw_kind) else { return None }
  guard @workspace.WorkspaceEntryKind::from_string(raw_kind) is Some(kind) else {
    return None
  }
  let children = match json_field(value, "children") {
    Some(Array(items)) => Some(items.filter_map(parse_workspace_stat))
    _ => None
  }
  Some({
    uri,
    name: json_string_field(value, "name").unwrap_or(
      @base_common.basename_or_authority(uri),
    ),
    kind,
    children,
  })
}

///|
fn diagnostics_payload_json(payload : DiagnosticsPayload) -> Json {
  let fields = packet_fields("Diagnostics", "")
  fields["uri"] = payload.uri.to_string().to_json()
  fields["documentRevision"] = payload.revision.to_json()
  fields["diagnostics"] = Json(payload.diagnostics.map(diagnostic_json))
  Json(fields)
}

///|
fn hover_result_json(payload : HoverResultPayload) -> Json {
  let fields = packet_fields("HoverResult", payload.id)
  fields["uri"] = payload.uri.to_string().to_json()
  fields["documentRevision"] = payload.revision.to_json()
  fields["hover"] = match payload.hover {
    Some(hover) => hover_json(hover)
    None => Json::null()
  }
  Json(fields)
}

///|
fn definition_result_json(payload : DefinitionResultPayload) -> Json {
  let fields = packet_fields("DefinitionResult", payload.id)
  fields["uri"] = payload.uri.to_string().to_json()
  fields["documentRevision"] = payload.revision.to_json()
  fields["locations"] = Json(payload.locations.map(location_json))
  Json(fields)
}

///|
fn references_result_json(payload : ReferencesResultPayload) -> Json {
  let fields = packet_fields("ReferencesResult", payload.id)
  fields["uri"] = payload.uri.to_string().to_json()
  fields["documentRevision"] = payload.revision.to_json()
  fields["references"] = Json(payload.references.map(reference_item_json))
  Json(fields)
}

///|
fn reference_item_json(item : ReferenceItem) -> Json {
  {
    "uri": item.uri.to_string().to_json(),
    "range": range_json(item.range),
    "line": item.line.to_json(),
    "column": item.column.to_json(),
    "lineText": item.line_text.to_json(),
  }
}

///|
fn document_symbols_result_json(payload : DocumentSymbolsResultPayload) -> Json {
  let fields = packet_fields("DocumentSymbolsResult", payload.id)
  fields["uri"] = payload.uri.to_string().to_json()
  fields["documentRevision"] = payload.revision.to_json()
  fields["symbols"] = Json(payload.symbols.map(document_symbol_json))
  Json(fields)
}

///|
fn error_packet_json(error : ProtocolError) -> Json {
  let fields = packet_fields("Error", error.request_id)
  fields["error"] = ToJson::to_json(error)
  Json(fields)
}

///|
/// JSON error payload used inside `RemoteError` server packets.
pub impl ToJson for ProtocolError with fn to_json(self) {
  let fields : Map[String, Json] = {
    "code": self.code.to_string().to_json(),
    "message": self.message.to_json(),
    "requestId": self.request_id.to_json(),
  }
  if self.provider_code != "" {
    fields["providerCode"] = self.provider_code.to_json()
  }
  Json(fields)
}

///|
fn packet_fields(kind : String, id : String) -> Map[String, Json] {
  let fields : Map[String, Json] = {
    "version": protocol_version().to_json(),
    "type": kind.to_json(),
  }
  if id != "" {
    fields["id"] = id.to_json()
  }
  fields
}

///|
fn diagnostic_json(diagnostic : @language.Diagnostic) -> Json {
  let fields : Map[String, Json] = {
    "range": range_json(diagnostic.range),
    "severity": diagnostic.severity.label().to_json(),
    "message": diagnostic.message.to_json(),
  }
  if diagnostic.tags is Some(tags) {
    fields["tags"] = Json(tags.map(tag => tag.label().to_json()))
  }
  Json(fields)
}

///|
fn document_symbol_json(symbol : @language.DocumentSymbol) -> Json {
  {
    "name": symbol.name.to_json(),
    "kind": symbol.kind.to_json(),
    "range": range_json(symbol.range),
  }
}

///|
fn hover_json(hover : @language.Hover) -> Json {
  {
    "range": range_json(hover.range),
    "contents": Json(hover.contents.map(hover_content_json)),
  }
}

///|
fn hover_content_json(content : @language.HoverContent) -> Json {
  match content {
    PlainText(text) => { "kind": Json("plaintext"), "value": text.to_json() }
    Markdown(text) => { "kind": Json("markdown"), "value": text.to_json() }
  }
}

///|
fn location_json(location : @language.Location) -> Json {
  {
    "uri": location.uri.to_string().to_json(),
    "range": range_json(location.range),
  }
}

///|
/// Serializes a line/column `Range`, used by the types that carry a `Range`
/// (Location, DocumentSymbol, ReferenceItem).
fn range_json(range : @base_common.Range) -> Json {
  {
    "startLineNumber": range.start_line_number.to_json(),
    "startColumn": range.start_column.to_json(),
    "endLineNumber": range.end_line_number.to_json(),
    "endColumn": range.end_column.to_json(),
  }
}

///|
fn parse_range(value : Json) -> @base_common.Range? {
  match
    (
      json_int_field(value, "startLineNumber"),
      json_int_field(value, "startColumn"),
      json_int_field(value, "endLineNumber"),
      json_int_field(value, "endColumn"),
    ) {
    (Some(start_line), Some(start_column), Some(end_line), Some(end_column)) =>
      Some(Range(start_line, start_column, end_line, end_column))
    _ => None
  }
}

///|
fn parse_diagnostic(value : Json) -> @language.Diagnostic? {
  guard value is Object(_) else { return None }
  guard json_field(value, "range") is Some(range_json) else { return None }
  guard parse_range(range_json) is Some(range) else { return None }
  Some({
    range,
    severity: diagnostic_severity(
      json_string_field(value, "severity").unwrap_or("Info"),
    ),
    message: json_string_field(value, "message").unwrap_or(""),
    tags: parse_diagnostic_tags(value),
  })
}

///|
fn parse_diagnostic_tags(value : Json) -> Array[@language.DiagnosticTag]? {
  match json_field(value, "tags") {
    Some(Array(items)) => {
      let tags : Array[@language.DiagnosticTag] = []
      for item in items {
        match item {
          String("Unnecessary") => tags.push(Unnecessary)
          String("Deprecated") => tags.push(Deprecated)
          _ => ()
        }
      }
      if tags.is_empty() {
        None
      } else {
        Some(tags)
      }
    }
    _ => None
  }
}

///|
fn parse_hover(value : Json) -> @language.Hover? {
  guard value is Object(_) else { return None }
  guard json_field(value, "range") is Some(range_json) else { return None }
  guard json_field(value, "contents") is Some(contents_json) else {
    return None
  }
  guard parse_range(range_json) is Some(range) else { return None }
  let contents = parse_hover_contents(contents_json)
  guard contents.length() != 0 else { return None }
  Some({ range, contents, })
}

///|
fn parse_hover_contents(value : Json) -> Array[@language.HoverContent] {
  match value {
    String(text) => parse_hover_plaintext(text)
    Object(_) =>
      match parse_hover_content(value) {
        Some(content) => [content]
        None => []
      }
    Array(items) => {
      let out : Array[@language.HoverContent] = []
      for item in items {
        for content in parse_hover_contents(item) {
          out.push(content)
        }
      }
      out
    }
    _ => []
  }
}

///|
fn parse_hover_content(value : Json) -> @language.HoverContent? {
  match value {
    String(text) =>
      match parse_hover_plaintext(text) {
        [content] => Some(content)
        _ => None
      }
    Object(_) => {
      guard json_string_field(value, "value") is Some(text) else { return None }
      if text == "" {
        return None
      }
      match json_string_field(value, "kind") {
        Some("markdown") => Some(Markdown(text))
        _ => Some(PlainText(text))
      }
    }
    _ => None
  }
}

///|
fn parse_hover_plaintext(text : String) -> Array[@language.HoverContent] {
  if text == "" {
    []
  } else {
    [PlainText(text)]
  }
}

///|
fn parse_location(value : Json) -> @language.Location? {
  guard value is Object(_) else { return None }
  guard json_string_field(value, "uri") is Some(raw_uri) else { return None }
  guard json_field(value, "range") is Some(range_json) else { return None }
  guard try_parse_uri(raw_uri) is Some(uri) else { return None }
  guard parse_range(range_json) is Some(range) else { return None }
  Some({ uri, range, })
}

///|
fn parse_reference_item(value : Json) -> ReferenceItem? {
  guard value is Object(_) else { return None }
  guard json_string_field(value, "uri") is Some(raw_uri) else { return None }
  guard json_field(value, "range") is Some(range_json) else { return None }
  guard try_parse_uri(raw_uri) is Some(uri) else { return None }
  guard parse_range(range_json) is Some(range) else { return None }
  Some({
    uri,
    range,
    line: json_int_field(value, "line").unwrap_or(0),
    column: json_int_field(value, "column").unwrap_or(0),
    line_text: json_string_field(value, "lineText").unwrap_or(""),
  })
}

///|
fn parse_document_symbol(value : Json) -> @language.DocumentSymbol? {
  guard value is Object(_) else { return None }
  guard json_field(value, "range") is Some(range_json) else { return None }
  guard parse_range(range_json) is Some(range) else { return None }
  Some({
    name: json_string_field(value, "name").unwrap_or(""),
    kind: json_string_field(value, "kind").unwrap_or(""),
    range,
  })
}

///|
fn diagnostic_severity(label : String) -> @language.DiagnosticSeverity {
  match label {
    "Error" => Error
    "Warning" => Warning
    "Hint" => Hint
    _ => Info
  }
}

///|
fn parse_json(raw : String) -> Json? {
  Some(@json.parse(raw)) catch {
    _ => None
  }
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn json_string_field(value : Json, key : String) -> String? {
  match json_field(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn json_int_field(value : Json, key : String) -> Int? {
  match json_field(value, key) {
    Some(Number(number, repr=_)) => Some(number.to_int())
    _ => None
  }
}

///|
/// Every element of the JSON array at `key`, dropping the ones `parse`
/// rejects. A missing or non-array field yields an empty array.
fn[T] json_array_field(
  value : Json,
  key : String,
  parse : (Json) -> T?,
) -> Array[T] {
  match json_field(value, key) {
    Some(Array(items)) => items.filter_map(parse)
    _ => []
  }
}

///|
pub extend ClientPacket with Debug::{to_repr}

///|
pub extend ClientPacket with ToJson::{to_json}

///|
pub extend ClientPacketDecodeResult with Debug::{to_repr}

///|
pub extend DefinitionResultPayload with Debug::{to_repr}

///|
pub extend DiagnosticsPayload with Debug::{to_repr}

///|
pub extend DirectoryResolvedPayload with Debug::{to_repr}

///|
pub extend DocumentPayload with Debug::{to_repr}

///|
pub extend DocumentPositionRequest with Debug::{to_repr}

///|
pub extend DocumentRequest with Debug::{to_repr}

///|
pub extend DocumentRevisionRequest with Debug::{to_repr}

///|
pub extend DocumentSymbolsResultPayload with Debug::{to_repr}

///|
pub extend HoverResultPayload with Debug::{to_repr}

///|
pub extend ProtocolError with Debug::{to_repr}

///|
pub extend ProtocolError with ToJson::{to_json}

///|
pub extend ProtocolErrorCode with Debug::{to_repr}

///|
pub extend ProtocolErrorCode with Eq::{equal, not_equal}

///|
pub extend ProtocolNegotiation with Debug::{to_repr}

///|
pub extend ReferenceItem with Debug::{to_repr}

///|
pub extend ReferencesResultPayload with Debug::{to_repr}

///|
pub extend ServerPacket with Debug::{to_repr}

///|
pub extend ServerPacket with ToJson::{to_json}

///|
pub extend ServerPacketDecodeResult with Debug::{to_repr}
