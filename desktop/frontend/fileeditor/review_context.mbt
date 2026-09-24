///|
// Cache the digest of the visible model pair: ordinary composer typing must
// not re-hash complete files. Equality includes both texts, not a hunk index.
let review_context_digest : Ref[(String, String, String)?] = Ref(None)

///|
fn review_source_version(original : String, modified : String) -> String {
  if review_context_digest.val is Some((old, new, version)) &&
    old == original &&
    new == modified {
    return version
  }
  let input = original.length().to_string() + ":" + original + modified
  let version = @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(input)))
  review_context_digest.val = Some((original, modified, version))
  version
}

///|
fn State::review_source(
  self : State,
  change : ChangedFile,
) -> @mention_context.ReviewSource? {
  guard self.placement.identity().bind(placement => placement.checkout_root())
    is Some(root) &&
    self.docs.get(@resource.join_relative(root, change.path)) is Some(doc) &&
    doc.review is Some(review) &&
    review.selected == change &&
    doc.visible_diff() is Some((original, modified)) else {
    return None
  }
  Some({
    workspace: root.path,
    file: change.path.0,
    original_file: change.original_path.map(path => path.0),
    base: self.changes_head,
    version: review_source_version(original, modified),
  })
}

///|
pub fn State::accepts_review_context(
  self : State,
  selection : @mention_context.ReviewChanges,
) -> Bool {
  guard self.placement.identity().bind(placement => placement.checkout_root())
    is Some(root) &&
    self.docs.get(
      @resource.join_relative(root, @pathx.Relative(selection.source.file)),
    )
    is Some(doc) &&
    doc.review is Some(review) else {
    return false
  }
  self.review_source(review.selected) == Some(selection.source)
}

///|
fn selected_context_lines(
  text : String,
  ranges : Array[@common.LineRange],
) -> Array[@mention_context.ChangeLine] {
  // An empty TextModel has an anchor line for layout, not source context.
  if text.is_empty() {
    return []
  }
  let lines = text.split("\n").to_array()
  let selected : Array[@mention_context.ChangeLine] = []
  for range in ranges {
    for number = range.start_line_number
        number < range.end_line_number_exclusive
        number = number + 1 {
      if lines.get(number - 1) is Some(line) {
        selected.push({ number, text: line.to_owned(), })
      }
    }
  }
  selected
}

///|
fn State::review_context_selection(
  self : State,
  change : ChangedFile,
  hunk : ReviewHunk,
) -> @mention_context.ReviewChanges? {
  guard self.placement.identity().bind(placement => placement.checkout_root())
    is Some(root) &&
    self.review_source(change) is Some(source) &&
    self.docs.get(@resource.join_relative(root, change.path)) is Some(doc) &&
    doc.visible_diff() is Some((original, modified)) else {
    return None
  }
  let excerpt : @mention_context.ChangeExcerpt = {
    original: selected_context_lines(original, hunk.old_ranges),
    modified: selected_context_lines(modified, hunk.new_ranges),
  }
  if excerpt.is_empty() {
    None
  } else {
    Some({ source, excerpts: [excerpt], })
  }
}

///|
pub fn State::with_review_context_reveal(
  self : State,
  selection : @mention_context.ReviewChanges,
) -> State {
  { ..self, review_context_reveal: Some(selection), }
}

///|
fn review_context_intersects(
  selection : @mention_context.ReviewChanges,
  hunk : ReviewHunk,
) -> Bool {
  selection.excerpts.any(excerpt => {
    excerpt.original.any(line => {
      hunk.old_ranges.any(range => {
        line.number >= range.start_line_number &&
        line.number < range.end_line_number_exclusive
      })
    }) ||
    excerpt.modified.any(line => {
      hunk.new_ranges.any(range => {
        line.number >= range.start_line_number &&
        line.number < range.end_line_number_exclusive
      })
    })
  })
}

///|
fn reveal_context_in_editor(
  editor : @viewer.DiffEditor,
  selection : @mention_context.ReviewChanges,
  old_offset : Int?,
  new_offset : Int?,
) -> Bool {
  guard editor.is_diff_up_to_date() else { return false }
  for index, hunk in editor.get_hunks() {
    if review_context_intersects(
        selection,
        ReviewHunk::from_diff_hunk(hunk, old_offset, new_offset),
      ) {
      if index == 0 {
        editor.reveal_first_diff()
      } else {
        editor.select_hunk(index - 1)
        ignore(editor.reveal_next_change())
      }
      return true
    }
  }
  false
}

///|
fn review_context_layout_ready(editor : @viewer.DiffEditor) -> Bool {
  // The logical diff can finish before the first layout publishes visual
  // hunks. Its visible changes distinguish that pending layout from a ready
  // comparison with no visible changes. The active-hunk callback retries the
  // reveal once the renderer has committed those hunks.
  editor.is_diff_up_to_date() &&
  (
    !editor.get_hunks().is_empty() ||
    projected_review_file_changes(editor) is None
  )
}

///|
fn reveal_pending_review_context(
  state : State,
  target : ReviewHunkBridgeTarget,
) -> Unit {
  guard state.review_context_reveal is Some(selection) &&
    target.change.path.0 == selection.source.file &&
    target.ready else {
    return
  }
  if !state.accepts_review_context(selection) {
    (target.dispatch)(
      ReviewContextRevealFinished(source=selection.source, found=false),
    )
    return
  }
  let found = if target.surface is ReviewLineSurface {
    guard mounted_diff_editor() is Some(editor) &&
      review_context_layout_ready(editor) else {
      return
    }
    reveal_context_in_editor(editor, selection, Some(0), Some(0))
  } else {
    guard target.semantic_keys.all(key => {
      semantic_review_editors.get(key) is Some(entry) &&
      review_context_layout_ready(entry.editor)
    }) else {
      return
    }
    let mut found = false
    for key in target.semantic_keys {
      if semantic_review_editors.get(key) is Some(entry) &&
        reveal_context_in_editor(
          entry.editor,
          selection,
          semantic_feedback_line_offset(entry.section, SemanticReviewOriginal),
          semantic_feedback_line_offset(entry.section, SemanticReviewModified),
        ) {
        semantic_review_active_key.val = Some(key)
        reveal_semantic_review_item_start(entry.host)
        found = true
        break
      }
    }
    found
  }
  (target.dispatch)(
    ReviewContextRevealFinished(source=selection.source, found~),
  )
}

///|
fn append_review_context_action(
  actions : @dom.Element,
  state : State,
  target : ReviewHunkBridgeTarget,
  selection : @mention_context.ReviewChanges,
) -> Unit {
  let coverage = selection.coverage(state.review_context)
  actions.set_attribute(
    "data-context",
    match coverage {
      @mention_context.NotIncluded => "none"
      @mention_context.PartlyIncluded => "partial"
      @mention_context.Included => "full"
    },
  )
  let send = fn(adding : Bool) {
    guard review_hunk_bridge_target.val is Some(current) &&
      current.owner == target.owner &&
      current.change == target.change &&
      current.review_generation == target.review_generation &&
      current.surface_generation == target.surface_generation else {
      return
    }
    (current.dispatch)(
      ReviewContextChanged(owner=current.owner, selection~, adding~),
    )
  }
  let control = @dom.document().create_element("div")
  control.set_attribute("class", "review-hunk-context")
  let button = @dom.document().create_element("button")
  button.set_attribute("type", "button")
  button.set_attribute("class", "review-hunk-context-button")
  button.set_attribute("data-hunk-action", "context")
  let label = match coverage {
    @mention_context.NotIncluded => ui(viewer_locale(), AddToContext)
    @mention_context.PartlyIncluded => ui(viewer_locale(), PartlyInContext)
    @mention_context.Included => ui(viewer_locale(), InContext)
  }
  button.set_attribute("aria-label", label)
  button.set_attribute(
    "aria-pressed",
    match coverage {
      @mention_context.NotIncluded => "false"
      @mention_context.PartlyIncluded => "mixed"
      @mention_context.Included => "true"
    },
  )
  button.set_attribute(
    "title",
    if coverage is @mention_context.Included {
      ui(viewer_locale(), RemoveHunkContext)
    } else {
      label
    },
  )
  // Constant icon markup; selected source is only ever inserted as text.
  button.set_inner_html(
    "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" aria-hidden=\"true\"><path d=\"M21 11 12 20a6 6 0 0 1-8-8L14 2a4 4 0 0 1 6 6L9 19a2 2 0 0 1-3-3L16 6\"/></svg>",
  )
  let label_element = @dom.document().create_element("span")
  label_element.set_attribute("class", "review-hunk-context-label")
  label_element.append_child(@dom.document().create_text_node(label).as_node())
  button.append_child(label_element.as_node())
  control.append_child(button.as_node())
  if coverage is @mention_context.PartlyIncluded {
    button.set_attribute("aria-haspopup", "menu")
    button.set_attribute("aria-expanded", "false")
    let menu = @dom.document().create_element("div")
    menu.set_attribute("class", "review-hunk-context-menu")
    menu.set_attribute("role", "menu")
    menu.set_attribute("hidden", "")
    button.add_event_listener("click", event => {
      event.stop_propagation()
      if menu.has_attribute("hidden") {
        menu.remove_attribute("hidden")
        button.set_attribute("aria-expanded", "true")
      } else {
        menu.set_attribute("hidden", "")
        button.set_attribute("aria-expanded", "false")
      }
    })
    control.add_event_listener("keydown", event => {
      guard event.to_keyboard_event() is Some(key) else { return }
      if key.key() == "Escape" {
        event.prevent_default()
        event.stop_propagation()
        menu.set_attribute("hidden", "")
        button.set_attribute("aria-expanded", "false")
        @base_browser.focus_prevent_scroll(button)
      } else if key.key() == "ArrowDown" || key.key() == "ArrowUp" {
        event.prevent_default()
        event.stop_propagation()
        menu.remove_attribute("hidden")
        button.set_attribute("aria-expanded", "true")
        let items = [ for item in menu.query_selector_all("button") => item ]
        guard !items.is_empty() else { return }
        let current = items.search_by(item => {
          @base_browser.element_contains_active_element(item)
        })
        let next = match current {
          Some(index) =>
            (
              index +
              (if key.key() == "ArrowDown" { 1 } else { items.length() - 1 })
            ) %
            items.length()
          None => if key.key() == "ArrowDown" { 0 } else { items.length() - 1 }
        }
        @base_browser.focus_prevent_scroll(items[next])
      }
    })
    for
      (label, adding) in [
        (ui(viewer_locale(), AddRemainingChanges), true),
        (ui(viewer_locale(), RemoveIncludedChanges), false),
      ] {
      let item = @dom.document().create_element("button")
      item.set_attribute("type", "button")
      item.set_attribute("role", "menuitem")
      item.append_child(@dom.document().create_text_node(label).as_node())
      item.add_event_listener("click", event => {
        event.stop_propagation()
        @base_browser.focus_prevent_scroll(button)
        send(adding)
      })
      menu.append_child(item.as_node())
    }
    control.append_child(menu.as_node())
  } else {
    button.add_event_listener("click", event => {
      event.stop_propagation()
      send(coverage is @mention_context.NotIncluded)
    })
  }
  actions.append_child(control.as_node())
}

///|
priv suberror ReviewContextDismiss {
  ReviewContextDismiss
}

///|
fn review_context_dismiss_loader(
  _payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  let target = @dom.document().as_event_target()
  let listener : @dom.Listener = event => {
    for control in @dom.document().query_selector_all(".review-hunk-context") {
      if !@base_browser.event_target_has_matching_ancestor(
          event, control, ".review-hunk-context",
        ) &&
        control.query_selector(".review-hunk-context-menu") is Some(menu) {
        menu.set_attribute("hidden", "")
        if control.query_selector(".review-hunk-context-button") is Some(button) {
          button.set_attribute("aria-expanded", "false")
        }
      }
    }
  }
  target.add_event_listener_with_options("pointerdown", listener, capture=true)
  target.add_event_listener_with_options("focusin", listener, capture=true)
  Some({
    unload: _ => {
      target.remove_event_listener_with_options(
        "pointerdown",
        listener,
        capture=true,
      )
      target.remove_event_listener_with_options(
        "focusin",
        listener,
        capture=true,
      )
    },
    update_tagger: _ => (),
  })
}

///|
fn review_context_dismiss_subscription() -> @sub.Sub {
  @sub.custom_sub(
    "review-context-dismiss",
    @sub.Local,
    ReviewContextDismiss,
    review_context_dismiss_loader,
  )
}
