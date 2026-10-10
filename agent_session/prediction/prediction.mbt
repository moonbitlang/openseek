///|
const PredictionPrompt : String =
  #|Predict the single message the user is most likely to type next.
  #|Use the preceding conversation as context. This is a next-message prediction
  #|request; do not continue the task or call tools.
  #|Use the user's recent messages, original goal, and what has already been done.
  #|Predict what they would naturally type, not what you think they should do.
  #|A good suggestion should make the user think: "I was about to type that."
  #|Match their language and concise writing style. Never call tools.
  #|
  #|Completing the current task does not mean the conversation has no next step.
  #|When supported by the context, suggest a natural follow-up, for example:
  #|- A requested fix is implemented but not tested: "run the tests".
  #|- Changes are ready to try: "build a development version so I can test it".
  #|- A fix is complete and tests pass: "commit the changes" or "open a PR".
  #|- The assistant presents a plan and awaits confirmation: "implement that plan".
  #|- The assistant offers options: the option the user is most likely to choose.
  #|These are examples, not a checklist. Choose only one likely next message.
  #|Do not repeat completed actions or suggest actions the user has ruled out.
  #|Do not invent unrelated work or new goals, give generic praise or thanks,
  #|speak as the assistant, or provide a list of alternatives or an explanation.
  #|Return null when there is no reasonably clear next message. Do not return
  #|null merely because the current task is complete, and do not force a follow-up.
  #|
  #|Output only a JSON object with exactly one field: {"text": "suggested message"}.
  #|The suggestion must be one short line, at most 240 characters.
  #|If there is no suitable suggestion, output {"text": null}.

///|
/// A skipped prediction made no provider request. A completed prediction carries
/// usage even when the model chose not to suggest a next message (`text=None`).
pub enum GenerationResult {
  Skipped
  Completed(text~ : String?, usage~ : @deepseek.Usage)
}

///|
/// Predict from an immutable session snapshot without recording a user turn.
/// Reuse the main agent's model-facing projection and tool definitions so the
/// provider can reuse its cached prefix. Only the prediction instruction is new.
/// Tool definitions are context: this function never executes returned calls.
/// The caller supplies a client with its own bounded retry/reasoning policy.
pub async fn generate(
  client : @client.Client,
  session : @agent_session.Session,
  tools~ : Array[@deepseek.ToolDefinition],
) -> GenerationResult {
  let messages = session.chat_messages()
  guard messages.length() > 1 else { return Skipped }
  messages.push(ChatMessage(User, content=[Text(PredictionPrompt)]))
  // Adding JSON mode reduced parent cache hits in DeepSeek comparisons.
  // Request JSON in the appended prompt and validate it below instead.
  let response = @async.with_timeout(8000, () => {
    client.chat(messages, tools~, max_tokens=1024)
  })
  guard response.tool_calls.is_empty() else {
    fail("prediction returned a tool call")
  }
  let value = @json.parse(response.content)
  let text = match value {
    { "text": Null, .. } => None
    { "text": String(text), .. } => {
      let text = text.trim().to_owned()
      guard !text.is_empty() &&
        text.length() <= 240 &&
        !text.contains("\n") &&
        !text.contains("\r") else {
        fail("invalid prediction text")
      }
      Some(text)
    }
    _ => fail("invalid prediction response")
  }
  Completed(text~, usage=response.usage)
}
