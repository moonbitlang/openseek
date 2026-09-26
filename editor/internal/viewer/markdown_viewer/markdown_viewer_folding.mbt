///|
priv struct MarkdownViewerWidgetFoldRecord {
  mut collapsed : Bool
  fingerprint : String
}

///|
/// Attachment-scoped section state. Records are never carried across a model
/// swap; source replacement retains a reader decision only when both the
/// section key and exact body fingerprint remain unchanged.
priv struct MarkdownViewerWidgetFoldState {
  mut source : String
  mut section_keys : Array[String]
  records : Map[String, MarkdownViewerWidgetFoldRecord]
}

///|
fn MarkdownViewerWidgetFoldState::MarkdownViewerWidgetFoldState() -> MarkdownViewerWidgetFoldState {
  { source: "", section_keys: [], records: Map([]), }
}

///|
fn MarkdownViewerWidgetAttachment::initialize_folding(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  guard self.view is Some(view) else { return }
  let source = self.model.model.get_value()
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let keys = @markdown_core.markdown_section_keys(sections, projection, source)
  let defaults = @markdown_core.markdown_default_collapsed_sections(
    projection, source,
  )
  self.fold.source = source
  self.fold.section_keys = keys
  self.fold.records.clear()
  for section_index, section in sections {
    guard section_index < keys.length() else { continue }
    self.fold.records[keys[section_index]] = {
      collapsed: defaults.contains(section_index),
      fingerprint: markdown_viewer_fold_fingerprint(section, source),
    }
  }
  view.set_section_fold_toggle_handler(section_index => {
    self.toggle_section(section_index) |> ignore
  })
  self.apply_folding()
  self.apply_toc()
}

///|
fn MarkdownViewerWidgetAttachment::reconcile_folding(
  self : MarkdownViewerWidgetAttachment,
  source : String,
) -> Unit {
  guard self.view is Some(view) else { return }
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let keys = @markdown_core.markdown_section_keys(sections, projection, source)
  let retained : Map[String, MarkdownViewerWidgetFoldRecord] = Map([])
  for section_index, section in sections {
    guard section_index < keys.length() else { continue }
    let key = keys[section_index]
    let fingerprint = markdown_viewer_fold_fingerprint(section, source)
    retained[key] = match self.fold.records.get(key) {
      Some(record) if record.fingerprint == fingerprint => record
      _ => { collapsed: false, fingerprint, }
    }
  }
  self.fold.source = source
  self.fold.section_keys = keys
  self.fold.records.clear()
  for key, record in retained {
    self.fold.records[key] = record
  }
  self.apply_folding()
  self.apply_toc()
}

///|
fn MarkdownViewerWidgetAttachment::toggle_section(
  self : MarkdownViewerWidgetAttachment,
  section_index : Int,
) -> Bool {
  guard section_index >= 0 &&
    section_index < self.fold.section_keys.length() &&
    self.fold.records.get(self.fold.section_keys[section_index]) is Some(record) else {
    return false
  }
  record.collapsed = !record.collapsed
  self.apply_folding()
  self.layout_changed()
  true
}

///|
fn MarkdownViewerWidgetAttachment::apply_folding(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  guard self.view is Some(view) else { return }
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let hidden : Set[Int] = Set([])
  let controls : Array[@markdown_document.MarkdownSectionFoldControl] = []
  for section_index, section in sections {
    guard section.is_foldable(projection) &&
      section_index < self.fold.section_keys.length() else {
      continue
    }
    let collapsed = match
      self.fold.records.get(self.fold.section_keys[section_index]) {
      Some(record) => record.collapsed
      None => false
    }
    let anchor = projection.block_anchors[section.heading_anchor_index]
    guard anchor.is_root_element else { continue }
    controls.push({ heading_node_id: anchor.node_id, section_index, collapsed, })
    if collapsed {
      for node_id in section.body_node_ids(projection) {
        hidden.add(node_id)
      }
    }
  }
  let hidden_sorted = hidden.to_array()
  hidden_sorted.sort()
  view.set_hidden_root_elements(hidden_sorted)
  view.install_section_fold_controls(controls)
}

///|
fn markdown_viewer_fold_fingerprint(
  section : @markdown_core.MarkdownSection,
  source : String,
) -> String {
  match section.body_source_range {
    Some(range) => {
      let start = range.start.max(0).min(source.length())
      let end = range.end_exclusive.max(start).min(source.length())
      source[start:end].to_owned()
    }
    None => ""
  }
}

///|
fn MarkdownViewerWidgetAttachment::apply_toc(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  guard self.view is Some(view) else { return }
  let entries = @markdown_core.markdown_table_of_contents(view.projection()).map(entry => {
      let bar_entry : @markdown_document.MarkdownTocBarEntry = {
        depth: entry.depth,
        text: entry.text,
        source_offset: entry.source_offset,
      }
      bar_entry
    },
  )
  view.set_toc_entries(entries, offset => self.navigate_section(offset))
}

///|
fn MarkdownViewerWidgetAttachment::navigate_section(
  self : MarkdownViewerWidgetAttachment,
  source_offset : Int,
) -> Unit {
  guard self.view is Some(view) else { return }
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let mut changed = false
  for section_index, section in sections {
    guard section.source_range.contains(source_offset) &&
      section_index < self.fold.section_keys.length() else {
      continue
    }
    match self.fold.records.get(self.fold.section_keys[section_index]) {
      Some(record) if record.collapsed => {
        record.collapsed = false
        changed = true
      }
      _ => ()
    }
  }
  if changed {
    self.apply_folding()
  }
  self.layout_changed()
}

///|
/// Collapses or expands the innermost foldable section containing the source
/// offset. Offsets are 0-based UTF-16 positions in the original TextModel.
pub fn MarkdownViewerWidget::toggle_section_at(
  self : MarkdownViewerWidget,
  source_offset : Int,
) -> Bool {
  guard self.current is Some(current) && current.view is Some(view) else {
    return false
  }
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  guard @markdown_core.markdown_section_at_source_offset(
      sections, source_offset,
    )
    is Some(section) &&
    section.is_foldable(projection) else {
    return false
  }
  for section_index, candidate in sections {
    if candidate.heading_anchor_index == section.heading_anchor_index {
      return current.toggle_section(section_index)
    }
  }
  false
}

///|
/// Returns collapsed heading offsets in document order.
pub fn MarkdownViewerWidget::collapsed_sections(
  self : MarkdownViewerWidget,
) -> Array[Int] {
  let collapsed : Array[Int] = []
  guard self.current is Some(current) && current.view is Some(view) else {
    return collapsed
  }
  let projection = view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  for section_index, section in sections {
    guard section_index < current.fold.section_keys.length() else { continue }
    match current.fold.records.get(current.fold.section_keys[section_index]) {
      Some(record) if record.collapsed =>
        collapsed.push(
          projection.block_anchors[section.heading_anchor_index].source_range.start,
        )
      _ => ()
    }
  }
  collapsed
}
