///|
/// Closed row family for the feature-local result tree. Group identity is the
/// normalized model group index; reference identity is its flat index.
priv enum ReferenceResultsTreeRow {
  GroupRow(Int)
  ReferenceRow(Int)
} derive(Eq)

///|
/// Browser-only materialization of one normalized result model. Model identity,
/// row previews, expansion, selection, and DOM ownership remain separate so a
/// later virtualized renderer can replace this implementation without changing
/// the root Viewer API.
priv struct ReferenceResultsTree {
  node : @rdom.Element
  callbacks : ReferencesPeekWidgetCallbacks
  layout_changed : () -> Unit
  listeners : Array[@base_common.Disposable]
  mut model : @references.ReferencesModel?
  mut previews : Array[Array[@references.ReferenceRowPreview]]
  mut expanded_groups : Array[Bool]
  mut requested_groups : Array[Bool]
  mut selected_flat_index : Int
  mut roving : ReferenceResultsTreeRow?
  mut group_rows : Array[@rdom.Element?]
  mut group_children : Array[@rdom.Element?]
  mut reference_rows : Array[@rdom.Element?]
  mut disposed : Bool
}

///|
fn ReferenceResultsTree::ReferenceResultsTree(
  node : @rdom.Element,
  callbacks : ReferencesPeekWidgetCallbacks,
  layout_changed : () -> Unit,
) -> ReferenceResultsTree {
  node.set_attribute("class", "moonbit-viewer-reference-results-tree")
  node.set_attribute("role", "tree")
  node.set_attribute("tabindex", "-1")
  node.set_attribute("aria-label", "No results found")
  let tree : ReferenceResultsTree = {
    node,
    callbacks,
    layout_changed,
    listeners: [],
    model: None,
    previews: [],
    expanded_groups: [],
    requested_groups: [],
    selected_flat_index: -1,
    roving: None,
    group_rows: [],
    group_children: [],
    reference_rows: [],
    disposed: false,
  }
  tree.install_listeners()
  tree
}

///|
fn ReferenceResultsTree::get_dom_node(
  self : ReferenceResultsTree,
) -> @rdom.Element {
  self.node
}

///|
fn ReferenceResultsTree::clear(self : ReferenceResultsTree) -> Unit {
  if self.disposed {
    return
  }
  self.node.set_inner_html("")
  self.node.set_attribute("aria-label", "No results found")
  self.model = None
  self.previews = []
  self.expanded_groups = []
  self.requested_groups = []
  self.selected_flat_index = -1
  self.roving = None
  self.group_rows = []
  self.group_children = []
  self.reference_rows = []
}

///|
fn ReferenceResultsTree::set_results(
  self : ReferenceResultsTree,
  model : @references.ReferencesModel,
  selected : @references.ReferenceItem?,
) -> Unit {
  if self.disposed {
    return
  }
  self.model = Some(model)
  self.previews = [
    for group in model.groups => {
      [
        for reference in group.references => {
          LocationFallback(reference.fallback_label())
        }
      ]
    }
  ]
  self.expanded_groups = Array::make(model.groups.length(), false)
  self.requested_groups = Array::make(model.groups.length(), false)
  self.group_rows = Array::make(model.groups.length(), None)
  self.group_children = Array::make(model.groups.length(), None)
  self.reference_rows = Array::make(model.references.length(), None)
  let selected_item = match selected {
    Some(item) if self.contains_reference(item) => Some(item)
    _ => model.references.get(0)
  }
  self.selected_flat_index = match selected_item {
    Some(item) => item.flat_index
    None => -1
  }
  match selected_item {
    Some(item) => {
      if item.group_index >= 0 &&
        item.group_index < self.expanded_groups.length() {
        self.expanded_groups[item.group_index] = true
      }
      self.roving = Some(ReferenceRow(item.flat_index))
    }
    None => self.roving = None
  }
  if model.groups.length() == 1 {
    self.expanded_groups[0] = true
  }
  self.render()
  self.node.set_attribute("aria-label", reference_results_summary(model))
  match selected_item {
    Some(item) => self.request_group(item.group_index)
    None => ()
  }
}

///|
fn ReferenceResultsTree::set_group_previews(
  self : ReferenceResultsTree,
  group_index : Int,
  previews : Array[@references.ReferenceRowPreview],
) -> Unit {
  if self.disposed {
    return
  }
  guard self.model is Some(model) &&
    group_index >= 0 &&
    group_index < model.groups.length() &&
    previews.length() == model.groups[group_index].references.length() else {
    return
  }
  let had_tree_focus = @base_browser.element_contains_active_element(self.node)
  let restore_row_focus = had_tree_focus &&
    (match self.roving {
      Some(ReferenceRow(flat_index)) =>
        model.references[flat_index].group_index == group_index
      _ => false
    })
  self.previews[group_index] = previews.copy()
  guard self.group_reference_container(group_index) is Some(container) else {
    return
  }
  self.render_group_references(group_index, container)
  self.update_row_states()
  if restore_row_focus &&
    self.roving is Some(row) &&
    self.row_node(row) is Some(node) {
    @base_browser.focus_prevent_scroll(node)
  }
}

///|
fn ReferenceResultsTree::set_selected(
  self : ReferenceResultsTree,
  selected : @references.ReferenceItem,
) -> Unit {
  if self.disposed || !self.contains_reference(selected) {
    return
  }
  let had_tree_focus = @base_browser.element_contains_active_element(self.node)
  if self.model is Some(model) &&
    model.groups.length() > 1 &&
    !self.expanded_groups[selected.group_index] {
    self.set_group_expanded(selected.group_index, true)
  }
  self.selected_flat_index = selected.flat_index
  self.roving = Some(ReferenceRow(selected.flat_index))
  self.update_row_states()
  match self.row_node(ReferenceRow(selected.flat_index)) {
    Some(node) => {
      self.reveal_row(node)
      if had_tree_focus {
        @base_browser.focus_prevent_scroll(node)
      }
    }
    None => ()
  }
}

///|
/// Returns false when no result row exists and the caller should focus the
/// dialog shell instead.
fn ReferenceResultsTree::focus(self : ReferenceResultsTree) -> Bool {
  if self.disposed {
    return false
  }
  self.ensure_roving_visible()
  guard self.roving is Some(row) && self.row_node(row) is Some(node) else {
    return false
  }
  self.update_row_states()
  @base_browser.focus_prevent_scroll(node)
  true
}

///|
fn ReferenceResultsTree::dispose(self : ReferenceResultsTree) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
}

///|
fn ReferenceResultsTree::render(self : ReferenceResultsTree) -> Unit {
  self.node.set_inner_html("")
  self.group_rows = []
  self.group_children = []
  self.reference_rows = []
  guard self.model is Some(model) else { return }
  for _ in model.groups {
    self.group_rows.push(None)
    self.group_children.push(None)
  }
  for _ in model.references {
    self.reference_rows.push(None)
  }
  if model.groups.length() == 1 {
    self.group_children[0] = Some(self.node)
    self.render_group_references(0, self.node)
  } else {
    for group in model.groups {
      self.render_group(group)
    }
  }
  self.ensure_roving_visible()
  self.update_row_states()
  (self.layout_changed)()
}

///|
fn ReferenceResultsTree::render_group(
  self : ReferenceResultsTree,
  group : @references.ReferenceGroup,
) -> Unit {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute("class", "moonbit-viewer-reference-results-group")
  wrapper.set_attribute("role", "none")
  let row = document.create_element("button")
  row.set_attribute(
    "class", "moonbit-viewer-reference-results-row moonbit-viewer-reference-results-file",
  )
  row.set_attribute("type", "button")
  row.set_attribute("role", "treeitem")
  row.set_attribute("aria-level", "1")
  row.set_attribute("aria-posinset", (group.group_index + 1).to_string())
  guard self.model is Some(model) else { return }
  row.set_attribute("aria-setsize", model.groups.length().to_string())
  row.set_attribute(
    "aria-expanded",
    reference_results_bool(self.expanded_groups[group.group_index]),
  )
  row.set_attribute("data-reference-row-kind", "group")
  row.set_attribute("data-reference-group-index", group.group_index.to_string())
  let basename = @base_common.basename_or_authority(group.uri)
  let parent = @base_common.dirname(group.uri.path)
  row.set_attribute(
    "aria-label",
    reference_group_accessible_label(group, basename, parent),
  )
  row.set_attribute("title", group.uri_string)
  let twistie = document.create_element("span")
  twistie.set_attribute("class", "moonbit-viewer-reference-results-twistie")
  twistie.set_attribute("aria-hidden", "true")
  twistie.append_child(document.create_text_node("\u{25b6}").as_node())
  let filename = document.create_element("span")
  filename.set_attribute("class", "moonbit-viewer-reference-results-file-name")
  filename.append_child(document.create_text_node(basename).as_node())
  let dirname = document.create_element("span")
  dirname.set_attribute("class", "moonbit-viewer-reference-results-file-parent")
  if parent != "" {
    dirname.append_child(document.create_text_node(parent).as_node())
  }
  let badge = document.create_element("span")
  badge.set_attribute("class", "moonbit-viewer-reference-results-file-count")
  badge.set_attribute("aria-hidden", "true")
  badge.append_child(
    document.create_text_node(group.references.length().to_string()).as_node(),
  )
  row.append_child(twistie.as_node())
  row.append_child(filename.as_node())
  row.append_child(dirname.as_node())
  row.append_child(badge.as_node())
  wrapper.append_child(row.as_node())
  let children = document.create_element("div")
  children.set_attribute(
    "class", "moonbit-viewer-reference-results-group-children",
  )
  children.set_attribute("role", "group")
  if !self.expanded_groups[group.group_index] {
    children.set_attribute("hidden", "")
  }
  wrapper.append_child(children.as_node())
  self.node.append_child(wrapper.as_node())
  self.group_rows[group.group_index] = Some(row)
  self.group_children[group.group_index] = Some(children)
  self.render_group_references(group.group_index, children)
}

///|
fn ReferenceResultsTree::render_group_references(
  self : ReferenceResultsTree,
  group_index : Int,
  container : @rdom.Element,
) -> Unit {
  guard self.model is Some(model) &&
    group_index >= 0 &&
    group_index < model.groups.length() else {
    return
  }
  let group = model.groups[group_index]
  for reference in group.references {
    if reference.flat_index >= 0 &&
      reference.flat_index < self.reference_rows.length() {
      self.reference_rows[reference.flat_index] = None
    }
  }
  container.set_inner_html("")
  let level = if model.groups.length() == 1 { 1 } else { 2 }
  for reference in group.references {
    let row = self.render_reference_row(
      reference,
      self.previews[group_index][reference.index_in_group],
      level,
      group.references.length(),
    )
    container.append_child(row.as_node())
    self.reference_rows[reference.flat_index] = Some(row)
  }
}

///|
fn ReferenceResultsTree::render_reference_row(
  _self : ReferenceResultsTree,
  reference : @references.ReferenceItem,
  preview : @references.ReferenceRowPreview,
  level : Int,
  set_size : Int,
) -> @rdom.Element {
  let document = @rdom.document()
  let row = document.create_element("button")
  row.set_attribute("type", "button")
  row.set_attribute("role", "treeitem")
  row.set_attribute("aria-level", level.to_string())
  row.set_attribute("aria-posinset", (reference.index_in_group + 1).to_string())
  row.set_attribute("aria-setsize", set_size.to_string())
  row.set_attribute("data-reference-row-kind", "reference")
  row.set_attribute(
    "data-reference-flat-index",
    reference.flat_index.to_string(),
  )
  row.set_attribute(
    "data-reference-group-index",
    reference.group_index.to_string(),
  )
  let display = reference_row_preview_text(preview)
  row.set_attribute(
    "aria-label",
    reference_accessible_label(reference, display),
  )
  row.set_attribute("title", reference.fallback_label())
  match preview {
    Snippet(snippet) => {
      let snippet_node = document.create_element("span")
      snippet_node.set_attribute(
        "class", "moonbit-viewer-reference-results-snippet",
      )
      let before = document.create_element("span")
      before.set_attribute(
        "class", "moonbit-viewer-reference-results-snippet-before",
      )
      before.append_child(document.create_text_node(snippet.before).as_node())
      let matched = document.create_element("span")
      matched.set_attribute(
        "class", "moonbit-viewer-reference-results-snippet-match",
      )
      matched.append_child(document.create_text_node(snippet.matched).as_node())
      let after = document.create_element("span")
      after.set_attribute(
        "class", "moonbit-viewer-reference-results-snippet-after",
      )
      after.append_child(document.create_text_node(snippet.after).as_node())
      snippet_node.append_child(before.as_node())
      snippet_node.append_child(matched.as_node())
      snippet_node.append_child(after.as_node())
      row.append_child(snippet_node.as_node())
    }
    LocationFallback(label) => {
      let fallback = document.create_element("span")
      fallback.set_attribute(
        "class", "moonbit-viewer-reference-results-fallback",
      )
      fallback.append_child(document.create_text_node(label).as_node())
      row.append_child(fallback.as_node())
    }
  }
  row
}

///|
fn ReferenceResultsTree::install_listeners(self : ReferenceResultsTree) -> Unit {
  self.listen("click", event => self.handle_click(event))
  self.listen("dblclick", event => self.handle_double_click(event))
  self.listen("keydown", event => self.handle_keydown(event))
}

///|
fn ReferenceResultsTree::listen(
  self : ReferenceResultsTree,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  self.node.add_event_listener(event_type, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      self.node.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn ReferenceResultsTree::handle_click(
  self : ReferenceResultsTree,
  event : @rdom.Event,
) -> Unit {
  guard !self.disposed && self.row_from_event(event) is Some(row) else {
    return
  }
  event.prevent_default()
  event.stop_propagation()
  match row {
    GroupRow(group_index) => {
      self.roving = Some(row)
      self.set_group_expanded(group_index, !self.expanded_groups[group_index])
      self.focus_row(row, reveal=false, notify_selection=false)
    }
    ReferenceRow(flat_index) => {
      guard self.reference_at(flat_index) is Some(reference) else { return }
      self.selected_flat_index = flat_index
      self.roving = Some(row)
      self.update_row_states()
      match self.row_node(row) {
        Some(node) => @base_browser.focus_prevent_scroll(node)
        None => ()
      }
      (self.callbacks.on_select)(reference)
    }
  }
}

///|
fn ReferenceResultsTree::handle_double_click(
  self : ReferenceResultsTree,
  event : @rdom.Event,
) -> Unit {
  guard !self.disposed &&
    self.row_from_event(event) is Some(ReferenceRow(flat_index)) &&
    self.reference_at(flat_index) is Some(reference) else {
    return
  }
  event.prevent_default()
  event.stop_propagation()
  self.selected_flat_index = flat_index
  self.roving = Some(ReferenceRow(flat_index))
  self.update_row_states()
  (self.callbacks.on_select)(reference)
  (self.callbacks.on_confirm)(reference)
}

///|
fn ReferenceResultsTree::handle_keydown(
  self : ReferenceResultsTree,
  event : @rdom.Event,
) -> Unit {
  guard !self.disposed && event.to_keyboard_event() is Some(keyboard) else {
    return
  }
  let key = keyboard.key()
  match key {
    "ArrowDown" => {
      event.prevent_default()
      event.stop_propagation()
      self.move_visible(1)
    }
    "ArrowUp" => {
      event.prevent_default()
      event.stop_propagation()
      self.move_visible(-1)
    }
    "Home" => {
      event.prevent_default()
      event.stop_propagation()
      self.focus_boundary(first=true)
    }
    "End" => {
      event.prevent_default()
      event.stop_propagation()
      self.focus_boundary(first=false)
    }
    "ArrowRight" => {
      guard self.current_event_or_roving_row(event) is Some(row) else { return }
      match row {
        GroupRow(group_index) => {
          event.prevent_default()
          event.stop_propagation()
          if !self.expanded_groups[group_index] {
            self.set_group_expanded(group_index, true)
            self.focus_row(row, reveal=true, notify_selection=false)
          } else if self.model is Some(model) &&
            model.groups[group_index].references.get(0) is Some(first) {
            self.focus_row(
              ReferenceRow(first.flat_index),
              reveal=true,
              notify_selection=true,
            )
          }
        }
        ReferenceRow(_) => ()
      }
    }
    "ArrowLeft" => {
      guard self.current_event_or_roving_row(event) is Some(row) else { return }
      match row {
        GroupRow(group_index) =>
          if self.expanded_groups[group_index] {
            event.prevent_default()
            event.stop_propagation()
            self.set_group_expanded(group_index, false)
            self.focus_row(row, reveal=true, notify_selection=false)
          }
        ReferenceRow(flat_index) =>
          if self.reference_at(flat_index) is Some(reference) &&
            self.model is Some(model) &&
            model.groups.length() > 1 {
            event.prevent_default()
            event.stop_propagation()
            self.focus_row(
              GroupRow(reference.group_index),
              reveal=true,
              notify_selection=false,
            )
          }
      }
    }
    "Enter" => {
      guard self.current_event_or_roving_row(event)
        is Some(ReferenceRow(flat_index)) &&
        self.reference_at(flat_index) is Some(reference) else {
        return
      }
      event.prevent_default()
      event.stop_propagation()
      self.selected_flat_index = flat_index
      self.roving = Some(ReferenceRow(flat_index))
      self.update_row_states()
      if keyboard.ctrl_key() || keyboard.meta_key() {
        (self.callbacks.on_open_side)(reference)
      } else {
        (self.callbacks.on_confirm)(reference)
      }
    }
    _ => ()
  }
}

///|
fn ReferenceResultsTree::move_visible(
  self : ReferenceResultsTree,
  delta : Int,
) -> Unit {
  let rows = self.visible_rows()
  guard rows.length() > 0 else { return }
  let current = match self.roving {
    Some(row) => reference_results_row_index(rows, row)
    None => -1
  }
  let next = if current < 0 {
    0
  } else if delta < 0 {
    (current - 1).max(0)
  } else {
    (current + 1).min(rows.length() - 1)
  }
  self.focus_row(rows[next], reveal=true, notify_selection=true)
}

///|
fn ReferenceResultsTree::focus_boundary(
  self : ReferenceResultsTree,
  first~ : Bool,
) -> Unit {
  let rows = self.visible_rows()
  guard rows.length() > 0 else { return }
  self.focus_row(
    if first {
      rows[0]
    } else {
      rows[rows.length() - 1]
    },
    reveal=true,
    notify_selection=true,
  )
}

///|
fn ReferenceResultsTree::focus_row(
  self : ReferenceResultsTree,
  row : ReferenceResultsTreeRow,
  reveal~ : Bool,
  notify_selection~ : Bool,
) -> Unit {
  guard reference_results_row_index(self.visible_rows(), row) >= 0 else {
    return
  }
  let selection_changed = match row {
    ReferenceRow(flat_index) => {
      let changed = flat_index != self.selected_flat_index
      self.selected_flat_index = flat_index
      changed
    }
    GroupRow(_) => false
  }
  self.roving = Some(row)
  self.update_row_states()
  if self.row_node(row) is Some(node) {
    if reveal {
      self.reveal_row(node)
    }
    @base_browser.focus_prevent_scroll(node)
  }
  if selection_changed &&
    notify_selection &&
    row is ReferenceRow(flat_index) &&
    self.reference_at(flat_index) is Some(reference) {
    (self.callbacks.on_select)(reference)
  }
}

///|
fn ReferenceResultsTree::set_group_expanded(
  self : ReferenceResultsTree,
  group_index : Int,
  expanded : Bool,
) -> Unit {
  guard self.model is Some(model) &&
    model.groups.length() > 1 &&
    group_index >= 0 &&
    group_index < model.groups.length() else {
    return
  }
  self.expanded_groups[group_index] = expanded
  match self.group_rows[group_index] {
    Some(row) =>
      row.set_attribute("aria-expanded", reference_results_bool(expanded))
    None => ()
  }
  match self.group_children[group_index] {
    Some(children) =>
      if expanded {
        children.remove_attribute("hidden")
      } else {
        children.set_attribute("hidden", "")
      }
    None => ()
  }
  if expanded {
    self.request_group(group_index)
  } else {
    match self.roving {
      Some(ReferenceRow(flat_index)) if model.references[flat_index].group_index ==
        group_index => self.roving = Some(GroupRow(group_index))
      _ => ()
    }
  }
  self.ensure_roving_visible()
  self.update_row_states()
  (self.layout_changed)()
}

///|
fn ReferenceResultsTree::request_group(
  self : ReferenceResultsTree,
  group_index : Int,
) -> Unit {
  guard self.model is Some(model) &&
    group_index >= 0 &&
    group_index < model.groups.length() &&
    !self.requested_groups[group_index] else {
    return
  }
  self.requested_groups[group_index] = true
  (self.callbacks.on_expand_group)(model.groups[group_index])
}

///|
fn ReferenceResultsTree::ensure_roving_visible(
  self : ReferenceResultsTree,
) -> Unit {
  let rows = self.visible_rows()
  if rows.length() == 0 {
    self.roving = None
    return
  }
  match self.roving {
    Some(row) if reference_results_row_index(rows, row) >= 0 => ()
    _ => {
      let preferred = ReferenceRow(self.selected_flat_index)
      self.roving = if reference_results_row_index(rows, preferred) >= 0 {
        Some(preferred)
      } else {
        Some(rows[0])
      }
    }
  }
}

///|
fn ReferenceResultsTree::update_row_states(self : ReferenceResultsTree) -> Unit {
  guard self.model is Some(model) else { return }
  for group_index, row in self.group_rows {
    match row {
      Some(row) => {
        row.set_attribute(
          "tabindex",
          reference_results_tabindex(self.roving == Some(GroupRow(group_index))),
        )
        row.set_attribute(
          "aria-expanded",
          reference_results_bool(self.expanded_groups[group_index]),
        )
      }
      None => ()
    }
  }
  for reference in model.references {
    match self.reference_rows[reference.flat_index] {
      Some(row) => {
        let selected = reference.flat_index == self.selected_flat_index
        row.set_attribute("class", reference_results_reference_class(selected))
        row.set_attribute("aria-selected", reference_results_bool(selected))
        row.set_attribute(
          "tabindex",
          reference_results_tabindex(
            self.roving == Some(ReferenceRow(reference.flat_index)) &&
            self.reference_is_visible(reference),
          ),
        )
      }
      None => ()
    }
  }
}

///|
fn ReferenceResultsTree::visible_rows(
  self : ReferenceResultsTree,
) -> Array[ReferenceResultsTreeRow] {
  let result : Array[ReferenceResultsTreeRow] = []
  guard self.model is Some(model) else { return result }
  if model.groups.length() == 1 {
    for reference in model.references {
      result.push(ReferenceRow(reference.flat_index))
    }
  } else {
    for group in model.groups {
      result.push(GroupRow(group.group_index))
      if self.expanded_groups[group.group_index] {
        for reference in group.references {
          result.push(ReferenceRow(reference.flat_index))
        }
      }
    }
  }
  result
}

///|
fn ReferenceResultsTree::contains_reference(
  self : ReferenceResultsTree,
  reference : @references.ReferenceItem,
) -> Bool {
  match self.model {
    Some(model) =>
      reference.flat_index >= 0 &&
      reference.flat_index < model.references.length() &&
      model.references[reference.flat_index] == reference
    None => false
  }
}

///|
fn ReferenceResultsTree::reference_at(
  self : ReferenceResultsTree,
  flat_index : Int,
) -> @references.ReferenceItem? {
  match self.model {
    Some(model) if flat_index >= 0 && flat_index < model.references.length() =>
      Some(model.references[flat_index])
    _ => None
  }
}

///|
fn ReferenceResultsTree::reference_is_visible(
  self : ReferenceResultsTree,
  reference : @references.ReferenceItem,
) -> Bool {
  match self.model {
    Some(model) =>
      model.groups.length() == 1 || self.expanded_groups[reference.group_index]
    None => false
  }
}

///|
fn ReferenceResultsTree::row_node(
  self : ReferenceResultsTree,
  row : ReferenceResultsTreeRow,
) -> @rdom.Element? {
  match row {
    GroupRow(index) =>
      if index >= 0 && index < self.group_rows.length() {
        self.group_rows[index]
      } else {
        None
      }
    ReferenceRow(index) =>
      if index >= 0 && index < self.reference_rows.length() {
        self.reference_rows[index]
      } else {
        None
      }
  }
}

///|
fn ReferenceResultsTree::group_reference_container(
  self : ReferenceResultsTree,
  group_index : Int,
) -> @rdom.Element? {
  if group_index >= 0 && group_index < self.group_children.length() {
    self.group_children[group_index]
  } else {
    None
  }
}

///|
fn ReferenceResultsTree::row_from_event(
  self : ReferenceResultsTree,
  event : @rdom.Event,
) -> ReferenceResultsTreeRow? {
  guard event.target().to_element() is Some(target) &&
    target.closest("[data-reference-row-kind]") is Some(row) &&
    self.node.contains(row.as_node()) &&
    row.get_attribute("data-reference-row-kind") is Some(kind) else {
    return None
  }
  if kind == "group" {
    guard row.get_attribute("data-reference-group-index") is Some(raw) else {
      return None
    }
    reference_results_parse_index(raw).map(index => GroupRow(index))
  } else if kind == "reference" {
    guard row.get_attribute("data-reference-flat-index") is Some(raw) else {
      return None
    }
    reference_results_parse_index(raw).map(index => ReferenceRow(index))
  } else {
    None
  }
}

///|
fn ReferenceResultsTree::current_event_or_roving_row(
  self : ReferenceResultsTree,
  event : @rdom.Event,
) -> ReferenceResultsTreeRow? {
  match self.row_from_event(event) {
    Some(row) => Some(row)
    None => self.roving
  }
}

///|
fn ReferenceResultsTree::reveal_row(
  _self : ReferenceResultsTree,
  row : @rdom.Element,
) -> Unit {
  row.scroll_into_view_with_options(
    behavior="auto",
    block="nearest",
    inline="nearest",
    container="nearest",
  )
}

///|
fn reference_results_parse_index(raw : String) -> Int? {
  guard raw.length() > 0 && raw.length() <= 9 else { return None }
  let mut value = 0
  for unit in raw {
    guard unit >= '0' && unit <= '9' else { return None }
    value = value * 10 + (unit.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn reference_results_row_index(
  rows : Array[ReferenceResultsTreeRow],
  target : ReferenceResultsTreeRow,
) -> Int {
  rows.search(target).unwrap_or(-1)
}

///|
fn reference_results_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn reference_results_tabindex(selected : Bool) -> String {
  if selected {
    "0"
  } else {
    "-1"
  }
}

///|
fn reference_results_reference_class(selected : Bool) -> String {
  if selected {
    "moonbit-viewer-reference-results-row moonbit-viewer-reference-results-reference selected"
  } else {
    "moonbit-viewer-reference-results-row moonbit-viewer-reference-results-reference"
  }
}

///|
fn reference_row_preview_text(
  preview : @references.ReferenceRowPreview,
) -> String {
  match preview {
    Snippet(snippet) => snippet.display_text()
    LocationFallback(label) => label
  }
}

///|
fn reference_accessible_label(
  reference : @references.ReferenceItem,
  display : String,
) -> String {
  display +
  " in " +
  @base_common.basename_or_authority(reference.uri) +
  " on line " +
  reference.range.start_line_number.to_string() +
  " at column " +
  reference.range.start_column.to_string()
}

///|
fn reference_group_accessible_label(
  group : @references.ReferenceGroup,
  basename : String,
  parent : String,
) -> String {
  let count = group.references.length()
  let result = if count == 1 {
    "1 result in " + basename
  } else {
    count.to_string() + " results in " + basename
  }
  if parent == "" {
    result
  } else {
    result + ", full path " + parent
  }
}

///|
fn reference_results_summary(model : @references.ReferencesModel) -> String {
  let reference_count = model.references.length()
  let group_count = model.groups.length()
  if reference_count == 0 {
    "No results found"
  } else if reference_count == 1 {
    "Found 1 result in " + model.references[0].uri_string
  } else if group_count == 1 {
    "Found " +
    reference_count.to_string() +
    " results in " +
    model.groups[0].uri_string
  } else {
    "Found " +
    reference_count.to_string() +
    " results in " +
    group_count.to_string() +
    " files"
  }
}
