///|
#derive(Eq, Debug)
pub(all) struct Reasoning {
  content : String
  complete : Bool
}

///|
/// Provisional text belongs to an engine turn, never to durable history.
#derive(Eq)
pub(all) struct Stream {
  response : String?
  reasoning : Reasoning?
}

///|
pub fn Stream::event(self : Stream, event : @transcript.EngineEvent) -> Stream {
  match event {
    @transcript.AgentStep(_) | @transcript.StreamRetry(..) =>
      { response: None, reasoning: None, }
    @transcript.AssistantDelta(text) => {
      guard !text.is_empty() else { return self }
      {
        response: Some(self.response.unwrap_or("") + text),
        reasoning: self.reasoning.map(r => { ..r, complete: true, }),
      }
    }
    @transcript.ReasoningDelta(text) => {
      guard !text.is_empty() &&
        !(self.reasoning is Some({ complete: true, .. })) else {
        return self
      }
      {
        ..self,
        reasoning: Some({
          content: self.reasoning.map_or("", r => r.content) + text,
          complete: false,
        }),
      }
    }
    @transcript.ReasoningMessage(text) =>
      {
        ..self,
        reasoning: if text.trim().is_empty() {
          None
        } else {
          Some({ content: text, complete: true, })
        },
      }
    @transcript.AssistantMessage(_) =>
      {
        response: None,
        reasoning: self.reasoning.map(r => { ..r, complete: true, }),
      }
    _ => self
  }
}

///|
/// The provisional reasoning to render beside the durable `committed`
/// transcript. A sealed preview equal to reasoning committed after `frontier`,
/// the durable frontier when this step began, is already shown by its durable
/// row, so hide only that visual duplicate. Never hide an in-flight prefix and
/// never change the preview from a commit: commits carry no run or step
/// identity, and an older delayed commit must not truncate a newer stream.
pub fn Stream::visible_reasoning(
  self : Stream,
  committed : Array[@transcript.TranscriptItem],
  frontier~ : Int32,
) -> (String?, Bool) {
  guard self.reasoning is Some(live) && !live.content.is_empty() else {
    return (None, false)
  }
  let candidate = live.content.trim()
  if live.complete && !candidate.is_empty() {
    for item in committed.rev_iter() {
      if item.kind is Assistant(reasoning=Some(thought), ..) {
        if item.sequence is Some(sequence) &&
          sequence > frontier &&
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
pub extend Reasoning with Eq::{equal, not_equal}

///|
pub extend Stream with Eq::{equal, not_equal}

///|
pub fn Stream::empty() -> Stream {
  { response: None, reasoning: None, }
}

///|
pub extend Reasoning with Debug::{to_repr}
