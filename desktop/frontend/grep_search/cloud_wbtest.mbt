///|
fn cloud_input(
  account~ : String = "account",
  session~ : String = "session",
) -> Input {
  Input::cloud(
    owner=Cloud(account~, session~),
    access={ token: "test-token", epoch: 4, },
    root=@resource.cloud_root(@cloud_client.CloudOrigin, account, session).unwrap(),
  )
}

///|
test "Cloud text search sends the shared options without Host routing fields" {
  let input = cloud_input()
  let state = State::empty()
    .handle(QueryChanged("moon\\w+"), input)
    .handle(ToggleRegex, input)
    .handle(ToggleCaseSensitive, input)
    .handle(ToggleWholeWord, input)
    .handle(IncludeChanged("src/**/*.mbt"), input)
    .handle(ExcludeChanged("**/*_test.mbt"), input)
    .handle(Submit, input)
  let payload = state.page.text_request_payload(input).unwrap()
  let body : Map[String, Json] = @json.from_json(cloud_search_body(payload))
  assert_eq(body.length(), 8)
  assert_eq(body.get("root"), None)
  assert_eq(body.get("session_key"), None)
  assert_eq(body.get("query"), Some(Json("moon\\w+")))
  assert_eq(body.get("regex"), Some(Json(true)))
  assert_eq(body.get("case_sensitive"), Some(Json(true)))
  assert_eq(body.get("whole_word"), Some(Json(true)))
  assert_eq(body.get("include_glob"), Some(Json("src/**/*.mbt")))
  assert_eq(body.get("exclude_glob"), Some(Json("**/*_test.mbt")))
  assert_eq(body.get("generation"), Some(Json(state.page.generation)))
  assert_eq(body.get("max_results"), Some(Json(MaxSearchResults)))
}

///|
test "Cloud search reuses match decoding and navigation with a virtual root" {
  let input = cloud_input()
  let state = State::empty().handle(QueryChanged("moon"), input)
  let raw : Json = {
    "generation": state.page.generation,
    "matches": [
      {
        "path": "src/main.mbt",
        "line_number": 7,
        "preview": "😀 moon",
        "preview_start_column": 9,
        "ranges": [{ "start_column": 12, "end_column": 16 }],
      },
    ],
    "match_count": 1,
    "file_count": 1,
    "limit_hit": false,
    "cancelled": false,
  }
  let reply = decode_cloud_search_reply(raw, input.root_text())
  let next = state.handle(
    Loaded(
      owner=input.owner,
      root=input.root_text(),
      generation=state.page.generation,
      reply~,
    ),
    input,
  )
  assert_eq(reply.root, "/")
  assert_true(next.page.phase is Ready)
  let items = next.page.result_items()
  assert_eq(items.length(), 1)
  assert_eq(items[0].path, "src/main.mbt")
  assert_eq(items[0].target, @common.Range(7, 12, 7, 16))
  assert_eq(items[0].preview[0].highlight_slices(items[0].ranges), [(3, 7)])
  assert_eq(next.page.match_count, 1)
  // Account/session identities fence responses even though both virtual paths
  // are slash-rooted, and old query generations never replace current data.
  let stale = Loaded(
    owner=input.owner,
    root="/",
    generation=state.page.generation,
    reply~,
  )
  let other = cloud_input(account="other")
  assert_true(state.handle(stale, other).page == state.page)
  let changed = state.handle(QueryChanged("new"), input)
  assert_true(changed.handle(stale, input).page == changed.page)
}

///|
test "Cloud search preserves service errors and rejects malformed match ranges" {
  let reply = decode_cloud_search_reply(
    {
      "generation": 1,
      "matches": [],
      "match_count": 0,
      "file_count": 0,
      "limit_hit": false,
      "cancelled": false,
      "error_code": "invalid_regex",
      "error_message": "regex parse error",
    },
    "/",
  )
  assert_eq(
    reply.error,
    Some({ code: "invalid_regex", message: "regex parse error", }),
  )
  let malformed : Json = {
    "generation": 1,
    "matches": [
      {
        "path": "main.mbt",
        "line_number": 1,
        "preview": "moon",
        "preview_start_column": 1,
        "ranges": [{ "start_column": 0, "end_column": 3 }],
      },
    ],
    "match_count": 1,
    "file_count": 1,
    "limit_hit": false,
    "cancelled": false,
  }
  let rejected = try {
    ignore(decode_cloud_search_reply(malformed, "/"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "Cloud semantic search keeps workspace ownership and shares request limits" {
  let input = cloud_input()
  assert_true(input.owns_root(input.root.unwrap()))
  assert_false(input.owns_root(cloud_input(session="other").root.unwrap()))
  assert_false(input.owns_root(@common.Uri::parse("file:///work")))
  let state = State::empty().handle(ModeChanged(Semantic), input)
  assert_true(state.page.mode is Semantic)
  let host = Input(
    model="model",
    thinking=None,
    owner={ channel: Local, session: "local", },
    root=Some(@resource.of_path(Local, "/work").unwrap()),
  )
  let semantic = State::empty().handle(ModeChanged(Semantic), host)
  assert_true(semantic.reset_checkout().page.mode is Semantic)
  let cloud = semantic.reset_checkout(text_only=true)
  assert_true(cloud.page.mode is Text)
  assert_eq(cloud.page.generation, semantic.page.generation + 1)
  let requested = state.handle(PatternChanged(0, "inspect($_)"), input)
  let payload = requested.page.semantic_request_payload(input).unwrap()
  assert_eq(payload.root, "/")
  assert_eq(payload.session_key, input.semantic_session_key())
  assert_eq(payload.max_results, MaxSearchResults)
  let body : Map[String, Json] = @json.from_json(cloud_semantic_body(payload))
  assert_eq(body.length(), 5)
  assert_eq(body.get("root"), None)
  assert_eq(body.get("session_key"), None)
  assert_eq(body.get("patterns"), Some(Json(["inspect($_)"])))
}
