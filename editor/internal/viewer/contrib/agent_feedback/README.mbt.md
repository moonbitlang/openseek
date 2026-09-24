# internal/viewer/contrib/agent_feedback

The DOM-free agent-feedback implementation. It owns the mutable feedback
service, editor-comment projection, deterministic sorting/grouping, navigation,
reply, acceptance, and submission state used by the root Viewer and workbench.

```mermaid
flowchart LR
  S["AgentFeedbackService<br>mutable per-URI store"] -->|agent_feedback_handle| API["viewer/common/agent_feedback_api<br>12-callback handle"]
  S -->|get_session_editor_comments| P["SessionEditorComment[]<br>ordered projection"]
  P -->|group_nearby_session_editor_comments| G["visual groups"]
  API --> V["root Viewer"]
  G --> B["…/agent_feedback/browser<br>input + bubble widgets"]
```

## The store

Feedback is per resource. Mutations and reads flow through the callback handle;
the concrete service retains only host-owned lifecycle and snapshot setters.
The optional `selected_text` snapshot stays with the item through acceptance,
comment edits, replies, and submission. The service preserves both absent and
explicitly empty snapshots without substituting source content.

```mbt check
///|
test "feedback is stored per resource with an allocated id" {
  let service = @agent_feedback.AgentFeedbackService()
  let handle = service.agent_feedback_handle()
  let uri = @base_common.Uri::parse("file:///src/main.mbt")
  let other = @base_common.Uri::parse("file:///src/other.mbt")
  let created = handle.add_feedback(uri, Range(4, 1, 4, 9), "look here")
  debug_inspect(
    (
      created.text,
      created.kind,
      created.state,
      handle.get_feedback(uri).length(),
      handle.get_feedback(other).length(),
    ),
    content=(
      #|("look here", UserReview, Accepted, 1, 0)
    ),
  )
}
```

Acceptance, replies, and submission are state transitions on an existing item
rather than separate collections.

```mbt check
///|
test "accept, reply, and submit move the same item through its states" {
  let service = @agent_feedback.AgentFeedbackService()
  let handle = service.agent_feedback_handle()
  let uri = @base_common.Uri::parse("file:///src/main.mbt")
  let item = handle.add_feedback(uri, Range(1, 1, 1, 4), "note", state=Created)
  handle.accept_feedback(uri, item.id)
  let accepted = handle.get_feedback(uri)[0].state
  handle.add_reply(uri, item.id, "acknowledged")
  let replies = handle.get_feedback(uri)[0].replies
  handle.mark_feedback_submitted(uri)
  debug_inspect(
    (accepted, replies, handle.get_feedback(uri)[0].state),
    content=(
      #|(Accepted, ["acknowledged"], Submitted)
    ),
  )
}
```

Removing one resource's item leaves another resource's store intact.

```mbt check
///|
test "removing one resource's item leaves the others intact" {
  let service = @agent_feedback.AgentFeedbackService()
  let handle = service.agent_feedback_handle()
  let first = @base_common.Uri::parse("file:///a.mbt")
  let second = @base_common.Uri::parse("file:///b.mbt")
  let removed = handle.add_feedback(first, Range(1, 1, 1, 2), "a")
  handle.add_feedback(second, Range(1, 1, 1, 2), "b") |> ignore
  handle.remove_feedback(first, removed.id)
  debug_inspect(
    (handle.get_feedback(first).length(), handle.get_feedback(second).length()),
    content=(
      #|(0, 1)
    ),
  )
}
```

## The editor-comment projection

`get_session_editor_comments` projects host DTOs into the value the editor
renders and returns the result in deterministic position order, so two comments
never swap places between renders.

```mbt check
///|
fn feedback_at(
  line : Int,
  text : String,
) -> @agent_feedback_api.AgentFeedback raise {
  {
    id: "fb-\{line}",
    text,
    resource: @base_common.Uri::parse("file:///src/main.mbt"),
    range: Range(line, 1, line, 4),
    selected_text: None,
    kind: UserReview,
    replies: [],
    state: Created,
  }
}

///|
test "the projection is ordered deterministically by position" {
  let projected = @agent_feedback.get_session_editor_comments([
    feedback_at(30, "third"),
    feedback_at(10, "first"),
    feedback_at(20, "second"),
  ])
  debug_inspect(
    projected.map(comment => (comment.range.start_line_number, comment.text)),
    content=(
      #|[(10, "first"), (20, "second"), (30, "third")]
    ),
  )
}
```

`group_nearby_session_editor_comments` collapses comments that sit within a line
threshold of each other into one visual group, so adjacent notes render as a
stack rather than as overlapping bubbles.

```mbt check
///|
test "nearby comments group and distant ones do not" {
  let projected = @agent_feedback.get_session_editor_comments([
    feedback_at(10, "a"),
    feedback_at(11, "b"),
    feedback_at(40, "c"),
  ])
  debug_inspect(
    @agent_feedback.group_nearby_session_editor_comments(projected).map(group => {
      group.map(comment => comment.text)
    }),
    content=(
      #|[["a", "b"], ["c"]]
    ),
  )
}
```

## Boundaries and checks

Public host DTOs and callback handles remain in
`viewer/common/agent_feedback_api`; this package is an internal implementation
owner and must not become a dependency of embedded clients. Browser widgets
live in `internal/viewer/contrib/agent_feedback/browser`. The planned
agent-loop submit/resolve seam is isolated in the owning packages' `exports.mbt`
files.

Exact callable types are in `pkg.generated.mbti`. Run the focused suite on
both supported targets with:

```sh
moon test internal/viewer/contrib/agent_feedback --target js
moon test internal/viewer/contrib/agent_feedback --target native
```
