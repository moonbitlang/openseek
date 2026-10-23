///|
pub(all) struct Reasoning {
  content : String
  complete : Bool
} derive(Eq, Debug)

///|
/// Provisional text belongs to an engine turn, never to durable history.
pub(all) struct Stream {
  response : String?
  reasoning : Reasoning?
} derive(Eq)

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
pub extend Reasoning with Eq::{equal, not_equal}

///|
pub extend Stream with Eq::{equal, not_equal}

///|
pub fn Stream::empty() -> Stream {
  { response: None, reasoning: None, }
}

///|
pub extend Reasoning with Debug::{to_repr}
