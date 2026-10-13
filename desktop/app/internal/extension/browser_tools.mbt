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
//
// Opening a tab is the page's to do, not the host's: the page allocates a
// tab's id, puts it in a strip, and knows the theme its view starts in. So
// `browser_open` asks the page (`browser.event` kind `open_requested`) and
// waits for the `browser.open` the page answers with. Everything else acts
// on a view that already exists, and the page follows along through the
// view events it already listens to.

///|
/// How long the page has to open a tab it was asked for.
const OpenTimeoutMs : Int32 = 10000

///|
/// How long a tool waits for the page it navigated to finish loading before
/// it answers with the page as it stands.
const SettleTimeoutMs : Int32 = 15000

///|
/// How long a navigation has to start loading before it is taken for one
/// that loads nothing — a step within one document's own history.
const StartGraceMs : Int32 = 1000

///|
const SettlePollMs : Int32 = 50

///|
/// How many loads a view has started and finished.
priv struct LoadCount {
  started : Int32
  finished : Int32
} derive(Eq)

///|
/// The tools an agent uses the dock's browser with.
pub fn browser_tools(views : BrowserViews) -> Array[@mcp.Tool] {
  [
    {
      name: "browser_tabs",
      description: "List the browser tabs open beside this conversation in SeekMoon: each tab's id, URL, title, whether it is still loading, and whether it is the one currently shown to the user.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: call => views.tabs(call.session).stringify(),
    },
    {
      name: "browser_open",
      description: "Open a new browser tab beside this conversation in SeekMoon and load an address in it. The user sees the tab. Answers with the tab once its page has loaded.",
      input_schema: {
        "type": "object",
        "properties": {
          "url": {
            "type": "string",
            "description": "The address to load: http://, https://, or file://.",
          },
        },
        "required": ["url"],
        "additionalProperties": false,
      },
      call: call => views.open_tab(call.session, call.arguments).stringify(),
    },
    {
      name: "browser_navigate",
      description: "Take one of this conversation's browser tabs somewhere else: load an address in it, go back or forward in its history, or reload it. Give exactly one of `url` and `action`. Answers with the tab once its page has loaded.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": {
            "type": "integer",
            "description": "The tab's id, from browser_tabs or browser_open.",
          },
          "url": {
            "type": "string",
            "description": "An address to load: http://, https://, or file://.",
          },
          "action": { "type": "string", "enum": ["back", "forward", "reload"] },
        },
        "required": ["tab"],
        "additionalProperties": false,
      },
      call: call => views.navigate_tab(call.session, call.arguments).stringify(),
    },
  ]
}

///|
/// One tab as a tool reports it.
fn BrowserViews::tab_json(
  self : BrowserViews,
  id : Int32,
  view : @proton.ViewHandle,
) -> Json raise {
  let tab : Map[String, Json] = { "id": Json(id) }
  // A view that has not committed its first navigation has no entry yet:
  // the tab exists, with no page to name.
  if view.navigation_history().active_entry() is Some(entry) {
    tab["url"] = Json(entry.url)
    tab["title"] = Json(entry.title)
  }
  let count = self.load_count(id)
  tab["loading"] = Json(count.started > count.finished)
  tab["visible"] = Json(view.state().visible)
  Json::object(tab)
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
    tabs.push((id, self.tab_json(id, view)))
  }
  tabs.sort_by_key(tab => tab.0)
  { "tabs": Json(tabs.map(tab => tab.1)) }
}

///|
/// The view of tab `id`, which must be one of `session`'s. A tab of another
/// conversation is, to this one, a tab that does not exist.
fn BrowserViews::tab_view(
  self : BrowserViews,
  session : String,
  id : Int32,
) -> @proton.ViewHandle raise {
  guard self.owners.get(id) == Some(session) else {
    raise @mcp.ToolError(
      "This conversation has no browser tab \{id}; browser_tabs lists the ones it has.",
    )
  }
  self.view(id)
}

///|
fn refuse_unless_page_url(url : String) -> Unit raise @mcp.ToolError {
  guard allowed_page_url(url) else {
    raise ToolError(
      "Only http://, https://, and file:// addresses can be loaded, and this is none of them: \{url}",
    )
  }
}

///|
fn BrowserViews::load_count(self : BrowserViews, id : Int32) -> LoadCount {
  // A view no event has been seen for has loaded nothing yet.
  self.loads.get(id).unwrap_or({ started: 0, finished: 0, })
}

///|
/// Whether a tool that asked a view for a navigation `waited` milliseconds
/// ago has waited long enough, given the view's loads `before` asking and
/// `now`: the load it started has finished, or none started within the
/// grace a load is given to begin, or it has outlasted the tool's patience.
fn settled(before : LoadCount, now : LoadCount, waited : Int32) -> Bool {
  if now.started > before.started {
    now.finished >= now.started || waited >= SettleTimeoutMs
  } else {
    waited >= StartGraceMs
  }
}

///|
/// Wait for the navigation just asked of page `id`'s view to settle.
async fn BrowserViews::settle(
  self : BrowserViews,
  id : Int32,
  before : LoadCount,
) -> Unit {
  for waited = 0
      !settled(before, self.load_count(id), waited)
      waited = waited + SettlePollMs {
    @async.sleep(SettlePollMs)
  }
}

///|
/// Deliver the id of a tab the page opened because it was asked to. Part of
/// every `browser.open`; an open nobody asked for, or one whose asker has
/// stopped waiting, delivers nothing.
fn BrowserViews::answer_open(
  self : BrowserViews,
  payload : @protocol.BrowserOpenPayload,
) -> Unit {
  guard payload.request is Some(request) &&
    self.opening.get(request) is Some(waiting) else {
    return
  }
  // The queue is unbounded and never closed, so this cannot refuse.
  (waiting.try_put(payload.id) catch { _ => false }) |> ignore
}

///|
/// `browser_open`: ask the page for a tab in `session`'s strip, and answer
/// with it once the page it loads has settled.
async fn BrowserViews::open_tab(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> Json {
  guard arguments is { "url": String(url), .. } else {
    raise @mcp.ToolError("browser_open needs `url`, the address to load.")
  }
  refuse_unless_page_url(url)
  ignore(self.attached_window())
  guard self.notify is Some(notify) else { raise WindowNotReady }
  let request = @uuid.mint()
  let opened : @async.Queue[Int32] = Queue(kind=Unbounded)
  self.opening[request] = opened
  defer self.opening.remove(request)
  notify({
    "kind": "open_requested",
    "request": Json(request),
    "session": Json(session),
    "url": Json(url),
  })
  guard @async.with_timeout_opt(OpenTimeoutMs, () => opened.get()) is Some(id) else {
    raise @mcp.ToolError(
      "SeekMoon did not open the tab within \{OpenTimeoutMs / 1000} seconds.",
    )
  }
  // A view the page has just created has loaded nothing before this.
  self.settle(id, { started: 0, finished: 0, })
  self.tab_json(id, self.tab_view(session, id))
}

///|
/// Where `browser_navigate` takes a tab.
priv enum Navigation {
  To(String)
  Back
  Forward
  Reload
}

///|
/// The tab and destination a `browser_navigate` call names.
fn navigation(arguments : Json) -> (Int32, Navigation) raise @mcp.ToolError {
  guard arguments is { "tab": Number(tab, ..), .. } &&
    tab.to_int().to_double() == tab else {
    raise ToolError(
      "browser_navigate needs `tab`, the id of the tab to navigate.",
    )
  }
  let url = match arguments {
    { "url": String(url), .. } => Some(url)
    _ => None
  }
  let action = match arguments {
    { "action": String(action), .. } => Some(action)
    _ => None
  }
  let destination = match (url, action) {
    (Some(url), None) => To(url)
    (None, Some("back")) => Back
    (None, Some("forward")) => Forward
    (None, Some("reload")) => Reload
    (None, Some(other)) =>
      raise ToolError("`action` is back, forward, or reload, not \{other}.")
    _ =>
      raise ToolError(
        "browser_navigate needs exactly one of `url` (an address to load) and `action` (back, forward, or reload).",
      )
  }
  (tab.to_int(), destination)
}

///|
/// `browser_navigate`: take one of `session`'s tabs somewhere, and answer
/// with it once the page has settled.
async fn BrowserViews::navigate_tab(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> Json {
  let (id, destination) = navigation(arguments)
  if destination is To(url) {
    refuse_unless_page_url(url)
  }
  let view = self.tab_view(session, id)
  // The element the user is picking belongs to the page being left.
  if self.pick is Some(pick) && pick.id == id {
    self.cancel_pick()
  }
  let before = self.load_count(id)
  match destination {
    To(url) => view.load_url(url)
    Back => {
      guard view.can_go_back() else {
        raise @mcp.ToolError("Tab \{id} has no earlier page to go back to.")
      }
      view.back()
    }
    Forward => {
      guard view.can_go_forward() else {
        raise @mcp.ToolError("Tab \{id} has no later page to go forward to.")
      }
      view.forward()
    }
    Reload => view.reload(ignore_cache=true)
  }
  self.settle(id, before)
  self.tab_json(id, view)
}

///|
/// What a tool call came to, as the text of its refusal.
async fn refusal(
  views : BrowserViews,
  tool : String,
  session : String,
  arguments : Json,
) -> String? {
  for candidate in browser_tools(views) {
    if candidate.name == tool {
      return try (candidate.call)({ session, arguments, }) catch {
        error => Some("\{error}")
      } noraise {
        _ => None
      }
    }
  }
  fail("no browser tool named \{tool}")
}

///|
async test "browser tools refuse to run without a window" {
  let views = BrowserViews()
  let not_ready = Some("The desktop window is not ready")
  assert_eq(refusal(views, "browser_tabs", "s-1", {}), not_ready)
  assert_eq(
    refusal(views, "browser_open", "s-1", { "url": "https://example.com/" }),
    not_ready,
  )
  // A tab the conversation owns but the window cannot produce.
  views.owners[1] = "s-1"
  assert_eq(
    refusal(views, "browser_navigate", "s-1", { "tab": 1, "action": "reload" }),
    not_ready,
  )
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

///|
async test "a conversation cannot navigate a tab that is not its own" {
  let views = BrowserViews()
  views.owners[1] = "s-other"
  for tab in [1, 7] {
    guard refusal(views, "browser_navigate", "s-1", {
        "tab": Json(tab),
        "url": "https://example.com/",
      })
      is Some(message) else {
      fail("navigating tab \{tab} was not refused")
    }
    assert_true(message.contains("has no browser tab \{tab}"))
  }
}

///|
async test "browser_open and browser_navigate refuse what they cannot load or cannot read" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  let refused = (tool : String, arguments : Json, expected : String) => {
    guard refusal(views, tool, "s-1", arguments) is Some(message) else {
      fail("\{tool} \{arguments.stringify()} was not refused")
    }
    assert_true(message.contains(expected))
  }
  refused("browser_open", {}, "needs `url`")
  refused("browser_open", { "url": "javascript:alert(1)" }, "Only http://")
  refused("browser_navigate", { "url": "https://example.com/" }, "needs `tab`")
  refused(
    "browser_navigate",
    { "tab": 1.5, "url": "https://example.com/" },
    "needs `tab`",
  )
  refused("browser_navigate", { "tab": 1 }, "exactly one of")
  refused(
    "browser_navigate",
    { "tab": 1, "url": "https://example.com/", "action": "reload" },
    "exactly one of",
  )
  refused("browser_navigate", { "tab": 1, "action": "home" }, "not home")
  refused(
    "browser_navigate",
    { "tab": 1, "url": "about:blank" },
    "Only http://",
  )
}

///|
test "a navigation call names its tab and one destination" {
  assert_true(
    navigation({ "tab": 3, "url": "https://example.com/" })
    is (3, To("https://example.com/")),
  )
  assert_true(navigation({ "tab": 3, "action": "back" }) is (3, Back))
  assert_true(navigation({ "tab": 3, "action": "forward" }) is (3, Forward))
  assert_true(navigation({ "tab": 3, "action": "reload" }) is (3, Reload))
}

///|
test "a tool waits for the load it started, and not for one that never starts" {
  let before : LoadCount = { started: 2, finished: 2, }
  // Nothing has started: wait out the grace, then take it that nothing will.
  assert_false(settled(before, before, 0))
  assert_false(settled(before, before, StartGraceMs - SettlePollMs))
  assert_true(settled(before, before, StartGraceMs))
  // A load started: wait for it to finish, however long past the grace,
  // until patience runs out.
  let loading : LoadCount = { started: 3, finished: 2, }
  assert_false(settled(before, loading, 0))
  assert_false(settled(before, loading, StartGraceMs * 3))
  assert_true(settled(before, loading, SettleTimeoutMs))
  assert_true(settled(before, { started: 3, finished: 3, }, 0))
  // A load that was already under way when the tool asked does not count
  // as the tool's until a new one has started.
  let busy : LoadCount = { started: 3, finished: 2, }
  assert_false(settled(busy, { started: 3, finished: 3, }, 0))
  assert_true(settled(busy, { started: 4, finished: 4, }, 0))
}

///|
test "a view's loads are counted from its loading events alone" {
  let views : BrowserViews = {
    window: None,
    debug_port: 0,
    pick: None,
    owners: Map([]),
    notify: None,
    opening: Map([]),
    loads: Map([]),
  }
  assert_true(views.load_count(1) == { started: 0, finished: 0, })
  views.view_event(1, LoadingChanged(is_loading=true))
  views.view_event(1, TitleUpdated(title="Example"))
  assert_true(views.load_count(1) == { started: 1, finished: 0, })
  views.view_event(1, LoadingChanged(is_loading=false))
  assert_true(views.load_count(1) == { started: 1, finished: 1, })
  assert_true(views.load_count(2) == { started: 0, finished: 0, })
}

///|
async test "the page's open delivers its tab's id to the tool that asked for it" {
  let views = BrowserViews()
  let opened : @async.Queue[Int32] = Queue(kind=Unbounded)
  views.opening["r-1"] = opened
  let payload : @protocol.BrowserOpenPayload = {
    id: 5,
    url: "https://example.com/",
    dark: false,
    session: Some("s-1"),
    request: None,
  }
  // An open nobody asked for, and one answering a request nobody is waiting
  // on any more, deliver nothing.
  views.answer_open(payload)
  views.answer_open({ ..payload, id: 6, request: Some("r-gone"), })
  views.answer_open({ ..payload, id: 7, request: Some("r-1"), })
  assert_eq(opened.get(), 7)
}
