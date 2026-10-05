// `subagent_status` and `subagent_send`: how the agent that delegated work
// watches its subagents and talks to them while they run.
//
// A workflow snippet prints nothing until its children report, so without
// these the delegating agent's only moves are to wait or to stop the whole
// job. Both tools work from the session store alone: a child's transcript is
// the sibling session `<parent>-sr-N`, and its inbox is a file beside that
// transcript (`agent_subrun/inbox`). Nothing here talks to a child process —
// which is why it works the same for a child a snippet launched and for one
// the engine launched itself.

///|
/// How many trailing transcript events one status shows.
const RecentEvents : Int = 8

///|
/// How many instructions may wait untaken in one subagent's inbox. A parent
/// that keeps posting to a child that is not reading is not steering it.
const MaxWaiting : Int = 8

///|
/// The two tools for the durable session `parent` stored under
/// `session_root`: read a subagent's progress, and post it a new instruction.
pub fn definitions(
  session_root~ : String,
  parent~ : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  let store = @store.SessionStore(session_root)
  [
    AgentToolDefinition(
      name="subagent_status",
      description=(
        #|Look at the subagents this conversation started (the children of a
        #|`subrun` workflow): what each was asked, whether it is still working, how
        #|many steps it has taken, and its most recent actions. Without `id` it
        #|lists every subagent in one line each; with `id` (for example "sr-2") it
        #|shows that one's recent transcript and where each instruction you sent
        #|stands: waiting (not taken yet), delivered (in its transcript, no model
        #|response recorded after it yet), or seen (a model response followed it —
        #|which is not the same as obeyed). Reads immediately; it does not wait. A
        #|subagent with no end recorded and no activity for minutes was probably cut
        #|off. Use it while a workflow job runs to check that a scout is on the right
        #|track, and subagent_send to correct one that is not.
      ),
      schema=JsonSchema({
        "type": "object",
        "properties": {
          "id": {
            "type": "string",
            "description": "A subagent id such as \"sr-2\". Omit to list all of them.",
          },
        },
      }),
      execute=Async(arguments => status(store, parent, arguments)),
      concurrent_safe=true,
    ),
    AgentToolDefinition(
      name="subagent_send",
      description=(
        #|Post a new instruction to a subagent that is still working: narrow or
        #|redirect its task, hand it a fact it is missing, or tell it to stop
        #|searching and report what it has. This only queues the instruction: the
        #|subagent takes it before its next model request, as a message from you,
        #|and a report it submitted before taking it is discarded so that it reports
        #|again. Delivery is not confirmed here — subagent_status shows it. A
        #|subagent sees nothing of this conversation, so make the instruction
        #|self-contained. Refused for a subagent that already ended, and for a
        #|review: a reviewer stays independent of the agent it audits.
      ),
      schema=JsonSchema({
        "type": "object",
        "properties": {
          "id": {
            "type": "string",
            "description": "The subagent id from subagent_status, such as \"sr-2\".",
          },
          "message": {
            "type": "string",
            "description": "The instruction, self-contained.",
          },
        },
        "required": ["id", "message"],
      }),
      execute=Async(arguments => send(store, parent, arguments)),
    ),
  ]
}

///|
/// The N of a subagent id `sr-N`, or `None` for anything else. The id is
/// about to name a directory, so nothing but this shape gets through.
fn ordinal(id : String) -> Int? {
  match @openseek_protocol.split_child_session_id("p-\{id}") {
    Some(("p", n)) => Some(n)
    _ => None
  }
}

///|
/// The ordinals of every subagent `parent` has a session for, ascending.
async fn children(store : @store.SessionStore, parent : String) -> Array[Int] {
  let found = []
  for id in store.list() {
    if @openseek_protocol.split_child_session_id(id.value()) is Some((owner, n)) &&
      owner == parent {
      found.push(n)
    }
  }
  found.sort()
  found
}

///|
/// What the store holds about one subagent.
priv struct Child {
  log : @session_log.ParsedLog
  /// Its inbox; `None` when it opened none.
  inbox : @inbox.Inbox?
}

///|
/// Read subagent `n` of `parent`, or `None` when it has no transcript.
async fn Child::read(
  store : @store.SessionStore,
  parent : String,
  n : Int,
) -> Child? {
  let id = @agent_session.SessionId("\{parent}-sr-\{n}")
  let file = store.session_file(id)
  guard @fs.exists(file) else { return None }
  Some({
    log: @session_log.parse_events(@fs.read_file(file).text()),
    inbox: @inbox.read(store.inbox_path(id)),
  })
}

///|
/// How the subagent's turn ended, when it has.
fn Child::ended(self : Child) -> String? {
  guard self.log.events.last() is Some(event) &&
    event.item() is Terminal(terminal) else {
    return None
  }
  Some(
    match terminal {
      Finished(note) => "finished: \{clip(note, 200)}"
      ContextYield(_) => "stopped at its context ceiling"
      Aborted(reason) => "aborted: \{clip(reason, 200)}"
      Interrupted(reason) => "interrupted: \{clip(reason, 200)}"
      MaxStepsExhausted => "ran out of steps"
      Failed(reason) => "failed: \{clip(reason, 200)}"
    },
  )
}

///|
/// Where one posted instruction stands, read off the subagent's transcript.
/// None of these says the subagent obeyed it.
priv enum Delivery {
  /// Posted, and no transcript item carries its receipt.
  Waiting
  /// Recorded in the transcript, with no model RESPONSE recorded after it.
  /// A request that carried it may be in flight, or may have been cut off:
  /// the transcript records responses, not requests.
  Delivered
  /// Recorded, and a model response follows it — so a request carried it.
  Seen
} derive(Eq)

///|
/// Where `message` stands. A delivered instruction is the user item tagged
/// with the message's receipt — sender and id, not position — so a damaged
/// inbox line cannot shift the answer and another sender's message with the
/// same id cannot borrow it.
fn Child::delivery(self : Child, message : @inbox.Message) -> Delivery {
  let events = self.log.events
  for index, event in events {
    guard event.item() is User(user) &&
      user.submission_id() == Some(message.receipt()) else {
      continue
    }
    return if events[index + 1:].iter().any(e => e.is_agent_step()) {
      Seen
    } else {
      Delivered
    }
  }
  Waiting
}

///|
/// Every instruction posted to the subagent with where it stands, oldest
/// first. Empty when it has no inbox.
fn Child::instructions(self : Child) -> Array[(@inbox.Message, Delivery)] {
  match self.inbox {
    None => []
    Some(inbox) =>
      inbox.messages.map(message => (message, self.delivery(message)))
  }
}

///|
/// How one instruction's standing reads, given whether the subagent ended.
fn Delivery::describe(self : Delivery, ended~ : Bool) -> String {
  match (self, ended) {
    (Waiting, false) => "waiting"
    (Waiting, true) => "never delivered"
    (Delivered, false) => "delivered"
    (Delivered, true) => "delivered, with no response recorded after it"
    (Seen, _) => "seen"
  }
}

///|
/// One line: state, steps, how its instructions stand, and anything about
/// its record that makes the rest uncertain.
fn Child::summary(self : Child, now_ms~ : Int64) -> String {
  let steps = self.log.events.iter().filter(e => e.is_agent_step()).count()
  let ended = self.ended()
  let state = match (ended, self.log.events.last()) {
    (Some(ended), _) => ended
    (None, Some(event)) => {
      let idle = (now_ms - event.unix_ms()) / 1000L
      "working, last activity \{idle}s ago"
    }
    (None, None) => "starting"
  }
  let line = StringBuilder()
  line.write_string("\{state} · \{steps} step(s)")
  let instructions = self.instructions()
  if !instructions.is_empty() {
    let counts = [Seen, Delivered, Waiting].filter_map(standing => {
      let n = instructions.iter().filter(pair => pair.1 == standing).count()
      if n > 0 {
        Some("\{n} \{standing.describe(ended=ended is Some(_))}")
      } else {
        None
      }
    })
    line.write_string(
      " · \{instructions.length()} instruction(s): \{counts.join(", ")}",
    )
  }
  // Evidence that could not be read is said, not papered over: the state
  // above is then only what the readable part shows.
  if !self.log.errors.is_empty() {
    line.write_string(
      " · \{self.log.errors.length()} transcript line(s) unreadable, so this may be out of date",
    )
  }
  if self.inbox is Some({ unreadable, .. }) && unreadable > 0 {
    line.write_string(" · \{unreadable} inbox line(s) unreadable")
  }
  line.to_string()
}

///|
/// The subagent's task: its first user message.
fn Child::task(self : Child) -> String {
  for event in self.log.events {
    if event.item() is User(message) {
      return text_of(message.content())
    }
  }
  ""
}

///|
/// The last few transcript events, one line each, oldest first.
fn Child::recent(self : Child) -> Array[String] {
  let events = self.log.events
  let start = if events.length() > RecentEvents {
    events.length() - RecentEvents
  } else {
    0
  }
  [
    for event in events[start:] => {
      let line = match event.item() {
        User(message) => {
          let what = if message.submission_id() is Some(_) {
            "instruction delivered"
          } else {
            "task"
          }
          "\{what}: \{clip(text_of(message.content()), 300)}"
        }
        Assistant(message) => {
          let calls = message
            .tool_calls()
            .map(call => {
              // A call's own `description` says what it is for; raw arguments
              // of a snippet are a page of source.
              match (@json.parse(call.arguments) catch { _ => Json::null() }) {
                { "description": String(description), .. } =>
                  "\{call.name}: \{clip(description, 100)}"
                _ => "\{call.name} \{clip(call.arguments, 100)}"
              }
            })
            .join("; ")
          let said = clip(message.content(), 300)
          match (said, calls) {
            ("", calls) => "calls \{calls}"
            (said, "") => "says: \{said}"
            (said, calls) => "says: \{said} — calls \{calls}"
          }
        }
        Tool(result) => {
          let name = result.brief().unwrap_or(result.tool_name())
          if result.is_error() {
            "result \{name} ERROR: \{clip(text_of(result.content()), 200)}"
          } else {
            "result \{name}"
          }
        }
        Runtime(notice) => "notice: \{clip(notice.content(), 200)}"
        Summary(_) => "context compacted"
        Terminal(_) => "ended"
      }
      "  [\{event.sequence()}] \{line}"
    }
  ]
}

///|
/// The text parts of `content`, joined; images are named, not shown.
fn text_of(content : @agent_session.Content) -> String {
  content.0
  .map(part => {
    match part {
      Text(text) => text
      Image(_) => "[image]"
    }
  })
  .join("\n")
}

///|
/// `text` on one line, cut to `limit` characters.
fn clip(text : String, limit : Int) -> String {
  @agent_tool.brief_line(text, limit~)
}

///|
async fn status(
  store : @store.SessionStore,
  parent : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let now_ms = @env.now().reinterpret_as_int64()
  let wanted = match arguments {
    { "id": String(id), .. } =>
      match ordinal(id) {
        Some(n) => Some(n)
        None =>
          return @agent_tool.respond(
            "error: \{id.to_json().stringify()} is not a subagent id; ids look like sr-2",
            is_error=true,
          )
      }
    { "id": _, .. } =>
      return @agent_tool.respond(
        "error: subagent_status takes a string id",
        is_error=true,
      )
    _ => None
  }
  let report = try {
    match wanted {
      None => {
        let lines = []
        for n in children(store, parent) {
          guard Child::read(store, parent, n) is Some(child) else { continue }
          lines.push(
            "sr-\{n} — \{child.summary(now_ms~)} — \{clip(child.task(), 100)}",
          )
        }
        if lines.is_empty() {
          "no subagents yet: none has recorded a step in this conversation"
        } else {
          lines.join("\n")
        }
      }
      Some(n) => {
        guard Child::read(store, parent, n) is Some(child) else {
          return @agent_tool.respond(
            "error: no subagent sr-\{n} has recorded a step in this conversation",
            is_error=true,
          )
        }
        let ended = child.ended() is Some(_)
        let lines = [
          "sr-\{n} — \{child.summary(now_ms~)}",
          "task: \{clip(child.task(), 600)}",
          "recent:",
          ..child.recent(),
          ..[
            for pair in child.instructions() if pair.1 != Seen => {
              "  [\{pair.1.describe(ended~)}] \{clip(pair.0.text, 300)}"
            }
          ],
        ]
        lines.join("\n")
      }
    }
  } catch {
    error =>
      return @agent_tool.respond(
        "error: could not read the subagent's record: \{error}",
        is_error=true,
      )
  }
  @agent_tool.respond(report, brief="subagent_status")
}

///|
async fn send(
  store : @store.SessionStore,
  parent : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "id": String(id), "message": String(message), .. } else {
    return @agent_tool.respond(
      "error: subagent_send requires a string id and a string message",
      is_error=true,
    )
  }
  guard ordinal(id) is Some(n) else {
    return @agent_tool.respond(
      "error: \{id.to_json().stringify()} is not a subagent id; ids look like sr-2",
      is_error=true,
    )
  }
  guard !message.is_blank() else {
    return @agent_tool.respond(
      "error: subagent_send needs a non-empty message",
      is_error=true,
    )
  }
  guard message.length() <= @inbox.MaxTextChars else {
    return @agent_tool.respond(
      "error: the message is \{message.length()} characters; one instruction carries at most \{@inbox.MaxTextChars}",
      is_error=true,
    )
  }
  let outcome : Result[String, String] = try {
    match Child::read(store, parent, n) {
      None =>
        Err(
          "no subagent sr-\{n} has recorded a step in this conversation; subagent_status lists the ones that have",
        )
      Some(child) =>
        match (child.ended(), child.inbox) {
          (Some(ended), _) =>
            Err(
              "sr-\{n} already ended (\{ended}) and takes no more instructions",
            )
          // Its inbox is opened before its first record, so a subagent with
          // a transcript and no inbox is one that takes none.
          (None, None) =>
            Err(
              "sr-\{n} takes no instructions: a reviewer stays independent of the agent it audits. Nothing was sent",
            )
          (None, Some(_)) => {
            let waiting = child
              .instructions()
              .iter()
              .filter(pair => pair.1 == Waiting)
              .count()
            if waiting >= MaxWaiting {
              Err(
                "sr-\{n} has not taken the last \{waiting} instructions sent to it; nothing more was queued. See subagent_status (id=\"sr-\{n}\")",
              )
            } else {
              let posted = @inbox.Message(from=parent, text=message)
              let path = store.inbox_path(SessionId("\{parent}-sr-\{n}"))
              if @inbox.post(path, posted) {
                Ok(posted.id)
              } else {
                Err("sr-\{n} has no inbox to post to. Nothing was sent")
              }
            }
          }
        }
    }
  } catch {
    error => Err("could not post to sr-\{n}: \{error}")
  }
  match outcome {
    Ok(id) =>
      @agent_tool.respond(
        "queued instruction \{id} for sr-\{n}. It takes it before its next model request; that is not confirmed here. subagent_status (id=\"sr-\{n}\") shows whether it is waiting, delivered or seen.",
        brief="subagent_send sr-\{n}",
      )
    Err(reason) => @agent_tool.respond("error: \{reason}", is_error=true)
  }
}
