///|
test "Cloud preferences inherit defaults within an account and never alter Local" {
  let model = integrated_cloud_model()
  let owner : @interop.ConversationIdentity = Cloud(
    account="fixture-user",
    session="cloud-a",
  )
  let options : @cloud.CommandSettings = {
    model: V4Pro,
    thinking: ThinkingMax,
  }
  let (_, chosen) = model.choose_cloud_settings(owner, options)
  assert_true(chosen.cloud_settings(owner) == options)
  assert_true(
    chosen.cloud_settings(Cloud(account="fixture-user", session="new")) ==
    options,
  )
  assert_true(
    chosen.cloud_settings(Cloud(account="other", session="cloud-a")) ==
    @cloud.CommandSettings::default(),
  )
  assert_true(
    chosen.default_model == model.default_model &&
    chosen.openseek_reasoning == model.openseek_reasoning &&
    chosen.conversation_models == model.conversation_models,
  )
  let (_, ignored) = chosen.choose_cloud_settings(
    Cloud(account="other", session="cloud-a"),
    options,
  )
  assert_true(ignored.cloud_preferences == chosen.cloud_preferences)
  let (_, workspace) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    chosen,
  )
  let (_, ignored) = workspace.choose_cloud_settings(
    owner,
    @cloud.CommandSettings::default(),
  )
  assert_true(ignored.cloud_preferences == workspace.cloud_preferences)
  let (_, pinned) = chosen.remember_cloud_settings(
    Cloud(account="fixture-user", session="pinned"),
    options,
  )
  let (_, changed) = pinned.choose_cloud_settings(
    owner,
    @cloud.CommandSettings::default(),
  )
  assert_true(
    changed.cloud_settings(Cloud(account="fixture-user", session="pinned")) ==
    options,
  )
  let rows : Array[Json] = changed.cloud_preferences.map(entry => {
    "key": Json(entry.0),
    "settings": ToJson::to_json(entry.1),
  })
  let (_, restored) = update(
    test_dispatch(),
    CloudPreferencesLoaded(Some(Json(rows).stringify())),
    model,
  )
  assert_true(restored.cloud_preferences == changed.cloud_preferences)
  assert_true(parse_cloud_preferences("invalid").is_empty())
  let (_, stale) = update(
    test_dispatch(),
    CloudPreferencesLoaded(Some(Json(rows).stringify())),
    chosen,
  )
  assert_true(stale.cloud_settings(owner) == options)
}

///|
test "Cloud draft selection can change while its submitted command waits for creation" {
  let (_, draft) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let identity = draft.cloud_composer_input().unwrap().identity
  let (_, submitting) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity~, draft={
        task: "First",
        mentions: [],
        images: [],
      }),
    ),
    draft,
  )
  let (_, changed) = submitting.choose_cloud_settings(identity.owner, {
    model: V4Pro,
    thinking: ThinkingOff,
  })
  assert_true(
    changed.cloud.conversations[identity.owner.session()].outgoing
    is Some({ settings: { model: V4Flash, thinking: ThinkingHigh, }, .. }),
  )
  let (_, created) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Created(
        changed.cloud.epoch,
        changed.cloud.creation.unwrap().request,
        "created",
      ),
    ),
    changed,
  )
  assert_true(
    created.cloud_settings(Cloud(account="fixture-user", session="created")) ==
    { model: V4Pro, thinking: ThinkingOff, },
  )
}

///|
fn cloud_settings_history(settings : @cloud.CommandSettings?) -> @cloud.History {
  {
    settings,
    etag: Some("remote-settings"),
    offset: Some(0),
    prediction: None,
    generating: false,
    messages: [],
    session: { version: None, id: None, system_prompt: None, events: Some([]), },
  }
}

///|
fn load_remote_settings(
  model : Model,
  settings : @cloud.CommandSettings?,
) -> Model {
  let (_, opened) = update(
    test_dispatch(),
    CloudAction(@cloud.Open("cloud-a")),
    model,
  )
  let request = opened.cloud.conversations["cloud-a"].request
  update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(
        opened.cloud.epoch,
        "cloud-a",
        request,
        cloud_settings_history(settings),
      ),
    ),
    opened,
  ).1
}

///|
test "latest history initializes Cloud choices while unsent edits survive delayed responses" {
  let model = integrated_cloud_model()
  let owner : @interop.ConversationIdentity = Cloud(
    account="fixture-user",
    session="cloud-a",
  )
  let (_, remembered) = model.remember_cloud_settings(
    owner,
    @cloud.CommandSettings::default(),
  )
  let remote = load_remote_settings(
    remembered,
    Some({ model: V4Pro, thinking: ThinkingMax, }),
  )
  assert_true(
    remote.cloud_settings(owner) == { model: V4Pro, thinking: ThinkingMax, },
  )
  let unknown = load_remote_settings(remote, None)
  assert_true(unknown.cloud.conversations["cloud-a"].settings is None)
  assert_true(
    unknown.cloud_settings(owner) == @cloud.CommandSettings::default(),
  )
  let (_, waiting) = update(
    test_dispatch(),
    CloudAction(@cloud.Open("cloud-a")),
    remote,
  )
  let request = waiting.cloud.conversations["cloud-a"].request
  let choice : @cloud.CommandSettings = {
    model: V4Flash,
    thinking: ThinkingOff,
  }
  let (_, edited) = waiting.choose_cloud_settings(owner, choice)
  let (_, late) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(
        waiting.cloud.epoch,
        "cloud-a",
        request,
        cloud_settings_history(Some({ model: V4Pro, thinking: ThinkingHigh, })),
      ),
    ),
    edited,
  )
  assert_true(late.cloud_settings(owner) == choice)
  let late = late.with_cloud_baseline("cloud-a")
  let identity = late.cloud_composer_input().unwrap().identity
  let (_, submitted) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity~, draft={
        task: "Use my choice",
        mentions: [],
        images: [],
      }),
    ),
    late,
  )
  let send_request = submitted.cloud.conversations["cloud-a"].send_request
  assert_true(send_request > request)
  assert_true(submitted.cloud_settings(owner) == choice)
  let authoritative = load_remote_settings(
    submitted,
    Some({ model: V4Pro, thinking: ThinkingMax, }),
  )
  assert_true(
    authoritative.cloud_settings(owner) ==
    { model: V4Pro, thinking: ThinkingMax, },
  )
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(
      @cloud.SendFailed(
        submitted.cloud.epoch,
        "cloud-a",
        send_request,
        Unreachable,
      ),
    ),
    submitted,
  )
  let refreshed = load_remote_settings(
    failed,
    Some({ model: V4Pro, thinking: ThinkingMax, }),
  )
  assert_true(refreshed.cloud_settings(owner) == choice)
}
