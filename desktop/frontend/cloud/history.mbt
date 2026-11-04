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
  while start > 0 &&
        self.history_pages.get(start - 1) is Some({ generating: false, .. }) {
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
  request : Int32,
  latest~ : Bool,
) -> Conversation {
  let pending_assistants = self.uncovered_assistants(
    request,
    history.offset.map(_ => history.messages),
  )
  guard history.offset is Some(offset) else {
    return {
      ..self,
      records: history.messages,
      document: history.session,
      pending_assistants,
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
    pending_assistants,
    document: { ..tail.session, events: Some(events), },
  }
}

///|
/// SSE publishes assistants after commit. A read started after the event
/// includes that commit if it covers the task's turn. A read for a different
/// turn or an older in-flight page cannot replace the temporary reply.
fn Conversation::uncovered_assistants(
  self : Conversation,
  request : Int32,
  page_records : Array[Record]?,
) -> Array[PendingAssistant] {
  self.pending_assistants.filter(pending => {
    request < pending.history_request ||
    page_records.map_or(false, records => {
      !records.any(record => {
        record.task_id == pending.task && record.kind == "assistant_message"
      })
    })
  })
}
