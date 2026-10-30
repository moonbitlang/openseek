///|
/// Reconcile an accepted application update with navigation. Observation owns
/// domain messages, transition policy owns history writes, and activation owns
/// loading/restoring the destination. Preserve this order: address a blank,
/// promote identities, record the foreground visit, then activate the target.
fn reconcile_navigation(
  dispatch : @cmd.Emit[Msg],
  message : Msg,
  previous : Model,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let mut next = {
    ..model,
    conversations: model.conversations.map(conv => {
      if !conv.draft_addressed && !conv.draft_empty() {
        { ..conv, draft_addressed: true, }
      } else {
        conv
      }
    }),
  }
  // Browser URLs are account-neutral. A changed login or renewed credential
  // re-resolves the URL after its Cloud state is retired; desktop history
  // retains its account-bound identity.
  if !next.is_desktop &&
    (
      previous.cloud.user_id != next.cloud.user_id ||
      previous.cloud.epoch != next.cloud.epoch
    ) &&
    next.navigation.location
    is Some(
      { target: CloudSession(session~, ..) | CloudDraft(id=session, ..), .. } as location
    ) {
    let target : @routes.Target = if location.target is CloudDraft(..) {
      CloudDraft(account=next.cloud.user_id, id=session)
    } else {
      CloudSession(account=next.cloud.user_id, session~)
    }
    next = {
      ..next,
      navigation: {
        ..next.navigation,
        location: Some({ device: None, target, }),
        phase: Waiting,
      },
    }
  }
  let commands : Array[@cmd.Cmd] = []
  next = { ..next, navigation: observe_navigation_catalogs(message, next), }
  let observation = observe_navigation(message, previous, next)
  if observation.addresses_blank(next.navigation) &&
    observation.location is Some(location) {
    let (command, updated) = navigation_visit(next, location, replace=true)
    commands.push(command)
    next = updated
  }
  if observation.promotion is Some((old, promoted)) {
    let (command, updated) = promote_navigation(next, old, promoted)
    commands.push(command)
    next = updated
  }
  match
    observation.write(
      next.navigation,
      previous.navigation.revision,
      desktop=next.is_desktop,
    ) {
    Keep => ()
    Push(location) | Replace(location) as write => {
      let (command, updated) = navigation_visit(
        next,
        location,
        replace=write is Replace(_),
      )
      commands.push(command)
      next = updated
    }
  }
  for (old, promoted) in observation.durable {
    let (command, updated) = promote_navigation(next, old, promoted)
    commands.push(command)
    next = updated
  }
  // Lifecycle fallback may retire a selection deleted elsewhere; navigation
  // keeps the requested identity and renders its unavailable state instead of
  // another chat. This page's own delete already replaced its entry above.
  if next.navigation.phase is Active &&
    next.navigation.location is Some(location) {
    match location.target {
      Session(id) | ChatDraft(id) =>
        if next.find_conversation(next.focused, id) is None &&
          next.host_selection().map(selection => selection.session) != Some(id) {
          next = { ..next, navigation: { ..next.navigation, phase: Waiting, }, }
        }
      _ => ()
    }
  }
  if next.navigation.phase is Active &&
    next.navigation.location is Some({ target: CodexNew, .. }) &&
    !next.codex.composing_draft() &&
    next.codex.can_start_thread() {
    next = { ..next, navigation: { ..next.navigation, phase: Waiting, }, }
  }
  let (activate, next) = activate_navigation(dispatch, next)
  commands.push(activate)
  (@cmd.batch(commands), next)
}

///|
test "renewing a browser Cloud credential reactivates the same session without retiring its host" {
  let dispatch = test_dispatch()
  let base = test_model()
  let account : @protocol.AccountSession = {
    token: "old-token",
    user: { user_id: "fixture-user", login: "octocat", avatar_url: "", },
  }
  let browser = {
    ..base,
    is_desktop: false,
    account: Some(account),
    console: {
      ..base.console,
      page_device: Some("host"),
      auth: AuthSignedIn(login="local", avatar=""),
    },
    cloud: {
      ..@cloud.State::empty(),
      user_id: Some(account.user.user_id),
      epoch: 3,
    },
    navigation: {
      ..base.navigation,
      location: Some({
        device: None,
        target: CloudSession(
          account=Some(account.user.user_id),
          session="cloud-session",
        ),
      }),
      phase: Active,
    },
  }
  let (_, opened) = update(
    dispatch,
    OpenCloudConversation(account=account.user.user_id, session="cloud-session"),
    browser,
  )
  guard opened.cloud.conversations.get("cloud-session") is Some(previous) else {
    fail("the selected Cloud session starts loading")
  }
  let message = AccountLoaded(
    opened.account_epoch,
    Ok(Some({ ..account, token: "new-token", })),
  )
  let (_, renewed) = update(dispatch, message, opened)
  let (_, repeated) = update(dispatch, message, opened)
  guard renewed.cloud.conversations.get("cloud-session") is Some(current) else {
    fail("the selected Cloud session reloads after the credential changes")
  }
  assert_true(current.loading)
  assert_true(current.request > previous.request)
  assert_eq(renewed.cloud.epoch, opened.cloud.epoch + 1)
  assert_eq(renewed.cloud.user_id, opened.cloud.user_id)
  assert_eq(renewed.cloud_identity(), opened.cloud_identity())
  assert_true(renewed.navigation.location == opened.navigation.location)
  assert_true(renewed.navigation.phase is Active)
  assert_eq(renewed.focused, opened.focused)
  assert_eq(renewed.devices.length(), opened.devices.length())
  assert_eq(renewed.conversations.length(), opened.conversations.length())
  assert_true(renewed.console.auth is AuthSignedIn(login="local", ..))
  assert_eq(renewed.cloud.epoch, repeated.cloud.epoch)
  assert_true(renewed.navigation.location == repeated.navigation.location)
  assert_true(renewed.cloud.conversations == repeated.cloud.conversations)
}
