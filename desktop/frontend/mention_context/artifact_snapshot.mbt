///|
/// A user-selected snapshot of one interactive answer. It is data carried by
/// the ordinary prompt; the reference identifies the authored page revision.
pub(all) struct ArtifactSnapshot {
  reference : String
  title : String
  state : Json
} derive(Eq, Debug)

///|
pub fn artifact_snapshot(
  reference : String,
  payload : String,
) -> ArtifactSnapshot? {
  guard @workspace_file_ref.artifact_path(reference) is Some(_) &&
    @utf8.encode(reference).length() <= 1024 &&
    @utf8.encode(payload).length() <= 16 * 1024 else {
    return None
  }
  let value = @json.parse(payload) catch { _ => return None }
  guard value is { "title": String(title), "state": state, .. } &&
    !title.trim().is_empty() &&
    title.length() <= 160 &&
    @utf8.encode(state.stringify()).length() <= 12 * 1024 else {
    return None
  }
  Some({ reference, title, state, })
}

///|
fn write_artifact_snapshot(
  parts : StringBuilder,
  snapshot : ArtifactSnapshot,
) -> Unit {
  // One JSON line keeps quotes, newlines and apparent closing tags inside
  // values. A captured state cannot introduce another envelope element.
  let payload : Json = {
    "reference": snapshot.reference,
    "title": snapshot.title,
    "state": snapshot.state,
  }
  parts <+
    "<interactive_answer>\n\{payload.stringify()}\n</interactive_answer>\n"
}

///|
fn parse_artifact_snapshot(line : String) -> ArtifactSnapshot? {
  let value = @json.parse(line) catch { _ => return None }
  guard value is { "reference": String(reference), .. } else { return None }
  artifact_snapshot(reference, line)
}

///|
pub extend ArtifactSnapshot with Eq::{equal, not_equal}

///|
pub extend ArtifactSnapshot with Debug::{to_repr}
