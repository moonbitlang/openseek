///|
const New = "/device/d1/chat/new"

///|
const Settings = "/device/d1/settings"

///|
const Skills = "/device/d1/skills"

///|
test "visits deduplicate and branch without mutating previous states" {
  let initial = @browser_history.History(New, group="g", key="a")
  assert_false(initial.can_back())
  assert_false(initial.can_forward())
  assert_true(initial.visit(New, replace=false, key="unused") == Some(initial))
  guard initial.visit(Settings, replace=false, key="b") is Some(settings) else {
    fail("same-device visit rejected")
  }
  guard settings.visit(Skills, replace=false, key="c") is Some(skills) else {
    fail("same-device visit rejected")
  }
  guard skills.select(Settings, settings.marker()) is Some(back) else {
    fail("known browser entry rejected")
  }
  assert_true(back.can_back())
  assert_true(back.can_forward())
  guard back.visit(New, replace=false, key="d") is Some(branch) else {
    fail("branch rejected")
  }
  assert_false(branch.can_forward())
  assert_true(branch.select(Skills, skills.marker()) == None)
  assert_eq(initial.path(), New)
  assert_false(initial.can_back())
  assert_true(back.visit(New, replace=false, key="d") == Some(branch))
}

///|
test "v1 storage restores the cursor by entry key even for repeated paths" {
  let marker : Json = { "group": "old-group", "key": "second" }
  let stored : Json = {
    "entries": [
      { "key": "first", "path": Settings, "original": Settings },
      { "key": "second", "path": Settings, "original": Settings },
      { "key": "third", "path": Skills, "original": Skills },
    ],
    "unknown": true,
  }
  guard @browser_history.History::restore(Settings, Settings, marker, stored)
    is Some(history) else {
    fail("v1 history was not restored")
  }
  assert_eq(history.marker(), marker)
  assert_true(history.can_back())
  assert_true(history.can_forward())
  assert_eq(@browser_history.storage_group(marker), Some("old-group"))
  assert_true(
    @browser_history.History::restore(
      Settings,
      Settings,
      marker,
      history.stored(),
    ) ==
    Some(history),
  )
}

///|
test "malformed or foreign storage never restores a known segment" {
  let marker : Json = { "group": "g", "key": "a" }
  let entry : Json = { "key": "a", "path": Settings, "original": Settings }
  for
    stored in [
      Json::null(),
      { "entries": [] },
      { "entries": "wrong type" },
      { "entries": [entry, Json::null()] },
      { "entries": [{ "key": "a", "path": Settings }] },
      {
        "entries": [
          { "key": "a", "path": Settings, "original": "/device/d2/settings" },
        ],
      },
      {
        "entries": [
          { "key": "a", "path": "/device/d2/settings", "original": Settings },
        ],
      },
    ] {
    assert_true(
      @browser_history.History::restore(Settings, Settings, marker, stored) ==
      None,
    )
  }
  for
    bad_marker in [
      Json::null(),
      { "group": "g" },
      { "group": 1, "key": "a" },
      { "group": "g", "key": "missing" },
    ] {
    assert_true(
      @browser_history.History::restore(Settings, Settings, bad_marker, {
        "entries": [entry],
      }) ==
      None,
    )
  }
  assert_true(
    @browser_history.History::restore(Settings, Skills, marker, {
      "entries": [entry],
    }) ==
    None,
  )
}

///|
test "covered draft promotion survives refresh and an old browser URL" {
  let draft = "/device/d1/chat/draft/draft-1"
  let session = "/device/d1/chat/session/session-1"
  let initial = @browser_history.History(draft, group="g", key="a")
  guard initial.visit(Settings, replace=false, key="b") is Some(settings) else {
    fail("visit")
  }
  guard settings.promote(draft, session) is Some(promoted) else {
    fail("promotion")
  }
  assert_eq(promoted.path(), Settings)
  assert_eq(promoted.marker(), settings.marker())
  guard @browser_history.History::restore(
      Settings,
      Settings,
      settings.marker(),
      promoted.stored(),
    )
    is Some(refreshed) else {
    fail("refresh")
  }
  guard refreshed.select(draft, initial.marker()) is Some(back) else {
    fail("old browser entry")
  }
  assert_eq(back.path(), session)
  assert_false(back.can_back())
  assert_true(back.can_forward())
  assert_true(
    @browser_history.History::restore(
      draft,
      draft,
      initial.marker(),
      promoted.stored(),
    ) ==
    Some(back),
  )
  assert_true(
    @browser_history.History::restore(
      session,
      session,
      initial.marker(),
      promoted.stored(),
    ) ==
    Some(back),
  )
  assert_eq(initial.path(), draft)
  assert_true(settings.promote(draft, session) == Some(promoted))
}

///|
test "replacement keeps entry identity and forward history but retires the original path" {
  let draft = "/device/d1/codex/draft/expired"
  let initial = @browser_history.History(draft, group="g", key="a")
  guard initial.visit(Settings, replace=false, key="b") is Some(settings) else {
    fail("visit")
  }
  guard settings.select(draft, initial.marker()) is Some(back) else {
    fail("back")
  }
  guard back.visit("/device/d1/codex/new", replace=true, key="unused")
    is Some(replaced) else {
    fail("replace")
  }
  assert_eq(replaced.marker(), initial.marker())
  assert_true(replaced.can_forward())
  assert_true(replaced.select(draft, initial.marker()) == None)
  assert_eq(
    replaced.select(Settings, settings.marker()).map(h => h.path()),
    Some(Settings),
  )
}

///|
test "foreign and unknown browser entries are distinguished from known positions" {
  let initial = @browser_history.History(New, group="g", key="a")
  assert_false(initial.owns("/device/d10/chat/new"))
  assert_false(initial.owns("/console/"))
  assert_true(
    initial.visit("/device/d2/settings", replace=false, key="b") == None,
  )
  assert_true(initial.promote(New, "/device/d2/chat/new") == None)
  assert_true(initial.select(New, { "group": "other", "key": "a" }) == None)
  assert_true(initial.select(New, { "group": "g", "key": "unknown" }) == None)
  assert_true(initial.select(Settings, initial.marker()) == None)
  assert_true(initial.select(New, initial.marker()) == Some(initial))
}

///|
test "successive promotions retain the URL actually written to each entry" {
  let chat = "/device/d1/chat/draft/draft-1"
  let codex = "/device/d1/codex/draft/draft-1"
  let thread = "/device/d1/codex/thread/thread-1"
  let initial = @browser_history.History(chat, group="g", key="a")
  // Exercise writing after an active promotion, a pop, and a reload.
  for mode in ["active", "pop", "reload"] {
    guard initial.visit(Settings, replace=false, key="b") is Some(settings) else {
      fail("visit")
    }
    let promoted = if mode == "active" {
      initial.promote(chat, codex)
    } else {
      settings.promote(chat, codex)
    }
    guard promoted is Some(promoted) else { fail("promotion") }
    let selected = if mode == "active" {
      Some(promoted)
    } else if mode == "pop" {
      promoted.select(chat, initial.marker())
    } else {
      @browser_history.History::restore(
        chat,
        chat,
        initial.marker(),
        promoted.stored(),
      )
    }
    guard selected is Some(selected) else { fail("selection") }
    let written = selected.written()
    assert_true(written.written() == written)
    guard written.visit(Settings, replace=false, key="c") is Some(covered) &&
      covered.promote(codex, thread) is Some(sent) else {
      fail("covered promotion")
    }
    // A refresh of Settings must retain the intermediate URL too.
    guard @browser_history.History::restore(
        Settings,
        Settings,
        sent.marker(),
        sent.stored(),
      )
      is Some(refreshed) &&
      refreshed.select(codex, written.marker()) is Some(back) else {
      fail("intermediate browser URL lost")
    }
    assert_eq(back.path(), thread)
    assert_false(back.can_back())
    assert_true(back.can_forward())
    assert_eq(
      back.written().select(Settings, sent.marker()).map(h => h.path()),
      Some(Settings),
    )
    assert_eq(initial.path(), chat)
  }
}
