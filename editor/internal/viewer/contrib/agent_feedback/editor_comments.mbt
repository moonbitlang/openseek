// The editor-facing comment view and grouping logic, ported from
// `vscode/src/vs/sessions/contrib/agentFeedback/browser/sessionEditorComments.ts`.
// Upstream unifies agent feedback with raw PR-review comments
// (`ISessionEditorComment` with two sources plus dedup of the PR mirror); the
// viewer has no PR source, so the view collapses to agent feedback only:
// `canConvertToAgentFeedback` is always false and the source tag disappears
// from the type and the comparator. The display-height estimate and the
// nearby-grouping algorithm are kept verbatim (minus the suggestion-edit
// lines — suggestions are not ported).

///|
/// `ISessionEditorComment` trimmed to the single agent-feedback source.
/// `id` is the prefixed navigation/anchor id (`to_session_editor_comment_id`);
/// `source_id` is the raw `AgentFeedback.id` the service mutations take.
pub struct SessionEditorComment {
  id : String
  source_id : String
  kind : @agent_feedback_api.AgentFeedbackKind
  resource : @base_common.Uri
  range : @base_common.Range
  text : String
  replies : Array[String]
  state : @agent_feedback_api.AgentFeedbackState
} derive(Debug)

///|
/// `toSessionEditorCommentId(source, sourceId)` with the source fixed to
/// `agentFeedback` — kept so anchors stay distinct from raw feedback ids and
/// stable if another source ever lands.
fn to_session_editor_comment_id(source_id : String) -> String {
  "agentFeedback:\{source_id}"
}

///|
/// `getSessionEditorComments`: projects stored feedback into the editor view.
/// Resolved items are hidden; the result is sorted with
/// `compare_session_editor_comments`. (The upstream PR-mirror dedup rules vanish with
/// the PR source.)
pub fn get_session_editor_comments(
  items : Array[@agent_feedback_api.AgentFeedback],
) -> Array[SessionEditorComment] {
  let comments : Array[SessionEditorComment] = []
  for item in items {
    guard item.state != Resolved else { continue }
    comments.push({
      id: to_session_editor_comment_id(item.id),
      source_id: item.id,
      kind: item.kind,
      resource: item.resource,
      range: item.range,
      text: item.text,
      replies: item.replies,
      state: item.state,
    })
  }
  comments.sort_by(compare_session_editor_comments)
  comments
}

///|
/// `compareSessionEditorComments`: resource, then range start, then id.
/// (Upstream uses `localeCompare`; the viewer uses MoonBit's `String`
/// ordering — only determinism matters here, not collation.)
fn compare_session_editor_comments(
  a : SessionEditorComment,
  b : SessionEditorComment,
) -> Int {
  let by_resource = a.resource.to_string().compare(b.resource.to_string())
  if by_resource != 0 {
    return by_resource
  }
  let by_range = @base_common.Range::compare_ranges_using_starts(
    a.range,
    b.range,
  )
  if by_range != 0 {
    return by_range
  }
  a.source_id.compare(b.source_id)
}

///|
/// `estimateExpandedCommentLines`: the vertical space (in editor lines) a
/// comment roughly occupies when rendered expanded in the feedback widget,
/// so grouping accounts for long comments that would overlap the next
/// widget. ~50 characters per widget line, +1 for the item header, plus the
/// replies at the same rate.
fn estimate_expanded_comment_lines(comment : SessionEditorComment) -> Int {
  let chars_per_line = 50
  let text_length = comment.text.length().max(1)
  let text_lines = (text_length + chars_per_line - 1) / chars_per_line
  let reply_lines = for reply in comment.replies; reply_lines = 0 {
    let reply_length = reply.length().max(1)
    continue reply_lines + (reply_length + chars_per_line - 1) / chars_per_line
  } nobreak {
    reply_lines
  }
  text_lines + 1 + reply_lines
}

///|
/// `groupNearbySessionEditorComments`: partitions sorted comments into
/// widget groups. A comment joins the current group when it is on the same
/// resource and its start line is within `line_threshold` lines of the
/// group's first comment — widened by the group's estimated expanded height
/// so a long comment pulls in items below it.
pub fn group_nearby_session_editor_comments(
  items : Array[SessionEditorComment],
  line_threshold? : Int = 5,
) -> Array[Array[SessionEditorComment]] {
  if items.is_empty() {
    return []
  }
  let sorted = items.copy()
  sorted.sort_by(compare_session_editor_comments)
  let groups : Array[Array[SessionEditorComment]] = []
  let mut current_group : Array[SessionEditorComment] = [sorted[0]]
  let mut current_group_expanded_lines = estimate_expanded_comment_lines(
    sorted[0],
  )
  for index in 1..<sorted.length() {
    let first_item = current_group[0]
    let current_item = sorted[index]
    let same_resource = current_item.resource.to_string() ==
      first_item.resource.to_string()
    let vertical_span = current_item.range.start_line_number -
      first_item.range.start_line_number
    let effective_threshold = line_threshold + current_group_expanded_lines
    if same_resource && vertical_span <= effective_threshold {
      current_group.push(current_item)
      current_group_expanded_lines += estimate_expanded_comment_lines(
        current_item,
      )
    } else {
      groups.push(current_group)
      current_group = [current_item]
      current_group_expanded_lines = estimate_expanded_comment_lines(
        current_item,
      )
    }
  }
  groups.push(current_group)
  groups
}

///|
pub extend SessionEditorComment with Debug::{to_repr}
