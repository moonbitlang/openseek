///|
test "a blank Cloud terminal cannot fall back to the selected local workspace" {
  let dispatch = test_dispatch()
  let (_, blank) = update(
    dispatch,
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let ctx = terminal_ctx(blank)
  assert_true(ctx.channel is @terminal.Cloud(account="fixture-user", ..))
  assert_true(ctx.placement is None)
  let (_, starting) = update(
    dispatch,
    Terminal(@terminal.ToggleTerminal),
    blank,
  )
  assert_true(starting.cloud.creating_session())
  assert_false(starting.terminal.is_open())
  assert_true(terminal_ctx(starting).placement is None)
}

///|
test "old-account Cloud terminal readiness cannot open a terminal after sign-out" {
  let dispatch = test_dispatch()
  let model = integrated_cloud_model()
  let (_, signed_out) = update(
    dispatch,
    AccountLoaded(model.account_epoch, Ok(None)),
    model,
  )
  let (_, ignored) = update(
    dispatch,
    CloudAction(@cloud.TerminalReady(model.cloud.epoch, "cloud-a")),
    signed_out,
  )
  assert_true(ignored.terminal == signed_out.terminal)
}
