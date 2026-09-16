// The palette's contract as the shell sees it: what it draws, what it accepts,
// and what makes it close. Nothing here reads inside `State` — a run is built
// by driving the same entry points `frontend` drives.

///|
fn emit() -> @cmd.Emit[@quick_open.Msg] {
  Emit(_ => @cmd.none)
}

///|
fn owner() -> @interop.ConversationKey {
  { channel: Local, session: "desktop-test", }
}

///|
fn workspace_root() -> @common.Uri raise {
  guard @resource.of_path(Local, "/work/proj") is Some(resource) else {
    fail("test resource path was invalid")
  }
  resource
}

///|
fn input(
  open_files? : Array[@pathx.Relative] = [],
  active_file? : @pathx.Relative,
) -> @quick_open.Input raise {
  Input(owner=owner(), root=Some(workspace_root()), open_files~, active_file~)
}

///|
/// A palette showing one workspace symbol. `SymbolsLoaded` carries the
/// generation its request was minted with; standing in for the effect layer
/// means minting it here too, and a run opened out of `State::empty` is the
/// first, so it is generation 1.
fn symbol_run(name : String, path : String) -> @quick_open.State raise {
  let input = input()
  let (_, opened) = @quick_open.State::empty().open(emit(), input, Symbols)
  let (_, ready, _) = opened.handle(
    emit(),
    SymbolsLoaded(owner=owner(), query="", generation=1, items=[
      {
        name,
        kind: Some(12),
        container: Some("Parser"),
        path,
        range: Range(5, 2, 5, 13),
      },
    ]),
    input,
  )
  ready
}

///|
test "a new palette starts closed" {
  let state = @quick_open.State::empty()
  assert_false(state.is_open())
}

///|
test "accepting a row closes the palette and hands back its editor target" {
  let ready = symbol_run("parse_hover", "src/main.mbt")
  let (_, accepted, target) = ready.handle(emit(), Pick(0), input())
  assert_false(accepted.is_open())
  assert_eq(
    target,
    Some({ path: "src/main.mbt", range: Some(Range(5, 2, 5, 13)), }),
  )
  // A file row opens without a range: the whole document is the destination.
  let (_, files) = @quick_open.State::empty().open(
    emit(),
    input(open_files=[Relative("src/open.mbt")]),
    Files,
  )
  let (_, _, file_target) = files.handle(emit(), Pick(0), input())
  assert_eq(file_target, Some({ path: "src/open.mbt", range: None, }))
}

///|
test "accepting nothing is not an accept" {
  let (_, opened) = @quick_open.State::empty().open(emit(), input(), Symbols)
  let (_, unchanged, target) = opened.handle(emit(), Pick(0), input())
  assert_eq(target, None)
  assert_true(unchanged == opened)
}

///|
test "selection wraps in both directions" {
  let ready = symbol_run("parse_hover", "src/main.mbt")
  let (_, up, _) = ready.handle(emit(), Move(-1), input())
  // One row, so either direction returns to the same state.
  let (_, down, _) = up.handle(emit(), Move(1), input())
  assert_true(down == up)
}

///|
test "dismissing closes the palette" {
  let (_, opened) = @quick_open.State::empty().open(emit(), input(), Files)
  let (_, dismissed, _) = opened.handle(emit(), Dismiss, input())
  assert_false(dismissed.is_open())
}

///|
test "a conversation switch retires the run that opened before it" {
  let (_, opened) = @quick_open.State::empty().open(emit(), input(), Files)
  let elsewhere = @quick_open.Input(
    owner={ channel: Local, session: "desktop-second", },
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
