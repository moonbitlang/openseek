///|
fn Conversation::older_history_start(self : Conversation) -> Int32? {
  guard self.history_older_request is None else { return None }
  let mut start = 0
  for offset in self.history_pages.keys() {
    if offset > start {
      start = offset
    }
  }
  // A fresh tail can jump ahead if another device sent several turns.
  // Close any gap before walking beyond the cached prefix.
  // The response's generating flag belongs to the whole conversation.
  // A terminal service record proves this page's turn is complete.
  while start > 0 &&
        self.history_pages.get(start - 1) is Some(page) &&
        (
          !page.generating ||
          page.messages.any(record => record.kind == "task_finished")
        ) {
    start -= 1
  }
  if start > 0 {
    Some(start)
  } else {
    None
  }
}

///|
pub fn Conversation::can_load_older_history(self : Conversation) -> Bool {
  self.older_history_start() is Some(_)
}

///|
fn Conversation::with_history_page(
  self : Conversation,
  history : History,
  request? : Int32,
  latest~ : Bool,
) -> Conversation {
  // Disk hydration supplies no request because its snapshot can predate SSE.
  let self = match request {
    Some(request) =>
      self.acknowledge_assistants(request, history.session, history.messages)
    None => self
  }
  guard history.offset is Some(offset) else {
    return {
      ..self,
      records: history.messages,
      document: history.session,
      history_pages: Map([]),
      history_older_request: None,
    }
  }
  let pages = self.history_pages.copy()
  if latest {
    for key in self.history_pages.keys() {
      if key > offset {
        pages.remove(key)
      }
    }
  }
  pages[offset] = history
  let offsets = pages.keys().to_array()
  offsets.sort()
  let records = []
  let events = []
  let sequences : Set[Int32] = Set([])
  for key in offsets {
    let page = pages[key]
    records.append(page.messages)
    for event in page.session.events.unwrap_or([]) {
      if !sequences.contains(event.sequence) {
        sequences.add(event.sequence)
        events.push(event)
      }
    }
  }
  let tail = pages[offsets[offsets.length() - 1]]
  {
    ..self,
    history_pages: pages,
    history_older_request: self.history_older_request.filter(request => {
      !latest || request.1 < offset
    }),
    records,
    document: { ..tail.session, events: Some(events), },
  }
}

///|
/// Only an assistant actually present in the returned document can replace
/// its preview. A task may contain several identical replies, so consume
/// matching native sequences once and in order.
fn Conversation::acknowledge_assistants(
  self : Conversation,
  request : Int32,
  document : @protocol.SessionDocument,
  records : Array[Record],
) -> Conversation {
  guard !self.pending_assistants.is_empty() else { return self }
  let events = document.events
    .unwrap_or([])
    .filter(event => {
      event.item is @protocol.Assistant(reply) &&
      (
        !reply.content.is_empty() ||
        reply.reasoning_content.map_or(false, text => !text.is_empty())
      )
    })
  let links = records.filter(record => record.kind == "assistant_message")
  let owners : Map[Int32, String] = Map([])
  if links.length() == events.length() &&
    links.all(link => link.engine_sequence is None) {
    // The legacy projection lists one marker per visible native reply in
    // journal order. Its body is irrelevant even in older cache files.
    for index, event in events {
      owners[event.sequence] = links[index].task_id
    }
  } else {
    for link in links {
      if link.engine_sequence is Some(sequence) {
        owners[sequence] = link.task_id
      }
    }
  }
  let matched = self.assistant_handoffs.copy()
  let pending_assistants = self.pending_assistants.filter(pending => {
    guard request >= pending.history_request &&
      pending.item.kind is @transcript.Assistant(prose~, reasoning~, ..) else {
      return true
    }
    let after = matched.get(pending.task).unwrap_or(0)
    guard events
      .iter()
      .find_first(event => {
        event.sequence > after &&
        owners.get(event.sequence) == Some(pending.task) &&
        event.item is @protocol.Assistant(reply) &&
        reply.is_replay != Some(true) &&
        (match prose {
          Some(text) => reply.content == text
          None =>
            reply.content.is_blank() && reply.reasoning_content == reasoning
        })
      })
      is Some(event) else {
      return true
    }
    matched[pending.task] = event.sequence
    false
  })
  let assistant_handoffs = Map([])
  for task, sequence in matched {
    if self.task == Some(task) ||
      pending_assistants.any(pending => pending.task == task) {
      assistant_handoffs[task] = sequence
    }
  }
  { ..self, pending_assistants, assistant_handoffs, }
}
