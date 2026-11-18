///|
async fn ApiState::submit_feedback(
  self : ApiState,
  payload : @protocol.SessionFeedbackPayload,
  origin~ : String,
  token~ : String,
) -> @protocol.FeedbackReceipt {
  let metadata : Map[String, Json] = {
    "message": Json(payload.metadata.message),
    "environment": Json::object(payload.metadata.environment),
    "source": { "mode": "local", "session_id": payload.source.session },
  }
  let (files, transcript_error) = try {
    let (shell, bundle) = self.host_state().viz_assets().read()
    let files = @engine.ConversationExport::capture(
      self.manager(),
      payload.source,
      shell,
      bundle,
    )
    (
      Some(@protocol.SessionSnapshot::{ html: files.html, json: files.json, }),
      None,
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      let reason = error.to_string()
      metadata["transcript_error"] = Json(reason)
      (None, Some(reason))
    }
  }
  let receipt = @feedback.submit(
    origin,
    "/v1/feedback",
    token,
    Json::object(metadata),
    files?,
  )
  { ..receipt, transcript_error, }
}
