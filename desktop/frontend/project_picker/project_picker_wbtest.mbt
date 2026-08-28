///|
test "picker paths join with URI separators" {
  inspect("/home/u".picker_child_path("proj"), content="/home/u/proj")
  inspect("/".picker_child_path("etc"), content="/etc")
  inspect("/C:/code".picker_child_path("app"), content="/C:/code/app")
}

///|
test "a listing keeps its raw protocol path" {
  assert_true(
    reply_message(
      @interop.ChannelId::Local,
      @protocol.Listing(path="/C:/project", parent=Some("/C:/"), entries=[]),
      generation=7,
      drives=true,
    )
    is Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/C:/project"),
      entries=[],
      generation=7
    ),
  )
}

///|
fn emit() -> @cmd.Emit[Msg] {
  @cmd.Emit(_ => @cmd.none)
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
    Loaded(channel~, location~, entries~, generation=opening.generation),
  )
  guard loaded is Some(picker) else { fail("picker closed by its own listing") }
  picker
}

///|
fn updated(picker : State, msg : Msg) -> State raise {
  guard State::handle(picker, emit(), msg) is (_, Some(next), _) else {
    fail("message closed picker")
  }
  next
}

///|
test "the picker opens loading and adopts the first listing" {
  let home = "/home/u"
  let (_, opening) = State::open(@interop.ChannelId::Local, emit())
  assert_true(opening.loading)
  assert_true(opening.location is None)
  let (_, loaded, _) = State::handle(
    opening,
    emit(),
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory(home),
      entries=["proj"],
      generation=opening.generation,
    ),
  )
  guard loaded is Some(picker) else { fail("picker closed by its own listing") }
  assert_true(picker.location is Some(Directory(path)) && path == "/home/u")
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
}

///|
test "a listing for another channel or generation is dropped" {
  let opening = opened(location=Directory("/home/u"), entries=["proj"])
  // A different device's listing cannot replace this picker's.
  let (_, foreign, _) = State::handle(
    opening,
    emit(),
    Loaded(
      channel=@interop.ChannelId::Remote("d_b"),
      location=Directory("/from-b"),
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
    Navigate("/home/u/proj"),
  )
  guard navigated is Some(browsing) else { fail("picker closed by navigation") }
  assert_true(browsing.loading)
  assert_true(browsing.location is Some(Directory(path)) && path == "/home/u")
  let (_, stale, _) = State::handle(
    browsing,
    emit(),
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/elsewhere"),
      entries=["wrong"],
      generation=opening.generation,
    ),
  )
  guard stale is Some(picker) else { fail("picker closed by a stale listing") }
  assert_true(picker == browsing)
}

///|
test "a failed navigation keeps the listing" {
  let opening = opened(location=Directory("/home/u"), entries=["proj"])
  let (_, failed, outcome) = State::handle(
    opening,
    emit(),
    Failed(
      channel=@interop.ChannelId::Local,
      message="no such directory: /gone",
      generation=opening.generation,
    ),
  )
  guard failed is Some(picker) else {
    fail("picker closed by a failed navigation")
  }
  assert_true(picker.location is Some(Directory(path)) && path == "/home/u")
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
  assert_true(
    outcome is Some(Failed(message)) &&
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
  let home = "/home/u"
  let opening = opened(location=Directory(home))
  let (_, browsing, _) = State::handle(
    opening,
    emit(),
    Navigate("/home/u/other"),
  )
  guard browsing is Some(navigating) else {
    fail("picker closed by navigation")
  }
  // The shown listing is stale while the navigation is in flight: Enter
  // must not attach the previous directory.
  let (_, held, outcome) = State::handle(navigating, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "path editing filters the loaded rows and ranks prefixes first" {
  let picker = opened(location=Directory("/home/u"), entries=[
    "alphabet", "Beryl", "beta", "coda",
  ])
  let editing = updated(picker, EditPath)
  assert_eq(editing.path_draft, Some("/home/u"))
  assert_eq(editing.visible_entries(), picker.entries)
  let filtered = updated(editing, PathChanged("/home/u/be"))
  assert_eq(filtered.path_filter(), "be")
  assert_eq(filtered.visible_entries(), ["Beryl", "beta", "alphabet"])
  assert_eq(filtered.selected_path_suggestion(), Some("Beryl"))
  assert_eq(filtered.path_destination(), Some("/home/u/Beryl"))
  // The draft now names a child, so the current-directory actions wait.
  let (_, held, outcome) = State::handle(filtered, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
  let unchanged = updated(filtered, BeginCreateFolder)
  assert_true(unchanged == filtered)
  // A path under another directory is completed from that directory once
  // the host lists it; until then the rows here would only mislead.
  let absolute = updated(filtered, PathChanged("/tmp/other/"))
  assert_true(absolute.loading)
  assert_eq(absolute.completion_parent, Some("/tmp/other/"))
  assert_eq(absolute.path_filter(), "")
  assert_eq(absolute.visible_entries(), [])
  assert_eq(absolute.path_destination(), Some("/tmp/other/"))
  // Alternate casing is another directory until the host says otherwise.
  let different_case = updated(filtered, PathChanged("/HOME/u/be"))
  assert_true(different_case.loading)
  assert_eq(different_case.completion_parent, Some("/HOME/u/"))
  assert_eq(different_case.path_filter(), "")
  assert_eq(different_case.path_destination(), Some("/HOME/u/be"))
  let windows = opened(location=Directory("/C:/Code"), entries=["Project"])
  let windows_editing = updated(windows, EditPath)
  let windows_filtered = updated(windows_editing, PathChanged("/C:/Code/pro"))
  assert_eq(windows_filtered.path_filter(), "pro")
  assert_eq(windows_filtered.selected_path_suggestion(), Some("Project"))
}

///|
test "path keyboard selection wraps and completion remains local" {
  let picker = opened(location=Directory("/home/u"), entries=[
    "alpha", "betterment", "better",
  ])
  let editing = updated(picker, EditPath)
  let filtered = updated(editing, PathChanged("/home/u/be"))
  let moved = updated(filtered, MovePathSelection(-1))
  assert_eq(moved.path_selection, 1)
  assert_eq(moved.selected_path_suggestion(), Some("better"))
  let completed = updated(moved, CompletePath)
  assert_eq(completed.path_draft, Some("/home/u/better"))
  assert_eq(completed.visible_entries(), ["betterment", "better"])
  assert_eq(completed.selected_path_suggestion(), None)
  assert_eq(completed.path_destination(), Some("/home/u/better"))
  assert_false(completed.loading)
  assert_true(completed.location == picker.location)
}

///|
test "typing a separator after an exact child navigates immediately" {
  let picker = opened(location=Directory("/Users/dii"), entries=["git", "go"])
  let editing = updated(picker, EditPath)
  let navigating = updated(editing, PathChanged("git/"))
  assert_true(navigating.loading)
  assert_eq(navigating.path_draft, Some("/Users/dii/git/"))

  let git = "/Users/dii/git"
  let cancelled = updated(navigating, Escape)
  assert_false(cancelled.loading)
  assert_eq(cancelled.path_draft, None)
  assert_true(cancelled.generation != navigating.generation)
  let loaded_after_cancel = updated(
    cancelled,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory(git),
      entries=["openseek"],
      generation=navigating.generation,
    ),
  )
  assert_true(loaded_after_cancel == cancelled)

  let navigating = updated(editing, PathChanged("/Users/dii/git/"))
  let loaded = updated(
    navigating,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory(git),
      entries=["openseek"],
      generation=navigating.generation,
    ),
  )
  assert_eq(loaded.path_draft, Some("/Users/dii/git/"))
  let submitted = updated(loaded, SubmitPath)
  assert_false(submitted.loading)
  assert_eq(submitted.path_draft, None)
  assert_eq(submitted.generation, loaded.generation)
  assert_true(submitted.location == loaded.location)
  let nested = updated(loaded, PathChanged("/Users/dii/git/openseek/"))
  assert_true(nested.loading)
  assert_eq(nested.path_draft, Some("/Users/dii/git/openseek/"))

  let drives = opened(location=DriveList, entries=["C:", "D:"])
  let navigating_drive = updated(updated(drives, EditPath), PathChanged("/c:/"))
  assert_true(navigating_drive.loading)
  // The host's reply supplies the canonical spelling.
  assert_eq(navigating_drive.path_draft, Some("/c:/"))
  let drive = "/C:/"
  let loaded_drive = updated(
    navigating_drive,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory(drive),
      entries=["Users"],
      generation=navigating_drive.generation,
    ),
  )
  assert_eq(loaded_drive.path_draft, Some("/C:/"))
  let submitted_drive = updated(loaded_drive, SubmitPath)
  assert_false(submitted_drive.loading)
  assert_eq(submitted_drive.path_draft, None)
  assert_eq(submitted_drive.generation, loaded_drive.generation)

  let code = opened(location=Directory("/C:/Code"), entries=["src"])
  let mixed_case = updated(updated(code, EditPath), PathChanged("/c:/CODE/"))
  let submitted_mixed_case = updated(mixed_case, SubmitPath)
  assert_true(submitted_mixed_case.loading)
  assert_eq(submitted_mixed_case.path_draft, None)
  assert_true(submitted_mixed_case.generation != mixed_case.generation)
  assert_true(submitted_mixed_case.location == code.location)
  let mixed_case_child = updated(
    updated(code, EditPath),
    PathChanged("/c:/CODE/src/"),
  )
  // Validated by the host rather than refused locally.
  assert_true(mixed_case_child.loading)

  // A drive-shaped prefix is not proof that the host is Windows. These are
  // distinct legal POSIX paths, so the alternate spelling must be validated.
  let drive_shaped = opened(location=Directory("/c:/project"))
  let alternate = updated(
    updated(drive_shaped, EditPath),
    PathChanged("/C:/project"),
  )
  let validating = updated(alternate, SubmitPath)
  assert_true(validating.loading)
  assert_true(validating.generation != alternate.generation)

  let upper = opened(location=Directory("/C:/project"))
  let upper_editing = updated(upper, EditPath)
  assert_eq(upper_editing.path_draft, Some("/C:/project"))
  let upper_submitted = updated(upper_editing, SubmitPath)
  assert_false(upper_submitted.loading)
  assert_eq(upper_submitted.generation, upper_editing.generation)
  assert_true(upper_submitted.location == upper.location)
}

///|
test "a path edit still naming the listed directory yields to its actions" {
  let picker = opened(location=Directory("/Users/dii"), entries=["git"])
  // Opened and left untouched: the draft is the listed directory.
  let editing = updated(picker, EditPath)
  assert_true(editing.path_draft_names_location())
  let composing = updated(editing, BeginCreateFolder)
  assert_eq(composing.new_folder, Some(""))
  assert_eq(composing.path_draft, None)
  assert_true(composing.location == picker.location)
  let (_, closed, outcome) = State::handle(editing, emit(), Confirm)
  assert_true(closed is None)
  assert_true(outcome is Some(Outcome::Picked(_, path)) && path == "/Users/dii")
  // Resumed after a separator-committed browse: the draft is the canonical
  // path the host listed, trailing separator included.
  let navigating = updated(editing, PathChanged("git/"))
  let loaded = updated(
    navigating,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/Users/dii/git"),
      entries=[],
      generation=navigating.generation,
    ),
  )
  assert_eq(loaded.path_draft, Some("/Users/dii/git/"))
  assert_true(loaded.path_draft_names_location())
  let (_, closed, outcome) = State::handle(loaded, emit(), Confirm)
  assert_true(closed is None)
  assert_true(
    outcome is Some(Outcome::Picked(_, path)) && path == "/Users/dii/git",
  )
  let composing_after_browse = updated(loaded, BeginCreateFolder)
  assert_eq(composing_after_browse.new_folder, Some(""))
  assert_eq(composing_after_browse.path_draft, None)
  // A draft naming another directory — or a completion — still waits.
  let elsewhere = updated(editing, PathChanged("/tmp/other"))
  assert_false(elsewhere.path_draft_names_location())
  assert_true(updated(elsewhere, BeginCreateFolder) == elsewhere)
  let completing = updated(editing, PathChanged("/Users/dii/gi"))
  assert_eq(completing.path_destination(), Some("/Users/dii/git"))
  assert_false(completing.path_draft_names_location())
  // The drive list is still not a directory.
  let drives = updated(opened(location=DriveList, entries=["C:"]), EditPath)
  assert_true(drives.path_draft_names_location())
  assert_true(updated(drives, BeginCreateFolder) == drives)
  let (_, held, outcome) = State::handle(drives, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "submitting or cancelling a path keeps one navigation path" {
  let picker = opened(location=Directory("/home/u"), entries=["project"])
  let editing = updated(picker, EditPath)
  let typed = updated(editing, PathChanged("/home/u/pro"))
  let navigating = updated(typed, SubmitPath)
  assert_true(navigating.loading)
  assert_eq(navigating.path_draft, None)
  assert_true(navigating.generation != typed.generation)
  let cancelled = updated(updated(picker, EditPath), CancelPathEdit)
  assert_eq(cancelled.path_draft, None)
  assert_true(cancelled.location == picker.location)
  assert_false(cancelled.loading)
}

///|
test "the Windows drive list shows its drives and refuses a confirm" {
  let opening = opened(location=DriveList, entries=["C:", "D:"])
  assert_true(opening.location is Some(DriveList))
  inspect(opening.entries.length(), content="2")
  assert_true(!opening.loading)
  let (_, held, outcome) = State::handle(opening, emit(), Confirm)
  assert_true(held is Some(_))
  assert_true(outcome is None)
}

///|
test "new folder creation enters the created directory" {
  let opening = opened(location=Directory("/home/u"), entries=["existing"])
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
  let created = "/home/u/new project"
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
  let opening = opened(location=Directory("/home/u"))
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
    outcome is Some(Failed(message)) &&
    message == "Cannot create folder: already exists",
  )
}

///|
test "deleting back across a separator completes from the parent directory" {
  let picker = opened(location=Directory("/Users/dii/git"), entries=["openseek"])
  let editing = updated(picker, EditPath)
  // Deleting into the listed directory's own name asks the host for its
  // parent; the editor keeps the partial name and stays enabled meanwhile.
  let deleting = updated(editing, PathChanged("/Users/dii/gi"))
  assert_true(deleting.loading)
  assert_eq(deleting.path_draft, Some("/Users/dii/gi"))
  assert_eq(deleting.completion_parent, Some("/Users/dii/"))
  assert_true(deleting.generation != editing.generation)
  assert_false(deleting.listing_completes_draft())
  assert_eq(deleting.visible_entries(), [])
  // Typing on inside the pending parent does not repeat the request.
  let typing = updated(deleting, PathChanged("/Users/dii/g"))
  assert_eq(typing.generation, deleting.generation)
  assert_true(typing.loading)
  assert_eq(typing.path_draft, Some("/Users/dii/g"))
  // The reply lists the parent and keeps what was typed after it.
  let loaded = updated(
    typing,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/Users/dii"),
      entries=["git", "go"],
      generation=typing.generation,
    ),
  )
  assert_false(loaded.loading)
  assert_true(loaded.location == Some(Directory("/Users/dii")))
  assert_eq(loaded.path_draft, Some("/Users/dii/g"))
  assert_eq(loaded.path_filter(), "g")
  assert_eq(loaded.visible_entries(), ["git", "go"])
  assert_eq(loaded.selected_path_suggestion(), Some("git"))
  // Each further separator deleted climbs one more level, one request each.
  let climbing = updated(loaded, PathChanged("/Users/di"))
  assert_true(climbing.loading)
  assert_eq(climbing.completion_parent, Some("/Users/"))
  assert_true(climbing.generation != loaded.generation)
  // Windows: a drive's own separator is still that drive; deleting into the
  // letter leads back to the drive list, whose rows complete it.
  let drive = opened(location=Directory("/C:/"), entries=["Users"])
  let drive_editing = updated(drive, EditPath)
  let still_drive = updated(drive_editing, PathChanged("/C:"))
  assert_false(still_drive.loading)
  assert_eq(still_drive.visible_entries(), ["Users"])
  let to_drives = updated(still_drive, PathChanged("/C"))
  assert_true(to_drives.loading)
  assert_eq(to_drives.completion_parent, Some("/"))
  let drives = updated(
    to_drives,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=DriveList,
      entries=["C:", "D:"],
      generation=to_drives.generation,
    ),
  )
  assert_eq(drives.path_draft, Some("/C"))
  assert_eq(drives.visible_entries(), ["C:"])
}

///|
test "returning to the listed directory drops a pending parent browse" {
  let picker = opened(location=Directory("/Users/dii/git"), entries=["openseek"])
  let editing = updated(picker, EditPath)
  let deleting = updated(editing, PathChanged("/Users/dii/gi"))
  assert_true(deleting.loading)
  let back = updated(deleting, PathChanged("/Users/dii/git"))
  assert_false(back.loading)
  assert_eq(back.completion_parent, None)
  assert_true(back.generation != deleting.generation)
  assert_eq(back.visible_entries(), ["openseek"])
  // The parent's late reply must not move the picker.
  let stale = updated(
    back,
    Loaded(
      channel=@interop.ChannelId::Local,
      location=Directory("/Users/dii"),
      entries=["git", "go"],
      generation=deleting.generation,
    ),
  )
  assert_true(stale == back)
  // Narrowing inside the listed directory needs no request either.
  let narrowed = updated(back, PathChanged("/Users/dii/git/open"))
  assert_false(narrowed.loading)
  assert_eq(narrowed.generation, back.generation)
  assert_eq(narrowed.visible_entries(), ["openseek"])
}

///|
test "a directory the host cannot list fails quietly and is not asked again" {
  let picker = opened(location=Directory("/home/u"), entries=["proj"])
  let editing = updated(picker, EditPath)
  let asking = updated(editing, PathChanged("/gone/"))
  assert_true(asking.loading)
  assert_eq(asking.completion_parent, Some("/gone/"))
  let (_, failed, outcome) = State::handle(
    asking,
    emit(),
    Failed(
      channel=@interop.ChannelId::Local,
      message="no such directory: /gone",
      generation=asking.generation,
    ),
  )
  guard failed is Some(failed) else { fail("quiet failure closed the picker") }
  assert_true(outcome is None)
  assert_false(failed.loading)
  assert_true(failed.location == picker.location)
  assert_false(failed.listing_completes_draft())
  assert_eq(failed.visible_entries(), [])
  // Typing inside the missing directory does not retry.
  let typing = updated(failed, PathChanged("/gone/x"))
  assert_false(typing.loading)
  assert_eq(typing.generation, failed.generation)
  // Enter still navigates, so the host's reason surfaces as a toast.
  let submitted = updated(typing, SubmitPath)
  assert_true(submitted.loading)
  assert_eq(submitted.path_draft, None)
  assert_eq(submitted.completion_parent, None)
  let (_, _, toast) = State::handle(
    submitted,
    emit(),
    Failed(
      channel=@interop.ChannelId::Local,
      message="no such directory: /gone/x",
      generation=submitted.generation,
    ),
  )
  assert_true(
    toast is Some(Outcome::Failed(message)) &&
    message == "Cannot open folder: no such directory: /gone/x",
  )
  // Leaving the editor forgets the miss.
  let cancelled = updated(typing, CancelPathEdit)
  assert_eq(cancelled.completion_parent, None)
}
