// Page navigation and transcript viewport transitions.

///|
test "a conversation's sub-run twisty toggles only its own row" {
  let dispatch = test_dispatch()
  let model = test_model()
  assert_false(model.subruns_expanded(Local, "a"))
  let (_, opened) = update(dispatch, ToggleSubruns(Local, "a"), model)
  assert_true(opened.subruns_expanded(Local, "a"))
  // A neighbour, and the same id on another device, stay folded: the state
  // is keyed by both halves.
  assert_false(opened.subruns_expanded(Local, "b"))
  assert_false(opened.subruns_expanded(Remote("dev"), "a"))
  let (_, closed) = update(dispatch, ToggleSubruns(Local, "a"), opened)
  assert_false(closed.subruns_expanded(Local, "a"))
}

///|
test "viewport resize flips the narrow flag and resets the sidebar" {
  let dispatch = test_dispatch()
  let (_, narrow) = update(dispatch, ViewportResized(width=390), test_model())
  assert_true(narrow.narrow)
  assert_false(narrow.sidebar_open)
  // Same side of the breakpoint: nothing moves (idempotent).
  let (_, same) = update(dispatch, ViewportResized(width=390), narrow)
  assert_true(same.narrow)
  assert_false(same.sidebar_open)
  let (_, wide) = update(dispatch, ViewportResized(width=1280), same)
  assert_false(wide.narrow)
  assert_true(wide.sidebar_open)
}

///|
test "the narrow drawer closes when navigation lands elsewhere" {
  let dispatch = test_dispatch()
  let (_, narrow) = update(dispatch, ViewportResized(width=390), test_model())
  let (_, opened) = update(dispatch, ToggleSidebar, narrow)
  assert_true(opened.sidebar_open)
  // Navigating to the Skills page from the drawer closes it; on the wide
  // layout the same navigation leaves the sidebar column alone.
  let (_, settled) = update(dispatch, OpenSkills, opened)
  assert_false(settled.sidebar_open)
  let (_, wide) = update(dispatch, ViewportResized(width=1280), settled)
  let (_, back) = update(dispatch, OpenSetup, wide)
  assert_true(back.sidebar_open)
}

///|
test "a host action failure pops a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    HostActionFailed("open path failed: no opener"),
    test_model(),
  )
  inspect(next.notifications.length(), content="1")
  inspect(next.notifications[0].message, content="open path failed: no opener")
}

///|
test "opening an external link is a pure model transition" {
  let dispatch = test_dispatch()
  let base = test_model()
  let (_, first) = update(
    dispatch,
    ExternalLinkClicked("https://example.com/docs"),
    base,
  )
  let (_, second) = update(
    dispatch,
    ExternalLinkClicked("https://example.com/docs"),
    base,
  )
  inspect(first.active_session, content="desktop-test")
  inspect(second.active_session, content="desktop-test")
  inspect(first.notifications.length(), content="0")
  inspect(second.notifications.length(), content="0")
}

///|
/// The Settings page has no Done button — the sidebar is the only way out,
/// even while the endpoint is unusable (the composer blocks sending then).
test "sidebar navigation leaves the settings page" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), api_provider: Deepseek, screen: Settings }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "s-fresh" }),
    model,
  )
  assert_true(next.screen is Chat)
}

///|
test "the scroll watcher's report lands on the model" {
  let dispatch = test_dispatch()
  let (_, away) = update(dispatch, TranscriptPinned(false), test_model())
  inspect(away.transcript_pinned, content="false")
  let (_, back) = update(dispatch, TranscriptPinned(true), away)
  inspect(back.transcript_pinned, content="true")
}

///|
/// A `git.branch` reply for the test conversation.
fn branch_reply(
  branch : String,
  generation? : Int = 0,
  session? : String = "desktop-test",
  diffstat? : DiffStat,
  base_hint? : String,
) -> DeviceMsg {
  BranchLoaded(
    session~,
    branch=Some(branch),
    diffstat~,
    generation~,
    base_hint~,
  )
}

///|
/// A `git.pull_request` reply for the test conversation. `queried` defaults to
/// the branch asked about, which is the ordinary case: only a checkout that
/// moved mid-request makes them differ.
fn pull_request_reply(
  branch : String,
  generation~ : Int,
  queried? : String,
  pull_request? : PullRequest,
  compare_url? : String,
) -> DeviceMsg {
  PullRequestLoaded(
    session="desktop-test",
    branch~,
    generation~,
    queried=Some(queried.unwrap_or(branch)),
    pull_request~,
    compare_url~,
  )
}

///|
/// The probe a lookup for `branch` leaves behind while it runs.
fn probing_for(
  branch : String,
  pull_request? : PullRequest,
  compare_url? : String,
) -> PullRequestProbe {
  { branch, probing: true, stale: false, pull_request, compare_url }
}

///|
/// One pull request, varied per test by field update.
fn test_pull_request() -> PullRequest {
  {
    number: 710,
    title: "Add a changed-files explorer",
    state: PullRequestOpen,
    draft: true,
    url: "https://github.test/acme/app/pull/710",
    base: "main",
    additions: 2972,
    deletions: 287,
    changed_files: 18,
    checks: Some({ passed: 1, failed: 0, pending: 3 }),
  }
}

///|
test "a branch reply lands on its conversation and an empty one hides it" {
  let dispatch = test_dispatch()
  let stat : DiffStat = {
    added: 12,
    removed: 3,
    files: 2,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, named) = update_dev(
    dispatch,
    branch_reply("feature/x", diffstat=stat),
    test_model(),
  )
  assert_true(named.active().branch is Some("feature/x"))
  assert_eq(named.active().diffstat, Some(stat))
  // A named branch is also what the pull-request lookup keys on, and the
  // lookup it issued is on record so a second reply cannot stack another.
  assert_eq(named.active().pull_request, Some(probing_for("feature/x")))
  assert_eq(named.active().pull_request_generation, 1)
  let (_, cleared) = update_dev(dispatch, branch_reply(""), named)
  assert_true(cleared.active().branch is Some(""))
  // A workspace that stopped being a repository keeps no pull request from
  // the branch it used to have — and the lookup still running for it is
  // retired rather than left holding a number the next one would reuse.
  assert_eq(cleared.active().pull_request, None)
  assert_eq(cleared.active().pull_request_generation, 2)
  let (_, overtaken) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      pull_request=test_pull_request(),
    ),
    cleared,
  )
  assert_eq(overtaken.active().pull_request, None)
  // A reply for an unknown session is dropped.
  let (_, ignored) = update_dev(
    dispatch,
    branch_reply("main", session="desktop-gone"),
    test_model(),
  )
  assert_true(ignored.active().branch is None)
}

///|
test "a superseded branch probe cannot put its older answer back" {
  let dispatch = test_dispatch()
  // Two probes in flight: a run's start and its finish, or either of those and
  // the popover being opened. The first is still counting untracked files.
  let (_, first) = probe_branch(
    dispatch,
    test_model(),
    @interop.ChannelId::Local,
    "desktop-test",
    None,
  )
  let (_, second) = probe_branch(
    dispatch,
    first,
    @interop.ChannelId::Local,
    "desktop-test",
    None,
  )
  assert_eq(second.active().branch_generation, 2)
  let newer : DiffStat = {
    added: 9,
    removed: 0,
    files: 1,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, settled) = update_dev(
    dispatch,
    branch_reply("feature/new", generation=2, diffstat=newer),
    second,
  )
  assert_eq(settled.active().diffstat, Some(newer))
  // The slower first probe answers last, and is discarded: nothing would have
  // corrected its stale totals until the next refresh.
  let (_, overtaken) = update_dev(
    dispatch,
    branch_reply("feature/old", generation=1),
    settled,
  )
  assert_true(overtaken.active().branch is Some("feature/new"))
  assert_eq(overtaken.active().diffstat, Some(newer))
}

///|
test "a pull-request reply only lands on the branch it was asked about" {
  let dispatch = test_dispatch()
  // Measured from the base the answers below report, so settling one asks for
  // nothing further and this stays about which reply lands where.
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/x", base_hint="main"),
    test_model(),
  )
  let answer = test_pull_request()
  // A reply from a lookup that has since been superseded is dropped. The
  // branch name cannot decide this: a checkout that moves X → Y → X leaves two
  // lookups for X in flight at once, so which request answered is the question.
  let (_, stale) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=0, pull_request=answer),
    probing,
  )
  assert_eq(stale.active().pull_request.unwrap().pull_request, None)
  assert_true(stale.active().pull_request.unwrap().probing)
  // The host answers about whatever `HEAD` said when it ran. An answer that
  // came back describing a different branch is filed under that branch, not
  // under the one the lookup was issued for — so the chip, which only shows a
  // probe matching the checked-out branch, does not show it against this one.
  let (_, moved) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      queried="feature/y",
      pull_request=answer,
    ),
    probing,
  )
  assert_eq(moved.active().pull_request.unwrap().branch, "feature/y")
  assert_eq(moved.active().settled_probe(), None)
  let (_, settled) = update_dev(
    dispatch,
    PullRequestLoaded(
      session="desktop-test",
      branch="feature/x",
      generation=1,
      queried=Some("feature/x"),
      pull_request=Some(answer),
      compare_url=None,
    ),
    probing,
  )
  assert_eq(
    settled.active().pull_request,
    Some({ ..probing_for("feature/x", pull_request=answer), probing: false }),
  )
  // Refreshing the same branch keeps that answer on screen while it re-probes,
  // so the chip does not blink on every run boundary. A new request means a new
  // number; the answer it carries is the old one's, kept only until this lookup
  // replaces it.
  let (_, refreshing) = update_dev(
    dispatch,
    branch_reply("feature/x", base_hint="main"),
    settled,
  )
  assert_eq(
    refreshing.active().pull_request,
    Some(probing_for("feature/x", pull_request=answer)),
  )
  assert_eq(refreshing.active().pull_request_generation, 2)
}

///|
test "a pull request's base is measured from as soon as it is known" {
  let dispatch = test_dispatch()
  // The first probe of a session has no pull request to ask about, so the host
  // measured from its own guess and said so.
  let guessed : DiffStat = {
    added: 2467,
    removed: 51,
    files: 24,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/y", diffstat=guessed),
    test_model(),
  )
  assert_eq(probing.active().diffstat_hint, None)
  let branch_generation = probing.active().branch_generation
  // The lookup comes back naming a base no local rule would have guessed: this
  // branch sits on another one, so the totals on screen are the stack's, not
  // this branch's. Settling therefore asks for another measurement.
  let stacked = { ..test_pull_request(), base: "feature/x" }
  let (_, settled) = update_dev(
    dispatch,
    pull_request_reply("feature/y", generation=1, pull_request=stacked),
    probing,
  )
  assert_true(settled.active().branch_generation > branch_generation)
  // That measurement answers with the base it was given, which is what stops
  // the next settled answer from asking again.
  let measured : DiffStat = {
    ..guessed,
    added: 41,
    base: Some("origin/feature/x"),
  }
  let (_, remeasured) = update_dev(
    dispatch,
    branch_reply(
      "feature/y",
      generation=settled.active().branch_generation,
      diffstat=measured,
      base_hint="feature/x",
    ),
    settled,
  )
  assert_eq(remeasured.active().diffstat, Some(measured))
  assert_eq(remeasured.active().diffstat_hint, Some("feature/x"))
  let (_, quiet) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/y",
      generation=remeasured.active().pull_request_generation,
      pull_request=stacked,
    ),
    remeasured,
  )
  assert_eq(
    quiet.active().branch_generation,
    remeasured.active().branch_generation,
  )
}

///|
test "a checkout that returns to a branch does not accept the older lookup" {
  let dispatch = test_dispatch()
  // X, then away to Y, then back to X: the first X lookup is still running,
  // and a second one for the same branch is now in flight beside it.
  let (_, first) = update_dev(dispatch, branch_reply("feature/x"), test_model())
  assert_eq(first.active().pull_request_generation, 1)
  let (_, away) = update_dev(dispatch, branch_reply("feature/y"), first)
  let (_, back) = update_dev(dispatch, branch_reply("feature/x"), away)
  assert_eq(back.active().pull_request_generation, 3)
  fn answered(generation : Int, number : Int) {
    pull_request_reply("feature/x", generation~, pull_request={
      ..test_pull_request(),
      number,
    })
  }

  fn picked(model : Model) {
    model.active().pull_request.unwrap().pull_request.unwrap().number
  }

  // The newer one settles first.
  let (_, settled) = update_dev(dispatch, answered(3, 710), back)
  assert_eq(picked(settled), 710)
  // The older one for the same branch arrives afterwards. Matching by name
  // would take it; matching by request does not.
  let (_, overtaken) = update_dev(dispatch, answered(1, 404), settled)
  assert_eq(picked(overtaken), 710)
}

///|
test "a reopened conversation does not accept the old record's replies" {
  let dispatch = test_dispatch()
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/x"),
    test_model(),
  )
  let generation = probing.active().pull_request_generation
  // Archiving and reopening the same session does not clear the record, it
  // builds a new one — counters included, which is why they cannot live there.
  let reopened = probing.replace_conversation(test_conversation())
  assert_eq(reopened.active().pull_request_generation, 0)
  let (_, again) = update_dev(dispatch, branch_reply("feature/x"), reopened)
  assert_true(again.active().pull_request_generation > generation)
  // The lookup the first record left running answers now, for a checkout the
  // reopened conversation has not confirmed anything about yet.
  let (_, late) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation~,
      pull_request=test_pull_request(),
    ),
    again,
  )
  assert_eq(late.active().pull_request.unwrap().pull_request, None)
}

///|
test "a refresh during a lookup is run afterwards, not dropped" {
  let dispatch = test_dispatch()
  let refresh = branch_reply("feature/x")
  let (_, probing) = update_dev(dispatch, refresh, test_model())
  assert_true(probing.active().pull_request.unwrap().probing)
  // A run finishing while the run-start lookup is still in flight does not
  // stack a second request — but the answer it is waiting on was gathered
  // before that run's work, so it must not be the last word either.
  let (_, queued) = update_dev(dispatch, refresh, probing)
  assert_eq(
    queued.active().pull_request,
    Some({ ..probing_for("feature/x"), stale: true }),
  )
  // Settling that lookup therefore issues another rather than leaving the
  // composer describing the repository as it was when the run started.
  let compare = "https://github.test/acme/app/compare/feature/x"
  let (_, followed) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=1, compare_url=compare),
    queued,
  )
  guard followed.active().pull_request is Some(probe) else {
    fail("the queued refresh dropped the probe")
  }
  assert_true(probe.probing)
  assert_false(probe.stale)
  // Its answer stays on screen while the follow-up runs.
  assert_true(probe.compare_url is Some(_))
  // With nothing queued, settling is the end of it.
  let (_, quiet) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=1),
    probing,
  )
  assert_false(quiet.active().pull_request.unwrap().probing)
  // A queued retry after an answer about a branch the checkout has left drops
  // that answer instead of relabelling it: carrying it over would reintroduce
  // exactly the mismatch the reply's own branch is there to prevent. The retry
  // is a new request, so it carries the next number.
  let (_, elsewhere) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      queried="feature/y",
      pull_request=test_pull_request(),
    ),
    queued,
  )
  assert_eq(elsewhere.active().pull_request, Some(probing_for("feature/x")))
  assert_eq(elsewhere.active().pull_request_generation, 2)
}

///|
test "the composer's git details popover toggles shut again" {
  let dispatch = test_dispatch()
  // The popover has no trigger without a branch, so a conversation that has
  // one is where this starts — the flag cannot be raised otherwise.
  let (_, on_branch) = update_dev(
    dispatch,
    branch_reply("feature/x"),
    test_model(),
  )
  assert_false(on_branch.git_details_open)
  let (_, opened) = update(dispatch, ToggleGitDetails, on_branch)
  assert_true(opened.git_details_open)
  // Opening re-probes (the command is not inspectable here), which must not
  // disturb what is already on screen: the answer stays until its reply lands.
  assert_eq(opened.active().pull_request, on_branch.active().pull_request)
  assert_eq(opened.active().diffstat, on_branch.active().diffstat)
  let (_, closed) = update(dispatch, ToggleGitDetails, opened)
  assert_false(closed.git_details_open)
  // Switching conversations closes it, and so does the branch going away under
  // the conversation on screen. Neither produces a click for the dismissal
  // listener to see, and with no chip rendered nothing is left to click the
  // popover shut — the flag would go on hiding the native browser with no
  // visible cause.
  let (_, switched) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-other" }),
    opened,
  )
  assert_eq(switched.active_session, "desktop-other")
  assert_false(switched.git_details_open)
  let (_, lost) = update_dev(
    dispatch,
    branch_reply("", generation=opened.active().branch_generation),
    opened,
  )
  assert_false(lost.active().shows_git_chip())
  assert_false(lost.git_details_open)
  // Dismissal is idempotent where the toggle is not: the click that closes the
  // popover also reaches whatever it landed on, and a second dismissal — from
  // a page that dispatched one on its own — must not bring it back.
  let (_, dismissed) = update(dispatch, CloseGitDetails, opened)
  assert_false(dismissed.git_details_open)
  let (_, still_closed) = update(dispatch, CloseGitDetails, dismissed)
  assert_false(still_closed.git_details_open)
}

///|
test "every click-away menu closes without reopening on a second dismissal" {
  let dispatch = test_dispatch()
  // The topbar app launcher.
  let (_, launched) = update(dispatch, ToggleLauncher, test_model())
  assert_true(launched.launcher.open)
  let (_, dropped) = update(dispatch, CloseLauncher, launched)
  assert_false(dropped.launcher.open)
  let (_, twice) = update(dispatch, CloseLauncher, dropped)
  assert_false(twice.launcher.open)
  // Dismissing does not discard the catalog the launcher already probed, so
  // reopening it does not go back to the host for a list it has.
  assert_true(dropped.launcher.apps is AppsLoading)
  // The dock strip's `+` menu, which needs its panel open first (the same
  // setup the launcher-row test uses).
  let (_, docked) = update(dispatch, Dock(TogglePanel), desktop_model())
  let (_, menued) = update(dispatch, Dock(MenuToggled), docked)
  assert_true(menued.dock.menu_open)
  let (_, unmenued) = update(dispatch, CloseDockMenu, menued)
  assert_false(unmenued.dock.menu_open)
  let (_, unmenued_twice) = update(dispatch, CloseDockMenu, unmenued)
  assert_false(unmenued_twice.dock.menu_open)
}

///|
test "the color-scheme watcher only changes a system-following theme" {
  let dispatch = test_dispatch()
  let system = { ..test_model(), theme: System, system_dark: false }
  let (_, dark) = update(dispatch, ColorSchemeChanged(true), system)
  assert_true(dark.theme is System)
  assert_true(dark.system_dark)
  let fixed = { ..dark, theme: Light }
  let (_, changed_host) = update(dispatch, ColorSchemeChanged(false), fixed)
  assert_true(changed_host.theme is Light)
  assert_false(changed_host.system_dark)
}

///|
test "theme settings switch fixed palettes and are idempotent" {
  let dispatch = test_dispatch()
  let system = { ..test_model(), theme: System, system_dark: true }
  let (_, first) = update(dispatch, ThemeChanged("dark"), system)
  let (_, repeated) = update(dispatch, ThemeChanged("dark"), first)
  assert_true(first.theme is Dark)
  assert_true(repeated.theme is Dark)
  assert_true(first.system_dark && repeated.system_dark)
  let (_, following) = update(dispatch, ThemeChanged("system"), first)
  assert_true(following.theme is System)
  assert_true(following.system_dark)
  let (_, light) = update(dispatch, ThemeChanged("light"), first)
  assert_true(light.theme is Light)
  let (_, unchanged) = update(dispatch, ThemeChanged("unknown"), system)
  assert_true(unchanged.theme is System)
}

///|
test "update is pure: a pinned-state change is idempotent" {
  let dispatch = test_dispatch()
  let (_, first) = update(dispatch, TranscriptPinned(false), test_model())
  let (_, second) = update(dispatch, TranscriptPinned(false), test_model())
  inspect(first.transcript_pinned, content="false")
  inspect(second.transcript_pinned, content="false")
}

///|
test "an unpinned transcript stays unpinned while a stream grows" {
  // The pinned flag is the scroll gate; a delta to the active conversation
  // must not flip it back, or the next render would yank the reader down.
  let dispatch = test_dispatch()
  let model = { ..running_model(), transcript_pinned: false }
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("more"), session=None),
    model,
  )
  inspect(next.transcript_pinned, content="false")
  inspect(next.active().streaming_response, content="more")
}

///|
test "explicit user actions re-pin the transcript" {
  let dispatch = test_dispatch()

  // Sending a prompt jumps to the tail.
  let unpinned = {
    ..test_model().replace_conversation({ ..test_conversation(), task: "do it" }),
    transcript_pinned: false,
  }
  let (_, sent) = update(dispatch, Send, unpinned)
  inspect(sent.transcript_pinned, content="true")

  // Steering a running turn does too.
  let steering = {
    ..running_model().replace_conversation({
      ..running_conversation(),
      task: "and this",
    }),
    transcript_pinned: false,
  }
  let (_, steered) = update(dispatch, Send, steering)
  inspect(steered.transcript_pinned, content="true")

  // Switching to a conversation that has live state lands at its tail.
  let two = {
    ..test_model().replace_conversation(
      empty_conversation(@interop.ChannelId::Local, "desktop-other"),
    ),
    transcript_pinned: false,
  }
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-other"),
    two,
  )
  inspect(switched.transcript_pinned, content="true")

  // So does loading a stored session or rotating to a fresh one.
  let (_, loading_old) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-old"),
    { ..test_model(), transcript_pinned: false },
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-old",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_old,
  )
  inspect(loaded.transcript_pinned, content="true")
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh" }),
    { ..test_model(), transcript_pinned: false },
  )
  inspect(rotated.transcript_pinned, content="true")
}
