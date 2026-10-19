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
  // Browser URLs are account-neutral. A changed login re-resolves the URL;
  // desktop history retains its account-bound identity.
  if !next.is_desktop &&
    previous.cloud.user_id != next.cloud.user_id &&
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
  // Lifecycle fallback may retire a deleted selection; navigation keeps the
  // requested identity and renders its unavailable state instead of another chat.
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
