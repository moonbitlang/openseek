// The row-target path joining the view uses, exercised directly: resource
// URI paths always use `/`, including Windows drive resources.

///|
fn test_resource(
  channel : @interop.ChannelId,
  path : String,
) -> @common.Uri raise {
  guard @resource.of_path(channel, path) is Some(resource) else {
    fail("test resource path was invalid: \{path}")
  }
  resource
}

///|
test "picker paths join with URI separators" {
  let channel = @interop.ChannelId::Local
  inspect(
    test_resource(channel, "/home/u").picker_child_path("proj"),
    content="/home/u/proj",
  )
  inspect(test_resource(channel, "/").picker_child_path("etc"), content="/etc")
  inspect(
    test_resource(channel, "/C:/code").picker_child_path("app"),
    content="/c:/code/app",
  )
}

///|
fn emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
}

///|
#warnings("-alert_unstable")
fn markup(picker : State) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(emit(), picker)))
}

///|
/// Open the picker and land one listing at `location`.
fn opened(
  channel? : @interop.ChannelId = @interop.ChannelId::Local,
  location~ : Location,
  entries? : Array[String] = [],
) -> State raise {
  let (_, opening) = State::open(channel, emit())
  assert_true(opening.loading)
  let (_, loaded, _) = State::handle(
    opening,
    emit(),
    Msg::Loaded(channel~, location~, entries~, generation=opening.generation),
  )
  guard loaded is Some(picker) else { fail("picker closed by its own listing") }
  picker
}

///|
test "the picker opens loading and adopts the first listing" {
  let home = test_resource(@interop.ChannelId::Local, "/home/u")
  let (_, opening) = State::open(@interop.ChannelId::Local, emit())
  assert_true(opening.loading)
  assert_true(opening.location is None)
  let (_, loaded, _) = State::handle(
    opening,
    emit(),
    Msg::Loaded(
      channel=@interop.ChannelId::Local,
      location=Location::Directory(home),
      entries=["proj"],
      generation=opening.generation,
    ),
  )
  guard loaded is Some(picker) else { fail("picker closed by its own listing") }
  assert_true(
    picker.location is Some(Location::Directory(path)) && path.path == "/home/u",
  )
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
}

///|
test "a listing for another channel or generation is dropped" {
  let opening = opened(
    location=Location::Directory(
      test_resource(@interop.ChannelId::Local, "/home/u"),
    ),
    entries=["proj"],
  )
  // A different device's listing cannot replace this picker's.
  let (_, foreign, _) = State::handle(
    opening,
    emit(),
    Msg::Loaded(
      channel=@interop.ChannelId::Remote("d_b"),
      location=Location::Directory(
        test_resource(@interop.ChannelId::Remote("d_b"), "/from-b"),
      ),
      entries=["wrong"],
      generation=opening.generation,
    ),
  )
  guard foreign is Some(picker) else {
    fail("current picker closed by a foreign listing")
  }
  assert_true(picker == opening)
  // A navigation bumps the generation and keeps the current listing; the
  // original listing's late reply cannot move the picker back.
  let (_, navigated, _) = State::handle(
    opening,
    emit(),
    Msg::Navigate("/home/u/proj"),
  )
  guard navigated is Some(browsing) else { fail("picker closed by navigation") }
  assert_true(browsing.loading)
  assert_true(
    browsing.location is Some(Location::Directory(path)) &&
    path.path == "/home/u",
  )
  let (_, stale, _) = State::handle(
    browsing,
    emit(),
    Msg::Loaded(
      channel=@interop.ChannelId::Local,
      location=Location::Directory(
        test_resource(@interop.ChannelId::Local, "/elsewhere"),
      ),
      entries=["wrong"],
      generation=opening.generation,
    ),
  )
  guard stale is Some(picker) else { fail("picker closed by a stale listing") }
  assert_true(picker == browsing)
}

///|
test "a failed navigation keeps the listing" {
  let opening = opened(
    location=Location::Directory(
      test_resource(@interop.ChannelId::Local, "/home/u"),
    ),
    entries=["proj"],
  )
  let (_, failed, outcome) = State::handle(
    opening,
    emit(),
    Msg::Failed(
      channel=@interop.ChannelId::Local,
      message="no such directory: /gone",
      generation=opening.generation,
    ),
  )
  guard failed is Some(picker) else {
    fail("picker closed by a failed navigation")
  }
  assert_true(
    picker.location is Some(Location::Directory(path)) && path.path == "/home/u",
  )
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
  assert_true(
    outcome is Some(Outcome::Failed(message)) &&
    message == "Cannot open folder: no such directory: /gone",
  )
}

///|
test "reopened pickers do not reuse request generations" {
  let (_, first) = State::open(@interop.ChannelId::Local, emit())
  let (_, second) = State::open(@interop.ChannelId::Local, emit())
  assert_true(first.generation != second.generation)
}

///|
test "confirm waits for an in-flight navigation" {
  let home = test_resource(@interop.ChannelId::Local, "/home/u")
  let opening = opened(location=Location::Directory(home))
  let (_, browsing, _) = State::handle(
    opening,
    emit(),
    Msg::Navigate("/home/u/other"),
  )
  guard browsing is Some(navigating) else {
    fail("picker closed by navigation")
  }
  // The shown listing is stale while the navigation is in flight: Enter
  // must not attach the previous directory.
  let (_, held, outcome) = State::handle(navigating, emit(), Msg::Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "path editing filters the loaded rows and ranks prefixes first" {
  let picker = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
    entries=["alphabet", "Beryl", "beta", "coda"],
  )
  let (_, editing, _) = State::handle(picker, emit(), EditPath)
  guard editing is Some(editing) else { fail("path editor closed picker") }
  assert_eq(editing.path_draft, Some("/home/u"))
  assert_eq(editing.visible_entries(), picker.entries)
  let (_, held, outcome) = State::handle(editing, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
  let (_, unchanged, _) = State::handle(editing, emit(), BeginCreateFolder)
  guard unchanged is Some(unchanged) else { fail("new folder closed picker") }
  assert_true(unchanged == editing)
  let (_, filtered, _) = State::handle(
    editing,
    emit(),
    PathChanged("/home/u/be"),
  )
  guard filtered is Some(filtered) else { fail("path filter closed picker") }
  assert_eq(filtered.path_filter(), "be")
  assert_eq(filtered.visible_entries(), ["Beryl", "beta", "alphabet"])
  assert_eq(filtered.selected_path_suggestion(), Some("Beryl"))
  assert_eq(filtered.path_destination(), Some("/home/u/Beryl"))
  let (_, absolute, _) = State::handle(
    filtered,
    emit(),
    PathChanged("/tmp/other"),
  )
  guard absolute is Some(absolute) else { fail("absolute path closed picker") }
  assert_eq(absolute.path_filter(), "")
  assert_eq(absolute.visible_entries(), picker.entries)
  assert_eq(absolute.path_destination(), Some("/tmp/other"))
}

///|
test "path keyboard selection wraps and completion remains local" {
  let picker = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
    entries=["alpha", "beta", "better"],
  )
  let (_, editing, _) = State::handle(picker, emit(), EditPath)
  guard editing is Some(editing) else { fail("path editor did not open") }
  let (_, filtered, _) = State::handle(
    editing,
    emit(),
    PathChanged("/home/u/be"),
  )
  guard filtered is Some(filtered) else { fail("path filter closed picker") }
  let (_, moved, _) = State::handle(filtered, emit(), MovePathSelection(-1))
  guard moved is Some(moved) else { fail("selection closed picker") }
  assert_eq(moved.path_selection, 1)
  assert_eq(moved.selected_path_suggestion(), Some("better"))
  let (_, completed, _) = State::handle(moved, emit(), CompletePath)
  guard completed is Some(completed) else { fail("completion closed picker") }
  assert_eq(completed.path_draft, Some("/home/u/better"))
  assert_false(completed.loading)
  assert_true(completed.location == picker.location)
}

///|
test "submitting or cancelling a path keeps one navigation path" {
  let picker = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
    entries=["project"],
  )
  let (_, editing, _) = State::handle(picker, emit(), EditPath)
  guard editing is Some(editing) else { fail("path editor did not open") }
  let (_, typed, _) = State::handle(editing, emit(), PathChanged("/home/u/pro"))
  guard typed is Some(typed) else { fail("path draft closed picker") }
  let (_, navigating, _) = State::handle(typed, emit(), SubmitPath)
  guard navigating is Some(navigating) else {
    fail("path submit closed picker")
  }
  assert_true(navigating.loading)
  assert_eq(navigating.path_draft, None)
  assert_true(navigating.generation != typed.generation)
  let (_, editing, _) = State::handle(picker, emit(), EditPath)
  guard editing is Some(editing) else { fail("path editor did not reopen") }
  let (_, cancelled, _) = State::handle(editing, emit(), CancelPathEdit)
  guard cancelled is Some(cancelled) else { fail("path cancel closed picker") }
  assert_eq(cancelled.path_draft, None)
  assert_true(cancelled.location == picker.location)
  assert_false(cancelled.loading)
}

///|
test "the Windows drive list shows its drives and refuses a confirm" {
  let opening = opened(location=Location::DriveList, entries=["C:", "D:"])
  assert_true(opening.location is Some(Location::DriveList))
  inspect(opening.entries.length(), content="2")
  assert_true(!opening.loading)
  let (_, held, outcome) = State::handle(opening, emit(), Msg::Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "new folder creation enters the created directory" {
  let opening = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
    entries=["existing"],
  )
  let (_, composing, _) = State::handle(opening, emit(), BeginCreateFolder)
  guard composing is Some(composing) else {
    fail("picker closed while opening the new-folder composer")
  }
  assert_eq(composing.new_folder, Some(""))
  let (_, held, outcome) = State::handle(composing, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
  let (_, named, _) = State::handle(
    composing,
    emit(),
    NewFolderNameChanged("new project"),
  )
  guard named is Some(named) else {
    fail("picker closed while naming a folder")
  }
  let (_, creating, _) = State::handle(named, emit(), CreateFolder)
  guard creating is Some(creating) else {
    fail("picker closed while creating a folder")
  }
  assert_true(creating.loading)
  assert_true(creating.generation != named.generation)
  assert_eq(creating.new_folder, Some("new project"))
  let created = test_resource(@interop.ChannelId::Local, "/home/u/new project")
  let (_, loaded, outcome) = State::handle(
    creating,
    emit(),
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory(created),
      entries=[],
      generation=creating.generation,
    ),
  )
  assert_true(outcome is None)
  guard loaded is Some(loaded) else { fail("created directory closed picker") }
  assert_true(loaded.location == Some(Directory(created)))
  assert_eq(loaded.new_folder, None)
  assert_false(loaded.loading)
}

///|
test "a failed folder create keeps its name editable" {
  let opening = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
  )
  let (_, composing, _) = State::handle(opening, emit(), BeginCreateFolder)
  guard composing is Some(composing) else { fail("composer did not open") }
  let (_, named, _) = State::handle(
    composing,
    emit(),
    NewFolderNameChanged("taken"),
  )
  guard named is Some(named) else { fail("folder name was not kept") }
  let (_, creating, _) = State::handle(named, emit(), CreateFolder)
  guard creating is Some(creating) else { fail("create closed picker") }
  let (_, failed, outcome) = State::handle(
    creating,
    emit(),
    Failed(
      channel=@interop.ChannelId::Local,
      message="already exists",
      generation=creating.generation,
    ),
  )
  guard failed is Some(failed) else { fail("failed create closed picker") }
  assert_eq(failed.new_folder, Some("taken"))
  assert_false(failed.loading)
  assert_true(
    outcome is Some(Outcome::Failed(message)) &&
    message == "Cannot create folder: already exists",
  )
}

///|
#warnings("-alert_unstable")
test "picker view exposes the folder controls" {
  let picker = opened(
    location=Directory(test_resource(@interop.ChannelId::Local, "/home/u")),
    entries=["alpha", "beta"],
  )
  let html = markup(picker)
  assert_true(html.contains("role=\"dialog\""))
  assert_true(html.contains("Choose a folder to use as a project workspace"))
  assert_true(html.contains("New folder"))
  assert_true(html.contains("Open folder alpha"))
  assert_true(html.contains("picker-row-chevron"))
  assert_true(html.contains("2 folders"))
  assert_true(html.contains("Current folder"))
  assert_true(html.contains("/home/u"))
  assert_true(html.contains("Edit current path"))
  assert_true(html.contains("Add project"))
  let (_, editing, _) = State::handle(picker, emit(), EditPath)
  guard editing is Some(editing) else { fail("path editor did not open") }
  let editor_html = markup(editing)
  assert_true(editor_html.contains("role=\"combobox\""))
  assert_true(editor_html.contains("aria-label=\"Folder path\""))
  assert_true(editor_html.contains("value=\"/home/u\""))
  assert_true(editor_html.contains("placeholder=\"Enter a folder path\""))
  let (_, filtered, _) = State::handle(
    editing,
    emit(),
    PathChanged("/home/u/al"),
  )
  guard filtered is Some(filtered) else { fail("path filter closed picker") }
  let filtered_html = markup(filtered)
  assert_true(filtered_html.contains("1 match"))
  assert_true(filtered_html.contains("Open folder alpha"))
  assert_false(filtered_html.contains("Open folder beta"))
  assert_true(filtered_html.contains("picker-row selected"))
  let (_, composing, _) = State::handle(picker, emit(), BeginCreateFolder)
  guard composing is Some(composing) else { fail("composer did not open") }
  let composer_html = markup(composing)
  assert_true(composer_html.contains("picker-create-row"))
  assert_true(composer_html.contains("placeholder=\"New folder name\""))
  assert_true(composer_html.contains("autofocus"))
}
