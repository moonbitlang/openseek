// The palette's contract as the shell sees it: what it draws, what it accepts,
// and what makes it close. Nothing here reads inside `State` — a run is built
// by driving the same entry points `frontend` drives.

///|
fn emit() -> @cmd.Emit[@quick_open.Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
fn owner() -> @interop.ConversationKey {
  { channel: @interop.ChannelId::Local, session: "desktop-test", }
}

///|
fn workspace_root() -> @common.Uri raise {
  guard @resource.of_path(@interop.ChannelId::Local, "/work/proj")
    is Some(resource) else {
    fail("test resource path was invalid")
  }
  resource
}

///|
fn input(
  open_files? : Array[@pathx.Relative] = [],
  active_file? : @pathx.Relative,
) -> @quick_open.Input raise {
  @quick_open.Input(
    owner=owner(),
    root=Some(workspace_root()),
    open_files~,
    active_file~,
  )
}

///|
test "a new palette starts closed" {
  let state = @quick_open.State::empty()
  assert_false(state.is_open())
}

///|
test "accepting a row closes the palette and hands back its editor target" {
  // A file row opens without a range: the whole document is the destination.
  // (Symbol rows, which need a Host reply, are covered by the state tests.)
  let (_, files) = @quick_open.State::empty().open(
    emit(),
    input(open_files=[Relative("src/open.mbt")]),
    @quick_open.Files,
  )
  let (_, accepted, target) = files.handle(emit(), @quick_open.Pick(0), input())
  assert_false(accepted.is_open())
  assert_eq(target, Some({ path: "src/open.mbt", range: None, }))
}

///|
test "accepting nothing is not an accept" {
  let (_, opened) = @quick_open.State::empty().open(
    emit(),
    input(),
    @quick_open.Symbols,
  )
  let (_, unchanged, target) = opened.handle(
    emit(),
    @quick_open.Pick(0),
    input(),
  )
  assert_eq(target, None)
  assert_true(unchanged == opened)
}

///|
test "dismissing closes the palette" {
  let (_, opened) = @quick_open.State::empty().open(
    emit(),
    input(),
    @quick_open.Files,
  )
  let (_, dismissed, _) = opened.handle(emit(), @quick_open.Dismiss, input())
  assert_false(dismissed.is_open())
}

///|
test "a conversation switch retires the run that opened before it" {
  let (_, opened) = @quick_open.State::empty().open(
    emit(),
    input(),
    @quick_open.Files,
  )
  let elsewhere = @quick_open.Input(
    owner={ channel: @interop.ChannelId::Local, session: "desktop-second", },
    root=Some(workspace_root()),
    open_files=[],
    active_file=None,
  )
  let (_, switched) = opened.reconcile(emit(), elsewhere)
  assert_false(switched.is_open())
  // The same conversation reconciles to a no-op, however often it is asked.
  let (_, settled) = opened.reconcile(emit(), input())
  assert_true(settled == opened)
}
