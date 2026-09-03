///|
/// Stable identity for one visible transcript row: the durable event it came
/// from, which projects to at most one row. Old fixtures without a sequence
/// use their durable-array position.
priv enum TranscriptRowIdentity {
  DurableTranscriptRow(Int)
  LegacyTranscriptRow(Int)
}

///|
/// Serialize a row identity for Rabbita's keyed-children map. The result is
/// renderer-private and is never emitted as a DOM id or attribute.
fn TranscriptRowIdentity::wire(self : TranscriptRowIdentity) -> String {
  match self {
    DurableTranscriptRow(sequence) => "s\{sequence}"
    LegacyTranscriptRow(index) => "l\{index}"
  }
}

///|
/// Key every durable row by the event it came from. This is deliberately
/// separate from `messages` itself, which callers that only need transcript
/// content read directly and should not know renderer keys.
fn Conversation::visible_transcript_rows(
  self : Conversation,
) -> Array[@transcript_component.VisibleRow] {
  let durable : Array[@transcript_component.VisibleRow] = []
  for index, item in self.messages {
    let identity = match item.sequence {
      Some(sequence) => DurableTranscriptRow(sequence)
      None => LegacyTranscriptRow(index)
    }
    durable.push({ item, identity: identity.wire(), })
  }
  durable
}

///|
/// Streaming output is owned by its run. The Starting/idle cases keep this
/// total for tests and transient states even though normal deltas arrive only
/// after the host has supplied a run id.
fn Conversation::streaming_render_identity(self : Conversation) -> String {
  match self.run {
    Open(run_id~, ..) => run_id
    Starting(submission_id~) => "submission\u{0}\{submission_id}"
    NoRun(..) =>
      match self.last_run_id {
        Some(run_id) => run_id
        None => "idle"
      }
  }
}

///|
/// The provisional reasoning to render. A sealed preview equal to reasoning
/// committed during this step is already present in the durable activity card,
/// so hide only that visual duplicate. Never hide an in-flight prefix and never
/// mutate the preview from a commit: session commits carry no run/step identity,
/// and an older delayed commit must not truncate a newer stream.
fn Conversation::reasoning_for_render(self : Conversation) -> (String?, Bool) {
  guard self.turn.live_reasoning is Some(live) && !live.content.is_empty() else {
    return (None, false)
  }
  let candidate = live.content.trim()
  if live.complete && !candidate.is_empty() {
    let mut index = self.messages.length()
    while index > 0 {
      index -= 1
      if self.messages[index].kind is Assistant(reasoning=Some(thought), ..) {
        if self.messages[index].sequence is Some(sequence) &&
          sequence > self.turn.reasoning_frontier &&
          thought.trim() == candidate {
          return (None, live.complete)
        }
        break
      }
    }
  }
  (Some(live.content), live.complete)
}

///|
test "transcript row identities key by event sequence" {
  let conv = {
    ..test_conversation(),
    messages: [
      { kind: User("question"), ts: None, sequence: Some(41), },
      {
        kind: Assistant(
          reasoning=None,
          prose=Some("answer"),
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(42),
      },
      // A fixture from before events carried sequences falls back to its
      // position, which cannot collide with any `s<n>` key.
      {
        kind: Assistant(
          reasoning=None,
          prose=Some("old"),
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: None,
      },
    ],
  }
  assert_eq(conv.visible_transcript_rows().map(row => row.identity), [
    "s41", "s42", "l2",
  ])
}
