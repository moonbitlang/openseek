///|
/// Cached Cloud history, one turn per page. `pages[i]` holds turn `lo + i`
/// and the last page is the latest turn read, so the rendered transcript is
/// contiguous by construction.
#derive(Eq)
pub struct HistoryWindow {
  lo : Int32
  pages : Array[History]
  // Cached turns separated from the window by turns not read yet. Paging
  // backward reattaches them; they are never rendered on their own.
  detached : Map[Int32, History]
}

///|
pub extend HistoryWindow with Eq::{equal, not_equal}

///|
fn HistoryWindow::empty() -> HistoryWindow {
  { lo: 0, pages: [], detached: Map([]), }
}

///|
fn HistoryWindow::latest(self : HistoryWindow) -> History? {
  self.pages.last()
}

///|
/// Offset of the next earlier turn, if the window does not start at the
/// conversation's first turn.
fn HistoryWindow::older_offset(self : HistoryWindow) -> Int32? {
  guard !self.pages.is_empty() && self.lo > 0 else { return None }
  Some(self.lo - 1)
}

///|
/// The latest page decides where the window ends. Another device may have
/// added several turns since the last read; the window then restarts at the
/// new latest turn and keeps the earlier cache for reattachment.
fn HistoryWindow::with_latest(
  self : HistoryWindow,
  offset : Int32,
  page : History,
) -> HistoryWindow {
  let end = self.lo + self.pages.length()
  if !self.pages.is_empty() && offset >= self.lo && offset <= end {
    let pages = self.pages[:offset - self.lo].to_owned()
    pages.push(page)
    return { ..self, pages, }
  }
  let detached : Map[Int32, History] = Map([])
  for key, cached in self.detached {
    if key < offset {
      detached[key] = cached
    }
  }
  for index, cached in self.pages {
    if self.lo + index < offset {
      detached[self.lo + index] = cached
    }
  }
  { lo: offset, pages: [page], detached, }
}

///|
/// Prepend the turn just before the window, then any cached turns that now
/// join it.
fn HistoryWindow::with_older(
  self : HistoryWindow,
  offset : Int32,
  page : History,
) -> HistoryWindow? {
  guard self.older_offset() == Some(offset) else { return None }
  let detached = self.detached.copy()
  detached.remove(offset)
  Some({ lo: offset, pages: [page, ..self.pages], detached, }.reattach())
}

///|
/// Move cached turns adjoining the window into it. A turn cached while it was
/// still running must be read again.
fn HistoryWindow::reattach(self : HistoryWindow) -> HistoryWindow {
  let detached = self.detached.copy()
  let earlier = []
  let mut lo = self.lo
  while detached.get(lo - 1) is Some(page) && page.turn_complete() {
    detached.remove(lo - 1)
    earlier.push(page)
    lo -= 1
  }
  guard !earlier.is_empty() else { return self }
  earlier.rev_in_place()
  { lo, pages: [..earlier, ..self.pages], detached, }
}

///|
/// The first turn cached while it was running that is no longer the latest.
/// A later turn exists, so that turn has finished and must be read again.
fn HistoryWindow::stale_offset(self : HistoryWindow) -> Int32? {
  for index in 0..<(self.pages.length() - 1) {
    if !self.pages[index].turn_complete() {
      return Some(self.lo + index)
    }
  }
  None
}

///|
/// Replace an earlier turn read again. The latest turn is owned by latest
/// reads, and a turn outside the window is not rendered.
fn HistoryWindow::with_turn(
  self : HistoryWindow,
  offset : Int32,
  page : History,
) -> HistoryWindow? {
  guard offset >= self.lo && offset < self.lo + self.pages.length() - 1 else {
    return None
  }
  let pages = self.pages.copy()
  pages[offset - self.lo] = page
  Some({ ..self, pages, })
}

///|
/// The response's generating flag belongs to the whole conversation. A
/// terminal service record proves this page's turn is complete.
fn History::turn_complete(self : History) -> Bool {
  !self.generating ||
  self.messages.any(record => record.kind == "task_finished")
}

///|
fn Conversation::older_history_offset(self : Conversation) -> Int32? {
  guard self.history_older_request is None else { return None }
  self.history_window.older_offset()
}

///|
pub fn Conversation::can_load_older_history(self : Conversation) -> Bool {
  self.older_history_offset() is Some(_)
}

///|
/// Whether this state shows earlier turns of the same latest turn than
/// `previous`, so the reader's position must be kept across the prepend.
pub fn Conversation::extends_history_backward(
  self : Conversation,
  previous : Conversation,
) -> Bool {
  let window = self.history_window
  let before = previous.history_window
  !before.pages.is_empty() &&
  window.lo < before.lo &&
  window.lo + window.pages.length() == before.lo + before.pages.length()
}

///|
/// Apply the latest history read. A response without a page offset is the
/// whole conversation and replaces the cache.
fn Conversation::with_latest_page(
  self : Conversation,
  history : History,
  request? : Int32,
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
      history_window: HistoryWindow::empty(),
      history_older_request: None,
    }
  }
  let window = self.history_window.with_latest(offset, history)
  {
    ..self.with_history_window(window),
    history_older_request: self.history_older_request.filter(request => {
      window.older_offset() == Some(request.1)
    }),
  }
}

///|
/// Apply an earlier page read by paging backward. A page that no longer
/// adjoins the window is ignored.
fn Conversation::with_older_page(
  self : Conversation,
  history : History,
  request : Int32,
) -> Conversation {
  guard history.offset is Some(offset) &&
    self.history_window.with_older(offset, history) is Some(window) else {
    return self
  }
  self
  .acknowledge_assistants(request, history.session, history.messages)
  .with_history_window(window)
}

///|
/// Apply a finished turn read again because it was cached while running.
fn Conversation::with_turn_page(
  self : Conversation,
  offset : Int32,
  history : History,
  request : Int32,
) -> Conversation {
  guard history.offset == Some(offset) &&
    self.history_window.with_turn(offset, history) is Some(window) else {
    return self
  }
  self
  .acknowledge_assistants(request, history.session, history.messages)
  .with_history_window(window)
}

///|
/// Render a non-empty window.
fn Conversation::with_history_window(
  self : Conversation,
  window : HistoryWindow,
) -> Conversation {
  let records = []
  let events = []
  let sequences : Set[Int32] = Set([])
  for page in window.pages {
    records.append(page.messages)
    for event in page.session.events.unwrap_or([]) {
      if !sequences.contains(event.sequence) {
        sequences.add(event.sequence)
        events.push(event)
      }
    }
  }
  let latest = window.pages[window.pages.length() - 1]
  {
    ..self,
    history_window: window,
    records,
    document: { ..latest.session, events: Some(events), },
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
    guard pending.history_request.map_or(true, first => request >= first) &&
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
