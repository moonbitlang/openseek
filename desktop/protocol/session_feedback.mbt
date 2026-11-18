///|
pub(all) struct FeedbackMetadata {
  message : String
  environment : Map[String, Json]
}

///|
pub impl ToJson for FeedbackMetadata with fn to_json(self) {
  { "message": self.message, "environment": Json::object(self.environment) }
}

///|
pub impl FromJson for FeedbackMetadata with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "feedback metadata")
  let message = obj.required_string("message")
  guard !message.is_blank() else {
    raise JsonDecodeError(
      (path.add_key("message"), "feedback requires a message"),
    )
  }
  {
    message,
    environment: @json.from_json(
      obj.required_json("environment"),
      path=path.add_key("environment"),
    ),
  }
}

///|
pub(all) struct SessionFeedbackPayload {
  user_id : String
  source : SessionExportPayload
  metadata : FeedbackMetadata
}

///|
pub impl ToJson for SessionFeedbackPayload with fn to_json(self) {
  {
    "user_id": self.user_id,
    "source": self.source.to_json(),
    "metadata": ToJson::to_json(self.metadata),
  }
}

///|
pub impl FromJson for SessionFeedbackPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session feedback")
  {
    user_id: obj.required_string("user_id"),
    source: @json.from_json(
      obj.required_json("source"),
      path=path.add_key("source"),
    ),
    metadata: @json.from_json(
      obj.required_json("metadata"),
      path=path.add_key("metadata"),
    ),
  }
}

///|
pub(all) struct FeedbackReceipt {
  id : String
}

///|
pub impl ToJson for FeedbackReceipt with fn to_json(self) {
  { "id": self.id }
}

///|
pub impl FromJson for FeedbackReceipt with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "feedback receipt")
  let id = obj.required_string("id")
  guard !id.is_blank() else {
    raise JsonDecodeError((path.add_key("id"), "missing feedback id"))
  }
  { id, }
}
