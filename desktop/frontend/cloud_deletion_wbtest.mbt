///|
fn delete_cloud(model : Model, session : String) -> Model {
  let (_, staged) = update(
    test_dispatch(),
    DeleteCloudSession(account="fixture-user", session~),
    model,
  )
  let (_, pending) = update(test_dispatch(), ConfirmDeleteSession, staged)
  pending
}

///|
test "Cloud delete captures its title and uses the shared confirmation" {
  let model = integrated_cloud_model()
  let (_, staged) = update(
    test_dispatch(),
    DeleteCloudSession(account="fixture-user", session="cloud-a"),
    model,
  )
  assert_true(
    staged.delete_confirm is Some(CloudDelete(title="Cloud conversation", ..)),
  )
  let (_, cancelled) = update(test_dispatch(), CancelDeleteSession, staged)
  assert_true(cancelled.delete_confirm is None)
  assert_true(cancelled.cloud.deletions.is_empty())
}

///|
test "Cloud deletion falls back within Cloud regardless of the sidebar mode" {
  let model = {
    ..integrated_cloud_model(),
    is_desktop: false,
    sidebar_mode: @sidebar.WorkMode,
  }
  let pending = delete_cloud(model, "cloud-a")
  let request = pending.cloud.deletions["cloud-a"]
  let (_, removed) = update(
    test_dispatch(),
    CloudAction(@cloud.Deleted(3, "cloud-a", request)),
    pending,
  )
  assert_true(removed.screen is Chat)
  assert_true(removed.cloud.creation is Some(_))
  assert_true(removed.cloud_identity() is None)
  assert_true(removed.cloud_selected())
  assert_true(
    removed.composer_entry_retirements.contains(
      @interop.Cloud(account="fixture-user", session="cloud-a"),
    ),
  )
  assert_false(removed.cloud.conversations.contains("cloud-a"))
  assert_true(removed.navigation.location == removed.navigation_location())
  let (_, settings) = update(test_dispatch(), OpenSetup, removed)
  let (_, back) = update(test_dispatch(), Navigation(Back), settings)
  assert_true(back.cloud_draft_identity() == removed.cloud_draft_identity())
}

///|
test "Cloud deletion preserves another page and ignores another account's replies" {
  let pending = delete_cloud(integrated_cloud_model(), "cloud-a")
  let request = pending.cloud.deletions["cloud-a"]
  let (_, settings) = update(test_dispatch(), OpenSetup, pending)
  let (_, removed) = update(
    test_dispatch(),
    CloudAction(@cloud.Deleted(3, "cloud-a", request)),
    settings,
  )
  assert_true(removed.screen is Settings)
  assert_true(removed.cloud.creation is None)
  let (_, switched) = update(
    test_dispatch(),
    CloudAction(@cloud.AccountChanged(Some("other"))),
    pending,
  )
  let (_, late) = update(
    test_dispatch(),
    CloudAction(@cloud.Deleted(3, "cloud-a", request)),
    switched,
  )
  assert_true(late.cloud == switched.cloud)
}

///|
test "a delete failure retains the selected Cloud conversation" {
  let pending = delete_cloud(integrated_cloud_model(), "cloud-a")
  let request = pending.cloud.deletions["cloud-a"]
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(@cloud.DeleteFailed(3, "cloud-a", request, Busy)),
    pending,
  )
  assert_true(failed.cloud_identity() == pending.cloud_identity())
  assert_true(failed.account == pending.account)
  assert_true(failed.cloud.can_delete("cloud-a"))
}

///|
test "Cloud deletion keeps a failed creation in Cloud and allows the normal new action" {
  let pending = delete_cloud(integrated_cloud_model(), "cloud-a")
  let request = pending.cloud.deletions["cloud-a"]
  let (_, removed) = update(
    test_dispatch(),
    CloudAction(@cloud.Deleted(3, "cloud-a", request)),
    pending,
  )
  let removed = submit_blank_cloud(removed)
  guard removed.cloud.creation is Some(creation) else {
    fail("expected Cloud creation")
  }
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(@cloud.CreateFailed(3, creation.request, Http(503))),
    removed,
  )
  assert_true(failed.cloud_selected())
  assert_true(failed.chat_column() is CloudTranscript(..))
  assert_true(failed.host_selection() is None)
  let (_, retried) = update(test_dispatch(), CloudAction(@cloud.Create), failed)
  assert_true(retried.cloud.creation is Some({ submission: None, .. }))
  assert_true(retried.chat_column() is CloudTranscript(..))
}

///|
test "deletion reuses an existing pending Cloud creation without losing its navigation" {
  let model = integrated_cloud_model()
  let (_, creating) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  let creating = submit_blank_cloud(creating)
  guard creating.cloud.creation is Some(creation) else {
    fail("expected creation")
  }
  let (_, returned) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    creating,
  )
  let pending = delete_cloud(returned, "cloud-a")
  let request = pending.cloud.deletions["cloud-a"]
  let (_, removed) = update(
    test_dispatch(),
    CloudAction(@cloud.Deleted(3, "cloud-a", request)),
    pending,
  )
  assert_true(removed.cloud_selected())
  guard removed.cloud.creation is Some(reused) else {
    fail("expected reused creation")
  }
  assert_eq(reused.request, creation.request)
  assert_eq(reused.navigation, removed.chat_navigation_generation)
  let (_, created) = update(
    test_dispatch(),
    CloudAction(@cloud.Created(3, creation.request, "new-cloud")),
    removed,
  )
  assert_true(
    created.cloud_identity() ==
    Some(@interop.Cloud(account="fixture-user", session="new-cloud")),
  )
}
