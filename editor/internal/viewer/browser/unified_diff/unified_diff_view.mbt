///|
/// Browser-owned DOM for one unified diff. The public facade owns the input
/// contract; this value owns only the subtree installed into its dedicated
/// host element.
struct UnifiedDiffBrowserView {
  host : @rdom.Element
  on_comment : ((@unified_diff_model.UnifiedDiffLineComment) -> Unit)?
  mut root : @rdom.Element?
  mut disposed : Bool
}

///|
/// Creates an empty renderer. The caller must reserve `host` for this view and
/// must not render its own children into it.
pub fn UnifiedDiffBrowserView::UnifiedDiffBrowserView(
  host : @rdom.Element,
  on_comment? : (@unified_diff_model.UnifiedDiffLineComment) -> Unit,
) -> UnifiedDiffBrowserView {
  { host, on_comment, root: None, disposed: false }
}

///|
/// Replaces the installed diff atomically so callers never expose a mixture
/// of rows from two document generations.
pub fn UnifiedDiffBrowserView::set_hunks(
  self : UnifiedDiffBrowserView,
  hunks : Array[@unified_diff_model.UnifiedDiffHunk],
) -> Unit {
  self.install(() => render_unified_diff(hunks, self.on_comment))
}

///|
/// Replaces the current comparison with a renderer-owned status message.
pub fn UnifiedDiffBrowserView::set_message(
  self : UnifiedDiffBrowserView,
  message : String,
) -> Unit {
  self.install(() => render_message(message))
}

///|
/// Swaps the installed subtree for a freshly rendered one. The replacement is
/// built before the previous root is detached so the host never holds rows from
/// two document generations at once.
fn UnifiedDiffBrowserView::install(
  self : UnifiedDiffBrowserView,
  render : () -> @rdom.Element,
) -> Unit {
  if self.disposed {
    return
  }
  let next = render()
  self.detach_root()
  self.host.append_child(next.as_node())
  self.root = Some(next)
}

///|
/// Removes rendered rows while retaining the reusable host binding.
pub fn UnifiedDiffBrowserView::clear(self : UnifiedDiffBrowserView) -> Unit {
  if self.disposed {
    return
  }
  self.detach_root()
}

///|
fn UnifiedDiffBrowserView::detach_root(self : UnifiedDiffBrowserView) -> Unit {
  if self.root is Some(root) {
    self.host.remove_child(root.as_node())
    self.root = None
  }
}

///|
/// Releases the renderer-owned subtree. Disposal is idempotent and leaves the
/// caller's host element in place.
pub fn UnifiedDiffBrowserView::dispose(self : UnifiedDiffBrowserView) -> Unit {
  if self.disposed {
    return
  }
  self.clear()
  self.disposed = true
}

///|
fn render_unified_diff(
  hunks : Array[@unified_diff_model.UnifiedDiffHunk],
  on_comment : ((@unified_diff_model.UnifiedDiffLineComment) -> Unit)?,
) -> @rdom.Element {
  if hunks.is_empty() {
    return render_message("No textual changes.")
  }
  let document = @rdom.document()
  let root = diff_root(document)
  for hunk_index, hunk in hunks {
    let section = document.create_element("section")
    section.set_attribute("class", "moonbit-unified-diff-hunk")
    section.set_attribute("data-hunk-index", hunk_index.to_string())
    let header = text_element(
      document,
      "div",
      "moonbit-unified-diff-hunk-header",
      hunk_header(hunk),
    )
    header.set_attribute("role", "heading")
    header.set_attribute("aria-level", "2")
    section.append_child(header.as_node())
    for line in hunk.lines {
      section.append_child(render_line(document, line, on_comment).as_node())
    }
    root.append_child(section.as_node())
  }
  root
}

///|
fn render_message(message : String) -> @rdom.Element {
  let document = @rdom.document()
  let root = diff_root(document)
  root.append_child(
    text_element(document, "div", "moonbit-unified-diff-empty", message).as_node(),
  )
  root
}

///|
fn diff_root(document : @rdom.Document) -> @rdom.Element {
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-unified-diff")
  root.set_attribute("role", "region")
  root.set_attribute("aria-label", "Unified diff")
  root.set_attribute("tabindex", "0")
  root
}

///|
fn render_line(
  document : @rdom.Document,
  line : @unified_diff_model.UnifiedDiffLine,
  on_comment : ((@unified_diff_model.UnifiedDiffLineComment) -> Unit)?,
) -> @rdom.Element {
  let (kind, marker) = match line.kind {
    Context => ("context", " ")
    Deletion => ("deletion", "-")
    Addition => ("addition", "+")
  }
  let row = document.create_element("div")
  let row_class = "moonbit-unified-diff-line moonbit-unified-diff-line-\{kind}"
  row.set_attribute("class", row_class)
  row.set_attribute("data-line-kind", kind)
  row.set_attribute("role", "group")
  row.set_attribute("aria-label", accessible_line_label(line))
  if line.original_line_number is Some(number) {
    row.set_attribute("data-original-line", number.to_string())
  }
  if line.modified_line_number is Some(number) {
    row.set_attribute("data-modified-line", number.to_string())
  }
  let original_number = text_element(
    document,
    "span",
    "moonbit-unified-diff-line-number",
    line.original_line_number.map(number => number.to_string()).unwrap_or(""),
  )
  original_number.set_attribute("aria-hidden", "true")
  let modified_number = text_element(
    document,
    "span",
    "moonbit-unified-diff-line-number",
    line.modified_line_number.map(number => number.to_string()).unwrap_or(""),
  )
  modified_number.set_attribute("aria-hidden", "true")
  let marker_element = text_element(
    document, "span", "moonbit-unified-diff-line-marker", marker,
  )
  let group = match on_comment {
    Some(on_comment) => {
      row.set_attribute(
        "class",
        "\{row_class} moonbit-unified-diff-line-commentable",
      )
      let group = document.create_element("div")
      group.set_attribute("class", "moonbit-unified-diff-line-group")
      let action = document.create_element("button")
      action.set_attribute("type", "button")
      action.set_attribute("class", "moonbit-unified-diff-comment-action")
      action.set_attribute("title", comment_action_label(line))
      action.set_attribute("aria-label", comment_action_label(line))
      action.append_child(document.create_text_node("+").as_node())
      action.add_event_listener("click", event => {
        event.prevent_default()
        event.stop_propagation()
        show_line_comment_editor(document, group, action, line, on_comment)
      })
      row.append_child(action.as_node())
      Some(group)
    }
    None => None
  }
  row.append_child(original_number.as_node())
  row.append_child(modified_number.as_node())
  row.append_child(marker_element.as_node())
  row.append_child(
    text_element(document, "code", "moonbit-unified-diff-line-text", line.text).as_node(),
  )
  match group {
    Some(group) => {
      group.append_child(row.as_node())
      group
    }
    None => row
  }
}

///|
/// Lazily installs one inline editor per line. Large diffs pay for only the
/// compact comment button until the reviewer explicitly opens a draft.
fn show_line_comment_editor(
  document : @rdom.Document,
  group : @rdom.Element,
  action : @rdom.Element,
  line : @unified_diff_model.UnifiedDiffLine,
  on_comment : (@unified_diff_model.UnifiedDiffLineComment) -> Unit,
) -> Unit {
  if group.query_selector(".moonbit-unified-diff-comment-form") is Some(form) {
    if form.query_selector("textarea") is Some(textarea) {
      unified_diff_focus(textarea)
    }
    return
  }
  let form = document.create_element("div")
  form.set_attribute("class", "moonbit-unified-diff-comment-form")
  form.set_attribute("role", "group")
  form.set_attribute("aria-label", comment_action_label(line))
  let textarea = document.create_element("textarea")
  textarea.set_attribute("rows", "2")
  textarea.set_attribute("placeholder", "Add review comment")
  textarea.set_attribute("aria-label", "Review comment")
  let actions = document.create_element("div")
  actions.set_attribute("class", "moonbit-unified-diff-comment-actions")
  let cancel = document.create_element("button")
  cancel.set_attribute("type", "button")
  cancel.set_attribute("class", "moonbit-unified-diff-comment-cancel")
  cancel.append_child(document.create_text_node("Cancel").as_node())
  let submit = document.create_element("button")
  submit.set_attribute("type", "button")
  submit.set_attribute("class", "moonbit-unified-diff-comment-submit")
  submit.set_attribute("disabled", "true")
  submit.append_child(document.create_text_node("Add comment").as_node())
  let dismiss = () => {
    if group.query_selector(".moonbit-unified-diff-comment-form")
      is Some(active) {
      group.remove_child(active.as_node())
    }
    unified_diff_focus(action)
  }
  let commit = () => {
    let comment = unified_diff_textarea_value(textarea).trim().to_owned()
    if comment.is_empty() {
      return
    }
    dismiss()
    on_comment({ line, comment })
  }
  cancel.add_event_listener("click", event => {
    event.prevent_default()
    dismiss()
  })
  submit.add_event_listener("click", event => {
    event.prevent_default()
    commit()
  })
  textarea.add_event_listener("input", _ => {
    if unified_diff_textarea_value(textarea).trim().is_empty() {
      submit.set_attribute("disabled", "true")
    } else {
      submit.remove_attribute("disabled")
    }
  })
  textarea.add_event_listener("keydown", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    match keyboard.key() {
      "Escape" => {
        event.prevent_default()
        dismiss()
      }
      "Enter" if keyboard.ctrl_key() || keyboard.meta_key() => {
        event.prevent_default()
        commit()
      }
      _ => ()
    }
  })
  actions.append_child(cancel.as_node())
  actions.append_child(submit.as_node())
  form.append_child(textarea.as_node())
  form.append_child(actions.as_node())
  group.append_child(form.as_node())
  unified_diff_focus(textarea)
}

///|
fn comment_action_label(line : @unified_diff_model.UnifiedDiffLine) -> String {
  match (line.kind, line.original_line_number, line.modified_line_number) {
    (Deletion, Some(number), _) => "Comment on original line \{number}"
    (Addition | Context, _, Some(number)) =>
      "Comment on modified line \{number}"
    _ => "Comment on diff line"
  }
}

///|
/// The visual number columns stay hidden from assistive technology so they are
/// not announced as detached digits. One row label exposes the semantic change
/// kind, its applicable line numbers, and the source text in reading order.
fn accessible_line_label(line : @unified_diff_model.UnifiedDiffLine) -> String {
  let kind = match line.kind {
    Context => "Unchanged"
    Deletion => "Deletion"
    Addition => "Addition"
  }
  let original = line.original_line_number
    .map(number => ", original line \{number}")
    .unwrap_or("")
  let modified = line.modified_line_number
    .map(number => ", modified line \{number}")
    .unwrap_or("")
  "\{kind}\{original}\{modified}: \{line.text}"
}

///|
fn text_element(
  document : @rdom.Document,
  tag : String,
  class_name : String,
  text : String,
) -> @rdom.Element {
  let element = document.create_element(tag)
  element.set_attribute("class", class_name)
  element.append_child(document.create_text_node(text).as_node())
  element
}

///|
fn hunk_header(hunk : @unified_diff_model.UnifiedDiffHunk) -> String {
  "@@ -\{hunk.original_start_line_number},\{hunk.original_line_count} +\{hunk.modified_start_line_number},\{hunk.modified_line_count} @@"
}

///|
extern "js" fn unified_diff_textarea_value(element : @rdom.Element) -> String = "(element) => element.value ?? ''"

///|
extern "js" fn unified_diff_focus(element : @rdom.Element) -> Unit = "(element) => element.focus({ preventScroll: true })"
