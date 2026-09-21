///|
fn emit() -> @cmd.Emit[@github.Msg] {
  Emit(_ => @cmd.none)
}

///|
fn reply(number : Int) -> @protocol.GithubListReply {
  {
    repository: "owner/repo",
    repository_url: "https://github.com/owner/repo",
    items: [
      {
        number,
        title: "Pull request",
        url: "https://github.com/owner/repo/pull/\{number}",
        author: None,
        avatar_url: None,
        draft: false,
      },
    ],
    has_more: true,
    avatar_error: None,
  }
}

///|
test "switching workspace or host and hiding reject pending GitHub responses" {
  let owner : @github.Owner = { channel: Local, cwd: "/workspace", }
  let (_, state) = @github.reconcile(
    emit(),
    @github.State::empty(),
    Some(owner),
    true,
  )
  for
    next_owner in [
      @github.Owner::{ channel: Local, cwd: "/other", },
      @github.Owner::{ channel: Remote("other-host"), cwd: "/workspace", },
    ] {
    let (_, next) = @github.reconcile(emit(), state, Some(next_owner), true)
    let (_, ignored) = @github.update(
      emit(),
      Listed(state.epoch, AllOpen, Ok(reply(1))),
      next,
    )
    assert_true(ignored.all_open.reply is None)
    assert_true(ignored.all_open.loading)
  }
  let (_, hidden) = @github.reconcile(emit(), state, Some(owner), false)
  let (_, ignored) = @github.update(
    emit(),
    Listed(state.epoch, AllOpen, Ok(reply(1))),
    hidden,
  )
  assert_true(ignored.all_open.reply is None)
  assert_false(ignored.all_open.loading)
}

///|
test "GitHub lists load on expansion and failures stay local to their group" {
  let owner : @github.Owner = { channel: Local, cwd: "/workspace", }
  let (_, state) = @github.reconcile(
    emit(),
    @github.State::empty(),
    Some(owner),
    true,
  )
  assert_false(state.created.loading)
  assert_true(state.all_open.loading)
  assert_true(state.issues.loading)
  let (_, state) = @github.update(
    emit(),
    Listed(state.epoch, AllOpen, Ok(reply(2))),
    state,
  )
  let (_, state) = @github.update(
    emit(),
    Listed(state.epoch, Issues, Err("Issues are disabled")),
    state,
  )
  assert_true(state.all_open.reply is Some(_))
  assert_eq(state.issues.error, Some("Issues are disabled"))
  assert_true(state.issues.reply is None)
  let (_, state) = @github.update(emit(), Toggle(CreatedByMe), state)
  assert_true(state.created.loading)
  let (_, retrying) = @github.update(emit(), Retry(Issues), state)
  assert_true(retrying.issues.loading)
  assert_true(retrying.issues.error is None)
  assert_true(retrying.all_open.reply is Some(_))
}

///|
test "refresh supersedes pending loads and growing lists replace their old prefix" {
  let owner : @github.Owner = { channel: Local, cwd: "/workspace", }
  let (_, state) = @github.reconcile(
    emit(),
    @github.State::empty(),
    Some(owner),
    true,
  )
  let (_, refreshed) = @github.update(emit(), Refresh, state)
  let (_, ignored) = @github.update(
    emit(),
    Listed(state.epoch, AllOpen, Ok(reply(1))),
    refreshed,
  )
  assert_true(ignored.all_open.reply is None)
  let (_, loaded) = @github.update(
    emit(),
    Listed(refreshed.epoch, AllOpen, Ok(reply(2))),
    ignored,
  )
  let (_, more) = @github.update(emit(), More(AllOpen), loaded)
  assert_true(more.all_open.loading)
  assert_true(more.all_open.reply is Some({ items: [{ number: 2, .. }], .. }))
  let (_, replaced) = @github.update(
    emit(),
    Listed(more.epoch, AllOpen, Ok(reply(3))),
    more,
  )
  assert_true(
    replaced.all_open.reply is Some({ items: [{ number: 3, .. }], .. }),
  )
}
