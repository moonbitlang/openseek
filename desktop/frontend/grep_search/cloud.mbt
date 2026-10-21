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

///|
fn cloud_semantic_body(payload : @protocol.SearchSemanticPayload) -> Json {
  {
    "patterns": payload.patterns,
    "include_glob": payload.include_glob,
    "exclude_glob": payload.exclude_glob,
    "generation": payload.generation,
    "max_results": payload.max_results,
  }
}

///|
/// Each subscription owns one HTTP stream. Closing it cancels only that
/// request; owner identity and generation fence progress in the shared reducer.
async fn cloud_semantic_search(
  token : String,
  session : String,
  payload : @protocol.SearchSemanticPayload,
  opened : (() -> Unit) -> Unit,
  active : () -> Bool,
  progress : (@protocol.SemanticSearchProgressPayload) -> Unit,
) -> @protocol.SearchSemanticReply {
  @async.with_task_group(group => {
    let task = group.spawn(
      () => {
        let client = @http.Client(@cloud_client.CloudOrigin, headers={
          "Authorization": "Bearer " + token,
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
        }) catch {
          _ => raise @cloud_client.RequestError(Unreachable)
        }
        defer client.close()
        let response = client.post(
          "/v1/sessions/\{@uri.encode_component(session)}/files/search/semantic",
          cloud_semantic_body(payload).stringify(),
        ) catch {
          _ => raise @cloud_client.RequestError(Unreachable)
        }
        @cloud_client.check_status(response.code)
        let parser = @cloud_client.SseParser::new()
        while active() {
          let line = client.read_until("\n") catch {
            _ => raise @cloud_client.RequestError(Unreachable)
          }
          guard active() && line is Some(line) else { break }
          if parser.line(line) is Some((event, data)) {
            if event != "progress" && event != "result" {
              continue
            }
            let fields : Map[String, Json] = @json.from_json(@json.parse(data))
            fields["root"] = Json(payload.root)
            if event == "result" {
              return @json.from_json(Json(fields))
            }
            fields["session_key"] = Json(payload.session_key)
            progress(@json.from_json(Json(fields)))
          }
        }
        // EOF before a final result must not report an incomplete scan as success.
        raise @cloud_client.RequestError(Malformed)
      },
      allow_failure=true,
    )
    opened(() => task.cancel())
    task.wait()
  })
}
