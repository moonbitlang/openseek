///|
/// One provider attempt. The deduplication key is (session_id, call, attempt).
/// `call` is session-local, shared by retries; it is not an agent step number.
/// `after_sequence` anchors metadata without consuming a conversation sequence.
/// Purpose is `agent`, `manual_compaction`, or `auto_compaction`; outcome is
/// `completed`, `failed`, or `interrupted`. A completed response can still fail
/// later during summary validation, tool processing or persistence.
pub struct UsageRecord {
  session_id : String
  call : Int32
  attempt : Int32
  after_sequence : Int32
  purpose : String
  model : String
  response_id : String?
  outcome : String
  report : @deepseek.UsageReport
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Build accounting metadata for a provider attempt without estimating counts.
pub fn UsageRecord::UsageRecord(
  session : Session,
  call~ : Int32,
  attempt~ : Int32,
  purpose~ : String,
  model~ : String,
  response_id? : String,
  outcome~ : String,
  report~ : @deepseek.UsageReport,
) -> UsageRecord {
  {
    session_id: session.id().value(),
    call,
    attempt,
    after_sequence: session.last_sequence(),
    purpose,
    model,
    response_id,
    outcome,
    report,
  }
}

///|
/// Attach the same attempt metadata emitted on the usage event to its first
/// assistant message. Replays must not carry a second copy.
pub fn AssistantMessage::with_usage_record(
  self : AssistantMessage,
  record : UsageRecord,
) -> AssistantMessage {
  { ..self, usage_record: Some(record), }
}

///|
/// Accounting identity and reporting facts; absent on historical messages.
pub fn AssistantMessage::usage_record(self : AssistantMessage) -> UsageRecord? {
  self.usage_record
}

///|
/// Records with no assistant carrier, in append order. They never enter model input.
pub fn Session::supplemental_usage(
  self : Session,
) -> @vector.Vector[UsageRecord] {
  self.supplemental_usage
}

///|
/// All new-format attempt records, once each, in call/attempt order. Historical
/// messages without reporting metadata remain available through `events()`;
/// their zero-filled counts cannot establish reporting completeness.
pub fn Session::usage_records(self : Session) -> Array[UsageRecord] {
  let records = self.supplemental_usage.to_array()
  for event in self.events {
    if event.item is Assistant(message) &&
      !message.is_replay() &&
      message.usage_record is Some(record) {
      records.push(record)
    }
  }
  records.sort_by((a, b) => {
    let order = a.call.compare(b.call)
    if order == 0 {
      a.attempt.compare(b.attempt)
    } else {
      order
    }
  })
  records
}

///|
/// Next session-local model invocation ordinal, including failed invocations.
pub fn Session::next_usage_call(self : Session) -> Int32 {
  let mut call = self.supplemental_usage.fold(init=0, (last, record) => {
    last.max(record.call)
  })
  for event in self.events {
    if event.item is Assistant(message) && message.usage_record is Some(record) {
      call = call.max(record.call)
    }
  }
  call + 1
}

///|
/// Append metadata without creating a model message or changing `last_sequence`.
/// A store-backed caller persists the returned snapshot with `append_usage`.
pub fn Session::append_usage(self : Session, record : UsageRecord) -> Session {
  { ..self, supplemental_usage: self.supplemental_usage.push(record), }
}

///|
#doc(hidden)
#deprecated
pub extend UsageRecord with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend UsageRecord with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend UsageRecord with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend UsageRecord with FromJson::{from_json}
