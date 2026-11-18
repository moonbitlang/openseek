///|
async fn ApiState::submit_feedback(
  self : ApiState,
  payload : @protocol.SessionFeedbackPayload,
  origin~ : String,
  token~ : String,
) -> @protocol.FeedbackReceipt {
  let conversation = self.manager().export_conversation_json(payload.source)
  @feedback.submit(
    origin,
    "/v1/feedback",
    token,
    {
      "message": payload.metadata.message,
      "environment": Json::object(payload.metadata.environment),
      "source": { "mode": "local", "session_id": payload.source.session },
    },
    conversation~,
  )
}
