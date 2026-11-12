///|
pub using @protocol {type Content}

///|
/// One model-facing message before it is encoded for a request. It has the
/// shape of `@deepseek.ChatMessage`, but keeps durable session content, so the
/// wire form of each part is chosen by `to_chat_message` at request time.
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
/// Build the wire message for one request; inline images become data URLs.
pub fn ModelMessage::to_chat_message(
  self : ModelMessage,
) -> @deepseek.ChatMessage {
  ChatMessage(
    self.role,
    content=self.content.0.map(part => {
      match part {
        Text(text) => Text(text)
        Image(image) => ImageUrl(url=image.data_url())
      }
    }),
    tool_calls=self.tool_calls,
    reasoning_content?=self.reasoning_content,
  )
}
