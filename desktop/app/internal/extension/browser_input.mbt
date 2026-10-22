// `browser_click` and `browser_type`: an agent acting on an element of a
// tab's page the way a person would, through the browser's own mouse and
// keyboard input rather than by calling the page's scripts. The element is
// a `ref` from `browser_snapshot`, the browser's id for its DOM node.
//
// Either tool answers with a fresh snapshot once the page has settled, so
// the agent sees what its input did — including the page a click led to.

///|
/// How long a page that has not begun to change after an input is given to
/// begin before the tool answers with it as it is.
const InputQuietMs : Int32 = 500

///|
/// A box smaller than this, in square CSS pixels, is no place to click.
const MinClickArea : Double = 1.0

///|
/// The element a call names by `ref`, as a handle scripts can be called on.
/// A ref outlives nothing: the browser forgets its nodes with the document
/// that held them.
async fn element(
  connection : @cdp.Connection,
  id : Int32,
  node : @cdp.BackendNodeId,
  document~ : Double,
) -> @cdp.RemoteObjectId {
  let gone = @mcp.ToolError(
    "Tab \{id} has no element \{node.0}. A ref lasts only as long as the page that gave it; take a new browser_snapshot.",
  )
  let object = connection.resolve_node(node) catch {
    @cdp.CommandFailed(..) => raise gone
    error => raise error
  }
  // The handle needs no releasing: it goes with the connection, which is
  // the tool's alone and closes when the tool is done.
  guard object.object_id is Some(object_id) else { raise gone }
  // The tab was showing the ref's `document` a moment ago, but a navigation
  // can commit before the ref is resolved, and the node found is then
  // another renderer's, numbered afresh. It must be in that document still.
  let origin : Double = connection
    .call_function_on({ object_id, declaration: element_origin_script, })
    .decode_value()
  guard origin == document else { raise gone }
  object_id
}

///|
/// A script that says which document the element it is called on is in,
/// by that document's time origin.
let element_origin_script : String = "function () { return performance.timeOrigin; }"

///|
/// What a script called on an element says of it: `None` for nothing to
/// say, or the text of a refusal.
priv struct Verdict(String?)

///|
impl @json.FromJson for Verdict with fn from_json(json, path) {
  match json {
    Null => Verdict(None)
    String(text) => Verdict(Some(text))
    _ => raise JsonDecodeError((path, "expected the text of a refusal or null"))
  }
}

///|
async fn verdict(
  connection : @cdp.Connection,
  object_id : @cdp.RemoteObjectId,
  declaration : String,
) -> String? {
  let verdict : Verdict = connection
    .call_function_on({ object_id, declaration, })
    .decode_value()
  verdict.0
}

///|
/// The area a quad encloses, whichever way round its corners go.
fn quad_area(quad : Array[@cdp.Point]) -> Double {
  let mut twice = 0.0
  for i, point in quad {
    let next = quad[(i + 1) % quad.length()]
    twice += point.x * next.y - next.x * point.y
  }
  twice.abs() / 2.0
}

///|
/// One edge of the viewport, as the half-plane on its inner side: where `x`
/// or `y` is at least (`Min`) or at most (`Max`) a bound.
priv enum ViewportEdge {
  MinX(Double)
  MaxX(Double)
  MinY(Double)
  MaxY(Double)
}

///|
fn ViewportEdge::keeps(self : ViewportEdge, point : @cdp.Point) -> Bool {
  match self {
    MinX(bound) => point.x >= bound
    MaxX(bound) => point.x <= bound
    MinY(bound) => point.y >= bound
    MaxY(bound) => point.y <= bound
  }
}

///|
/// Where the segment from `from` to `to`, which the edge keeps one end of,
/// crosses it.
fn ViewportEdge::crossing(
  self : ViewportEdge,
  from : @cdp.Point,
  to : @cdp.Point,
) -> @cdp.Point {
  match self {
    MinX(bound) | MaxX(bound) => {
      let t = (bound - from.x) / (to.x - from.x)
      { x: bound, y: from.y + t * (to.y - from.y), }
    }
    MinY(bound) | MaxY(bound) => {
      let t = (bound - from.y) / (to.y - from.y)
      { x: from.x + t * (to.x - from.x), y: bound, }
    }
  }
}

///|
/// The part of `polygon` the edge keeps, walking its sides in turn.
fn ViewportEdge::clip(
  self : ViewportEdge,
  polygon : Array[@cdp.Point],
) -> Array[@cdp.Point] {
  let kept = []
  for i, current in polygon {
    let previous = polygon[(i + polygon.length() - 1) % polygon.length()]
    match (self.keeps(previous), self.keeps(current)) {
      (true, true) => kept.push(current)
      (true, false) => kept.push(self.crossing(previous, current))
      (false, true) => {
        kept.push(self.crossing(previous, current))
        kept.push(current)
      }
      (false, false) => ()
    }
  }
  kept
}

///|
/// The part of `quad` on screen in a viewport `width` by `height`. A box is
/// convex however the page transforms it, and so is what the viewport
/// leaves of it.
fn clip_to_viewport(
  quad : Array[@cdp.Point],
  width : Double,
  height : Double,
) -> Array[@cdp.Point] {
  let mut shown = quad
  for edge in [MinX(0), MaxX(width), MinY(0), MaxY(height)] {
    shown = edge.clip(shown)
  }
  shown
}

///|
/// Where a person would click an element whose content occupies `quads`
/// in a viewport `width` by `height`: the middle of the part on screen of
/// its first box that shows any — the average of its corners, which lies
/// inside it as it is convex. `None` for an element that shows nowhere.
fn click_point(
  quads : Array[Array[@cdp.Point]],
  width : Double,
  height : Double,
) -> @cdp.Point? {
  for quad in quads {
    let shown = clip_to_viewport(quad, width, height)
    if shown.length() > 0 && quad_area(shown) >= MinClickArea {
      let mut x = 0.0
      let mut y = 0.0
      for point in shown {
        x += point.x
        y += point.y
      }
      let corners = shown.length().to_double()
      return Some({ x: x / corners, y: y / corners, })
    }
  }
  None
}

///|
/// A script that says what, if anything other than the element it is
/// called on, would take a click at `point`, a point in the viewport: the
/// element itself or one inside it takes the click, while one laid over it
/// — a dialog, a cookie banner — would take it instead.
///
/// The point is asked of the element's own root, its document or the shadow
/// root it is in, open or closed. The browser answers as mouse events see
/// the page: through the slots content is shown in, past elements that let
/// clicks through, and with what it finds in a shadow tree the element
/// cannot see into named by that tree's host. Walking up from what it finds
/// goes the same way, into the slot a node is shown in: a slot of a closed
/// root is not the node's to name, so the slots of the element's own root
/// are asked which nodes they show.
fn covering_script(point : @cdp.Point) -> String {
  (
    $|function () {
    $|  const root = this.getRootNode();
    $|  const slots = root instanceof ShadowRoot ? [...root.querySelectorAll("slot")] : [];
    $|  const slotOf = node => node.assignedSlot ||
    $|    slots.find(slot => slot.assignedNodes({ flatten: true }).includes(node));
    $|  const hit = root.elementFromPoint(\{point.x}, \{point.y});
    $|  for (let node = hit; node; node = slotOf(node) || node.parentNode || node.host) {
    $|    if (node === this) return null;
    $|  }
    $|  if (!hit) return "nothing at all";
    $|  return hit.localName + (hit.id ? "#" + hit.id : "");
    $|}
  )
}

///|
/// A script that readies the element it is called on to be typed into:
/// focus it and select all it holds, so that what is typed replaces it.
/// Answers with why it cannot when the element is no text field, or when
/// the keyboard's focus did not go to it — keys sent then would reach
/// whatever had the focus before.
let focus_script : String =
  #|function () {
  #|  // Only these hold text that selecting and typing over replaces; a date
  #|  // or time is typed segment by segment, and is not one of them.
  #|  const field = this instanceof HTMLTextAreaElement ||
  #|    (this instanceof HTMLInputElement &&
  #|      ["email", "number", "password", "search", "tel", "text", "url"]
  #|        .includes(this.type));
  #|  if (!field && !this.isContentEditable) return "is not a text field";
  #|  // A disabled fieldset disables its fields without setting `disabled`.
  #|  if (this.matches(":disabled")) return "is disabled";
  #|  if (this.readOnly) return "is read-only";
  #|  // Text inside an editable region is edited through the element that
  #|  // makes it editable, the outermost editable one around it, and that is
  #|  // what takes the focus.
  #|  let host = this;
  #|  while (!field && host.parentElement && host.parentElement.isContentEditable)
  #|    host = host.parentElement;
  #|  host.focus();
  #|  if (host.getRootNode().activeElement !== host)
  #|    return "cannot take the keyboard's focus";
  #|  if (field) {
  #|    this.select();
  #|  } else {
  #|    const range = document.createRange();
  #|    range.selectNodeContents(this);
  #|    const selection = getSelection();
  #|    selection.removeAllRanges();
  #|    selection.addRange(range);
  #|  }
  #|  return null;
  #|}

///|
async fn press(connection : @cdp.Connection, key : @cdp.Key) -> Unit {
  connection.dispatch_key_event({ action: Down, key, })
  connection.dispatch_key_event({ action: Up, key, })
}

///|
/// Wait for a page that showed `before` when it was given input to settle:
/// when it has gone to another document or history entry, until that has
/// loaded; when it has not begun to change within `InputQuietMs`, no
/// longer. Either way, not while its view is `loading` another page: a
/// handler may step the page's history and then go to another, and the
/// entry it stepped to is not where it is going. Whether it settled before
/// patience ran out, after which the page is left as it stands.
async fn settle_after_input(
  connection : @cdp.Connection,
  before : Document?,
  loading : () -> Bool,
) -> Bool {
  for waited = 0; waited < SettleTimeoutMs; waited = waited + SettlePollMs {
    @async.sleep(SettlePollMs)
    // Between two documents there is nothing to ask; keep waiting.
    guard document(connection) is Some(now) && !loading() else { continue }
    if settled(Change, before, now) {
      return true
    }
    let unchanged = before is Some(before) &&
      now.origin == before.origin &&
      now.entry == before.entry
    if unchanged && waited + SettlePollMs >= InputQuietMs {
      return true
    }
  }
  false
}

///|
/// Refuse to act on tab `id` by refs unless the document it `shows` is the
/// one that `gave` them, by its time origin: the document its latest
/// snapshot read when the call came in. That time origin when it is.
fn refuse_stale_refs(
  id : Int32,
  gave : Double?,
  shows : Document?,
) -> Double raise @mcp.ToolError {
  guard shows is Some(shown) && gave == Some(shown.origin) else {
    raise ToolError(
      "Tab \{id} no longer shows the page its latest browser_snapshot read, and that snapshot's refs may now name other elements; take a new browser_snapshot.",
    )
  }
  shown.origin
}

///|
/// Give tab `id`'s page input with `act`, then answer with its snapshot
/// once it has settled. Takes the tab's turn, like a navigation: input
/// that leads to another page is one.
async fn BrowserViews::give_input(
  self : BrowserViews,
  session : String,
  id : Int32,
  act : async (@cdp.Connection, Double) -> Unit,
) -> String {
  ignore(self.tab_view(session, id))
  // A pick in progress would take the click for the element it is picking.
  if self.pick is Some(pick) && pick.id == id {
    self.cancel_pick()
  }
  // Which document the call's refs belong to is settled as it comes in: a
  // call ahead of it in the tab's turn may lead the tab elsewhere, and its
  // answer is a snapshot of that other document.
  let gave = self.snapshotted.get(id)
  let turn = self.tab_turn(id)
  turn.acquire()
  defer turn.release()
  self.with_page(id, connection => {
    let before = document(connection)
    act(connection, refuse_stale_refs(id, gave, before))
    let settled = settle_after_input(connection, before, () => {
      self.loading.contains(id)
    })
    // A page that has not settled may still show the document it is
    // leaving, loaded in full; it is the page that is still loading.
    self.snapshot(connection, id, pending=!settled)
  })
}

///|
/// The tab and element a `tool` call names.
fn element_arguments(
  arguments : Json,
  tool : String,
) -> (Int32, @cdp.BackendNodeId) raise @mcp.ToolError {
  let id = integer_argument(
    arguments,
    "tab",
    "\{tool} needs `tab`, the id of the tab the element is in.",
  )
  let node = integer_argument(
    arguments,
    "ref",
    "\{tool} needs `ref`, the element's ref from browser_snapshot.",
  )
  (id, BackendNodeId(node))
}

///|
/// Click element `node` of tab `id`, a node of `document`, in its middle,
/// once it is in view and nothing covers it there.
async fn click_element(
  connection : @cdp.Connection,
  id : Int32,
  node : @cdp.BackendNodeId,
  document~ : Double,
) -> Unit {
  let object_id = element(connection, id, node, document~)
  connection.scroll_into_view(node)
  let (width, height) = connection.viewport_size()
  guard click_point(connection.content_quads(node), width, height) is Some(at) else {
    raise @mcp.ToolError(
      "Element \{node.0} shows nowhere on the page, so there is nowhere to click it.",
    )
  }
  // The pointer arrives first: what it opens by hovering, a menu laid over
  // the element, is there by the time the click would land.
  connection.dispatch_mouse_event({ action: Move, at, })
  if verdict(connection, object_id, covering_script(at)) is Some(cover) {
    raise @mcp.ToolError(
      "Element \{node.0} is covered by \{cover} where it would be clicked; deal with what covers it first.",
    )
  }
  for action in [@cdp.MouseAction::Press, Release] {
    connection.dispatch_mouse_event({ action, at, })
  }
}

///|
/// Make text field `node` of tab `id`, a node of `document`, hold `text`,
/// and press Enter after when `submit`.
async fn type_into(
  connection : @cdp.Connection,
  id : Int32,
  node : @cdp.BackendNodeId,
  document~ : Double,
  text~ : String,
  submit~ : Bool,
) -> Unit {
  let object_id = element(connection, id, node, document~)
  if verdict(connection, object_id, focus_script) is Some(reason) {
    raise @mcp.ToolError("Element \{node.0} \{reason}.")
  }
  // Typed text replaces the selection; nothing typed leaves it standing,
  // and it is deleted instead.
  if text == "" {
    press(connection, Backspace)
  } else {
    connection.insert_text(text)
  }
  if submit {
    press(connection, Enter)
  }
}

///|
/// `browser_click`: click an element of one of `session`'s tabs.
async fn BrowserViews::click(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> String {
  let (id, node) = element_arguments(arguments, "browser_click")
  self.give_input(session, id, (connection, document) => {
    click_element(connection, id, node, document~)
  })
}

///|
/// `browser_type`: replace what a text field of one of `session`'s tabs
/// holds, and press Enter after when asked to submit.
async fn BrowserViews::type_text(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> String {
  let (id, node) = element_arguments(arguments, "browser_type")
  guard optional_text(arguments, "text") is Some(text) else {
    raise @mcp.ToolError("browser_type needs `text`, what to type.")
  }
  let submit = match arguments {
    { "submit": True, .. } => true
    { "submit": False, .. } => false
    { "submit": _, .. } => raise @mcp.ToolError("`submit` must be a boolean.")
    _ => false
  }
  self.give_input(session, id, (connection, document) => {
    type_into(connection, id, node, document~, text~, submit~)
  })
}
