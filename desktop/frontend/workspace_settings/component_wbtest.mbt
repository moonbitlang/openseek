// White-box tests for the workspace-settings component: its menu state is
// local, so these drive `Model::update` directly, and the view's wiring is
// checked through the select controls it builds — the same command-recording
// seam the shared select_control tests use.

///|
fn test_actions() -> Actions {
  {
    choose_default_mode: (_, _, _) => @cmd.none,
    choose_submodules: (_, _, _) => @cmd.none,
    choose_submodule_timeout: (_, _, _) => @cmd.none,
  }
}

///|
fn loaded_input(
  worktree_mode? : Bool = true,
  checkout_submodules? : Bool = false,
  submodule_checkout_timeout_seconds? : Int = 30,
  generation? : Int = 1,
  device_epoch? : Int = 7,
) -> Input {
  {
    page: Active(
      channel=@interop.ChannelId::Local,
      workspace=@common.Uri::file("/proj"),
      generation~,
      device_epoch~,
    ),
    settings: Loaded(
      worktree_mode~,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~,
    ),
  }
}

///|
fn initial_model(input : Input) -> Model {
  { key: input.page, menu: None, }
}

///|
fn test_emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn default_mode_select(
  input : Input,
  state : Model,
  emit : @cmd.Emit[Msg],
  actions : Actions,
) -> @select_control.Control {
  let worktree_mode = match input.settings {
    Loaded(worktree_mode~, ..) => worktree_mode
    Unloaded => false
  }
  setting_select(
    DefaultMode,
    input,
    state,
    emit,
    id="workspace-default-mode-select",
    options=[
      { value: "local", label: "Local", },
      { value: "worktree", label: "Worktree", },
    ],
    selected=if worktree_mode { "worktree" } else { "local" },
    aria_label="New chats",
    change=actions.choose_default_mode,
  )
}

///|
test "an inactive input renders nothing" {
  let input = Input::inactive()
  assert_true(
    page_view(input, initial_model(input), test_emit(), test_actions()) ==
    @html.nothing,
  )
}

///|
test "the page builds enabled selects from the loaded mirror and disabled before it" {
  let unloaded : Input = {
    page: Active(
      channel=@interop.ChannelId::Local,
      workspace=@common.Uri::file("/proj"),
      generation=1,
      device_epoch=7,
    ),
    settings: Unloaded,
  }
  let unloaded_state = initial_model(unloaded)
  let disabled = default_mode_select(
    unloaded,
    unloaded_state,
    test_emit(),
    test_actions(),
  )
  assert_true(disabled.disabled)
  assert_false(disabled.open)
  assert_eq(disabled.selected, "local")

  let input = loaded_input()
  let state = initial_model(input)
  let enabled = default_mode_select(input, state, test_emit(), test_actions())
  assert_false(enabled.disabled)
  assert_false(enabled.open)
  assert_eq(enabled.selected, "worktree")
  // An open menu state is reflected on the control the page renders.
  let (opened_state, _) = state.update(
    input,
    ToggleMenu(DefaultMode),
    test_emit(),
  )
  let open = default_mode_select(
    input,
    opened_state,
    test_emit(),
    test_actions(),
  )
  assert_true(open.open)
}

///|
test "a select change closes the menu and emits the workspace choice" {
  let input = loaded_input()
  let state = initial_model(input)
  let mut received : Array[Msg] = []
  let emit : @cmd.Emit[Msg] = @cmd.Emit(msg => {
    received.push(msg)
    @cmd.none
  })
  let chosen : Array[(@interop.ChannelId, @common.Uri, String)] = []
  let actions : Actions = {
    choose_default_mode: (channel, workspace, value) => {
      chosen.push((channel, workspace, value))
      @cmd.none
    },
    choose_submodules: (_, _, _) => @cmd.none,
    choose_submodule_timeout: (_, _, _) => @cmd.none,
  }
  let control = default_mode_select(input, state, emit, actions)
  // Building the control eagerly constructs its toggle/dismiss commands, so
  // the change contract starts from a clean slate.
  received = []
  let _ : @cmd.Cmd = (control.change)("worktree")
  assert_eq(received.length(), 1)
  match received[0] {
    CloseMenu => ()
    _ => fail("expected CloseMenu before the choice")
  }
  assert_eq(chosen.length(), 1)
  guard input.page is Active(channel~, workspace~, ..) else {
    fail("expected an active page")
  }
  assert_eq(chosen[0].0, channel)
  assert_eq(chosen[0].1, workspace)
  assert_eq(chosen[0].2, "worktree")
}

///|
test "toggling opens one menu and a second toggle closes it" {
  let input = loaded_input()
  let state = initial_model(input)
  let emit = test_emit()
  let (opened, _) = state.update(input, ToggleMenu(DefaultMode), emit)
  assert_true(opened.menu == Some(DefaultMode))
  let (switched, _) = opened.update(input, ToggleMenu(Submodules), emit)
  assert_true(switched.menu == Some(Submodules))
  let (closed, _) = switched.update(input, ToggleMenu(Submodules), emit)
  assert_true(closed.menu == None)
}

///|
test "a changed page identity resets the menu before the next action" {
  let input = loaded_input()
  let state = initial_model(input)
  let emit = test_emit()
  let (opened, _) = state.update(input, ToggleMenu(DefaultMode), emit)
  assert_true(opened.menu == Some(DefaultMode))
  // Leaving and re-entering the page delivers no message, so the reopened
  // page arrives with the old menu still in state. The next message has to
  // find it reset: the toggle below would otherwise read as a second click
  // on a menu the user cannot see, and close it instead of opening it.
  let reopened = loaded_input(generation=2)
  let (back, _) = opened.update(reopened, ToggleMenu(DefaultMode), emit)
  assert_true(back.menu == Some(DefaultMode))
  assert_true(back.key == reopened.page)
  // Another workspace's page resets the same way.
  let other : Input = {
    ..input,
    page: Active(
      channel=@interop.ChannelId::Local,
      workspace=@common.Uri::file("/other"),
      generation=1,
      device_epoch=7,
    ),
  }
  let (switched, _) = back.update(other, ToggleMenu(DefaultMode), emit)
  assert_true(switched.menu == Some(DefaultMode))
  // Under an unchanged identity the toggle keeps its usual meaning, so the
  // reset above is the only thing that could have produced those opens.
  let (closed, _) = switched.update(other, ToggleMenu(DefaultMode), emit)
  assert_true(closed.menu == None)
}

///|
test "a stale open menu does not render under a different page identity" {
  // A detach redirects to Chat without any component message, and a later
  // reopen of the SAME workspace mints a fresh page generation: the stale
  // menu must not render open even though channel and workspace match.
  let input = loaded_input()
  let state = initial_model(input)
  let emit = test_emit()
  let (opened, _) = state.update(input, ToggleMenu(DefaultMode), emit)
  let reopened : Input = loaded_input(generation=2)
  let stale = default_mode_select(reopened, opened, test_emit(), test_actions())
  assert_false(stale.open)
  // A roster drop-and-restore re-creates the device under a fresh WebSocket
  // epoch while channel, workspace, and page generation all stay the same:
  // the stale menu must not render open for the restored device either.
  let restored : Input = loaded_input(device_epoch=8)
  assert_false(
    default_mode_select(restored, opened, test_emit(), test_actions()).open,
  )
  // A different workspace is rejected the same way.
  let other : Input = {
    ..input,
    page: Active(
      channel=@interop.ChannelId::Local,
      workspace=@common.Uri::file("/other"),
      generation=1,
      device_epoch=7,
    ),
  }
  assert_false(
    default_mode_select(other, opened, test_emit(), test_actions()).open,
  )
  // Under the original identity the same state still renders open.
  let original = default_mode_select(input, opened, test_emit(), test_actions())
  assert_true(original.open)
}
