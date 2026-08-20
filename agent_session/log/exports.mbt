// Deliberate exports whose consumers live outside this workspace (see
// shrink_package.md).

///|
/// pub(all): cmd/viz_app (its own module — invisible to this workspace's
/// analyze) constructs ParsedLog literals for its view fixtures.

///|
/// The result of parsing a session file line by line. `header` is the
/// identity record found on the first content line, when present; `events`
/// are the records that decoded cleanly (in file order); `errors` are
/// individual lines that failed to decode; `partial_tail` is true when the
/// final line looked like a half-written record from a process that exited
/// mid-append.
pub(all) struct ParsedLog {
  header : SessionFileHeader?
  events : Array[@agent_session.SessionEvent]
  errors : Array[LineError]
  partial_tail : Bool
} derive(Eq, Debug)

///|
/// Parse a session file into a header record and typed `SessionEvent`s,
/// tolerating a truncated trailing line and per-line decode failures. Blank
/// lines are ignored. The first content line is read as the header when it is
/// one; a header-less text (a bare event log) still parses with
/// `header=None`. A decode failure on any line other than an unterminated
/// final line is recorded as a `LineError` and parsing continues.
pub fn parse_events(text : String) -> ParsedLog {
  let mut header : SessionFileHeader? = None
  let events : Array[@agent_session.SessionEvent] = []
  let errors : Array[LineError] = []
  let ends_with_newline = text.has_suffix("\n")
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  let mut partial_tail = false
  // The one policy for a line that does not decode: an unterminated final
  // line is a torn tail; anything else is a recorded per-line error.
  fn note_bad_line(
    line_number : Int,
    line : String,
    torn : Bool,
    message : String,
  ) -> Unit {
    if torn {
      partial_tail = true
    } else {
      errors.push({ line_number, content: line, message })
    }
  }

  let mut first_content_line = true
  for index, line in lines {
    let line_number = index + 1
    if line.is_blank() {
      continue
    }
    let may_be_header = first_content_line
    first_content_line = false
    let torn = index == lines.length() - 1 && !ends_with_newline
    let json = @json.parse(line) catch {
      error => {
        note_bad_line(line_number, line, torn, "\{error}")
        continue
      }
    }
    if may_be_header && parse_header(json) is Some(parsed_header) {
      header = Some(parsed_header)
      continue
    }
    let event : @agent_session.SessionEvent = @json.from_json(json) catch {
      error => {
        note_bad_line(line_number, line, torn, "\{error}")
        continue
      }
    }
    events.push(event)
  }
  { header, events, errors, partial_tail }
}

///|
#deprecated
pub extend ParsedLog with Debug::{to_repr}

///|
pub extend ParsedLog with Eq::{equal, not_equal}
