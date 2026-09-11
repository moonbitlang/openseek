///|
/// A minimal call retains presentation text and derived edit previews, never
/// raw parameters or output. Categories describe the operation, not its success.
priv struct MinimalCall {
  category : String?
  caption : String
  pending : Bool
  failed : Bool
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
    "webSearch" => Some("Search the web")
    "imageView" => Some("View images")
    "review" | "spawn_agent" => Some("Create subagents")
    "wait_agent" => Some("Wait for subagents")
    "plan" => Some("Update plan")
    "goal" => Some("Update goal")
    // Job coordination stays in the expanded history, not the work summary.
    "job_wait" | "job_output" | "job_stop" => None
    _ => Some("Other tool calls")
  }
  let (pending, failed, brief) = match call.outcome {
    Pending(..) => (true, false, None)
    Done(is_error~, brief~, ..) => (false, is_error, brief)
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
  { category, caption, pending, failed, changes, }
}

///|
/// The `description` argument a tool call was given, when its payload is a
/// readable object carrying one.
fn argument_description(call : @transcript.ToolCall) -> String? {
  guard call.arguments is Some(arguments) else { return None }
  let value = Some(@json.parse(arguments)) catch { _ => None }
  if value is Some({ "description": String(text), .. }) && !text.is_blank() {
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
priv enum MinimalContent {
  Prose(text~ : String, assistant~ : String, finished~ : Bool, live~ : Bool)
  Activity(Array[MinimalActivity])
  Note(text~ : String, error~ : Bool)
  ContextSummary(String)
  Completed(Array[MinimalPart])
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
  self.blocks.push({
    stream: self.stream,
    key: { value: "minimal\u{0}\{part.identity}", },
    content: Minimal(part.content),
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
            content: Prose(text~, assistant~, finished=true, live=false),
          })
        } else if prose is Some(text) && !text.is_blank() {
          builder.push_part(
            "prose\u{0}\{identity}",
            Prose(text~, assistant~, finished=false, live=false),
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
                wait_label?=pending_job_wait_label(
                  call,
                  descriptions~,
                  minimal=true,
                ),
              ),
            ),
          )
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
            content: Prose(text~, assistant~, finished=true, live=false),
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
  builder.finish(collapse=false)
  if self.streaming_response is Some(text) && !text.is_blank() {
    builder.push_block({
      identity: "live\u{0}\{self.streaming_identity}",
      content: Prose(text~, assistant~, finished=false, live=true),
    })
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
    Completed(parts) => {
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
  // While this group is working, show what is happening now rather than its
  // accumulated history. Prefer the newest pending call; a later completed
  // call must not hide another operation that is still running. A completed
  // turn always summarizes all its activity, even if an old call lacks a result.
  // This switch follows the group's pending calls, not the whole turn's end:
  // once this group settles, it shows categories while later prose continues.
  if self is Activity(entries) {
    let mut current : String? = None
    for entry in entries {
      if entry is Call(call) && call.pending {
        current = Some(call.caption)
      }
    }
    if current is Some(caption) {
      return caption
    }
  }
  let categories : Array[String] = []
  let mut failed = 0
  for entry in self.activities() {
    let category = match entry {
      Call(call) => {
        if call.failed {
          failed += 1
        }
        call.category
      }
      Notice(..) => None
    }
    if category is Some(label) && !categories.contains(label) {
      categories.push(label)
    }
  }
  if categories.is_empty() {
    categories.push(
      if self is Completed(_) {
        "Work completed"
      } else {
        "View activity"
      },
    )
  }
  if failed > 0 {
    categories.push(
      if failed == 1 {
        "1 tool call failed"
      } else {
        "\{failed} tool calls failed"
      },
    )
  }
  categories.join(" · ")
}

///|
fn MinimalContent::render(
  self : MinimalContent,
  actions : Actions,
) -> @html.Html {
  match self {
    ContextSummary(text) =>
      @html.details(class="minimal-context-summary", [
        self.summary_view(),
        @html.div(
          class="minimal-process-body msg-content markdown",
          @markdown.markdown_nodes(text, open_file=path => (actions.open)(path)),
        ),
      ])
    Prose(text~, assistant~, finished~, live~) =>
      assistant_message_view(
        text,
        path => (actions.open)(path),
        assistant,
        is_danger=false,
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
      let children : Array[@html.Html] = []
      for entry in entries {
        let child = match entry {
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
              class=if call.failed {
                "minimal-call failed"
              } else {
                "minimal-call"
              },
              [
                @html.span(class="minimal-call-caption", call.caption),
                if call.failed {
                  @html.span(class="minimal-call-status", "Failed")
                } else if call.pending {
                  @html.span(class="minimal-call-status", "Running…")
                } else {
                  @html.nothing
                },
                if call.changes is Some(changes) {
                  @html.div(
                    class="minimal-edit-changes",
                    attrs=@html.Attrs::build().aria_label("Requested changes"),
                    changes.render(minimal=true),
                  )
                } else {
                  @html.nothing
                },
              ],
            )
        }
        children.push(child)
      }
      // Show requested changes as soon as a readable edit arrives. The virtual
      // attribute stays true on result updates, preserving a reader's manual
      // collapse. A completed turn still hides this inside its outer disclosure.
      let show_changes = entries.any(entry => {
        match entry {
          Call(call) => call.changes is Some(_)
          Notice(..) => false
        }
      })
      @html.details(class="minimal-tools", open=show_changes, [
        self.summary_view(),
        @html.div(class="minimal-call-list", children),
      ])
    }
    Completed(parts) => {
      let children : Map[String, @html.Html] = Map([])
      for part in parts {
        children[part.identity] = part.content.render(actions)
      }
      @html.details(class="minimal-process", [
        self.summary_view(),
        @html.div(class="minimal-process-body", children),
      ])
    }
  }
}

///|
/// Keep native disclosure semantics while drawing the same chevron used by
/// application controls. The icon is decorative; the text names the toggle.
fn MinimalContent::summary_view(self : MinimalContent) -> @html.Html {
  @html.summary(class="minimal-activity-summary", [
    @html.span(
      class="minimal-chevron",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @icons.icon(@icons.icon_chevron_down),
    ),
    @html.span(self.summary()),
  ])
}
