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
  share : SessionSharePayload
  metadata : FeedbackMetadata
}

///|
pub impl ToJson for SessionFeedbackPayload with fn to_json(self) {
  { "share": self.share.to_json(), "metadata": ToJson::to_json(self.metadata) }
}

///|
pub impl FromJson for SessionFeedbackPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session feedback")
  {
    share: @json.from_json(
      obj.required_json("share"),
      path=path.add_key("share"),
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
  url : String
}

///|
pub impl ToJson for FeedbackReceipt with fn to_json(self) {
  { "id": self.id, "url": self.url }
}

///|
pub impl FromJson for FeedbackReceipt with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "feedback receipt")
  let id = obj.required_string("id")
  guard !id.is_blank() else {
    raise JsonDecodeError((path.add_key("id"), "missing feedback id"))
  }
  let url = obj.required_string("url")
  guard @url.Url::try_parse(url) is Some(link) && link.protocol() == "https:" else {
    raise JsonDecodeError(
      (path.add_key("url"), "expected an HTTPS feedback URL"),
    )
  }
  { id, url: link.href(), }
}
