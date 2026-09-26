///|
/// The request format version this module writes and reads.
pub const RunRequestVersion : Int = 1

///|
/// One structured request for `openseek run --input-format json`: what to run
/// and on what. See `docs/run-result.md` for how it is framed on stdin.
pub(all) struct RunRequest {
  /// The caller's name for this request, echoed in the result so a parent can
  /// tell which request a result answers.
  request_id : String?
  /// The preset to run (`explore`, `review`, …) or `general`; `None` means
  /// general. The command line's `--kind`, when given, must agree.
  kind : String?
  /// What the run works on: `{"task": String}` for a general run, the
  /// preset's own input otherwise.
  input : Json
  /// The step ceiling the caller asks for (`limits.max_steps`). An explicit
  /// `--max-steps` on the command line wins over it.
  max_steps : Int?
} derive(Eq, Debug)

///|
/// Why a JSON value is not a request this module can run.
pub(all) suberror RunRequestError {
  /// A request from a newer (or unknown) format version.
  UnsupportedVersion(Int)
  /// A field is missing or mistyped; names the field.
  Malformed(String)
  /// A field this engine recognizes but does not implement; names it. A
  /// request is refused rather than run without what it asked for.
  Unsupported(String)
} derive(Eq, Debug)

///|
pub impl ToJson for RunRequest with fn to_json(self) {
  let fields : Map[String, Json] = {
    "version": RunRequestVersion.to_json(),
    "input": self.input,
  }
  if self.request_id is Some(id) {
    fields["request_id"] = id.to_json()
  }
  if self.kind is Some(kind) {
    fields["kind"] = kind.to_json()
  }
  if self.max_steps is Some(steps) {
    fields["limits"] = { "max_steps": steps.to_json() }
  }
  Json::object(fields)
}

///|
/// Read a request back into a `RunRequest`: the inverse of `to_json`. Unknown
/// fields are ignored so that a newer caller can add optional ones; `schema`
/// is refused, because this engine cannot constrain a report to a caller's
/// schema and must not pretend to.
pub fn parse_run_request(json : Json) -> RunRequest raise RunRequestError {
  guard json is Object(fields) else { raise Malformed("request") }
  guard int(fields, "version") is Some(version) else {
    raise Malformed("version")
  }
  guard version == RunRequestVersion else { raise UnsupportedVersion(version) }
  if fields.contains("schema") {
    raise Unsupported("schema")
  }
  fn optional_text(key) raise RunRequestError {
    match fields.get(key) {
      None => None
      Some(String(value)) if !value.is_blank() => Some(value)
      Some(_) => raise Malformed(key)
    }
  }
  let request_id = optional_text("request_id")
  let kind = optional_text("kind")
  guard fields.get("input") is Some(input) else { raise Malformed("input") }
  let max_steps = match fields.get("limits") {
    None => None
    Some(Object(limits)) =>
      match limits.get("max_steps") {
        None => None
        Some(_) =>
          match int(limits, "max_steps") {
            Some(steps) if steps >= 1 => Some(steps)
            _ => raise Malformed("limits.max_steps")
          }
      }
    Some(_) => raise Malformed("limits")
  }
  { request_id, kind, input, max_steps, }
}

///|
pub extend RunRequest with Debug::{to_repr}

///|
pub extend RunRequest with Eq::{equal, not_equal}

///|
pub extend RunRequest with ToJson::{to_json}

///|
pub extend RunRequestError with Debug::{to_repr}

///|
pub extend RunRequestError with Eq::{equal, not_equal}
