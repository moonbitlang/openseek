// The feedback speech-bubble widget, porting `AgentFeedbackEditorWidget`
// (`vscode/src/vs/sessions/contrib/agentFeedback/browser/
// agentFeedbackEditorWidgetContribution.ts:63-1027`): a right-edge overlay
// bubble for one group of nearby comments — collapsed to a one-line header
// (the comment text, or "N comments"), expandable body with per-item line
// info, type badge, hover action bar (reply/edit/remove), markdown text,
// replies, an inline reply composer whose drafts survive widget rebuilds
// (the shared draft map is owned by the contribution), an inline edit
// textarea, and the Accept/Delete button bar for `Created` items. The
// widget is a null-position overlay widget: the glue computes the
// right-edge/anchor-line position and writes `top`/`left`
// (`layout`/`layoutOverlayWidget` upstream). Dropped: suggestion-edit
// blocks (suggestions are not ported), the PR-review source arms,
// `getMinContentWidthInPx` (the viewer's overlay widgets don't feed the
// scroll width — recorded deviation), and the copy-focus/text-selection
// subtleties beyond the "don't navigate while selecting text" gate.

///|
/// The glue-facing seam: service mutations, navigation, range highlighting,
/// and relayout — everything the upstream widget reached `ICodeEditor` or
/// the services for. Identity-carrying callbacks pass the widget id so the
/// glue can find the instance in its list.
pub(all) struct AgentFeedbackEditorWidgetHost {
  /// Remove the comment (`_removeComment` → `removeFeedback`).
  on_remove : (@agent_feedback.SessionEditorComment) -> Unit
  /// Accept a `Created` comment (`_acceptFeedback`).
  on_accept : (@agent_feedback.SessionEditorComment) -> Unit
  /// Save an edited body (`_saveEdit` → `updateFeedback`).
  on_edit : (@agent_feedback.SessionEditorComment, String) -> Unit
  /// Append a reply (`_saveReply` → `addReply`).
  on_reply : (@agent_feedback.SessionEditorComment, String) -> Unit
  /// Item click: the glue anchors navigation on the comment and reveals its
  /// range (the widget already marked the item focused).
  on_click : (@agent_feedback.SessionEditorComment) -> Unit
  /// Item hover: highlight the comment's range in the editor
  /// (`_highlightRange`).
  on_hover : (@agent_feedback.SessionEditorComment) -> Unit
  /// Hover ended: clear the highlight.
  on_hover_end : () -> Unit
  /// The widget expanded; the glue collapses the file's other widgets.
  on_did_expand : (String) -> Unit
  /// The widget's height changed (toggle, composer, textarea growth); the
  /// glue re-runs its layout.
  on_layout : (String) -> Unit
}

///|
struct AgentFeedbackEditorWidget {
  host : AgentFeedbackEditorWidgetHost
  id : String
  comments : Array[@agent_feedback.SessionEditorComment]
  /// The contribution-owned reply drafts (comment id → draft text), shared
  /// across rebuilds (`IReplyDraftState.drafts`).
  drafts : Map[String, String]
  root : @rdom.Element
  header : @rdom.Element
  title : @rdom.Element
  toggle : @rdom.Element
  body : @rdom.Element
  item_nodes : Map[String, @rdom.Element]
  reply_textareas : Map[String, @rdom.Element]
  /// The shared Markdown renderer lifetime for each retained comment/reply
  /// target. Keys distinguish the comment body from each indexed reply.
  markdown_disposables : Map[String, @base_common.Disposable]
  mut expanded : Bool
  mut disposed : Bool
  mut start_line : Int
}

///|
/// Builds the bubble for one comment group. `focused_reply` restores focus
/// into a reply composer that had it before a rebuild
/// (`IReplyDraftState.focusedCommentId`).
pub fn AgentFeedbackEditorWidget::AgentFeedbackEditorWidget(
  host : AgentFeedbackEditorWidgetHost,
  id : String,
  comments : Array[@agent_feedback.SessionEditorComment],
  drafts : Map[String, String],
  focused_reply? : String,
) -> AgentFeedbackEditorWidget {
  let document = @rdom.document()
  let root = document.create_element("div")
  root.set_attribute("class", "agent-feedback-widget collapsed visible")
  root.set_attribute("tabindex", "-1")
  root.set_attribute("data-agent-feedback-widget", id)
  let header = document.create_element("div")
  header.set_attribute("class", "agent-feedback-widget-header")
  let icon = document.create_element("span")
  icon.set_attribute("class", "agent-feedback-widget-icon")
  icon.set_attribute("aria-hidden", "true")
  header.append_child(icon.as_node())
  let title = document.create_element("span")
  title.set_attribute("class", "agent-feedback-widget-title")
  header.append_child(title.as_node())
  let spacer = document.create_element("span")
  spacer.set_attribute("class", "agent-feedback-widget-spacer")
  header.append_child(spacer.as_node())
  let toggle = document.create_element("div")
  toggle.set_attribute("class", "agent-feedback-widget-toggle")
  header.append_child(toggle.as_node())
  root.append_child(header.as_node())
  let body = document.create_element("div")
  body.set_attribute("class", "agent-feedback-widget-body collapsed")
  root.append_child(body.as_node())
  let arrow = document.create_element("div")
  arrow.set_attribute("class", "agent-feedback-widget-arrow")
  root.append_child(arrow.as_node())
  let widget : AgentFeedbackEditorWidget = {
    host,
    id,
    comments,
    drafts,
    root,
    header,
    title,
    toggle,
    body,
    item_nodes: Map([]),
    reply_textareas: Map([]),
    markdown_disposables: Map([]),
    expanded: false,
    disposed: false,
    start_line: 1,
  }
  widget.update_title()
  widget.update_toggle()
  widget.hook_containment()
  widget.build_items(focused_reply?)
  widget
}

///|
pub fn AgentFeedbackEditorWidget::get_dom_node(
  self : AgentFeedbackEditorWidget,
) -> @rdom.Element {
  self.root
}

///|
pub fn AgentFeedbackEditorWidget::widget_id(
  self : AgentFeedbackEditorWidget,
) -> String {
  self.id
}

///|
/// The group's anchor line, stored by the glue's `layout`.
pub fn AgentFeedbackEditorWidget::anchor_line(
  self : AgentFeedbackEditorWidget,
) -> Int {
  self.start_line
}

///|
pub fn AgentFeedbackEditorWidget::set_anchor_line(
  self : AgentFeedbackEditorWidget,
  line : Int,
) -> Unit {
  self.start_line = line
}

///|
pub fn AgentFeedbackEditorWidget::mark_disposed(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.dispose_all_markdown_targets()
}

// --- header ----------------------------------------------------------------------

///|
/// `_updateTitle`: one comment shows its text, several show the count.
fn AgentFeedbackEditorWidget::update_title(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  if self.comments.length() == 1 {
    self.title.set_inner_html(@base_common.escape_html(self.comments[0].text))
  } else {
    self.title.set_inner_html("\{self.comments.length().to_string()} comments")
  }
}

///|
/// `_updateToggleButton`: chevron down (expand) / up (collapse).
fn AgentFeedbackEditorWidget::update_toggle(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  if self.expanded {
    self.toggle.set_attribute(
      "class", "agent-feedback-widget-toggle agent-feedback-widget-toggle-up",
    )
    self.toggle.set_attribute("title", "Collapse")
  } else {
    self.toggle.set_attribute(
      "class", "agent-feedback-widget-toggle agent-feedback-widget-toggle-down",
    )
    self.toggle.set_attribute("title", "Expand")
  }
}

///|
/// Header click toggles; widget interactions never reach the editor (the
/// comment widget's containment precedent).
fn AgentFeedbackEditorWidget::hook_containment(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  self.root.add_event_listener("mousedown", event => event.stop_propagation())
  self.root.add_event_listener("mouseup", event => event.stop_propagation())
  self.root.add_event_listener("contextmenu", event => event.stop_propagation())
  self.root.add_event_listener("keydown", event => event.stop_propagation())
  self.root.add_event_listener("click", event => event.stop_propagation())
  self.header.add_event_listener("click", event => {
    event.stop_propagation()
    if self.expanded {
      self.collapse()
    } else {
      self.expand()
    }
  })
}

// --- items -----------------------------------------------------------------------

///|
/// `_buildFeedbackItems`.
fn AgentFeedbackEditorWidget::build_items(
  self : AgentFeedbackEditorWidget,
  focused_reply? : String,
) -> Unit {
  self.dispose_all_markdown_targets()
  self.body.set_inner_html("")
  self.item_nodes.clear()
  self.reply_textareas.clear()
  for comment in self.comments {
    let item = self.build_item(comment)
    self.item_nodes.set(comment.id, item)
    self.body.append_child(item.as_node())
    // Restore an in-progress reply draft so rebuilds while typing don't
    // lose the composer.
    match self.drafts.get(comment.id) {
      Some(draft) => {
        let refocus = focused_reply is Some(reply) && reply == comment.id
        self.open_reply_composer(comment, item, draft, focus=refocus)
      }
      None => ()
    }
  }
}

///|
fn AgentFeedbackEditorWidget::build_item(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
) -> @rdom.Element {
  let document = @rdom.document()
  let item = document.create_element("div")
  item.set_attribute(
    "class", "agent-feedback-widget-item agent-feedback-widget-item-agentFeedback",
  )
  item.set_attribute("data-agent-feedback-item", comment.id)
  let item_header = document.create_element("div")
  item_header.set_attribute("class", "agent-feedback-widget-item-header")
  let meta = document.create_element("div")
  meta.set_attribute("class", "agent-feedback-widget-item-meta")
  let line_info = document.create_element("span")
  line_info.set_attribute("class", "agent-feedback-widget-line-info")
  let range = comment.range
  if range.start_line_number == range.end_line_number {
    line_info.set_inner_html("Line \{range.start_line_number.to_string()}")
  } else {
    line_info.set_inner_html(
      "Lines \{range.start_line_number.to_string()}-\{range.end_line_number.to_string()}",
    )
  }
  meta.append_child(line_info.as_node())
  // `_getTypeLabel`: agent-review comments carry a badge; user comments none.
  if comment.kind == AgentReview {
    let badge = document.create_element("span")
    badge.set_attribute("class", "agent-feedback-widget-item-type")
    badge.set_inner_html("Agent Review")
    meta.append_child(badge.as_node())
  }
  item_header.append_child(meta.as_node())
  // Hover action bar: reply, edit, and — unless the bottom button bar
  // already offers Remove — remove.
  let actions = document.create_element("div")
  actions.set_attribute("class", "agent-feedback-widget-item-actions")
  let text = document.create_element("div")
  text.set_attribute("class", "agent-feedback-widget-text")
  self.render_markdown_target(
    feedback_comment_target_key(comment.id),
    text,
    comment.text,
  )
  let reply_action = widget_icon_button(
    "reply",
    "Add to Comment",
    "agent-feedback-widget-action-reply",
    () => self.start_reply(comment),
  )
  actions.append_child(reply_action.as_node())
  let edit_action = widget_icon_button(
    "edit",
    "Edit",
    "agent-feedback-widget-action-edit",
    () => self.start_editing(comment, text),
  )
  actions.append_child(edit_action.as_node())
  let shows_button_bar = comment.state == Created
  if !shows_button_bar {
    let remove_action = widget_icon_button(
      "remove",
      "Remove",
      "agent-feedback-widget-action-remove",
      () => (self.host.on_remove)(comment),
    )
    actions.append_child(remove_action.as_node())
  }
  item_header.append_child(actions.as_node())
  item.append_child(item_header.as_node())
  item.append_child(text.as_node())
  if !comment.replies.is_empty() {
    item.append_child(self.build_replies(comment).as_node())
  }
  if shows_button_bar {
    item.append_child(self.build_action_buttons(comment).as_node())
  }
  // Hover drives the editor range highlight; click focuses/navigates unless
  // the press landed on an action, a composer, or a live text selection.
  item.add_event_listener("mouseenter", _ => (self.host.on_hover)(comment))
  item.add_event_listener("mouseleave", _ => (self.host.on_hover_end)())
  item.add_event_listener("click", event => {
    event.stop_propagation()
    if widget_event_in_class(event, "agent-feedback-widget-item-actions") ||
      widget_event_in_class(event, "agent-feedback-widget-add-reply") ||
      widget_event_in_class(event, "agent-feedback-widget-actions-bar") ||
      widget_event_in_class(event, "agent-feedback-widget-edit-textarea") {
      return
    }
    if widget_has_selection_inside(self.root) {
      return
    }
    self.focus_feedback(comment.id)
    (self.host.on_click)(comment)
  })
  item
}

///|
/// `_renderReplies`.
fn AgentFeedbackEditorWidget::build_replies(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
) -> @rdom.Element {
  ignore(self)
  let document = @rdom.document()
  let replies = document.create_element("div")
  replies.set_attribute("class", "agent-feedback-widget-replies")
  for reply_index, reply in comment.replies {
    let node = document.create_element("div")
    node.set_attribute("class", "agent-feedback-widget-reply")
    let text = document.create_element("div")
    text.set_attribute("class", "agent-feedback-widget-reply-text")
    self.render_markdown_target(
      feedback_reply_target_key(comment.id, reply_index),
      text,
      reply,
    )
    node.append_child(text.as_node())
    replies.append_child(node.as_node())
  }
  replies
}

///|
/// `_renderActionButtons`: the Accept / Delete bar under a `Created` item.
fn AgentFeedbackEditorWidget::build_action_buttons(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
) -> @rdom.Element {
  let document = @rdom.document()
  let bar = document.create_element("div")
  bar.set_attribute("class", "agent-feedback-widget-actions-bar")
  bar.add_event_listener("click", event => event.stop_propagation())
  let accept = document.create_element("button")
  accept.set_attribute("type", "button")
  accept.set_attribute("class", "agent-feedback-widget-button-accept")
  accept.set_attribute("title", "Share comment with agent")
  accept.set_inner_html("Accept")
  accept.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    (self.host.on_accept)(comment)
  })
  bar.append_child(accept.as_node())
  let delete = document.create_element("button")
  delete.set_attribute("type", "button")
  delete.set_attribute("class", "agent-feedback-widget-button-delete")
  delete.set_attribute("title", "Remove agent comment")
  delete.set_inner_html("Delete")
  delete.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    (self.host.on_remove)(comment)
  })
  bar.append_child(delete.as_node())
  bar
}

// --- edit / reply ----------------------------------------------------------------

///|
/// `_startEditing`: swap the rendered body for a textarea; Enter saves,
/// Escape restores.
fn AgentFeedbackEditorWidget::start_editing(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
  text_container : @rdom.Element,
) -> Unit {
  let document = @rdom.document()
  let target_key = feedback_comment_target_key(comment.id)
  self.dispose_markdown_target(target_key)
  text_container.set_inner_html("")
  text_container.set_attribute("class", "agent-feedback-widget-text editing")
  let textarea = document.create_element("textarea")
  textarea.set_attribute("class", "agent-feedback-widget-edit-textarea")
  textarea.set_attribute("rows", "1")
  input_set_textarea_value(textarea, comment.text)
  text_container.append_child(textarea.as_node())
  let auto_size = () => {
    let height = input_textarea_grown_height(textarea)
    @base_browser.set_style_property(
      textarea,
      "height",
      "\{height.to_string()}px",
    )
    (self.host.on_layout)(self.id)
  }
  auto_size()
  textarea.add_event_listener("input", _ => auto_size())
  let editing = Ref(true)
  let stop = () => {
    if !editing.val || self.disposed {
      return
    }
    editing.val = false
    text_container.set_attribute("class", "agent-feedback-widget-text")
    self.render_markdown_target(target_key, text_container, comment.text)
    (self.host.on_layout)(self.id)
  }
  textarea.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        match keyboard.key() {
          "Enter" =>
            if !keyboard.shift_key() {
              event.prevent_default()
              let new_text = input_textarea_value(textarea)
              if !is_blank(new_text) {
                (self.host.on_edit)(comment, new_text.trim().to_owned())
                // The change event rebuilds the widget.
              }
            }
          "Escape" => {
            event.prevent_default()
            stop()
          }
          _ => ()
        }
      None => ()
    }
    event.stop_propagation()
  })
  textarea.add_event_listener("blur", _ => if !self.disposed { stop() })
  @base_browser.focus_prevent_scroll(textarea)
}

///|
/// `_startAddingReply` for a user-triggered open (records the draft entry so
/// rebuilds restore the composer).
fn AgentFeedbackEditorWidget::start_reply(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
) -> Unit {
  match self.reply_textareas.get(comment.id) {
    Some(existing) => {
      @base_browser.focus_prevent_scroll(existing)
      return
    }
    None => ()
  }
  guard self.item_nodes.get(comment.id) is Some(item) else { return }
  self.drafts.set(comment.id, "")
  self.open_reply_composer(comment, item, "", focus=true)
  (self.host.on_layout)(self.id)
}

///|
/// The reply composer body shared by user opens and draft restores.
fn AgentFeedbackEditorWidget::open_reply_composer(
  self : AgentFeedbackEditorWidget,
  comment : @agent_feedback.SessionEditorComment,
  item : @rdom.Element,
  initial_text : String,
  focus~ : Bool,
) -> Unit {
  let document = @rdom.document()
  let composer = document.create_element("div")
  composer.set_attribute("class", "agent-feedback-widget-add-reply")
  let textarea = document.create_element("textarea")
  textarea.set_attribute("class", "agent-feedback-widget-edit-textarea")
  textarea.set_attribute("rows", "1")
  textarea.set_attribute("placeholder", "Add a comment…")
  input_set_textarea_value(textarea, initial_text)
  composer.append_child(textarea.as_node())
  item.append_child(composer.as_node())
  self.reply_textareas.set(comment.id, textarea)
  let auto_size = () => {
    let height = input_textarea_grown_height(textarea)
    @base_browser.set_style_property(
      textarea,
      "height",
      "\{height.to_string()}px",
    )
    (self.host.on_layout)(self.id)
  }
  auto_size()
  let clear_draft = () => self.drafts.remove(comment.id)
  let cleanup = () => {
    self.reply_textareas.remove(comment.id)
    @base_browser.remove_element(composer)
    clear_draft()
    (self.host.on_layout)(self.id)
  }
  textarea.add_event_listener("input", _ => {
    self.drafts.set(comment.id, input_textarea_value(textarea))
    auto_size()
  })
  textarea.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        match keyboard.key() {
          "Enter" =>
            if !keyboard.shift_key() {
              event.prevent_default()
              let reply = input_textarea_value(textarea)
              if is_blank(reply) {
                cleanup()
              } else {
                // Clear the draft before the change event so the rebuilt
                // widget doesn't re-open the composer.
                clear_draft()
                (self.host.on_reply)(comment, reply.trim().to_owned())
              }
            }
          "Escape" => {
            event.prevent_default()
            cleanup()
          }
          _ => ()
        }
      None => ()
    }
    event.stop_propagation()
  })
  // An empty composer closes when focus leaves; a draft survives (and the
  // teardown blur of a rebuild must not wipe the draft being restored).
  textarea.add_event_listener("blur", _ => {
    if !self.disposed {
      if is_blank(input_textarea_value(textarea)) {
        cleanup()
      }
    }
  })
  if focus {
    @base_browser.focus_prevent_scroll(textarea)
    input_move_caret_to_end(textarea)
  }
}

// --- expand / collapse / focus ------------------------------------------------------

///|
/// `expand`: reveal the body and let the glue collapse the file's other
/// widgets (one expanded per file).
pub fn AgentFeedbackEditorWidget::expand(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  let was_expanded = self.expanded
  self.expanded = true
  self.root.set_attribute("class", "agent-feedback-widget visible")
  self.body.set_attribute("class", "agent-feedback-widget-body")
  self.update_toggle()
  (self.host.on_layout)(self.id)
  if !was_expanded {
    (self.host.on_did_expand)(self.id)
  }
}

///|
pub fn AgentFeedbackEditorWidget::is_expanded(
  self : AgentFeedbackEditorWidget,
) -> Bool {
  self.expanded
}

///|
/// `collapse`.
pub fn AgentFeedbackEditorWidget::collapse(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  self.expanded = false
  self.root.set_attribute("class", "agent-feedback-widget collapsed visible")
  self.body.set_attribute("class", "agent-feedback-widget-body collapsed")
  self.update_toggle()
  self.clear_focus()
  (self.host.on_layout)(self.id)
}

///|
/// `focusFeedback`: mark one item focused and highlight its range.
pub fn AgentFeedbackEditorWidget::focus_feedback(
  self : AgentFeedbackEditorWidget,
  feedback_id : String,
) -> Unit {
  for comment_id, node in self.item_nodes {
    let base = "agent-feedback-widget-item agent-feedback-widget-item-agentFeedback"
    if comment_id == feedback_id {
      node.set_attribute("class", "\{base} focused")
    } else {
      node.set_attribute("class", base)
    }
  }
  match self.comments.search_by(comment => comment.id == feedback_id) {
    Some(index) => (self.host.on_hover)(self.comments[index])
    None => ()
  }
}

///|
/// `clearFocus`.
fn AgentFeedbackEditorWidget::clear_focus(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  for _, node in self.item_nodes {
    node.set_attribute(
      "class", "agent-feedback-widget-item agent-feedback-widget-item-agentFeedback",
    )
  }
  (self.host.on_hover_end)()
}

///|
/// `containsFeedback`.
pub fn AgentFeedbackEditorWidget::contains_feedback(
  self : AgentFeedbackEditorWidget,
  feedback_id : String,
) -> Bool {
  self.comments.search_by(comment => comment.id == feedback_id) is Some(_)
}

///|
/// `getCommentIds` — the contribution prunes orphaned drafts against these.
pub fn AgentFeedbackEditorWidget::comment_ids(
  self : AgentFeedbackEditorWidget,
) -> Array[String] {
  self.comments.map(comment => comment.id)
}

///|
/// `findReplyCommentIdForElement`, collapsed to "which composer has DOM
/// focus": the contribution snapshots this before tearing widgets down so
/// the rebuilt widget can refocus the restored draft.
pub fn AgentFeedbackEditorWidget::focused_reply_comment_id(
  self : AgentFeedbackEditorWidget,
) -> String? {
  for comment_id, textarea in self.reply_textareas {
    if @base_browser.element_has_focus(textarea) {
      return Some(comment_id)
    }
  }
  None
}

// --- geometry --------------------------------------------------------------------

///|
pub fn AgentFeedbackEditorWidget::set_position(
  self : AgentFeedbackEditorWidget,
  top : Double,
  left : Double,
) -> Unit {
  @base_browser.set_style_property(self.root, "top", "\{top.to_string()}px")
  @base_browser.set_style_property(self.root, "left", "\{left.to_string()}px")
}

///|
/// `_estimatedWidgetWidth` fallback until the node has been laid out.
pub fn AgentFeedbackEditorWidget::measured_width(
  self : AgentFeedbackEditorWidget,
) -> Double {
  let width = @base_browser.element_offset_width(self.root)
  if width > 0.0 {
    width
  } else {
    280.0
  }
}

///|
pub fn AgentFeedbackEditorWidget::measured_height(
  self : AgentFeedbackEditorWidget,
) -> Double {
  @base_browser.element_offset_height(self.root)
}

///|
pub fn AgentFeedbackEditorWidget::measured_header_height(
  self : AgentFeedbackEditorWidget,
) -> Double {
  @base_browser.element_offset_height(self.header)
}

// --- helpers / FFI ----------------------------------------------------------------

///|
/// Replaces one retained Markdown target while leaving sibling comment and
/// reply targets alive. Agent feedback has no command/link callback, so the
/// shared renderer keeps only its safe native-link behavior.
fn AgentFeedbackEditorWidget::render_markdown_target(
  self : AgentFeedbackEditorWidget,
  key : String,
  target : @rdom.Element,
  markdown : String,
) -> Unit {
  self.dispose_markdown_target(key)
  if self.disposed {
    return
  }
  let rendered = @browser_markdown.render_markdown(markdown, target~)
  self.markdown_disposables.set(key, rendered.dispose)
}

///|
fn AgentFeedbackEditorWidget::dispose_markdown_target(
  self : AgentFeedbackEditorWidget,
  key : String,
) -> Unit {
  match self.markdown_disposables.get(key) {
    Some(disposable) => {
      self.markdown_disposables.remove(key)
      disposable.dispose()
    }
    None => ()
  }
}

///|
fn AgentFeedbackEditorWidget::dispose_all_markdown_targets(
  self : AgentFeedbackEditorWidget,
) -> Unit {
  let pending : Array[@base_common.Disposable] = []
  for _, disposable in self.markdown_disposables {
    pending.push(disposable)
  }
  self.markdown_disposables.clear()
  for disposable in pending {
    disposable.dispose()
  }
}

///|
fn feedback_comment_target_key(comment_id : String) -> String {
  "comment:\{comment_id}"
}

///|
fn feedback_reply_target_key(comment_id : String, reply_index : Int) -> String {
  "reply:\{comment_id}:\{reply_index.to_string()}"
}

///|
fn widget_icon_button(
  action : String,
  title : String,
  class_name : String,
  run : () -> Unit,
) -> @rdom.Element {
  let button = @rdom.document().create_element("button")
  button.set_attribute("type", "button")
  button.set_attribute("class", "agent-feedback-widget-action \{class_name}")
  button.set_attribute("title", title)
  button.set_attribute("data-agent-feedback-action", action)
  button.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    run()
  })
  button
}

///|
/// Whether the event target sits inside an ancestor with the given class —
/// the widget's click-exclusion gates (`target.closest(...)` upstream).
extern "js" fn widget_event_in_class(
  event : @rdom.Event,
  class_name : String,
) -> Bool =
  #| (ev, cls) => !!(ev.target && ev.target.closest && ev.target.closest('.' + cls))

///|
/// Whether a non-collapsed DOM selection lives inside the widget — the
/// "don't navigate when the user just selected comment text" gate.
extern "js" fn widget_has_selection_inside(element : @rdom.Element) -> Bool =
  #| (el) => {
  #|   const selection = el.ownerDocument.defaultView?.getSelection?.();
  #|   return !!(selection && !selection.isCollapsed && el.contains(selection.anchorNode));
  #| }

///|
extern "js" fn input_move_caret_to_end(element : @rdom.Element) -> Unit =
  #| (el) => { const len = (el.value ?? '').length; el.setSelectionRange?.(len, len) }
