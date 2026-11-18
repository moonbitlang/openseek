///|
async fn ApiState::submit_feedback(
  self : ApiState,
  payload : @protocol.SessionFeedbackPayload,
  origin~ : String,
  token~ : String,
) -> @protocol.FeedbackReceipt {
  let (shell, bundle) = self.host_state().viz_assets().read()
  let files = @engine.ConversationExport::capture(
    self.manager(),
    payload.source,
    shell,
    bundle,
  )
  @feedback.submit(
    origin,
    "/v1/feedback",
    token,
    {
      "message": payload.metadata.message,
      "environment": Json::object(payload.metadata.environment),
      "source": { "mode": "local", "session_id": payload.source.session },
    },
    files={ html: files.html, json: files.json, },
  )
}
