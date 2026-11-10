///|
pub using @protocol {type Content}

///|
/// One model-facing message before provider resolution. It has the shape of
/// `@deepseek.ChatMessage`, but keeps durable session content: an `ImageRef`
/// stays a local reference until `to_chat_message` resolves it for one request.
#derive(Debug)
pub struct ModelMessage {
  role : @deepseek.Role
  content : Content
  tool_calls : Array[@deepseek.ToolCall]
  reasoning_content : String?
}

///|
pub extend ModelMessage with Debug::{to_repr}

///|
/// Construct a model message from ordered durable content parts.
pub fn ModelMessage::ModelMessage(
  role : @deepseek.Role,
  content~ : Array[@protocol.ContentPart],
  tool_calls~ : Array[@deepseek.ToolCall] = [],
  reasoning_content? : String,
) -> ModelMessage {
  { role, content: Content(content), tool_calls, reasoning_content, }
}

///|
/// Build the wire message for one request. `images` maps each attachment id to
/// the provider part resolved for this request; inline images become data URLs.
pub fn ModelMessage::to_chat_message(
  self : ModelMessage,
  images : Map[String, @deepseek.ContentPart],
) -> @deepseek.ChatMessage raise {
  let parts : Array[@deepseek.ContentPart] = []
  for part in self.content.0 {
    parts.push(
      match part {
        Text(text) => Text(text)
        Image(image) => ImageUrl(url=image.data_url())
        ImageRef(reference) => {
          guard images.get(reference.attachment_id) is Some(resolved) else {
            fail("unresolved image attachment: \{reference.attachment_id}")
          }
          resolved
        }
      },
    )
  }
  ChatMessage(
    self.role,
    content=parts,
    tool_calls=self.tool_calls,
    reasoning_content?=self.reasoning_content,
  )
}

///|
/// Distinct image references in first-use order, resolved once per request.
pub fn image_refs(messages : Array[ModelMessage]) -> Array[@protocol.ImageRef] {
  let refs : Array[@protocol.ImageRef] = []
  for message in messages {
    for part in message.content.0 {
      if part is ImageRef(reference) && !refs.contains(reference) {
        refs.push(reference)
      }
    }
  }
  refs
}

///|
/// Transform image-bearing content while preserving every event's metadata.
async fn SessionItem::map_content(
  self : SessionItem,
  transform : async (Content) -> Content,
) -> SessionItem {
  match self {
    User(message) => User({ ..message, content: transform(message.content), })
    Tool(result) => Tool({ ..result, content: transform(result.content), })
    _ => self
  }
}

///|
/// Transform a snapshot without changing event identities or timestamps.
pub async fn Session::map_content(
  self : Session,
  transform : async (Content) -> Content,
) -> Session {
  let mut events = @vector.from_array([])
  for event in self.events {
    events = events.push(event.map_content(transform))
  }
  { ..self, events, }
}

///|
/// Transform event content while retaining its original sequence and timestamp.
pub async fn SessionEvent::map_content(
  self : SessionEvent,
  transform : async (Content) -> Content,
) -> SessionEvent {
  { ..self, item: self.item.map_content(transform), }
}
