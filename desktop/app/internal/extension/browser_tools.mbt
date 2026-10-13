// The browser tools this host offers the agents it runs (`@mcp`, reached
// through `seekmoon mcp`): what an agent can do with the dock's Browser tabs. They act on the same
// native views the `browser.*` window commands drive, so a tab is one thing
// whether the user or an agent is looking at it.

///|
/// The tools an agent uses the dock's browser with.
pub fn browser_tools(views : BrowserViews) -> Array[@mcp.Tool] {
  [
    {
      name: "browser_tabs",
      description: "List the tabs open in the SeekMoon browser: each tab's id, URL, title, and whether it is the one currently shown to the user.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: _ => views.tabs().stringify(),
    },
  ]
}

///|
/// Every Browser tab the window holds, in id order. The window's views are
/// the truth here as everywhere else in this package; nothing is mirrored.
fn BrowserViews::tabs(self : BrowserViews) -> Json raise {
  let tabs : Array[(Int32, Json)] = []
  for view in self.attached_window().views() {
    guard browser_view_id(view.id()) is Some(id) else { continue }
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
