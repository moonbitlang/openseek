///|
#derive(Eq, Debug)
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
  source : SessionExportPayload
  user_id : String
  idempotency_key : String
  metadata : FeedbackMetadata
}

///|
pub impl ToJson for SessionFeedbackPayload with fn to_json(self) {
  {
    "source": self.source.to_json(),
    "user_id": self.user_id,
    "idempotency_key": self.idempotency_key,
    "metadata": ToJson::to_json(self.metadata),
  }
}

///|
pub impl FromJson for SessionFeedbackPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session feedback")
  {
    user_id: obj.required_string("user_id"),
    idempotency_key: obj.required_string("idempotency_key"),
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
pub impl FromJson for FeedbackReceipt with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "feedback receipt")
  let id = obj.required_string("id")
  guard !id.is_blank() else {
    raise JsonDecodeError((path.add_key("id"), "missing feedback id"))
  }
  { id, }
}

///|
#derive(Eq, Debug)
pub(all) enum SessionFeedbackReply {
  Submitted(id~ : String)
  SignInRequired
  Failed(message~ : String)
}

///|
pub impl FromJson for SessionFeedbackReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session feedback reply")
  match obj.required_string("status") {
    "submitted" => {
      let receipt : FeedbackReceipt = @json.from_json(json, path~)
      Submitted(id=receipt.id)
    }
    "sign_in_required" => SignInRequired
    "failed" => Failed(message=obj.required_string("message"))
    _ => raise JsonDecodeError((path, "invalid session feedback status"))
  }
}

///|
pub impl ToJson for SessionFeedbackReply with fn to_json(self) {
  match self {
    Submitted(id~) => { "status": "submitted", "id": id }
    SignInRequired => { "status": "sign_in_required" }
    Failed(message~) => { "status": "failed", "message": message }
  }
}
