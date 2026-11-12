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
