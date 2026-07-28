///|
/// Errors raised while parsing a git object payload.
///
/// - `InvalidZlib`: zlib stream cannot be decoded.
/// - `InvalidHeader`: malformed "type size\0" header.
/// - `InvalidSize`: header size does not match content length.
/// - `InvalidSha1`: expected SHA-1 is not a 40-char hex string.
pub(all) suberror GitObjectError {
  InvalidZlib(String)
  InvalidHeader(String)
  InvalidSize(String)
  InvalidSha1(String)
} derive(Show, Eq)

///|
/// Supported git object kinds.
///
/// Use `Unknown` for non-standard object types.
pub(all) enum GitObjectKind {
  Blob
  Tree
  Commit
  Tag
  Unknown(String)
} derive(Show, Eq)

///|
/// A single tree entry as rendered by git.
///
/// `mode` should match the 6-digit mode string from `git cat-file -p`.
/// `kind` is derived from the entry's object type.
pub(all) struct GitTreeEntry {
  mode : String
  kind : GitObjectKind
  oid : String
  name : String
} derive(Show, Eq)

///|
/// Blob content with base64 payload and optional UTF-8 text.
pub(all) struct GitBlobContent {
  base64 : String
  text : String?
} derive(Show, Eq)

///|
/// Tree content as a list of entries.
pub(all) struct GitTreeContent {
  entries : Array[GitTreeEntry]
} derive(Show, Eq)

///|
/// Commit content as raw header lines and message.
///
/// `headers` should include any multi-line header continuations as separate
/// lines, matching the literal object data.
pub(all) struct GitCommitContent {
  headers : Array[String]
  message : String
} derive(Show, Eq)

///|
/// Tag content as raw header lines and message.
pub(all) struct GitTagContent {
  headers : Array[String]
  message : String
} derive(Show, Eq)

///|
/// Parsed git object content.
///
/// `Unknown` should carry a base64-encoded payload.
pub(all) enum GitObjectContent {
  Blob(GitBlobContent)
  Tree(GitTreeContent)
  Commit(GitCommitContent)
  Tag(GitTagContent)
  Unknown(String)
} derive(Show, Eq)

///|
/// Parsed git object with SHA-1 validation metadata.
///
/// `sha1_ok` should be true when `expected_oid` (if provided) matches the
/// computed SHA-1 of "type size\0" + content.
pub(all) struct GitObject {
  oid : String
  kind : GitObjectKind
  size : Int
  sha1_ok : Bool
  content : GitObjectContent
} derive(Show, Eq)

///|
/// Convert a GitObject into JSON for snapshot testing.
///
/// Expected JSON shape:
/// - `oid`: string
/// - `kind`: string
/// - `size`: number
/// - `sha1_ok`: bool
/// - `content`: object keyed by `type` with kind-specific fields
declare pub fn GitObject::to_json(self : GitObject) -> Json

///|
/// Parse a zlib-compressed git object payload.
///
/// `bytes` must contain a complete loose object (zlib stream) with the
/// "type size\0" header followed by content bytes. If `expected_oid` is
/// provided, implementations must compute the SHA-1 and set `sha1_ok`
/// accordingly.
declare pub fn parse_object_bytes(
  bytes : Bytes,
  expected_oid? : String,
) -> GitObject raise GitObjectError
