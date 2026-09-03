///|
/// Snapshot the canonical user item ids already present in one turn. A steer
/// receipt records this set at submission time so repeated `item/started` and
/// `item/completed` notifications for an older item cannot consume it.
fn CodexThread::user_item_ids(
  self : CodexThread,
  turn_id : String,
) -> Array[String] {
  let ids : Array[String] = []
  for turn in self.turns {
    if turn.id == turn_id {
      for item in turn.items {
        if item.kind == "userMessage" {
          ids.push(item.id)
        }
      }
      break
    }
  }
  ids
}

///|
fn CodexThread::has_item_id(
  self : CodexThread,
  turn_id : String,
  item_id : String,
) -> Bool {
  for turn in self.turns {
    if turn.id == turn_id {
      return turn.items.iter().any(item => item.id == item_id)
    }
  }
  false
}

///|
/// Create the receipt synchronously before the asynchronous steer command can
/// emit either a reply or an item notification. `next_steer_submission_id` is
/// local presentation identity only; it is never sent to app-server.
fn State::with_pending_steer(self : State, turn_id : String) -> State {
  guard self.active_thread() is Some(active) else { return self }
  let pending_steers = self.pending_steers.copy()
  pending_steers.push({
    submission_id: self.next_steer_submission_id,
    turn_id,
    submitted: { task: self.draft, mentions: self.mentions.copy(), },
    known_user_item_ids: active.user_item_ids(turn_id),
    delivery: CodexSteerSending,
  })
  {
    ..self,
    pending_steers,
    next_steer_submission_id: self.next_steer_submission_id + 1,
  }
}

///|
/// A successful RPC says the steer was accepted, not that its durable User item
/// has entered history. Mark only the oldest still-Sending receipt for the
/// returned turn; the composer lock ensures at most one such local request is
/// in flight.
fn State::with_accepted_steer(self : State, value : Json) -> State {
  let mut turn_id : String? = None
  if value is Object(fields) {
    turn_id = @jsonx.json_text(fields, "turnId")
    if turn_id is None && fields.get("turn") is Some(Object(turn)) {
      turn_id = @jsonx.json_text(turn, "id")
    }
  }
  guard turn_id is Some(turn_id) else { return self }
  let mut accepted = false
  let pending_steers = self.pending_steers.map(receipt => {
    if !accepted &&
      receipt.turn_id == turn_id &&
      receipt.delivery is CodexSteerSending {
      accepted = true
      { ..receipt, delivery: CodexSteerAccepted, }
    } else {
      receipt
    }
  })
  { ..self, pending_steers, }
}

///|
/// A definite RPC failure rejects only the request currently holding the
/// composer lock. Older Accepted receipts still wait for their canonical item.
fn State::without_sending_steer(self : State, thread_id : String) -> State {
  guard self.active_thread() is Some(active) && active.id == thread_id else {
    return self
  }
  {
    ..self,
    pending_steers: self.pending_steers.filter(receipt => {
      !(receipt.delivery is CodexSteerSending)
    }),
  }
}

///|
/// Reconcile one previously unseen canonical User item with local receipts.
///
/// The protocol supplies `(threadId, turnId, item.id)`, but neither the steer
/// reply nor the item identifies the other: there is no returned `itemId`,
/// echoed client submission id, or `source: "steer"` marker. We therefore make
/// one explicit integration assumption here: this Desktop is the single writer
/// for the turn, its composer lock serializes steer RPCs, and app-server emits
/// User items for that connection in submission FIFO order. Under that rule,
/// the first previously unseen User item in the same turn consumes the oldest
/// eligible receipt. We never compare message text, so identical consecutive
/// messages remain distinct through their app-server item ids.
///
/// The first prompt has its own older receipt. If it has not produced a User
/// item yet, FIFO assigns the next unseen item to that prompt rather than to a
/// later steer. Duplicate started/completed notifications are ignored because
/// the item id is already present in the pre-notification state.
fn State::with_observed_user_item(
  self : State,
  thread_id : String,
  turn_id : String,
  item_id : String,
) -> State {
  guard self.active_thread() is Some(active) &&
    active.id == thread_id &&
    !active.has_item_id(turn_id, item_id) else {
    return self
  }
  if self.waiting_for_first_user_item() {
    return self
  }
  let mut consumed = false
  let pending_steers : Array[CodexSteerReceipt] = []
  for receipt in self.pending_steers {
    if !consumed &&
      receipt.turn_id == turn_id &&
      !receipt.known_user_item_ids.contains(item_id) {
      consumed = true
    } else {
      pending_steers.push(receipt)
    }
  }
  { ..self, pending_steers, }
}

///|
/// A full steer reply can install canonical items before their lifecycle
/// notifications arrive. Reconcile every newly observed User item first so
/// installing the turn cannot leave its display-only receipt beside it.
fn State::with_observed_steer_turn(self : State, turn : CodexTurn) -> State {
  guard self.active_thread() is Some(active) else { return self }
  let observed_user_item_ids = active.user_item_ids(turn.id)
  let mut next = self
  for item in turn.items {
    if item.kind == "userMessage" && !observed_user_item_ids.contains(item.id) {
      if next.waiting_for_first_user_item() {
        // This decoded turn is installed immediately after reconciliation, so
        // its first new User item can authoritatively replace the older prompt
        // receipt. Notifications keep the old install-then-observe ordering.
        next = { ..next, submitted_first_prompt: None, }
      } else {
        next = next.with_observed_user_item(active.id, turn.id, item.id)
      }
      observed_user_item_ids.push(item.id)
    }
  }
  next
}

///|
/// Decode one app-server item lifecycle notification before the canonical item
/// is installed in the selected turn.
fn State::with_observed_steer_item(
  self : State,
  method_ : String,
  params : Json,
) -> State {
  guard method_ == "item/started" || method_ == "item/completed" else {
    return self
  }
  guard params is Object(fields) &&
    @jsonx.json_text(fields, "threadId") is Some(thread_id) &&
    @jsonx.json_text(fields, "turnId") is Some(turn_id) &&
    fields.get("item") is Some(value) &&
    CodexItem::decode(value) is Some(item) &&
    item.kind == "userMessage" else {
    return self
  }
  self.with_observed_user_item(thread_id, turn_id, item.id)
}

///|
/// Project a local receipt through the shared transcript vocabulary without
/// manufacturing an app-server item or durable sequence number.
fn CodexSteerReceipt::transcript_item(
  self : CodexSteerReceipt,
) -> @transcript.TranscriptItem {
  { kind: @transcript.User(self.submitted.prompt()), ts: None, sequence: None, }
}
