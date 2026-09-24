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
/// The contract is the `sr-N` the `review` tool stamps into its brief. Every
/// position is scanned rather than one fixed token, so a brief that names
/// several children (a batch launch, say) links all of them, wherever the
/// ids sit.
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
  guard tool_name is "review" else { return [] }
  guard !parent.is_empty() else { return [] }
  let children : Array[String] = []
  for raw in brief.split(" ") {
    // A brief carrying several children joins them with punctuation, so a
    // token can arrive as `sr-3,` or `sr-3)`.
    let token = raw.trim(chars=",()")
    guard token.has_prefix("sr-") else { continue }
    let digits = token.view(start_offset=3)
    guard !digits.is_empty() &&
      digits.length() <= 9 &&
      digits.all(c => c.is_ascii_digit()) else {
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
  let shared = left.length().min(right.length())
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
      let content = match payload.content.0 {
        [Text(text)] => @deepseek.Content([Text(text.trim().to_owned())])
        _ => model_content(payload.content)
      }
      if !content.0.all(part => part is Text(text) && text.is_blank()) {
        items.push({ kind: User(content~), ts, sequence, })
      }
    }
    @desktop_protocol.Assistant(payload) => {
      let is_replay = payload.is_replay is Some(true)
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
      // Empty visible content contributes no prose to the transcript.
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
          children: [],
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
          children: program_calls(payload.data, call.call_id, origin=Recorded),
          outcome: Done(
            content=model_content(payload.content),
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
  let failure = match self.0 {
    // A current no-tool final is already the last provider response. Mark
    // that response finished instead of duplicating its prose; it keeps its
    // own stamp and sequence, so the settled bubble stays the same keyed node.
    @desktop_protocol.Finished(message) => {
      let message = message.trim().to_owned()
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
        return true
      }
      if !message.is_empty() {
        // A differing terminal message, such as a completion-tool answer,
        // remains a new final bubble.
        items.push({ kind: Answer(message), ts, sequence, })
      } else {
        items.push({ kind: TurnEnd, ts, sequence, })
      }
      return false
    }
    @desktop_protocol.Aborted(message) =>
      match message.trim().to_owned() {
        "" => "aborted"
        message => "aborted: \{message}"
      }
    @desktop_protocol.Interrupted(message) =>
      match message.trim() {
        "" => "cancelled"
        message => "cancelled: \{message}"
      }
    @desktop_protocol.Failed(message) =>
      match message.trim().to_owned() {
        "" => "failed"
        message => message
      }
  }
  items.push({ kind: Failure(failure), ts, sequence, })
  false
}

///|
/// The one-line summary a goal card folds to: the marker's first line,
/// marked when more follow.
fn goal_brief(label : String, text : String) -> String {
  if text.split_once("\n") is Some((first, _)) {
    "\{label}: \{first} …"
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
pub extend SessionTreeRow with Eq::{equal, not_equal}

///|
/// Project durable image bytes to inline URLs once, when building the transcript.
fn model_content(content : @protocol.Content) -> @deepseek.Content {
  @deepseek.Content(
    content.0.map(part => {
      match part {
        Text(text) => Text(text)
        Image(image) => ImageUrl(url=image.data_url())
      }
    }),
  )
}
