///|
/// Builds a provider error, defaulting an empty message to the stable code
/// label.
pub fn FileSystemProviderError::FileSystemProviderError(
  code : FileSystemProviderErrorCode,
  message : String,
  uri? : @base_common.Uri,
) -> FileSystemProviderError {
  let message = if message == "" { code.to_string() } else { message }
  { code, message, uri, }
}

///|
/// Reads and converts a file-provider result into an immutable
/// `DocumentSnapshot`, failing closed when the URI scheme does not match.
async fn read_document_impl(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
) -> DocumentReadResult {
  if uri.scheme != provider.scheme() {
    return DocumentReadFailed(
      DocumentError(
        InvalidUri,
        "No filesystem provider is registered for URI scheme \{uri.scheme}",
        uri~,
      ),
    )
  }
  match provider.read_file(uri) {
    FileReadOk(content) =>
      DocumentLoaded(DocumentSnapshot::from_content(uri, content))
    FileReadError(error) =>
      match error.code {
        FileNotFound => DocumentNotFound(uri)
        _ => DocumentReadFailed(DocumentError::from_file_system_error(error))
      }
  }
}

///|
/// Starts a default file watch only when the provider owns the URI scheme.
fn watch_file_impl(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
  listener : (Array[FileChange]) -> Unit,
) -> FileWatch {
  if uri.scheme == provider.scheme() {
    provider.watch(uri, WatchOptions::default(), listener)
  } else {
    { dispose: () => (), }
  }
}

///|
/// HTTP-like status used by the reference server when serializing provider
/// failures.
fn FileSystemProviderError::status(self : FileSystemProviderError) -> Int32 {
  match self.code {
    FileNotFound => 404
    FileExists => 409
    FileNotADirectory => 400
    IsDirectory => 400
    NoPermissions => 403
    Unavailable => 503
    InvalidUri => 400
    InvalidData => 415
  }
}

///|
/// Stable string label for wire format and JSON diagnostics.
pub fn FileSystemProviderErrorCode::to_string(
  self : FileSystemProviderErrorCode,
) -> String {
  match self {
    FileNotFound => "FileNotFound"
    FileExists => "FileExists"
    FileNotADirectory => "FileNotADirectory"
    IsDirectory => "IsDirectory"
    NoPermissions => "NoPermissions"
    Unavailable => "Unavailable"
    InvalidUri => "InvalidUri"
    InvalidData => "InvalidData"
  }
}

///|
/// Decodes both this package's labels and browser File System Access API names.
pub fn FileSystemProviderErrorCode::from_string(
  code : String,
) -> FileSystemProviderErrorCode {
  match code {
    "FileNotFound" => FileNotFound
    "FileExists" => FileExists
    "FileNotADirectory" => FileNotADirectory
    "IsDirectory" => IsDirectory
    "NoPermissions" => NoPermissions
    "Unavailable" => Unavailable
    "InvalidUri" => InvalidUri
    "InvalidData" => InvalidData
    "NotFound" => FileNotFound
    "NotAllowedError" => NoPermissions
    "AbortError" => Unavailable
    _ => Unavailable
  }
}

///|
/// Lowercase watch-event label used in JSON payloads.
fn FileChangeType::to_string(self : FileChangeType) -> String {
  match self {
    Created => "created"
    Changed => "changed"
    Deleted => "deleted"
  }
}

///|
fn revision_from_text_impl(text : String) -> String {
  let hash = for unit in text.code_units(); hash = 2166136261L {
    continue (hash ^ unit.to_int64()) * 16777619L
  } nobreak {
    hash
  }
  hash.to_string()
}
