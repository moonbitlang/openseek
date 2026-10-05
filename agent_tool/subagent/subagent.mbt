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
        #|lists every subagent in one line each, with the label and workflow the
        #|launching script gave it when that is on record; with `id` (for example "sr-2") it
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
      // Reads the store and returns: safe for a snippet to call, so a
      // script can check on several subagents and act on what it finds.
      program_callable=true,
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
      // One append to a file the engine owns, which a snippet's own policy
      // does not let it write: this is how a script posts.
      program_callable=true,
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
/// What a workflow run recorded about one child it launched, from the run's
/// `events.jsonl`. The workflow library writes that file best-effort, and a
/// script can write it too, so it only ever REFINES what is shown — a label,
/// which run, how the library says the child ended. It never decides who is
/// a child or whether one may be posted to on its own: a transcript does.
///
/// The start and finish records are written independently and either can be
/// missing, so neither depends on the other here: a finish with no start
/// still says the child is over.
priv struct Launch {
  /// The N of the run `wf-N` that recorded it.
  workflow : Int
  /// The kind and label the script gave it, when the start was recorded.
  named : (String, String)?
  /// The library's own word for how the child ended (`captured`,
  /// `timed_out`, `cancelled`, ...), when the finish was recorded.
  ended : String?
}

///|
/// What the workflow runs of one conversation recorded.
priv struct Launches {
  by_child : Map[Int, Launch]
  /// Runs whose record could not be read at all. Their children are then
  /// shown from their transcripts alone, and the listing says so.
  unreadable : Int
  /// Whole lines, in records that could be read, that are not a record:
  /// damaged in the writing. Which child one was about is unknowable, so any
  /// child may be missing a start or — what matters — a finish.
  damaged : Int
}

///|
/// Every launch the workflow runs of `parent` recorded, by child ordinal.
/// The runs' directories are the siblings `<parent>-wf-<N>` of `sessions/` in
/// the store's root.
///
/// This never raises: the records are a view, and a damaged one must not
/// take the transcripts and inboxes down with it. A run whose file cannot be
/// read is counted. Within a readable file each whole line is decoded on its
/// own, so a damaged one costs only itself — and is counted too, because a
/// lost finish would otherwise leave a child reading as running with nothing
/// to say the record is incomplete. That includes a final line with no
/// newline, and a record whose child id is not one. An event this build does
/// not know is not damage, and neither is a well-formed id under another
/// parent; both are passed over.
async fn launches(
  store : @store.SessionStore,
  parent : String,
) -> Launches noraise {
  let by_child : Map[Int, Launch] = Map([])
  let mut unreadable = 0
  let mut damaged = 0
  let root = store.root()
  let names = try {
    if @fs.exists(root) {
      @fs.readdir(root, sort=true)
    } else {
      []
    }
  } catch {
    _ => {
      unreadable += 1
      []
    }
  }
  let prefix = "\{parent}-wf-"
  for name in names {
    // A run's number has the same shape as a child's: reuse the one parser.
    guard name.strip_prefix(prefix) is Some(digits) &&
      ordinal("sr-\{digits}") is Some(workflow) else {
      continue
    }
    let events = "\{root}/\{name}/events.jsonl"
    let bytes = try {
      guard @fs.exists(events) else { continue }
      @fs.read_file(events).binary()
    } catch {
      _ => {
        unreadable += 1
        continue
      }
    }
    let mut start = 0
    for index in 0..<bytes.length() {
      guard bytes[index] == b'\n' else { continue }
      let line = bytes[start:index]
      start = index + 1
      guard line.length() > 0 else { continue }
      let json = @json.parse(@utf8.decode(line)) catch {
        _ => {
          damaged += 1
          continue
        }
      }
      guard json is { "event": String(event), .. } else {
        damaged += 1
        continue
      }
      guard event is ("agent_started" | "agent_finished") else { continue }
      guard json is { "child": String(child), .. } else {
        damaged += 1
        continue
      }
      // An id that is not a child id at all is damage: the record was
      // about SOME child, and cannot say which. A well-formed id under
      // another parent is simply not ours.
      guard @openseek_protocol.split_child_session_id(child) is Some((owner, n)) else {
        damaged += 1
        continue
      }
      guard owner == parent else { continue }
      let known = by_child
        .get(n)
        .unwrap_or({ workflow, named: None, ended: None, })
      match (event, json) {
        ("agent_started", { "kind": String(kind), "label": String(label), .. }) =>
          by_child[n] = { ..known, workflow, named: Some((kind, label)), }
        ("agent_finished", { "status": String(status), .. }) =>
          by_child[n] = { ..known, workflow, ended: Some(status), }
        _ => damaged += 1
      }
    }
    // What follows the last newline was cut off: the library writes a whole
    // line at once, so a tail is a write that died, not one in progress.
    if start < bytes.length() {
      damaged += 1
    }
  }
  { by_child, unreadable, damaged, }
}

///|
/// The bracketed tag that names a recorded child in a listing.
fn Launch::tag(self : Launch) -> String {
  match self.named {
    Some((kind, label)) =>
      " [\{clip(label, 60)} · \{kind} · wf-\{self.workflow}]"
    None => " [wf-\{self.workflow}]"
  }
}

///|
/// What to say when the workflows' records are incomplete, or nothing.
fn Launches::caveat(self : Launches) -> String? {
  let problems = []
  if self.unreadable > 0 {
    problems.push("\{self.unreadable} workflow record(s) could not be read")
  }
  if self.damaged > 0 {
    problems.push("\{self.damaged} line(s) in a workflow record are damaged")
  }
  guard !problems.is_empty() else { return None }
  Some(
    "(\{problems.join(" and ")}: a label or an end may be missing above, so a subagent shown as running may already be over)",
  )
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
fn Child::summary(self : Child, now_ms~ : Int64, launch~ : Launch?) -> String {
  let steps = self.log.events.iter().filter(e => e.is_agent_step()).count()
  let ended = self.ended()
  // The transcript's own terminal is the only thing called an end outright.
  // Without one, "running" is said only on the workflow's word, and a child
  // nothing vouches for is described by what is known: no end, and how long
  // since it last wrote.
  let state = match (ended, self.log.events.last(), launch) {
    (Some(ended), _, _) => ended
    (None, _, Some({ ended: Some(status), .. })) =>
      "no end in its transcript; the workflow recorded it as \{status}"
    (None, Some(event), launch) => {
      let idle = (now_ms - event.unix_ms()) / 1000L
      if launch is Some(_) {
        "running per the workflow's record, last activity \{idle}s ago"
      } else {
        "no end recorded, last activity \{idle}s ago"
      }
    }
    (None, None, _) => "starting"
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
        let recorded = launches(store, parent)
        let launched = recorded.by_child
        let ordinals = [..children(store, parent), ..launched.keys()]
        ordinals.sort()
        ordinals.dedup()
        let lines = []
        for n in ordinals {
          let launch = launched.get(n)
          let tag = launch.map_or("", launch => launch.tag())
          match (Child::read(store, parent, n), launch) {
            (Some(child), _) =>
              lines.push(
                "sr-\{n}\{tag} — \{child.summary(now_ms~, launch~)} — \{clip(child.task(), 100)}",
              )
            // Launched, by the workflow's account, and nothing of its own
            // on record yet — or ever, if it ended first.
            (None, Some({ ended: Some(status), .. })) =>
              lines.push(
                "sr-\{n}\{tag} — the workflow recorded it as \{status}; it recorded nothing itself",
              )
            (None, Some(_)) =>
              lines.push(
                "sr-\{n}\{tag} — launched per the workflow's record; nothing recorded yet",
              )
            (None, None) => ()
          }
        }
        if lines.is_empty() {
          lines.push(
            "no subagents yet: none has recorded a step in this conversation",
          )
        }
        if recorded.caveat() is Some(caveat) {
          lines.push(caveat)
        }
        lines.join("\n")
      }
      Some(n) => {
        guard Child::read(store, parent, n) is Some(child) else {
          return @agent_tool.respond(
            "error: no subagent sr-\{n} has recorded a step in this conversation",
            is_error=true,
          )
        }
        let ended = child.ended() is Some(_)
        let recorded = launches(store, parent)
        let launch = recorded.by_child.get(n)
        let tag = launch.map_or("", launch => launch.tag())
        let lines = [
          "sr-\{n}\{tag} — \{child.summary(now_ms~, launch~)}",
          "task: \{clip(child.task(), 600)}",
          "recent:",
          ..child.recent(),
          ..[
            for pair in child.instructions() if pair.1 != Seen => {
              "  [\{pair.1.describe(ended~)}] \{clip(pair.0.text, 300)}"
            }
          ],
          ..recorded.caveat().map_or([], caveat => [caveat]),
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
          // No terminal of its own, but the workflow that launched it says
          // it is over: cut off. Refusing costs nothing if that record is
          // wrong — nothing would have been lost — and saves an instruction
          // posted to a process that is gone.
          (None, _) if launches(store, parent).by_child.get(n)
            is Some({ ended: Some(status), .. }) =>
            Err(
              "sr-\{n} has no end in its transcript, but the workflow recorded it as \{status}: it is no longer running. Nothing was sent",
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
