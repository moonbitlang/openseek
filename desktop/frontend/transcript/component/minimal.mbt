///|
/// A minimal call retains presentation text and derived edit previews, never
/// raw parameters or output. Categories describe the operation, not its success.
priv struct MinimalCall {
  tool_name : String
  category : String?
  caption : String
  status : ToolStatus
  changes : EditChanges?
} derive(Eq)

///|
fn MinimalCall::from_tool(
  call : @transcript.ToolCall,
  wait_label? : String,
) -> MinimalCall {
  // Categories come only from tool names. A description such as "Capture gh
  // pr list/view/diff/checks shapes" still belongs to Execute mbtx scripts;
  // descriptions name individual calls, without reclassifying their contents.
  let category = match call.name {
    "read" => Some("Read files")
    "edit" | "multi_edit" => Some("Edit files")
    "write" => Some("Write files")
    "remove" => Some("Remove files")
    "mbtx" => Some("Execute mbtx scripts")
    "shell" => Some("Execute commands")
    "web_search" | "webSearch" => Some("Search the web")
    "imageView" => Some("View images")
    "imageGeneration" => Some("Generate images")
    "enteredReviewMode" | "exitedReviewMode" => Some("Review code")
    "review" | "spawn_agent" => Some("Create subagents")
    "wait_agent" => Some("Wait for subagents")
    "send_input" | "send_message" => Some("Send messages to subagents")
    "resume_agent" => Some("Resume subagents")
    "followup_task" => Some("Assign subagent tasks")
    "interrupt_agent" => Some("Stop subagents")
    "close_agent" => Some("Close subagents")
    "list_agents" => Some("List subagents")
    "submit_result" | "submit_answer" | "submit_pattern_repair" =>
      Some("Submit results")
    "submit_review" => Some("Submit reviews")
    "plan" => Some("Update plan")
    "goal" => Some("Update goal")
    // Coordination and turn completion are not additional kinds of work.
    // These names come from the registered tools and the Codex adapter; keep
    // MCP/dynamic names namespaced so a foreign "read" cannot impersonate one.
    "job_wait" | "job_output" | "job_stop" | "finish" | "sleep" => None
    _ => Some("Other tool calls")
  }
  let status = ToolStatus::from_outcome(call.outcome)
  let brief = match call.outcome {
    Snapshot(..) => Some("Snapshot")
    Pending(..) => None
    Done(brief~, ..) => brief
  }
  // Codex briefs a shell call with its command line, which is an argument,
  // not a description; the tool name stands in for it here.
  let brief = if call.name != "shell" && brief is Some(text) && !text.is_blank() {
    Some(text)
  } else {
    None
  }
  // An mbtx brief usually reports only an exit code, so its human-written
  // description stays visible after completion, just as while the script is
  // running. Other tools keep their brief without parsing large arguments.
  let caption = if wait_label is Some(text) {
    text
  } else if call.name == "mbtx" && argument_description(call) is Some(text) {
    text
  } else if brief is Some(text) {
    text
  } else if call.name != "mbtx" && argument_description(call) is Some(text) {
    text
  } else {
    call.name
  }
  let changes = if call.arguments is Some(arguments) {
    EditChanges::from_arguments(call.name, arguments)
  } else {
    None
  }
  { tool_name: call.name, category, caption, status, changes, }
}

///|
/// Tool identities stay independent of descriptions and success/failure status.
/// Use the same monochrome Codicons as app controls; status stays on the right.
fn MinimalCall::icon(self : MinimalCall) -> @html.Html {
  match self.tool_name {
    "read" => @icons.icon_book()
    "edit" => @icons.icon_edit()
    "multi_edit" => @icons.icon_diff_multiple()
    "write" => @icons.icon_file()
    "remove" => @icons.icon_trash()
    "mbtx" => @icons.icon_terminal()
    "shell" => @icons.icon_terminal()
    "web_search" | "webSearch" => @icons.icon_search()
    "imageView" => @icons.icon_file_media()
    "imageGeneration" => @icons.icon_sparkle()
    "enteredReviewMode" | "exitedReviewMode" | "submit_review" =>
      @icons.icon_search()
    "review" | "spawn_agent" => @icons.icon_robot()
    "wait_agent" | "job_wait" => @icons.icon_watch()
    "send_input" | "send_message" => @icons.icon_comment()
    "resume_agent" => @icons.icon_play()
    "followup_task" => @icons.icon_send()
    "interrupt_agent" | "job_stop" => @icons.icon_debug_stop()
    "close_agent" => @icons.icon_debug_stop()
    "list_agents" => @icons.icon_organization()
    "submit_result" | "submit_answer" | "submit_pattern_repair" =>
      @icons.icon_chat_export()
    "plan" => @icons.icon_tasklist()
    "goal" => @icons.icon_target()
    "job_output" => @icons.icon_arrow_down()
    "finish" => @icons.icon_check()
    "sleep" => @icons.icon_watch()
    _ => @icons.icon_tools()
  }
}

///|
/// A folded group uses its first call's icon; individual calls keep their own.
fn MinimalContent::icon(self : MinimalContent) -> @html.Html {
  if self is ContextSummary(_) {
    return @icons.icon_pin()
  }
  for entry in self.activities() {
    if entry is Call(call) {
      return call.icon()
    }
  }
  @icons.icon_comment()
}

///|
/// The `description` argument a tool call was given, when its payload is a
/// readable object carrying one. Use the same pre-parse payload ceiling as
/// detailed cards: a brief must not require parsing an arbitrarily large script.
fn argument_description(call : @transcript.ToolCall) -> String? {
  guard call.arguments is Some(arguments) else { return None }
  guard card_fields(arguments) is Some(fields) else { return None }
  if fields.get("description") is Some(String(text)) && !text.is_blank() {
    Some(text)
  } else {
    None
  }
}

///|
priv struct MinimalPart {
  identity : String
  content : MinimalContent
} derive(Eq)

///|
/// Background notifications share the ordered work log, but are not tool
/// calls and must never increase the failed-tool count.
priv enum MinimalActivity {
  Call(MinimalCall)
  Notice(text~ : String, error~ : Bool)
} derive(Eq)

///|
/// Count pending and failed calls represented by a group, including waits.
/// Notices are not tool rows, and successful calls need no minimal status.
priv struct MinimalToolStatus {
  failed : Int
  pending : Int
}

///|
fn MinimalToolStatus::from_activities(
  entries : Array[MinimalActivity],
) -> MinimalToolStatus {
  let mut failed = 0
  let mut pending = 0
  for entry in entries {
    if entry is Call(call) {
      match call.status {
        Pending => pending += 1
        Failed => failed += 1
        Succeeded | Snapshot => ()
      }
    }
  }
  { failed, pending, }
}

///|
/// A failed call must not hide another call still running. Keep both indicators
/// until the group settles, and use the same icons as the detailed tool rows.
/// Successful groups stay quiet in minimal mode, without an empty status slot.
fn MinimalToolStatus::view(self : MinimalToolStatus) -> @html.Html {
  if self.pending == 0 && self.failed == 0 {
    return @html.nothing
  }
  let children : Array[@html.Html] = []
  if self.pending > 0 {
    children.push(ToolStatus::Pending.view())
  }
  if self.failed > 0 {
    let label = if self.failed == 1 {
      "1 tool call failed"
    } else {
      "\{self.failed} tool calls failed"
    }
    children.push(@html.span(class="minimal-failure-count", title=label, label))
    children.push(ToolStatus::Failed.view())
  }
  @html.span(class="minimal-tool-status", children)
}

///|
priv enum MinimalContent {
  Prose(
    text~ : String,
    assistant~ : String,
    finished~ : Bool,
    live~ : Bool,
    // The durable commit instant of the item this prose came from, shown
    // beside the copy action on a finished answer exactly as detailed mode's
    // completion stamp is. `None` for prose still inside the process, for a
    // context-ceiling answer an older store left unstamped, and for the live
    // streaming bubble.
    completed_at~ : Double?
  )
  Activity(Array[MinimalActivity])
  Note(text~ : String, error~ : Bool)
  ContextSummary(String)
  Completed(Array[MinimalPart])
  Messages(Array[MinimalPart], active_group~ : String?)
} derive(Eq)

///|
/// This accumulator exists only while projecting an input. None of its mutable
/// arrays is shared with application state or with a previous render.
priv struct MinimalStream {
  stream : TranscriptSectionKey
  blocks : Array[Block]
  mut sections : Array[MinimalSection]
  mut parts : Array[MinimalPart]
}

///|
priv enum MinimalSection {
  User(row~ : VisibleRow, anchor~ : String)
  Process(Array[MinimalPart])
  // A context checkpoint is independently expandable, regardless of whether
  // its producer records it before or after the turn's terminal guidance.
  Checkpoint(MinimalPart)
}

///|
fn MinimalStream::flush_parts(self : MinimalStream) -> Unit {
  if !self.parts.is_empty() {
    self.sections.push(Process(self.parts))
    self.parts = []
  }
}

///|
fn MinimalStream::push_part(
  self : MinimalStream,
  identity : String,
  content : MinimalContent,
) -> Unit {
  // Tool calls and background notifications remain one ordered work group.
  // Only prose or user messages interrupt the group.
  if content is Activity(entries) &&
    self.parts is [.., last] &&
    last.content is Activity(previous) {
    self.parts[self.parts.length() - 1] = {
      ..last,
      content: Activity([..previous, ..entries]),
    }
  } else {
    self.parts.push({ identity, content, })
  }
}

///|
fn MinimalStream::push_block(self : MinimalStream, part : MinimalPart) -> Unit {
  // User rows delimit outer message groups. Keep all assistant content,
  // including live text and the final answer, inside that group's layout.
  // These arrays belong only to this projection, never a previous render.
  if self.blocks is [.., { content: Minimal(Messages(parts, ..)), .. }] {
    parts.push(part)
    return
  }
  self.blocks.push({
    stream: self.stream,
    // Anchor the group to its preceding user, not its first child: that child
    // becomes a Completed disclosure at final, while sibling checkpoints and
    // their browser-owned expansion state must survive.
    key: if self.blocks is [.., previous] {
      { value: "minimal-messages\u{0}\{previous.key.wire()}", }
    } else {
      { value: "minimal-messages", }
    },
    content: Minimal(Messages([part], active_group=None)),
  })
}

///|
/// Only an explicit final answer collapses the preceding process. User inputs
/// split disclosures without ending a turn. A stop, failure, or empty success
/// flushes the same process unfolded, fencing it off from the next turn.
fn MinimalStream::finish(self : MinimalStream, collapse~ : Bool) -> Unit {
  self.flush_parts()
  for section in self.sections {
    match section {
      Checkpoint(part) => self.push_block(part)
      User(row~, anchor~) =>
        self.blocks.push({
          stream: self.stream,
          key: { value: "minimal-user\u{0}\{row.identity}", },
          content: Item(
            item=row.item,
            anchor=Some(anchor),
            step_label=None,
            assistant_name="Assistant",
            subrun_parent=None,
            wait_labels=Map([]),
          ),
        })
      Process(parts) =>
        if collapse && parts is [first, ..] {
          self.push_block({
            identity: "completed\u{0}\{first.identity}",
            content: Completed(parts),
          })
        } else {
          for part in parts {
            self.push_block(part)
          }
        }
    }
  }
  self.sections = []
}

///|
fn Input::minimal_blocks(self : Input) -> @vector.Vector[Block] {
  let builder : MinimalStream = {
    stream: TranscriptSectionKey::stream(self),
    blocks: [],
    sections: [],
    parts: [],
  }
  let assistant = self.source.assistant_name()
  let descriptions : Map[String, String] = Map([])
  for index, row in self.items {
    let identity = row.identity
    match row.item.kind {
      User(_) => {
        builder.flush_parts()
        builder.sections.push(
          User(
            row~,
            anchor=@transcript_overview.TurnKey::of(row.item, index~).anchor(),
          ),
        )
      }
      Assistant(prose~, calls~, finished~, ..) => {
        if finished && prose is Some(text) && !text.is_blank() {
          builder.finish(collapse=true)
          builder.push_block({
            identity: "final\u{0}\{identity}",
            content: Prose(
              text~,
              assistant~,
              finished=true,
              live=false,
              completed_at=row.item.ts,
            ),
          })
        } else if prose is Some(text) && !text.is_blank() {
          builder.push_part(
            "prose\u{0}\{identity}",
            Prose(
              text~,
              assistant~,
              finished=false,
              live=false,
              completed_at=None,
            ),
          )
        }
        // Reuse detailed mode's recorded job names, scoped to this transcript.
        for call in calls {
          collect_job_description(call, descriptions)
        }
        let activity : Array[MinimalActivity] = []
        for call in calls {
          // Successful waits are coordination, not additional completed work.
          // Keep failed waits visible and counted; a wait result alone must
          // never be interpreted as a successful completion of its target job.
          if call.name == "job_wait" && call.outcome is Done(is_error=false, ..) {
            continue
          }
          activity.push(
            Call(
              MinimalCall::from_tool(
                call,
                wait_label?=pending_job_wait_label(call, descriptions~),
              ),
            ),
          )
          // Program calls are recorded under their parent. Preserve their
          // status and edit previews in the minimal work log as well.
          for child in call.children {
            activity.push(Call(MinimalCall::from_tool(child)))
          }
        }
        if !activity.is_empty() {
          builder.push_part("tools\u{0}\{identity}", Activity(activity))
        }
      }
      Answer(text) => {
        builder.finish(collapse=!text.is_blank())
        if !text.is_blank() {
          builder.push_block({
            identity: "final\u{0}\{identity}",
            content: Prose(
              text~,
              assistant~,
              finished=true,
              live=false,
              completed_at=row.item.ts,
            ),
          })
        }
      }
      TurnEnd => builder.finish(collapse=false)
      Failure(text) => {
        builder.finish(collapse=false)
        builder.push_block({
          identity: "failure\u{0}\{identity}",
          content: Note(text~, error=true),
        })
      }
      Notice(label~, brief~, is_error~, body~) => {
        let text = brief.unwrap_or(body.unwrap_or(label))
        builder.push_part(
          "notice\u{0}\{identity}",
          if label == "runtime notice" {
            Activity([Notice(text~, error=is_error)])
          } else {
            Note(text~, error=is_error)
          },
        )
      }
      Summary(text) => {
        builder.flush_parts()
        builder.sections.push(
          Checkpoint({
            identity: "summary\u{0}\{identity}",
            content: ContextSummary(text),
          }),
        )
      }
    }
  }
  // Only the group after the newest assistant prose is current. Explicit
  // terminal events already flushed parts; streamed prose also ends that group.
  let mut active_group : String? = None
  if !(self.streaming_response is Some(text) && !text.is_blank()) {
    for part in builder.parts {
      match part.content {
        Prose(..) => active_group = None
        Activity(entries) =>
          if entries.any(entry => entry is Call(_)) {
            active_group = Some(part.identity)
          }
        // A background notice does not start a new assistant message.
        _ => ()
      }
    }
  }
  builder.finish(collapse=false)
  if self.streaming_response is Some(text) && !text.is_blank() {
    builder.push_block({
      identity: "live\u{0}\{self.streaming_identity}",
      content: Prose(
        text~,
        assistant~,
        finished=false,
        live=true,
        completed_at=None,
      ),
    })
  }
  if active_group is Some(_) &&
    builder.blocks is [.., last] &&
    last.content is Minimal(Messages(parts, ..)) {
    builder.blocks[builder.blocks.length() - 1] = {
      ..last,
      content: Minimal(Messages(parts, active_group~)),
    }
  }
  if builder.blocks.is_empty() &&
    self.items.is_empty() &&
    self.streaming_response is None &&
    self.streaming_reasoning is None {
    builder.blocks.push({
      stream: builder.stream,
      key: TranscriptRenderKey::empty(),
      content: Empty(self.empty_content()),
    })
  }
  @vector.from_array(builder.blocks)
}

///|
/// Aggregate only the work actually represented by this disclosure, retaining
/// the distinction between calls and notifications.
fn MinimalContent::activities(self : MinimalContent) -> Array[MinimalActivity] {
  match self {
    Activity(entries) => entries
    Completed(parts) | Messages(parts, ..) => {
      let entries : Array[MinimalActivity] = []
      for part in parts {
        entries.append(part.content.activities())
      }
      entries
    }
    _ => []
  }
}

///|
fn MinimalContent::summary(self : MinimalContent) -> String {
  if self is ContextSummary(_) {
    return "Context summary"
  }
  // Preview the first three concrete operations in transcript order, including
  // failed calls and repeated captions. Outcome does not affect preview slots.
  // Signal omitted operations; status counts are rendered separately at the
  // right, where truncating this preview cannot hide them.
  let captions : Array[String] = []
  let mut more = false
  for entry in self.activities() {
    if entry is Call(call) {
      // Coordination and background notices do not consume preview slots.
      if call.category is Some(_) {
        if captions.length() < 3 {
          captions.push(call.caption)
        } else {
          more = true
        }
      }
    }
  }
  if captions.is_empty() {
    captions.push(
      if self is Completed(_) {
        "Work completed"
      } else {
        "View activity"
      },
    )
  }
  if more {
    captions.push("…")
  }
  captions.join(" · ")
}

///|
/// Render an operation identically inside a live tool group or directly inside
/// a completed process with only one group. This preserves statuses and edits
/// when the redundant inner disclosure is omitted.
fn MinimalActivity::render(
  self : MinimalActivity,
  single? : Bool = false,
) -> @html.Html {
  match self {
    Notice(text~, error~) =>
      @html.div(
        class=if error {
          "minimal-note transcript-error-message"
        } else {
          "minimal-note"
        },
        text,
      )
    Call(call) =>
      @html.div(
        class=if single {
          if call.status is Failed {
            "minimal-call minimal-single-call failed"
          } else {
            "minimal-call minimal-single-call"
          }
        } else if call.status is Failed {
          "minimal-call failed"
        } else {
          "minimal-call"
        },
        [
          @html.span(
            class="minimal-tool-icon",
            attrs=@html.Attrs::build().aria_hidden("true").title(call.tool_name),
            call.icon(),
          ),
          @html.span(
            class="minimal-call-caption",
            title=call.caption,
            call.caption,
          ),
          if single {
            MinimalToolStatus::from_activities([self]).view()
          } else if call.status is (Succeeded | Snapshot) {
            // Expanded calls follow the same quiet-success rule as summaries.
            @html.nothing
          } else {
            call.status.view()
          },
          if call.changes is Some(changes) {
            @html.div(
              class="minimal-edit-changes",
              attrs=@html.Attrs::build().aria_label("Requested changes"),
              changes.render(),
            )
          } else {
            @html.nothing
          },
        ],
      )
  }
}

///|
fn MinimalContent::render(
  self : MinimalContent,
  actions : Actions,
  active? : Bool = false,
) -> @html.Html {
  match self {
    Messages(parts, active_group~) => {
      // Preserve each child's identity while tool outcomes and live prose
      // update. Grouping must not recreate an already-open tool disclosure.
      let children : Map[String, @html.Html] = Map([])
      for part in parts {
        children[part.identity] = part.content.render(
          actions,
          active=active_group is Some(identity) && identity == part.identity,
        )
      }
      @html.div(class="minimal-messages minimal-rows", children)
    }
    ContextSummary(text) =>
      @html.details(class="minimal-context-summary", [
        self.summary_view(),
        @html.div(
          class="minimal-process-body msg-content markdown",
          @markdown.markdown_nodes(text, open_file=path => (actions.open)(path)),
        ),
      ])
    Prose(text~, assistant~, finished~, live~, completed_at~) =>
      assistant_message_view(
        text,
        path => (actions.open)(path),
        assistant,
        is_danger=false,
        completed_at?,
        show_actions=finished,
        streaming=live,
      )
    Note(text~, error~) =>
      @html.div(
        class=if error {
          "minimal-note transcript-error-message"
        } else {
          "minimal-note"
        },
        text,
      )
    Activity(entries) => {
      // A single call has nothing to summarize separately. Render its caption
      // once, including running/failed status and any requested edit preview.
      // This also applies inside a completed process that contains prose.
      if entries is [Call(call)] {
        return MinimalActivity::Call(call).render(single=true)
      }
      if active {
        return @html.div(
          class="minimal-tools-live minimal-rows",
          entries.map(entry => entry.render()),
        )
      }
      // Earlier groups start folded once a new assistant message arrives.
      @html.details(class="minimal-tools", [
        self.summary_view(),
        @html.div(
          class="minimal-call-list",
          entries.map(entry => entry.render()),
        ),
      ])
    }
    Completed(parts) => {
      // Neither the process nor its only tool group needs a disclosure when
      // they contain just one call. Keep the same row before and after final.
      if parts is [{ content: Activity([Call(call)]), .. }] {
        return MinimalActivity::Call(call).render(single=true)
      }
      // One group needs only the outer disclosure. Mixed prose and
      // tool groups retain their individual folds, with completed summaries.
      let body = if parts is [{ content: Activity(entries), .. }] {
        @html.div(
          class="minimal-process-body minimal-rows",
          entries.map(entry => entry.render()),
        )
      } else {
        let children : Map[String, @html.Html] = Map([])
        for part in parts {
          children[part.identity] = part.content.render(actions)
        }
        @html.div(class="minimal-process-body minimal-rows", children)
      }
      @html.details(class="minimal-process", [self.summary_view(), body])
    }
  }
}

///|
/// Keep native disclosure semantics while drawing the same chevron used by
/// application controls. The icon is decorative; the text names the toggle.
fn MinimalContent::summary_view(self : MinimalContent) -> @html.Html {
  let text = self.summary()
  @html.summary(class="minimal-activity-summary", [
    @html.span(
      class="minimal-tool-icon",
      attrs=@html.Attrs::build().aria_hidden("true"),
      self.icon(),
    ),
    @html.span(class="minimal-summary-text", title=text, text),
    @html.span(
      class="minimal-chevron",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @icons.icon(@icons.icon_chevron_down),
    ),
    MinimalToolStatus::from_activities(self.activities()).view(),
  ])
}
