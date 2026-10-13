// The browser tools this host offers the agents it runs (`@mcp`, reached
// through `seekmoon mcp`): what an agent can do with the dock's Browser
// tabs. They act on the same native views the `browser.*` window commands
// drive, so a tab is one thing whether the user or an agent is looking at
// it.
//
// A tool sees the tabs of the conversation that called it. The dock keeps a
// strip of tabs per conversation and the window keeps every strip's views
// alive, the off-screen ones hidden, so the window's views alone would show
// an agent every other conversation's tabs as well.

///|
/// The tools an agent uses the dock's browser with.
pub fn browser_tools(views : BrowserViews) -> Array[@mcp.Tool] {
  [
    {
      name: "browser_tabs",
      description: "List the browser tabs open beside this conversation in SeekMoon: each tab's id, URL, title, and whether it is the one currently shown to the user.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: call => views.tabs(call.session).stringify(),
    },
  ]
}

///|
/// `session`'s Browser tabs, in id order. Which views exist is the window's
/// to say, as everywhere else in this package; whose they are is what the
/// page told `open`.
fn BrowserViews::tabs(self : BrowserViews, session : String) -> Json raise {
  let tabs : Array[(Int32, Json)] = []
  for view in self.attached_window().views() {
    guard browser_view_id(view.id()) is Some(id) &&
      self.owners.get(id) == Some(session) else {
      continue
    }
    let tab : Map[String, Json] = { "id": Json(id) }
    // A view that has not committed its first navigation has no entry yet:
    // the tab exists, with no page to name.
    if view.navigation_history().active_entry() is Some(entry) {
      tab["url"] = Json(entry.url)
      tab["title"] = Json(entry.title)
    }
    tab["visible"] = Json(view.state().visible)
    tabs.push((id, Json::object(tab)))
  }
  tabs.sort_by_key(tab => tab.0)
  { "tabs": Json(tabs.map(tab => tab.1)) }
}

///|
async test "browser tools refuse to run without a window" {
  let views = BrowserViews()
  for tool in browser_tools(views) {
    let refused = try
      (tool.call)({ session: "s-1", arguments: Json::empty_object(), })
    catch {
      error => Some("\{error}")
    } noraise {
      _ => None
    }
    assert_eq(refused, Some("The desktop window is not ready"))
  }
}

///|
async test "a tab's conversation is forgotten with the tab" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  views.owners[2] = "s-1"
  views.owners[3] = "s-2"
  // Closing one tab forgets that tab alone, window or no window.
  assert_true(views.close({ id: 2, }) is Acknowledged)
  assert_eq(views.owners.to_array(), [(1, "s-1"), (3, "s-2")])
  // A reloaded page allocates ids from scratch, so nothing of the previous
  // page's tabs may be left to name a new one's.
  views.close_all()
  assert_true(views.owners.is_empty())
}
