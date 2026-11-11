///|
test "Cloud pickers share Local choices without changing Local preferences" {
  let initial = integrated_cloud_model()
  let preferences = (
    initial.default_model,
    initial.openseek_reasoning,
    initial.conversation_models,
  )
  let (_, draft) = update(test_dispatch(), CloudAction(@cloud.Create), initial)
  let input = draft.cloud_composer_input().unwrap()
  let identity = input.identity
  assert_eq(
    draft.cloud.inference(identity.owner.session()),
    (V4Flash, ThinkingHigh),
  )
  let (_, selected) = update(
    test_dispatch(),
    ComposerAction(
      @composer.ModelSelected(identity~, value="openseek:deepseek-v4-pro", draft={
        task: "",
        mentions: [],
        images: [],
      }),
    ),
    draft,
  )
  let (_, selected) = update(
    test_dispatch(),
    ComposerAction(@composer.ReasoningSelected(identity~, value="max")),
    selected,
  )
  assert_eq(
    selected.cloud.inference(identity.owner.session()),
    (V4Pro, ThinkingMax),
  )
  assert_true(
    (
      selected.default_model,
      selected.openseek_reasoning,
      selected.conversation_models,
    ) ==
    preferences,
  )
  let (_, workspace) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    selected,
  )
  let (_, stale) = update(
    test_dispatch(),
    ComposerAction(@composer.ReasoningSelected(identity~, value="no")),
    workspace,
  )
  assert_true(stale.cloud == workspace.cloud)
  assert_true(
    (stale.default_model, stale.openseek_reasoning, stale.conversation_models) ==
    preferences,
  )
  let (_, resumed) = update(test_dispatch(), CloudAction(@cloud.Create), stale)
  assert_eq(
    resumed.cloud.inference(identity.owner.session()),
    (V4Pro, ThinkingMax),
  )
  let (_, menu) = update(
    test_dispatch(),
    ComposerAction(@composer.ModelMenuToggled(identity~)),
    resumed,
  )
  assert_true(menu.select_menu is Some(OpenSeekModelMenu))
  let (_, submitting) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity~, draft={
        task: "Question",
        mentions: [],
        images: [],
      }),
    ),
    menu,
  )
  assert_true(submitting.select_menu is None)
}

///|
test "Cloud save errors stay with their composer and retry the desired selection" {
  let initial = integrated_cloud_model()
  let identity = initial.cloud_composer_input().unwrap().identity
  let (_, pending) = update(
    test_dispatch(),
    ComposerAction(@composer.ReasoningSelected(identity~, value="no")),
    initial,
  )
  let request = pending.cloud.metadata_saves["cloud-a"].request
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(@cloud.EditFailed(3, "cloud-a", request, Unreachable)),
    pending,
  )
  let input = failed.cloud_composer_input().unwrap()
  assert_true(
    input.presentation.context.any(item => {
      item is @composer.SettingsSaveFailed(..)
    }),
  )
  assert_true(
    input.presentation.primary_action is @composer.Send(available=false),
  )
  assert_true(failed.cloud.notice is None)
  let (_, retry) = update(
    test_dispatch(),
    ComposerAction(@composer.SettingsSaveRetried(identity~)),
    failed,
  )
  assert_true(retry.cloud.metadata_saves["cloud-a"].request > request)
  assert_true(retry.cloud.metadata_saves["cloud-a"].error is None)
  let (_, saved) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Edited(3, "cloud-a", retry.cloud.metadata_saves["cloud-a"].request),
    ),
    retry,
  )
  assert_eq(saved.cloud.inference("cloud-a"), (V4Flash, ThinkingOff))
  assert_false(
    saved.cloud_composer_input().unwrap().presentation.context.any(item => {
      item is @composer.SettingsSaveFailed(..)
    }),
  )
}
