// The picker's contract as the shell sees it: what it reports and what
// makes it close. `State` is opaque from here — runs are built by driving
// `State::open` and `State::handle`, and only the public outcomes and state
// identity are asserted, the way `frontend` consumes the package.

///|
fn emit() -> @cmd.Emit[@project_picker.Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
/// Open the picker on `channel` and land one listing at `location`.
fn listed(
  channel~ : @interop.ChannelId,
  location~ : @project_picker.Location,
  entries~ : Array[String],
) -> @project_picker.State raise {
  let (_, opening) = @project_picker.State::open(channel, emit(), windows=false)
  let (_, loaded, outcome) = @project_picker.State::handle(
    opening,
    emit(),
    @project_picker.Msg::Loaded(
      channel~,
      location~,
      entries~,
      generation=opening.request_generation(),
    ),
  )
  assert_true(outcome is None)
  guard loaded is Some(picker) else { fail("picker closed by its own listing") }
  picker
}

///|
test "a picker refuses to confirm before any listing" {
  let (_, opening) = @project_picker.State::open(
    @interop.ChannelId::Local,
    emit(),
    windows=false,
  )
  let (_, held, outcome) = @project_picker.State::handle(
    opening,
    emit(),
    @project_picker.Msg::Confirm,
  )
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "confirm picks the browsed directory and closes the picker" {
  let home = "/home/u/proj"
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::Directory(home),
    entries=[],
  )
  let (_, closed, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Confirm,
  )
  assert_true(closed is None)
  assert_true(
    outcome is Some(@project_picker.Outcome::Picked(channel, path)) &&
    channel == @interop.ChannelId::Local &&
    path == home,
  )
}

///|
test "a listing for another channel is dropped" {
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::Directory("/home/u"),
    entries=["proj"],
  )
  let (_, foreign, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Loaded(
      channel=@interop.ChannelId::Remote("d_b"),
      location=@project_picker.Location::Directory("/from-b"),
      entries=["wrong"],
      generation=picker.request_generation(),
    ),
  )
  assert_true(outcome is None)
  guard foreign is Some(state) else {
    fail("current picker closed by a foreign listing")
  }
  assert_true(state == picker)
}

///|
test "a stale listing leaves the picker untouched" {
  let home = "/home/u"
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::Directory(home),
    entries=["proj"],
  )
  let (_, browsing, _) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Navigate("/home/u/proj"),
  )
  guard browsing is Some(navigating) else {
    fail("picker closed by navigation")
  }
  // The reply to the original listing lands after navigation moved to a new
  // generation: it must not move the picker back.
  let (_, stale, outcome) = @project_picker.State::handle(
    navigating,
    emit(),
    @project_picker.Msg::Loaded(
      channel=@interop.ChannelId::Local,
      location=@project_picker.Location::Directory("/elsewhere"),
      entries=["wrong"],
      generation=picker.request_generation(),
    ),
  )
  assert_true(outcome is None)
  guard stale is Some(state) else { fail("picker closed by a stale listing") }
  assert_true(state == navigating)
}

///|
test "a failed navigation reports the failure and keeps the picker" {
  let home = "/home/u"
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::Directory(home),
    entries=["proj"],
  )
  let (_, kept, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Failed(
      channel=@interop.ChannelId::Local,
      message="no such directory: /gone",
      generation=picker.request_generation(),
    ),
  )
  guard kept is Some(state) else {
    fail("picker closed by a failed navigation")
  }
  assert_true(state == picker)
  assert_true(
    outcome is Some(@project_picker.Outcome::Failed(message)) &&
    message == "Cannot open folder: no such directory: /gone",
  )
  // A failure answering a superseded navigation stays silent.
  let (_, stale, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Failed(
      channel=@interop.ChannelId::Local,
      message="stale",
      generation=99,
    ),
  )
  guard stale is Some(state) else { fail("picker closed by a stale failure") }
  assert_true(state == picker)
  assert_true(outcome is None)
}

///|
test "the Windows drive list refuses a confirm" {
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::DriveList,
    entries=["C:", "D:"],
  )
  // The drive list is not a directory: Enter and "Add" have nothing to
  // register, so the picker stays open with nothing picked.
  let (_, held, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Confirm,
  )
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "close empties the picker slot" {
  let picker = listed(
    channel=@interop.ChannelId::Local,
    location=@project_picker.Location::DriveList,
    entries=[],
  )
  let (_, closed, outcome) = @project_picker.State::handle(
    picker,
    emit(),
    @project_picker.Msg::Close,
  )
  assert_true(closed is None)
  assert_true(outcome is None)
}
