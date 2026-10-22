// `browser_snapshot`: what a tab's page holds, as an agent reads it. The
// page's accessibility tree is the browser's own account of what a person
// can perceive and act on, so it says what the page means without the
// markup that lays it out. Each line is one node, indented under its
// parent; an element a person can act on carries a `ref`, the browser's id
// for its DOM node, which stays the element's for as long as the document
// does.

///|
/// Roles whose elements a person acts on, whether or not the page made them
/// focusable.
let actionable_roles : Set[String] = Set([
  "button", "checkbox", "combobox", "link", "listbox", "menuitem", "menuitemcheckbox",
  "menuitemradio", "option", "radio", "searchbox", "slider", "spinbutton", "switch",
  "tab", "textbox", "treeitem",
])

///|
/// Roles that say nothing of their own: without a name, a node of one of
/// these stands only for the nodes inside it.
let wrapper_roles : Set[String] = Set(["generic", "none", "presentation"])

///|
/// The states and attributes a line shows, in the order it shows them. A
/// state that is off is shown only where off is itself worth knowing.
let shown_properties : Array[(String, Bool)] = [
  ("level", false),
  ("checked", true),
  ("pressed", true),
  ("expanded", true),
  ("selected", false),
  ("disabled", false),
  ("required", false),
  ("readonly", false),
  ("focused", false),
  ("url", false),
]

///|
/// One property as a line shows it, or `None` when it is not worth showing.
fn property_label(name : String, value : Json, show_off : Bool) -> String? {
  match value {
    True | String("true") => Some(name)
    False | String("false") =>
      if show_off {
        Some("\{name}=false")
      } else {
        None
      }
    String(text) => Some("\{name}=\{text}")
    other => Some("\{name}=\{other.stringify()}")
  }
}

///|
/// The ref an element is acted on by, when a person can act on it.
fn snapshot_ref(node : @cdp.AxNode, role : String) -> @cdp.BackendNodeId? {
  guard node.dom_node is Some(dom_node) else { return None }
  let focusable = node.properties.get("focusable") is Some(True)
  if focusable || actionable_roles.contains(role) {
    Some(dom_node)
  } else {
    None
  }
}

///|
/// The line a node shows as, without its indentation.
fn snapshot_line(node : @cdp.AxNode, role : String) -> String {
  let line = StringBuilder()
  line.write_string("- ")
  line.write_string(role)
  if node.name is Some(name) && name != "" {
    line.write_string(" ")
    line.write_string(Json(name).stringify())
  }
  for property in shown_properties {
    let (name, show_off) = property
    if node.properties.get(name) is Some(value) &&
      property_label(name, value, show_off) is Some(label) {
      line.write_string(" [\{label}]")
    }
  }
  if snapshot_ref(node, role) is Some(ref_) {
    line.write_string(" [ref=\{ref_.0}]")
  }
  match node.value {
    None | Some(String("")) => ()
    Some(String(text)) => line.write_string(": \{Json(text).stringify()}")
    Some(other) => line.write_string(": \{other.stringify()}")
  }
  line.to_string()
}

///|
/// The tree as indented lines. A node the browser ignores, the document
/// itself, and an unnamed wrapper show nothing of their own and lift their
/// children into their place; the boxes the browser divides a line of text
/// into are left out, as is text that only repeats the name of the node it
/// sits in.
fn render_tree(nodes : Array[@cdp.AxNode]) -> String {
  let by_id : Map[@cdp.AxNodeId, @cdp.AxNode] = Map([])
  let parented : Set[@cdp.AxNodeId] = Set([])
  for node in nodes {
    by_id[node.id] = node
    for child in node.children {
      parented.add(child)
    }
  }
  let out = StringBuilder()
  fn visit(id : @cdp.AxNodeId, depth : Int32, context : String?) -> Unit {
    guard by_id.get(id) is Some(node) else { return }
    let lift = () => {
      for child in node.children {
        visit(child, depth, context)
      }
    }
    guard !node.ignored && node.role is Some(role) else { return lift() }
    match role {
      "RootWebArea" => lift()
      "InlineTextBox" => ()
      "StaticText" =>
        if node.name is Some(text) && text.trim() != "" && node.name != context {
          out.write_string("  ".repeat(depth))
          out.write_string("- text \{Json(text).stringify()}\n")
        }
      _ => {
        let named = node.name is Some(name) && name != ""
        if !named &&
          wrapper_roles.contains(role) &&
          snapshot_ref(node, role) is None {
          return lift()
        }
        out.write_string("  ".repeat(depth))
        out.write_string(snapshot_line(node, role))
        out.write_string("\n")
        for child in node.children {
          visit(child, depth + 1, node.name)
        }
      }
    }
  }
  for node in nodes {
    if !parented.contains(node.id) {
      visit(node.id, 0, None)
    }
  }
  out.to_string()
}

///|
/// What `browser_snapshot` answers: the page's address, title, and whether
/// it is still loading — its document, or a navigation away from it that
/// is `pending` — then its tree.
fn snapshot_text(
  document : Document,
  nodes : Array[@cdp.AxNode],
  pending~ : Bool = false,
) -> String {
  let header = StringBuilder()
  header.write_string("url: \{document.url}\n")
  header.write_string("title: \{Json(document.title).stringify()}\n")
  header.write_string("loading: \{!document.complete || pending}\n\n")
  header.to_string() + render_tree(nodes)
}

///|
/// How many times a snapshot is read before a page that keeps changing
/// documents under it is given up on.
const SnapshotAttempts : Int32 = 3

///|
/// What tab `id`'s page shows, as `browser_snapshot` answers it. The
/// document it reads is the one its refs belong to from here on.
async fn BrowserViews::snapshot(
  self : BrowserViews,
  connection : @cdp.Connection,
  id : Int32,
  pending~ : Bool = false,
) -> String {
  // The tree and the page's account of its document are asked one after
  // the other; a navigation between them would give refs of one document
  // under the name of another. Only a tree read within one document is
  // answered.
  for _ in 0..<SnapshotAttempts {
    guard document(connection) is Some(before) else {
      raise @mcp.ToolError("Tab \{id} has no page to read yet.")
    }
    let nodes = connection.accessibility_tree()
    if document(connection) is Some(after) && after.origin == before.origin {
      self.snapshotted[id] = after.origin
      return snapshot_text(after, nodes, pending~)
    }
  }
  raise @mcp.ToolError(
    "Tab \{id} kept going to other pages while it was read; try again once it has settled.",
  )
}

///|
/// `browser_snapshot`: what one of `session`'s tabs shows, as it stands.
async fn BrowserViews::snapshot_tab(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> String {
  let id = integer_argument(
    arguments, "tab", "browser_snapshot needs `tab`, the id of the tab to read.",
  )
  ignore(self.tab_view(session, id))
  self.with_page(id, connection => self.snapshot(connection, id))
}
