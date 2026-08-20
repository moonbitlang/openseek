///|
/// The version of the session-file header record this package understands.
let session_file_version : Int = 1

///|
/// The header record on the first line of a session file: the session identity
/// and system prompt for the event lines that follow. The system prompt lives
/// only here — it is a `Session` field, not an event — so a session file is
/// self-contained.
pub(all) struct SessionFileHeader {
  id : String
  system_prompt : String
} derive(Eq, Debug)

///|
/// Encode a header record as the JSON stored on a session file's first line.
///
/// The shape is `{ "version": 1, "id": <id>, "system_prompt": <text> }`.
pub impl ToJson for SessionFileHeader with fn to_json(
  header : SessionFileHeader,
) -> Json {
  {
    "version": session_file_version,
    "id": header.id,
    "system_prompt": header.system_prompt,
  }
}

///|
/// How a would-be header record classified. `UnsupportedVersion` is kept
/// distinct from `NotHeader` so a reader confronted with a file written by a
/// newer format can say so, instead of misreporting it as a file that has no
/// header at all.
pub enum HeaderParse {
  Header(SessionFileHeader)
  UnsupportedVersion(Int)
  NotHeader
} derive(Debug)

///|
/// Classify `json` as a session-file header record.
///
/// Header and event records are structurally disjoint (events carry
/// `sequence`/`item`, never `version`), so this is also how a reader tells
/// the two apart. Any object carrying a numeric `version` other than 1 is a
/// header from a format this build does not read — `UnsupportedVersion` —
/// even though its remaining fields cannot be interpreted.
pub fn classify_header(json : Json) -> HeaderParse {
  match json {
    { "version": Number(version, ..), .. } if version.to_int() !=
      session_file_version => UnsupportedVersion(version.to_int())
    {
      "version": Number(_, ..),
      "id": String(id),
      "system_prompt": String(system_prompt),
      ..
    } => Header({ id, system_prompt })
    _ => NotHeader
  }
}

///|
/// Decode a session-file header record, or `None` when `json` is not a
/// header this build can read. Use `classify_header` to distinguish an
/// unsupported version from a non-header.
fn parse_header(json : Json) -> SessionFileHeader? {
  match classify_header(json) {
    Header(header) => Some(header)
    UnsupportedVersion(_) | NotHeader => None
  }
}

///|
/// One JSONL line that could not be decoded into a `SessionEvent`. Kept so
/// downstream tools can surface the offending line instead of silently
/// dropping it or aborting the whole load.
pub struct LineError {
  line_number : Int
  content : String
  message : String
} derive(Eq, Debug)

///|
/// Build an immutable `Session` from parsed events plus the header values the
/// caller wants to use. When no header record is available, pass a
/// placeholder id and an empty system prompt.
pub fn session_from_parse(
  parsed : ParsedLog,
  id~ : String,
  system_prompt~ : String,
) -> @agent_session.Session {
  let session_id : @agent_session.SessionId = SessionId(id)
  Session(session_id, system_prompt~, events=@vector.from_array(parsed.events))
}

///|
#deprecated
pub extend HeaderParse with Debug::{to_repr}

///|
#deprecated
pub extend LineError with Debug::{to_repr}

///|
pub extend LineError with Eq::{equal, not_equal}

///|
#deprecated
pub extend SessionFileHeader with Debug::{to_repr}

///|
pub extend SessionFileHeader with Eq::{equal, not_equal}

///|
pub extend SessionFileHeader with ToJson::{to_json}
