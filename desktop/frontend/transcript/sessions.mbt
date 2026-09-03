// Projection of typed host session replies into sidebar and transcript view
// models. JSON decoding belongs to the engine or WebSocket adapter; this
// package never handles an open-ended durable-session object.

///|
/// Project a `list_sessions` reply into sidebar entries: the host groups
/// sessions by workspace store, and each entry carries its group's workspace
/// so the sidebar can section them. Failed groups remain empty; invalid engine
/// rows have already been dropped at the process adapter.
pub fn sessions_from_reply(
  reply : @desktop_protocol.SessionsReply,
  channel : @interop.ChannelId,
) -> Array[SessionListItem] {
  let items : Array[SessionListItem] = []
  for group in reply.groups {
    // Every group names the registered workspace whose store it was read
    // from. A blank or malformed path invalidates the grouping rather than
    // producing rows the sidebar cannot section or reopen.
    guard @resource.of_path(channel, group.workspace) is Some(workspace) else {
      continue
    }
    for entry in group.sessions {
      guard !entry.id.is_empty() else { continue }
      items.push({
        id: entry.id,
        title: entry.title,
        workspace,
        workspace_name: group.name,
        updated_at_ms: entry.updated_at_ms,
      })
    }
  }
  items
}

///|
/// One sidebar row of a session group: a conversation and the sub-run
/// transcripts it spawned, in sub-run order.
pub struct SessionTreeRow {
  item : SessionListItem
  children : Array[SessionListItem]
} derive(Eq)

///|
/// A session id is unique only inside one host session store. Keeping the
/// workspace beside it prevents a child or duplicate id from folding under a
/// parent row owned by another project.
priv struct SessionTreeKey {
  session : String
  workspace : String
} derive(Eq, Hash)

///|
fn SessionListItem::tree_key(
  self : SessionListItem,
  session : String,
) -> SessionTreeKey {
  { session, workspace: self.workspace.path, }
}

///|
/// The outermost listed session this item folds under in its own store, and
/// the sub-run ordinals leading down to it. A same-ID row from another store
/// is deliberately invisible to this walk.
fn SessionListItem::tree_fold_target(
  self : SessionListItem,
  listed : Map[SessionTreeKey, Bool],
) -> (SessionTreeKey, Array[Int])? {
  let path : Array[Int] = []
  let mut current = self.id
  for ;; {
    guard @protocol.split_child_session_id(current) is Some((parent, ordinal)) else {
      break
    }
    guard listed.get(self.tree_key(parent)) is Some(_) else { break }
    path.push(ordinal)
    current = parent
  }
  guard !path.is_empty() else { return None }
  Some((self.tree_key(current), path.rev()))
}

///|
/// Fold a group's sessions into rows, moving every sub-run child transcript
/// (`<parent>-sr-N`, see `@protocol.split_child_session_id`) under the
/// conversation that launched it.
///
/// The engine persists a sub-run's transcript as a sibling session, so a
/// single worker sweep can leave more child records in a store than there
/// are conversations — flat, they crowd every real chat off screen. Parents
/// keep the listing's order; children sort by sub-run ordinal, which a
/// lexicographic id sort would get wrong past `sr-9`.
///
/// Nothing is ever hidden: a child whose parent is NOT in this group (an
/// archived parent, a differently-scoped store) keeps a row of its own, in
/// its listed position. A grandchild folds under the outermost listed
/// ancestor rather than opening a second level of nesting — today the child
/// toolsets carry no sub-run tools, so it stands for a shape the sidebar
/// should survive, not one it should design around.
pub fn session_tree(items : Array[SessionListItem]) -> Array[SessionTreeRow] {
  let listed : Map[SessionTreeKey, Bool] = Map([])
  for item in items {
    listed[item.tree_key(item.id)] = true
  }
  let rows : Array[SessionTreeRow] = []
  let row_at : Map[SessionTreeKey, Int] = Map([])
  let folded : Array[(Array[Int], SessionTreeKey, SessionListItem)] = []
  for item in items {
    match item.tree_fold_target(listed) {
      None => {
        row_at[item.tree_key(item.id)] = rows.length()
        rows.push({ item, children: [], })
      }
      Some((root, path)) => folded.push((path, root, item))
    }
  }
  // `sort_by` is unstable, so the root joins the key: children of different
  // parents never share a row, but the order must not depend on the sort.
  folded.sort_by((left, right) => {
    let ordering = compare_subrun_path(left.0, right.0)
    if ordering != 0 {
      ordering
    } else {
      let by_session = left.1.session.compare(right.1.session)
      if by_session != 0 {
        by_session
      } else {
        left.1.workspace.compare(right.1.workspace)
      }
    }
  })
  for entry in folded {
    let (_, root, item) = entry
    match row_at.get(root) {
      Some(index) => rows[index].children.push(item)
      // `fold_target` only walks through listed parents, so the root it
      // stops at owns a row. Unreachable, and a row rather than a drop if it
      // ever is reached: a session the store holds stays visible.
      None => rows.push({ item, children: [], })
    }
  }
  rows
}

///|
/// The `sr-N` a folded child row is labelled with, or `None` for a session
/// that is not a sub-run child. It names the sub-run the way the engine's
/// `subrun_started`/`subrun_finished` events do, so a row in the sidebar and
/// a line in the transcript are recognizably the same run.
pub fn subrun_label(id : String) -> String? {
  match @protocol.split_child_session_id(id) {
    Some((_, ordinal)) => Some("sr-\{ordinal}")
    None => None
  }
}

///|
/// The parent conversation a sub-run's child session belongs to, or `None`
/// for an ordinary session id. A sub-run id (`sr-N`) is only unique within
/// its parent engine, so anything routing a sub-run to a conversation needs
/// this and not the bare id.
pub fn subrun_parent(id : String) -> String? {
  match @protocol.split_child_session_id(id) {
    Some((parent, _)) => Some(parent)
    None => None
  }
}

///|
/// Every child session a sub-run tool result names, in first-appearance order.
/// `parent` is the session the result was recorded in, because an `sr-N` is
/// only unique within its own engine.
///
/// The contract is the `sr-N` the `explore`/`review`/`subtask` tools stamp into
/// their briefs. Every position is scanned rather than one fixed token: a
/// `subtask` launch reports its workers through one brief that leads with a
/// slice COUNT and carries the per-worker briefs — each with its own `sr-N` —
/// nested inside it (`cmd/openseek/subtask_tool.mbt::subtask_launch_many`), so
/// a single result can name several children and none of them at token 1.
///
/// A brief is display-only metadata — the model never sees one — so reading it
/// here cannot change what a run did, and a brief naming nothing yields no
/// link.
///
/// Ordinals are bounded exactly as `@protocol.split_child_session_id` bounds
/// them, so every id this returns is one that parser reads back: this is the
/// inverse of `subrun_label`, which turns such an id into the `sr-N` a sidebar
/// row shows.
pub fn subrun_child_sessions(
  tool_name : String,
  brief : String,
  parent~ : String,
) -> Array[String] {
  guard tool_name is ("explore" | "review" | "subtask") else { return [] }
  guard !parent.is_empty() else { return [] }
  let children : Array[String] = []
  for raw in brief.split(" ") {
    // A brief carrying several children joins them with punctuation, so a
    // token can arrive as `sr-3,` or `sr-3)`.
    let token = raw.trim(chars=",()").to_owned()
    guard token.has_prefix("sr-") else { continue }
    let digits = token.view(start_offset=3)
    guard !digits.is_empty() &&
      digits.length() <= 9 &&
      digits.iter().all(c => c.is_ascii_digit()) else {
      continue
    }
    let child = "\{parent}-\{token}"
    if !children.contains(child) {
      children.push(child)
    }
  }
  children
}

///|
/// Order two sub-run ordinal paths: by ordinal at the first position they
/// differ, then by depth, so `sr-2` precedes `sr-10` and a child precedes
/// its own grandchildren.
fn compare_subrun_path(left : Array[Int], right : Array[Int]) -> Int {
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shared {
    if left[index] < right[index] {
      return -1
    }
    if left[index] > right[index] {
      return 1
    }
  }
  left.length().compare(right.length())
}

///|
/// A decoded `session.load` reply: the transcript the snapshot renders as,
/// and the highest event sequence it contains — the client's starting
/// watermark, deciding which later `session.event` commits are already in
/// the snapshot. An explicit top-level watermark is authoritative; replies
/// from older hosts derive it from the maximum stored event sequence instead.
/// An empty record therefore remains at 0 in either shape.
pub struct SessionLoadView {
  items : Array[TranscriptItem]
  watermark : Int
  // The standing goal the snapshot's `[goal]` markers reduce to — the seed
  // the client's live marker commits then fold on top of.
  goal : GoalStanding?
  // Every goal marker this snapshot contains, with the sequence it committed
  // at. The reduced state alone cannot say whether a set or clear was
  // *recorded* here — re-asserting an unchanged goal, or clearing an
  // already-goalless session, reduces to exactly what was there before — so
  // a request in flight needs the markers themselves to find its own result.
  //
  // All of them, not the newest: a set can be followed by a block, or by
  // another set, before the reload ever happens, and the request still
  // completed. What moved the goal on afterwards is a different question
  // from whether this one was recorded.
  goal_markers : Array[(Int, GoalMarker)]
}

///|
/// Project a `load_session` reply into transcript
/// items plus its watermark, reconstructing what the live transcript showed
/// while the conversation was running: reasoning before the answer, tool
/// cards, runtime updates, and error bubbles for turns that did not finish.
pub fn session_from_reply(
  reply : @desktop_protocol.LoadSessionReply,
) -> SessionLoadView {
  let items : Array[TranscriptItem] = []
  let mut derived_watermark = 0
  let mut goal : GoalStanding? = None
  let goal_markers : Array[(Int, GoalMarker)] = []
  for event in reply.session.events.unwrap_or([]) {
    // Old desktop hosts return the store JSON verbatim without a top-level
    // watermark, but every stored event already carries its sequence. Derive
    // the same frontier from those entries so reconnecting through an older
    // host cannot roll a newer client's watermark back to zero.
    if event.sequence > derived_watermark {
      derived_watermark = event.sequence
    }
    ignore(
      apply_session_item(
        items,
        event.item,
        ts?=event.ts,
        sequence=event.sequence,
      ),
    )
    // The standing goal replays from the same durable markers the cards
    // above come from, so a resumed conversation shows exactly the goal the
    // engine holds — see `goal.mbt`.
    if event.item is @desktop_protocol.RuntimeNotice(notice) &&
      goal_marker(notice.content) is Some(marker) {
      goal = apply_goal_marker(goal, marker)
      goal_markers.push((event.sequence, marker))
    }
  }
  {
    items,
    watermark: reply.watermark.unwrap_or(derived_watermark),
    goal,
    goal_markers,
  }
}

///|
/// The items half of `session_from_reply`.
fn transcript_from_session(
  reply : @desktop_protocol.LoadSessionReply,
) -> Array[TranscriptItem] {
  session_from_reply(reply).items
}

///|
/// Project one durable session item — a `session.event` commit's
/// `{kind, payload}` — onto the transcript. Every event appends at most one
/// item, kept in the event's own shape; a tool result instead fills its call
/// inside the response that made it. Returns whether the visible transcript
/// changed. Unknown items deliberately change nothing: their event sequence
/// still advances the durable watermark, while their raw JSON stays available
/// to newer code. The same projector replays snapshots and live commits, so
/// both paths agree by construction. `ts` is the committing event's stamp,
/// carried onto the item it appends so the view can date a turn; a store (or
/// fixture) written without one leaves the item undated. `sequence` is the
/// committing event's sequence, likewise carried onto the appended item as
/// its durable identity.
pub fn apply_session_item(
  items : Array[TranscriptItem],
  item : @desktop_protocol.SessionItem,
  ts? : Double,
  sequence? : Int,
) -> Bool {
  let before = items.length()
  let mut updated_existing = false
  match item {
    @desktop_protocol.User(payload) => {
      let content = payload.content.trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: User(content), ts, sequence, })
      }
    }
    @desktop_protocol.Assistant(payload) => {
      let is_replay = payload.is_replay == Some(true)
      // Thinking-mode turns store the reasoning alongside the answer (the
      // store omits the field entirely otherwise). A checkpoint replay
      // already has its reasoning on the original durable provider response,
      // so it carries none here rather than duplicating that activity.
      let reasoning = if !is_replay &&
        payload.reasoning_content is Some(text) &&
        !text.is_blank() {
        Some(text.trim().to_owned())
      } else {
        None
      }
      // The store writes an empty string for a response that said nothing.
      let prose = if payload.content.is_blank() {
        None
      } else {
        Some(payload.content.trim().to_owned())
      }
      // Tool calls stay in the exact order the model emitted them. Their
      // results arrive as later durable events and fill them in by id.
      let calls : Array[ToolCall] = []
      for call in payload.tool_calls.unwrap_or([]) {
        calls.push({
          call_id: call.id,
          name: if call.name.is_blank() {
            "tool"
          } else {
            call.name
          },
          arguments: Some(call.arguments),
          outcome: Pending(output=None),
        })
      }
      if reasoning is Some(_) || prose is Some(_) || !calls.is_empty() {
        items.push({
          kind: Assistant(
            reasoning~,
            prose~,
            calls~,
            replay=is_replay,
            finished=false,
          ),
          ts,
          sequence,
        })
      }
    }
    @desktop_protocol.ToolResult(payload) => {
      // A result answers the still-pending call recorded with its id. The
      // engine appends every response before running its calls, so the call
      // is always on record; a result nothing is waiting for changes nothing,
      // exactly as the engine's own replay projection drops it.
      let mut index = items.length()
      while index > 0 {
        index -= 1
        guard items[index].kind
          is Assistant(reasoning~, prose~, calls~, replay~, finished~) else {
          continue
        }
        guard calls.search_by(call => {
            call.call_id == payload.tool_call_id && call.outcome is Pending(..)
          })
          is Some(position) else {
          continue
        }
        let call = calls[position]
        // The response keeps its own stamp and sequence: the call is dated
        // when the agent made it, not when its output came back.
        let filled = calls.copy()
        filled[position] = {
          ..call,
          name: if payload.tool_name.is_blank() {
            call.name
          } else {
            payload.tool_name
          },
          outcome: Done(
            content=payload.content,
            is_error=payload.is_error,
            brief=payload.brief,
          ),
        }
        items[index] = {
          ..items[index],
          kind: Assistant(reasoning~, prose~, calls=filled, replay~, finished~),
        }
        updated_existing = true
        break
      }
    }
    @desktop_protocol.RuntimeNotice(payload) =>
      if !payload.content.is_blank() {
        match goal_marker(payload.content) {
          // The set/clear/block/unblock markers are the durable goal
          // confirmations this view shows (the TUI renders the same news off
          // `goal_updated` instead). Single-line cards fold to a plain
          // label; a multi-line goal expands to its full text.
          Some(GoalSet(text)) =>
            items.push({
              kind: Notice(
                label="goal",
                brief=Some(goal_brief("Goal set", text)),
                is_error=false,
                body=goal_body(text),
              ),
              ts,
              sequence,
            })
          Some(GoalCleared) =>
            items.push({
              kind: Notice(
                label="goal",
                brief=Some("Goal cleared"),
                is_error=false,
                body=None,
              ),
              ts,
              sequence,
            })
          Some(GoalBlocked(reason)) =>
            items.push({
              kind: Notice(
                label="goal",
                brief=Some(goal_brief("Goal blocked", reason)),
                is_error=true,
                body=goal_body(reason),
              ),
              ts,
              sequence,
            })
          Some(GoalUnblocked) =>
            items.push({
              kind: Notice(
                label="goal",
                brief=Some("Goal resumed"),
                is_error=false,
                body=None,
              ),
              ts,
              sequence,
            })
          // What is left is either model-directed text — never a display
          // card — or a runtime notice the engine injected between turns
          // (a background-job completion, or a legacy `moon_check` block).
          None =>
            if !is_model_directed_notice(payload.content) {
              items.push({
                // Runtime notices keep the compact completed-result row used
                // by the old projection, but the generic label no longer
                // claims every background event came from `moon_check`.
                kind: Notice(
                  label="runtime notice",
                  brief=None,
                  is_error=false,
                  body=Some(payload.content),
                ),
                ts,
                sequence,
              })
            }
        }
      }
    @desktop_protocol.Summary(payload) => {
      let content = payload.content.trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: Summary(content), ts, sequence, })
      }
    }
    @desktop_protocol.Terminal(terminal) =>
      updated_existing = SessionTerminalProjection(terminal).append_to(
        items,
        ts?,
        sequence?,
      )
    @desktop_protocol.UnknownTerminal(_) => ()
    @desktop_protocol.Unknown(_) => ()
  }
  items.length() > before || updated_existing
}

///|
/// One typed terminal item projected into its optional final/error bubble.
priv struct SessionTerminalProjection(@desktop_protocol.SessionTerminal)

///|
fn SessionTerminalProjection::append_to(
  self : SessionTerminalProjection,
  items : Array[TranscriptItem],
  ts? : Double,
  sequence? : Int,
) -> Bool {
  let (kind, message) = match self.0 {
    @desktop_protocol.Finished(message) => ("finished", message)
    @desktop_protocol.Aborted(message) => ("aborted", message)
    @desktop_protocol.Interrupted(message) => ("interrupted", message)
    @desktop_protocol.Failed(message) => ("failed", message)
  }
  let message = message.trim().to_owned()
  match kind {
    // A current no-tool final is already the last provider response. Mark
    // that response finished instead of duplicating its prose; it keeps its
    // own stamp and sequence, so the settled bubble stays the same keyed node.
    "finished" =>
      if !message.is_empty() &&
        items is [.., last] &&
        last.kind
        is Assistant(
          reasoning~,
          prose=Some(prose),
          calls=[],
          replay=false,
          finished=false
        ) &&
        prose == message {
        items[items.length() - 1] = {
          ..last,
          kind: Assistant(
            reasoning~,
            prose=Some(prose),
            calls=[],
            replay=false,
            finished=true,
          ),
        }
        true
      } else {
        if !message.is_empty() {
          // A differing terminal message, such as a completion-tool answer,
          // remains a new final bubble.
          items.push({ kind: Answer(message), ts, sequence, })
        }
        false
      }
    "aborted" => {
      items.push({
        kind: Failure(
          if message.is_empty() {
            "aborted"
          } else {
            "aborted: \{message}"
          },
        ),
        ts,
        sequence,
      })
      false
    }
    "interrupted" => {
      items.push({
        kind: Failure(
          if message.is_empty() {
            "cancelled"
          } else {
            "cancelled: \{message}"
          },
        ),
        ts,
        sequence,
      })
      false
    }
    "failed" => {
      items.push({
        kind: Failure(if message.is_empty() { "failed" } else { message }),
        ts,
        sequence,
      })
      false
    }
    _ => false
  }
}

///|
/// The one-line summary a goal card folds to: the marker's first line,
/// marked when more follow.
fn goal_brief(label : String, text : String) -> String {
  if text.split_once("\n") is Some((first, _)) {
    "\{label}: \{first.to_owned()} …"
  } else {
    "\{label}: \{text}"
  }
}

///|
/// A single-line goal is fully carried by its brief — with no body the card
/// stays a plain label instead of an expandable fold around a duplicate.
fn goal_body(text : String) -> String? {
  if text.contains("\n") {
    Some(text)
  } else {
    None
  }
}

// Tests for decoding the host's session replies: the sidebar list and the
// durable-session-to-transcript mapping.

///|
test "session list projection preserves grouping and skips empty ids" {
  let items = sessions_from_reply(
    {
      groups: [
        {
          workspace: "/home/user/first",
          name: "first",
          session_root: "/home/user/first/.openseek",
          error: "",
          sessions: [
            {
              id: "desktop-b",
              title: Some("newest"),
              updated_at_ms: Some(2.0),
            },
            { id: "", title: Some("no id"), updated_at_ms: None, },
          ],
        },
        {
          workspace: "/home/user/proj",
          name: "proj",
          session_root: "/home/user/proj/.openseek",
          error: "",
          sessions: [{ id: "tui-a", title: Some(""), updated_at_ms: None, }],
        },
      ],
    },
    @interop.ChannelId::Local,
  )
  inspect(items.length(), content="2")
  inspect(items[0].id, content="desktop-b")
  assert_true(items[0].title is Some("newest"))
  assert_true(items[0].updated_at_ms is Some(2.0))
  inspect(items[0].workspace.path, content="/home/user/first")
  inspect(items[1].id, content="tui-a")
  // The engine always writes `title`; "" is its value for a session with no
  // user message yet.
  assert_true(items[1].title is Some(""))
  inspect(items[1].workspace.path, content="/home/user/proj")
  inspect(items[1].workspace_name, content="proj")
}

///|
test "a group naming no readable workspace contributes no rows" {
  let items = sessions_from_reply(
    {
      groups: [
        {
          workspace: "",
          name: "",
          session_root: "/home/user/.openseek",
          error: "",
          sessions: [
            { id: "desktop-b", title: Some("newest"), updated_at_ms: None, },
          ],
        },
      ],
    },
    @interop.ChannelId::Local,
  )
  assert_true(items.is_empty())
}

///|
/// The store `listed` rows belong to. Valid by construction; a total fixture
/// keeps the tree tests free of a synthetic error effect.
fn listed_workspace(path : String) -> @common.Uri {
  match @resource.of_path(@interop.ChannelId::Local, path) {
    Some(root) => root
    None => @common.Uri::file(path)
  }
}

///|
/// Sidebar entries for `session_tree` tests: only the id distinguishes them.
fn listed(ids : Array[String]) -> Array[SessionListItem] {
  ids.map(id => {
    id,
    title: None,
    workspace: listed_workspace("/work"),
    workspace_name: "work",
    updated_at_ms: None,
  })
}

///|
/// A tree as `parent[child, …]` rows, so a case reads as the sidebar renders.
fn tree_shape(rows : Array[SessionTreeRow]) -> String {
  rows
  .map(row => {
    if row.children.is_empty() {
      row.item.id
    } else {
      "\{row.item.id}[\{row.children.map(child => child.id).join(", ")}]"
    }
  })
  .join(" ")
}

///|
test "sub-run transcripts fold under the conversation that launched them" {
  inspect(
    tree_shape(
      session_tree(
        listed(["desktop-a", "desktop-a-sr-1", "desktop-a-sr-2", "desktop-b"]),
      ),
    ),
    content="desktop-a[desktop-a-sr-1, desktop-a-sr-2] desktop-b",
  )
}

///|
test "session trees never fold children across stores" {
  guard @resource.of_path(@interop.ChannelId::Local, "/project")
    is Some(project) else {
    fail("test project path was invalid")
  }
  let other_parent = listed(["same"])[0]
  let project_parent : SessionListItem = {
    ..other_parent,
    workspace: project,
    workspace_name: "project",
  }
  let project_child : SessionListItem = { ..project_parent, id: "same-sr-1", }
  let rows = session_tree([other_parent, project_parent, project_child])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].item.workspace, other_parent.workspace)
  assert_true(rows[0].children.is_empty())
  assert_eq(rows[1].item.workspace, project)
  assert_eq(rows[1].children.length(), 1)
  assert_eq(rows[1].children[0].id, project_child.id)
  assert_eq(rows[1].children[0].workspace, project_child.workspace)
}

///|
test "children sort by sub-run ordinal, not by id text" {
  // Listed out of order and past `sr-9`, where a lexicographic sort would
  // put `sr-10` between `sr-1` and `sr-2`.
  inspect(
    tree_shape(session_tree(listed(["a-sr-10", "a-sr-2", "a", "a-sr-1"]))),
    content="a[a-sr-1, a-sr-2, a-sr-10]",
  )
}

///|
test "a child whose parent is not listed keeps its own row" {
  // The parent is archived (the archived twin is a separate reply), so its
  // children are all this group holds — they stay visible, in place.
  inspect(
    tree_shape(session_tree(listed(["a-sr-1", "b", "a-sr-2"]))),
    content="a-sr-1 b a-sr-2",
  )
}

///|
test "a grandchild folds under the outermost listed ancestor" {
  inspect(
    tree_shape(session_tree(listed(["a", "a-sr-1", "a-sr-1-sr-2"]))),
    content="a[a-sr-1, a-sr-1-sr-2]",
  )
  // The walk is link by link: with the middle generation missing from the
  // group, the grandchild keeps a row rather than jumping a gap.
  inspect(
    tree_shape(session_tree(listed(["a", "a-sr-1-sr-2"]))),
    content="a a-sr-1-sr-2",
  )
}

///|
test "a sub-run's progress routes by its child session, not its bare id" {
  // `sr-1` is only unique inside its parent engine, so the child session id
  // is what names the conversation a progress push belongs to.
  assert_eq(subrun_parent("desktop-a-sr-1"), Some("desktop-a"))
  assert_eq(subrun_parent("desktop-b-sr-1"), Some("desktop-b"))
  // An ordinary session is nobody's child, so nothing routes to it.
  assert_eq(subrun_parent("desktop-a"), None)
}

///|
test "a sub-run brief names the child sessions its card links to" {
  // The stamp `agent_explore` writes: `"<tool> sr-N (…)"`.
  assert_eq(
    subrun_child_sessions(
      "explore",
      "explore sr-2 (1 citation(s), 7 step(s))",
      parent="run",
    ),
    ["run-sr-2"],
  )
  assert_eq(
    subrun_child_sessions("review", "review sr-11 (ok)", parent="desktop-a"),
    ["desktop-a-sr-11"],
  )
  // Round-trips with the inverse: the id this yields is the id whose row is
  // labelled with the `sr-N` the brief carried.
  assert_eq(subrun_label("run-sr-2"), Some("sr-2"))
  assert_eq(subrun_parent("run-sr-2"), Some("run"))
}

///|
test "a subtask launch names every worker it started" {
  // `subtask_launch_many` leads with a slice COUNT and nests the per-worker
  // briefs — each with its own `sr-N` — inside one brief. Scanning one fixed
  // token would find the count and link nothing, even for a single slice.
  assert_eq(
    subrun_child_sessions(
      "subtask",
      "subtask 1 slices (subtask sr-3 alpha (captured, 7 step(s)))",
      parent="run",
    ),
    ["run-sr-3"],
  )
  assert_eq(
    subrun_child_sessions(
      "subtask",
      "subtask 2 slices (subtask sr-3 a (captured), subtask sr-4 b (captured))",
      parent="run",
    ),
    ["run-sr-3", "run-sr-4"],
  )
  // The same child named twice is one child.
  assert_eq(
    subrun_child_sessions("subtask", "subtask sr-3 a sr-3 b", parent="run"),
    ["run-sr-3"],
  )
}

///|
test "a brief that does not name a sub-run yields no link" {
  // Not a sub-run tool, however the brief happens to read.
  assert_eq(subrun_child_sessions("read", "read sr-2", parent="run"), [])
  // The tool is right but the brief names no child.
  assert_eq(subrun_child_sessions("explore", "explore", parent="run"), [])
  assert_eq(
    subrun_child_sessions("explore", "explore (budget exhausted)", parent="run"),
    [],
  )
  // `sr-` with nothing, or with something that is not an ordinal, is not a
  // sub-run id — linking on it would offer a session that cannot exist.
  assert_eq(subrun_child_sessions("explore", "explore sr- (x)", parent="run"), [])
  assert_eq(
    subrun_child_sessions("explore", "explore sr-x (x)", parent="run"),
    [],
  )
  assert_eq(
    subrun_child_sessions("explore", "explore sr-2x (x)", parent="run"),
    [],
  )
  // Bounded exactly as `split_child_session_id` bounds it, so this never
  // offers an id that parser refuses to read back.
  assert_eq(
    subrun_child_sessions("explore", "explore sr-1234567890 (x)", parent="run"),
    [],
  )
  assert_eq(subrun_parent("run-sr-1234567890"), None)
  // An unsaved conversation has no id to hang a child off.
  assert_eq(subrun_child_sessions("explore", "explore sr-2 (x)", parent=""), [])
}

///|
test "an id that merely looks like a child keeps its row" {
  inspect(
    tree_shape(session_tree(listed(["a", "a-sr-x", "a-sr-"]))),
    content="a a-sr-x a-sr-",
  )
}

///|
fn session_reply(
  events_json : String,
) -> @desktop_protocol.LoadSessionReply raise {
  let prefix =
    #|{"session":{"version":1,"id":"desktop-x","system_prompt":"system","events":[
  let suffix =
    #|]}}
  @json.from_json(@json.parse(prefix + events_json + suffix))
}

///|
test "session load derives an old host's missing watermark from event sequences" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":4,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  let reply = session_reply(events)
  let view = session_from_reply(reply)
  inspect(view.watermark, content="4")
  inspect(view.items.length(), content="2")
}

///|
test "projected rows carry their event's stamp, tool rows the call's own" {
  let events =
    #|{"sequence":1,"ts":1781144351123,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"ts":1781144352000,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[{"id":"c1","name":"read","arguments":"{}"}]}}},
    #|{"sequence":3,"ts":1781144399000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"read","content":"out","is_error":false}}}
  let items = session_from_reply(session_reply(events)).items
  inspect(items.length(), content="2")
  assert_true(items[0].ts is Some(1781144351123))
  assert_true(items[0].sequence is Some(1))
  // The result filled the call inside its response; the response is dated
  // when the call was made, not when its output came back — and keeps that
  // event's sequence for the same reason.
  guard items[1].kind is Assistant(calls=[call], ..) else {
    fail("expected the response with its one call")
  }
  assert_true(call.outcome is Done(content="out", ..))
  assert_true(items[1].ts is Some(1781144352000))
  assert_true(items[1].sequence is Some(2))
}

///|
test "rows from a store written without stamps stay undated" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}}
  let items = session_from_reply(session_reply(events)).items
  assert_true(items[0].ts is None)
  // The stamp is optional in old stores; the sequence never is.
  assert_true(items[0].sequence is Some(1))
}

///|
test "an explicit session watermark remains authoritative" {
  let event =
    #|{"sequence":9,"item":{"kind":"user","payload":{"content":"question"}}}
  let reply = session_reply(event)
  let view = session_from_reply({ ..reply, watermark: Some(7), })
  inspect(view.watermark, content="7")
}

///|
test "session load keeps unknown items without hiding known transcript" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"item":{"kind":"future_item","payload":{"value":42},"future_field":true}},
    #|{"sequence":3,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[]}}}
  let reply = session_reply(events)
  let view = session_from_reply(reply)
  inspect(view.watermark, content="3")
  inspect(view.items.length(), content="2")
  assert_eq(view.items[0].text(), Some("question"))
  assert_eq(view.items[1].text(), Some("answer"))
}

///|
test "a terminal payload this build cannot read projects no row" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"future_terminal","message":"later"}}}
  let view = session_from_reply(session_reply(events))
  inspect(view.items.length(), content="1")
  // It is still durable content, so it still moves the watermark: the client
  // must not re-read the record looking for an event it already has.
  inspect(view.watermark, content="2")
}

///|
test "transcript mapping replays a finished conversation" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"  question  "}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"shell","content":"output","is_error":true,"brief":"ran ls → exit 1"}}},
    #|{"sequence":3,"ts":1000,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[],"reasoning_content":"thought"}}},
    #|{"sequence":4,"ts":2000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  let items = transcript_from_session(session_reply(events))
  // The result at sequence 2 answers no recorded call and is dropped.
  inspect(items.length(), content="2")
  guard items[0].kind is User(_) else { fail("expected user item") }
  assert_eq(items[0].text(), Some("question"))
  guard items[1].kind
    is Assistant(
      reasoning=Some(thought),
      prose=Some(_),
      calls=[],
      replay=false,
      finished=true
    ) else {
    fail("expected the terminal-confirmed answer with its reasoning")
  }
  inspect(thought, content="thought")
  assert_eq(items[1].text(), Some("answer"))
  // The confirming terminal leaves the response its own stamp and sequence.
  assert_true(items[1].ts is Some(1000))
  assert_true(items[1].sequence is Some(3))
}

///|
test "a finished turn marks only its last assistant message as final" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"ts":1000,"item":{"kind":"assistant","payload":{"content":"I will inspect it.","tool_calls":[{"id":"c1","name":"read","arguments":"{}"}]}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"read","content":"result","is_error":false}}},
    #|{"sequence":4,"ts":2000,"item":{"kind":"assistant","payload":{"content":"Done.","tool_calls":[]}}},
    #|{"sequence":5,"ts":3000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"Done."}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="3")
  guard items[1].kind is Assistant(calls=[call], finished=false, ..) else {
    fail("expected tool-prefacing narration to stay non-final")
  }
  assert_eq(items[1].text(), Some("I will inspect it."))
  assert_true(call.outcome is Done(..))
  guard items[2].kind is Assistant(calls=[], finished=true, ..) else {
    fail("expected only the last answer to be terminal-confirmed")
  }
  assert_eq(items[2].text(), Some("Done."))
  assert_true(items[2].ts is Some(2000))
}

///|
test "checkpoint assistant provenance projects without duplicate reasoning" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"kept answer","tool_calls":[],"reasoning_content":"old thought","is_replay":true}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
  guard items[0].kind is Assistant(reasoning=None, replay=true, ..) else {
    fail("expected a checkpoint replay without its reasoning")
  }
  assert_eq(items[0].text(), Some("kept answer"))
}

///|
test "tool results fill calls by id without changing call order" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"","tool_calls":[{"id":"c1","name":"read","arguments":"{\"path\":\"moon.mod\"}"},{"id":"c2","name":"shell","arguments":"{\"cmd\":\"moon test\"}"}]}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"c2","tool_name":"shell","content":"tests passed","is_error":false,"brief":"ran moon test"}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"","content":"module contents","is_error":false,"brief":"read moon.mod"}}}
  let view = session_from_reply(session_reply(events))
  let items = view.items
  inspect(items.length(), content="1")
  guard items[0].kind is Assistant(calls=[read, shell], ..) else {
    fail("expected one response carrying both calls in order")
  }
  inspect(read.call_id, content="c1")
  inspect(read.name, content="read")
  assert_true(read.arguments is Some("{\"path\":\"moon.mod\"}"))
  assert_true(
    read.outcome
    is Done(
      content="module contents",
      is_error=false,
      brief=Some("read moon.mod")
    ),
  )
  inspect(shell.call_id, content="c2")
  inspect(shell.name, content="shell")
  assert_true(shell.arguments is Some("{\"cmd\":\"moon test\"}"))
  assert_true(
    shell.outcome
    is Done(content="tests passed", is_error=false, brief=Some("ran moon test")),
  )
}

///|
test "a result no recorded call is waiting for changes nothing" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"","tool_calls":[{"id":"d","name":"read","arguments":"{\"path\":\"x\"}"}]}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"d","tool_name":"read","content":"one","is_error":false}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"d","tool_name":"read","content":"two","is_error":false}}}
  let view = session_from_reply(session_reply(events))
  let items = view.items
  inspect(items.length(), content="1")
  // The first result fills the call; the second answers nothing pending, so
  // it is dropped rather than shown as a call the model never made.
  guard items[0].kind is Assistant(calls=[call], ..) else {
    fail("expected the recorded call with its first result")
  }
  assert_true(call.outcome is Done(content="one", ..))
}

///|
test "transcript mapping deduplicates the finished answer" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[]}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
}

///|
test "transcript mapping renders non-finished terminals as error bubbles" {
  let events =
    #|{"sequence":1,"item":{"kind":"terminal","payload":{"kind":"interrupted","message":""}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"aborted","message":"the agent gave up"}}},
    #|{"sequence":3,"item":{"kind":"terminal","payload":{"kind":"failed","message":"engine error"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="3")
  guard items[0].kind is Failure(_) else { fail("expected error bubble") }
  assert_eq(items[0].text(), Some("cancelled"))
  assert_eq(items[1].text(), Some("aborted: the agent gave up"))
  assert_eq(items[2].text(), Some("engine error"))
}

///|
test "transcript mapping keeps summaries and background notices" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"earlier turns compacted","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"background job bg-1 finished (exit=0)"}}},
    #|{"sequence":3,"item":{"kind":"runtime_notice","payload":{"content":""}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is Summary(_) else { fail("expected summary") }
  guard items[1].kind
    is Notice(label="runtime notice", brief=None, is_error=false, ..) else {
    fail("expected runtime notice row")
  }
  assert_eq(items[1].text(), Some("background job bg-1 finished (exit=0)"))
}

///|
test "transcript mapping renders goal markers as cards and reduces the standing goal" {
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[goal baseline] sha=abc dirty=false"}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"[goal]\nship the feature"}}},
    #|{"sequence":3,"item":{"kind":"runtime_notice","payload":{"content":"[goal reminder]\nThe standing goal for this session:"}}},
    #|{"sequence":4,"item":{"kind":"runtime_notice","payload":{"content":"[goal blocked]\nneeds a decision"}}}
  let view = session_from_reply(session_reply(events))
  inspect(view.items.length(), content="2")
  guard view.items[0].kind
    is Notice(label="goal", is_error=false, brief=Some(set_brief), ..) else {
    fail("expected the set card")
  }
  inspect(set_brief, content="Goal set: ship the feature")
  // A single-line goal is fully carried by its brief; no expandable body.
  assert_true(view.items[0].text() is None)
  guard view.items[1].kind
    is Notice(label="goal", is_error=true, brief=Some(blocked_brief), ..) else {
    fail("expected the blocked card")
  }
  inspect(blocked_brief, content="Goal blocked: needs a decision")
  assert_true(
    view.goal
    is Some({ text: "ship the feature", blocked: Some("needs a decision"), }),
  )
  // Every goal marker, with its sequence — not just the newest. A client
  // waiting on that set has to be able to find it here even though a block
  // has moved the standing goal on since; keeping only the last one would
  // hand it the block and nothing else.
  inspect(view.goal_markers.length(), content="2")
  assert_true(view.goal_markers[0] == (2, GoalSet("ship the feature")))
  assert_true(view.goal_markers[1] == (4, GoalBlocked("needs a decision")))
  // The goal-family notices that are not markers stay out of it.
  assert_true(
    view.goal_markers.iter().all(entry => entry.0 != 1 && entry.0 != 3),
  )
}

///|
test "transcript mapping drops the plan reminder instead of carding it" {
  // The reminder is durable model-directed text, so without an explicit
  // exclusion it would surface as a notice card. The live path drops the
  // matching `plan_reminder` event.
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[plan reminder]\nUpdate the plan before continuing."}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"background job bg-2 finished (exit=1)"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
  guard items[0].kind
    is Notice(label="runtime notice", brief=None, is_error=false, ..) else {
    fail("expected only the runtime notice row")
  }
  assert_eq(items[0].text(), Some("background job bg-2 finished (exit=1)"))
}

///|
test "a cleared goal leaves cards but no standing goal" {
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[goal]\nline one\nline two"}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"[goal cleared]"}}}
  let view = session_from_reply(session_reply(events))
  inspect(view.items.length(), content="2")
  guard view.items[0].kind is Notice(label="goal", brief=Some(set_brief), ..) else {
    fail("expected the set card")
  }
  // A multi-line goal folds to its first line and expands to the full text.
  inspect(set_brief, content="Goal set: line one …")
  guard view.items[0].text() is Some(body) else {
    fail("expected the full goal text as the card's body")
  }
  inspect(
    body,
    content=(
      #|line one
      #|line two
    ),
  )
  guard view.items[1].kind is Notice(label="goal", brief=Some(cleared), ..) else {
    fail("expected the cleared card")
  }
  inspect(cleared, content="Goal cleared")
  assert_true(view.goal is None)
}

///|
test "transcript mapping replays a context checkpoint and yield guidance" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"checkpoint recap","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"[context ceiling] continue in a new turn"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is Summary(_) else { fail("expected checkpoint summary") }
  assert_eq(items[0].text(), Some("checkpoint recap"))
  guard items[1].kind is Answer(_) else {
    fail("expected context-yield guidance")
  }
  assert_eq(items[1].text(), Some("[context ceiling] continue in a new turn"))
}

///|
pub extend SessionTreeRow with Eq::{equal, not_equal}
