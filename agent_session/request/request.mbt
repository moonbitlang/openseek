///|
/// Send model messages through `client`, resolving their image references to
/// DeepSeek file ids for this request only. A file the provider no longer
/// recognizes is forgotten and every image is resolved again once; a second
/// rejection propagates. `attachments` defaults to the user-level store and is
/// consulted only when the messages reference images.
pub async fn chat(
  client : @client.Client,
  messages : Array[@agent_session.ModelMessage],
  attachments? : @attachments.AttachmentStore,
  tools~ : Array[@deepseek.ToolDefinition] = [],
  response_format? : @deepseek.ResponseFormat,
  max_tokens? : Int32,
  stream? : @client.StreamHandler,
) -> @deepseek.ChatResponse {
  let references = @agent_session.image_refs(messages)
  if references.is_empty() {
    return client.chat(
      wire_messages(messages, Map([])),
      tools~,
      response_format?,
      max_tokens?,
      stream?,
    )
  }
  let attachments = attachments.unwrap_or_else(() => {
    @attachments.AttachmentStore::default()
  })
  let file_ids = client.upload_attachments(attachments, references)
  client.chat(
    wire_messages(messages, file_ids),
    tools~,
    response_format?,
    max_tokens?,
    stream?,
  ) catch {
    @client.RejectedImageFile(_) => {
      client.forget_uploads(attachments, file_ids.values().collect())
      client.chat(
        wire_messages(
          messages,
          client.upload_attachments(attachments, references),
        ),
        tools~,
        response_format?,
        max_tokens?,
        stream?,
      )
    }
    error => raise error
  }
}

///|
fn wire_messages(
  messages : Array[@agent_session.ModelMessage],
  file_ids : Map[String, String],
) -> Array[@deepseek.ChatMessage] raise {
  let images : Map[String, @deepseek.ContentPart] = file_ids.map((_, file_id) => {
    File(file_id~)
  })
  messages.map(message => message.to_chat_message(images))
}
