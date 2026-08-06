// Local preferences and host-owned engine settings transitions.

///|
test "the default provider needs no API key to be ready" {
  let model = test_model()
  assert_false(model.deepseek_key_saved)
  assert_true(model.api_ready())
}

///|
test "the official endpoint requires a key, a custom endpoint a URL" {
  let official = { ..test_model(), api_provider: Deepseek }
  assert_false(official.api_ready())
  assert_true(official.display_status() is ApiKeyRequired)
  assert_true({ ..official, deepseek_key_saved: true }.api_ready())
  let custom = { ..test_model(), api_provider: Custom, custom_api_url: "" }
  assert_false(custom.api_ready())
  assert_true(custom.display_status() is SetupRequired)
  let configured = {
    ..custom,
    custom_api_url: "https://proxy.example/chat/completions",
  }
  assert_true(configured.api_ready())
}

///|
test "loaded UI preferences parse their wire names" {
  let dispatch = test_dispatch()
  let (_, restored) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="top-left",
      tree_layout="",
      theme="dark",
      model="deepseek-v4-flash",
      conversation_models="[{\"key\":\"local/desktop-test\",\"model\":\"deepseek-v4-pro\"}]",
    ),
    test_model(),
  )
  assert_true(restored.notification_corner is TopLeft)
  assert_true(restored.theme is Dark)
  assert_true(restored.default_model is Low)
  // The stored conversation outranks the stored default for its own chat.
  assert_true(restored.active().engine_model is High)
  // Unknown stored values fall back to the defaults.
  let (_, unknown) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="",
      tree_layout="",
      theme="broken",
      model="",
      conversation_models="not json",
    ),
    test_model(),
  )
  assert_true(unknown.notification_corner is BottomRight)
  assert_true(unknown.theme is System)
  assert_true(unknown.default_model is High)
  // A store that will not parse remembers nothing rather than wedging.
  assert_eq(unknown.conversation_models.length(), 0)
}

///|
test "the model chip switches one conversation, not the app" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation(
    empty_conversation(@interop.ChannelId::Local, "other-chat"),
  )
  let (_, low) = update(dispatch, ToggleModel, model)
  assert_true(low.active().engine_model is Low)
  // The conversation next door keeps the tier it was already on.
  guard low.find_conversation(@interop.ChannelId::Local, "other-chat")
    is Some(other) else {
    fail("the second conversation vanished")
  }
  assert_true(other.engine_model is High)
  // The tier just picked is what conversations opened afterwards start from.
  assert_true(low.default_model is Low)
  assert_true(
    low.activate(@interop.ChannelId::Local, "fresh-chat").active().engine_model
    is Low,
  )
  // Toggling back is the same one click.
  let (_, high) = update(dispatch, ToggleModel, low)
  assert_true(high.active().engine_model is High)
}

///|
test "a start never overrides the tier picked for the next turn" {
  let dispatch = test_dispatch()
  // The chip stays live while a turn spawns, so the user can flip it for the
  // next turn before this one's `Started` arrives. The start is older than
  // that choice and must not undo it — the same holds for a turn another
  // client began, which says nothing about what this user means to send.
  let (_, queued) = update(dispatch, ToggleModel, test_model())
  assert_true(queued.active().engine_model is Low)
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=None,
      submission_id=None,
    ),
    queued,
  )
  assert_true(ran.active().engine_model is Low)
}

///|
test "reopening a conversation recovers its own tier, not the last pick" {
  let dispatch = test_dispatch()
  // Set the chat on screen to Low, then open a different one and put it back
  // on High. The second pick moves the default new chats inherit — it must
  // not follow the first conversation home.
  let (_, low) = update(dispatch, ToggleModel, test_model())
  let other = low.activate(@interop.ChannelId::Local, "other-chat")
  assert_true(other.active().engine_model is Low)
  let (_, high) = update(dispatch, ToggleModel, other)
  assert_true(high.default_model is High)
  // Reopening drops the conversation and mints it again (nothing was sent,
  // so `activate` does not retain it) — exactly the path that used to hand
  // back the unrelated default.
  let reopened = high.activate(@interop.ChannelId::Local, "desktop-test")
  assert_true(reopened.active().engine_model is Low)
}

///|
test "a run pins an inherited tier the user never clicked for" {
  let dispatch = test_dispatch()
  // This chat never touched the chip — it just inherited High and ran. That
  // still has to pin, or a later toggle elsewhere silently retiers it.
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_true(
    ran.remembered_model(@interop.ChannelId::Local, "desktop-test")
    is Some(High),
  )
  // Another chat moves the page default to Low...
  let elsewhere = ran.activate(@interop.ChannelId::Local, "other-chat")
  let (_, moved) = update(dispatch, ToggleModel, elsewhere)
  assert_true(moved.default_model is Low)
  // ...and the first one still comes back on the tier it ran with.
  let reopened = moved.activate(@interop.ChannelId::Local, "desktop-test")
  assert_true(reopened.active().engine_model is High)
}

///|
test "remembered tiers survive a round trip through storage" {
  let dispatch = test_dispatch()
  let (_, chosen) = update(dispatch, ToggleModel, test_model())
  let restored = parse_conversation_models(
    encoded_conversation_models(chosen.conversation_models),
  )
  assert_eq(restored, chosen.conversation_models)
  assert_true(restored is [{ key: "local/desktop-test", model: Low }])
}

///|
test "a write merges into the stored rows instead of replacing them" {
  // A sibling console tab on the same origin wrote these while this page held
  // a copy loaded at its own startup. Pinning here must not drop the other
  // tab's row — that conversation would silently revert to the default.
  let stored = parse_conversation_models(
    encoded_conversation_models([
      { key: "remote.b/sibling-chat", model: Low },
      { key: "remote.a/desktop-test", model: High },
    ]),
  )
  let merged = remembered_with(stored, "remote.a/desktop-test", Low)
  assert_true(
    merged
    is [
      { key: "remote.a/desktop-test", model: Low },
      { key: "remote.b/sibling-chat", model: Low },
    ],
  )
}

///|
/// Test-only: the stored spelling of a remembered list, as
/// `save_conversation_model` writes it.
fn encoded_conversation_models(
  entries : Array[StoredConversationModel],
) -> String {
  let rows : Array[Json] = entries.map(entry => {
    "key": entry.key.to_json(),
    "model": entry.model.wire().to_json(),
  })
  rows.to_json().stringify()
}

///|
test "the remembered list stays capped, newest first" {
  let mut model = test_model()
  // One past the cap, so the first conversation chosen for is the one that
  // falls off and reverts to the page default.
  for index in 0..<=ConversationModelsLimit {
    model = model.remember_model(
      @interop.ChannelId::Local,
      "session-\{index}",
      if index % 2 == 0 {
        Low
      } else {
        High
      },
    )
  }
  assert_eq(model.conversation_models.length(), ConversationModelsLimit)
  assert_true(
    model.remembered_model(@interop.ChannelId::Local, "session-0") is None,
  )
  assert_true(
    model.remembered_model(
      @interop.ChannelId::Local,
      "session-\{ConversationModelsLimit}",
    )
    is Some(Low),
  )
  // Re-choosing an existing conversation moves it, never duplicates it.
  let again = model.remember_model(@interop.ChannelId::Local, "session-1", Low)
  assert_eq(again.conversation_models.length(), ConversationModelsLimit)
  assert_true(
    again.remembered_model(@interop.ChannelId::Local, "session-1") is Some(Low),
  )
}

///|
test "a conversation first met through a live run adopts its tier" {
  let dispatch = test_dispatch()
  // No local choice exists to contradict the run, so its tier is the best
  // evidence available — and it lands on that conversation alone, moving
  // neither the chat on screen nor the default new chats start from.
  let (_, background) = update_dev(
    dispatch,
    Started(
      run_id="r2",
      session="background-chat",
      model=Low,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=None,
      submission_id=None,
    ),
    test_model(),
  )
  guard background.find_conversation(
      @interop.ChannelId::Local,
      "background-chat",
    )
    is Some(conv) else {
    fail("the background run materialized no conversation")
  }
  assert_true(conv.engine_model is Low)
  assert_true(background.active().engine_model is High)
  assert_true(background.default_model is High)
}

///|
fn host_settings(
  provider~ : String,
  revision? : Int = 0,
  has_deepseek_key? : Bool = false,
) -> HostSettings {
  {
    revision,
    provider,
    custom_api_url: "",
    has_deepseek_key,
    has_custom_key: false,
  }
}

///|
test "host settings edits wait for the focused host snapshot" {
  let dispatch = test_dispatch()
  // Model a queued DOM message from the old Settings page after focus already
  // moved. The negative revision is authoritative: none of these stale values
  // or events may be applied to the replacement host.
  let loading = {
    ..test_model(),
    api_provider: Deepseek,
    custom_api_url: "https://old.example/chat",
    deepseek_key_saved: true,
    setup_api_key: "old-device-key",
    host_settings_revision: -1,
  }
  let messages : Array[Msg] = [
    SetupApiKeyChanged("queued-key"),
    ProviderChanged("custom"),
    CustomApiUrlChanged("https://new.example/chat"),
    SaveApiKey,
  ]
  for message in messages {
    let (_, once) = update(dispatch, message, loading)
    let (_, twice) = update(dispatch, message, loading)
    assert_true(once.api_provider == loading.api_provider)
    assert_eq(once.custom_api_url, loading.custom_api_url)
    assert_eq(once.setup_api_key, loading.setup_api_key)
    assert_eq(once.settings_saves, 0)
    assert_true(twice.api_provider == loading.api_provider)
    assert_eq(twice.custom_api_url, loading.custom_api_url)
    assert_eq(twice.setup_api_key, loading.setup_api_key)
    assert_eq(twice.settings_saves, 0)
  }
}

///|
test "host settings open the settings page only when incomplete" {
  let dispatch = test_dispatch()
  let (_, zero_config) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="openseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(zero_config.screen is Chat)
  assert_true(zero_config.api_provider is Openseek)
  assert_true(zero_config.display_status() is Ready)
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(keyless.screen is Settings)
  assert_true(keyless.display_status() is ApiKeyRequired)
  let (_, restored) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", has_deepseek_key=true),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(restored.screen is Chat)
  assert_true(restored.deepseek_key_saved)
}

///|
test "a background device's pushes leave the focused mirrors alone" {
  let dispatch = test_dispatch()
  let background : @interop.ChannelId = Remote("d_bg")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected },
      { ..empty_device_state(background), bridge: Connected },
    ],
  }
  // A settings.changed broadcast from the background device: the form (and
  // the incomplete-settings redirect) keeps the focused host's state.
  let (_, settled) = update(
    dispatch,
    FromDevice(
      background,
      HostSettingsLoaded(
        host_settings(provider="deepseek"),
        connection_generation=None,
      ),
    ),
    model,
  )
  assert_true(settled.api_provider is Openseek)
  assert_true(settled.screen is Chat)
}

///|
test "host settings are deferred while this client's writes are in flight" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), settings_saves: 1 }
  // A broadcast (or a stale get reply) arriving mid-write must not clobber
  // the optimistic mirror.
  let (_, ignored) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", revision=1),
      connection_generation=None,
    ),
    model,
  )
  assert_true(ignored.api_provider is Openseek)
  inspect(ignored.settings_saves, content="1")
  // The write's own reply reconciles once it is the last one out.
  let (_, settled) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=2, has_deepseek_key=true),
      connection_generation=0,
      cleans_legacy=false,
    ),
    model,
  )
  inspect(settled.settings_saves, content="0")
  assert_true(settled.api_provider is Deepseek)
  assert_true(settled.deepseek_key_saved)
  inspect(settled.host_settings_revision, content="2")
  // With more writes still out, even a reply only decrements.
  let stacked = { ..model, settings_saves: 2 }
  let (_, still_pending) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=1),
      connection_generation=0,
      cleans_legacy=false,
    ),
    stacked,
  )
  inspect(still_pending.settings_saves, content="1")
  assert_true(still_pending.api_provider is Openseek)
}

///|
test "a newer peer broadcast beats a delayed local settings reply" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Custom,
    settings_saves: 1,
    host_settings_revision: 5,
  }
  let (_, broadcast) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", revision=7),
      connection_generation=None,
    ),
    model,
  )
  // Preserve the optimistic form until the local RPC settles.
  assert_true(broadcast.api_provider is Custom)
  let (_, settled) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="openseek", revision=6),
      connection_generation=0,
      cleans_legacy=false,
    ),
    broadcast,
  )
  assert_true(settled.api_provider is Deepseek)
  inspect(settled.host_settings_revision, content="7")
  inspect(settled.settings_saves, content="0")
}

///|
test "legacy client settings migrate up only from the desktop window" {
  let dispatch = test_dispatch()
  let legacy = LegacySettingsRead(
    provider="deepseek",
    custom_url="",
    api_key="sk-legacy",
    custom_api_key="",
  )
  let (_, desktop) = update(dispatch, legacy, {
    ..test_model(),
    is_desktop: true,
  })
  assert_true(desktop.api_provider is Deepseek)
  assert_true(desktop.deepseek_key_saved)
  inspect(desktop.settings_saves, content="1")
  assert_true(desktop.legacy_cleanup_pending)
  // A browser page only purges — its copy may belong to another device.
  let (_, browser) = update(dispatch, legacy, {
    ..test_model(),
    is_desktop: false,
  })
  assert_false(browser.deepseek_key_saved)
  inspect(browser.settings_saves, content="0")
  assert_false(browser.legacy_cleanup_pending)
}

///|
test "only the migration settings response owns legacy cleanup" {
  let dispatch = test_dispatch()
  let pending = {
    ..test_model(),
    settings_saves: 2,
    legacy_cleanup_pending: true,
  }
  // An unrelated save may finish first; it must not consume the migration's
  // right to clear localStorage when that exact write is acknowledged.
  let (_, unrelated) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="custom", revision=1),
      connection_generation=0,
      cleans_legacy=false,
    ),
    pending,
  )
  inspect(unrelated.settings_saves, content="1")
  assert_true(unrelated.legacy_cleanup_pending)
  let (_, migrated) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=2, has_deepseek_key=true),
      connection_generation=0,
      cleans_legacy=true,
    ),
    unrelated,
  )
  inspect(migrated.settings_saves, content="0")
  assert_false(migrated.legacy_cleanup_pending)
  assert_true(migrated.api_provider is Deepseek)
  assert_true(migrated.deepseek_key_saved)
}

///|
test "a failed migration keeps legacy storage for a later launch" {
  let dispatch = test_dispatch()
  let pending = {
    ..test_model(),
    settings_saves: 1,
    legacy_cleanup_pending: true,
  }
  let (_, failed) = update_dev(
    dispatch,
    HostSettingsSaveFailed(
      "host write failed",
      connection_generation=0,
      cleans_legacy=true,
    ),
    pending,
  )
  inspect(failed.settings_saves, content="0")
  // False means this launch must not clear localStorage; LegacySettingsRead
  // on the next launch will discover and retry the still-present values.
  assert_false(failed.legacy_cleanup_pending)
}

///|
test "background settings replies cannot alter the focused host mirror" {
  let dispatch = test_dispatch()
  let home = test_model()
  let focused = {
    ..home,
    devices: [
      home.devices[0],
      { ..empty_device_state(Remote("d_b")), bridge: Connected },
    ],
    focused: Remote("d_b"),
    api_provider: Custom,
    settings_saves: 1,
  }
  let (_, applied) = update(
    dispatch,
    FromDevice(
      Local,
      HostSettingsApplied(
        host_settings(provider="deepseek", revision=7),
        connection_generation=0,
        cleans_legacy=false,
      ),
    ),
    focused,
  )
  assert_true(applied.api_provider is Custom)
  assert_eq(applied.settings_saves, 1)
  let (_, failed) = update(
    dispatch,
    FromDevice(
      Local,
      HostSettingsSaveFailed(
        "old host failed",
        connection_generation=0,
        cleans_legacy=false,
      ),
    ),
    applied,
  )
  assert_eq(failed.settings_saves, 1)
  assert_eq(failed.notifications.length(), 0)
}

///|
test "the notification-corner setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, moved) = update(
    dispatch,
    NotificationCornerChanged("top-right"),
    test_model(),
  )
  assert_true(moved.notification_corner is TopRight)
  let (_, unknown) = update(
    dispatch,
    NotificationCornerChanged("nowhere"),
    moved,
  )
  assert_true(unknown.notification_corner is BottomRight)
}

///|
test "the tree-layout setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, docked) = update(
    dispatch,
    TreeLayoutChanged("bottom-panel"),
    test_model(),
  )
  assert_true(docked.tree_layout is BottomPanel)
  // An unknown stored value falls back to the default right sidebar.
  let (_, unknown) = update(dispatch, TreeLayoutChanged("floating"), docked)
  assert_true(unknown.tree_layout is RightSidebar)
}

///|
test "update is pure: a provider change is idempotent" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), setup_api_key: "typed" }
  let (_, once) = update(dispatch, ProviderChanged("deepseek"), model)
  let (_, twice) = update(dispatch, ProviderChanged("deepseek"), model)
  assert_true(once.api_provider is Deepseek)
  assert_true(twice.api_provider is Deepseek)
  inspect(once.setup_api_key, content="")
  inspect(twice.setup_api_key, content="")
  inspect(once.settings_saves, content="1")
  inspect(twice.settings_saves, content="1")
  assert_true(once.display_status() is ApiKeyRequired)
  assert_true(twice.display_status() is ApiKeyRequired)
}

///|
test "saving a key marks the active provider credential only" {
  let dispatch = test_dispatch()
  let deepseek = {
    ..test_model(),
    api_provider: Deepseek,
    setup_api_key: "  sk-new  ",
    screen: Settings,
  }
  let (_, saved_deepseek) = update(dispatch, SaveApiKey, deepseek)
  assert_true(saved_deepseek.deepseek_key_saved)
  assert_false(saved_deepseek.custom_key_saved)
  inspect(saved_deepseek.setup_api_key, content="")
  inspect(saved_deepseek.settings_saves, content="1")
  assert_true(saved_deepseek.screen is Chat)
  let custom = {
    ..deepseek,
    api_provider: Custom,
    custom_api_url: "https://proxy.example/chat/completions",
    setup_api_key: "  sk-custom-new  ",
  }
  let (_, saved_custom) = update(dispatch, SaveApiKey, custom)
  assert_false(saved_custom.deepseek_key_saved)
  assert_true(saved_custom.custom_key_saved)
  assert_true(saved_custom.screen is Chat)
}

///|
test "changing settings mid-run leaves the run status alone" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, ProviderChanged("deepseek"), running_model())
  assert_true(next.display_status() is Running)
  assert_true(next.api_provider is Deepseek)
}
