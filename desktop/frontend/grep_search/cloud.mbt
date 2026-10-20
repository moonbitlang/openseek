///|
/// The Cloud session URL owns the workspace; Host routing fields never cross
/// this HTTP boundary. Keep the shared text-search options and result codec.
fn cloud_search_body(payload : @protocol.SearchTextPayload) -> Json {
  {
    "query": Json(payload.query),
    "regex": Json(payload.regex),
    "case_sensitive": Json(payload.case_sensitive),
    "whole_word": Json(payload.whole_word),
    "include_glob": Json(payload.include_glob),
    "exclude_glob": Json(payload.exclude_glob),
    "generation": Json(payload.generation),
    "max_results": Json(payload.max_results),
  }
}

///|
fn decode_cloud_search_reply(
  json : Json,
  root : String,
) -> @protocol.SearchTextReply raise @json.JsonDecodeError {
  let fields : Map[String, Json] = @json.from_json(json)
  fields["root"] = Json(root)
  @json.from_json(Json(fields))
}

///|
fn Input::owns_root(self : Input, root : @common.Uri) -> Bool {
  match self.owner {
    Host(owner) => @resource.belongs_to(root, owner.channel)
    Cloud(account~, session~) =>
      @resource.cloud_root(@cloud_client.CloudOrigin, account, session)
      is Some(expected) &&
      expected == root
  }
}
