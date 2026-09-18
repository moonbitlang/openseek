///|
priv enum ReviewHunkBridgeSurface {
  ReviewLineSurface
  ReviewSemanticSurface
} derive(Eq)

///|
/// The active review identity is shared by the permanent Line editor and the
/// currently visible semantic editors. Keeping only the visible surface here
/// prevents the parked Line editor from replacing a Token/Tree selection.
priv struct ReviewHunkBridgeTarget {
  change : ChangedFile
  review_generation : Int
  surface_generation : Int
  surface : ReviewHunkBridgeSurface
  semantic_input : SemanticReviewInput?
  active_hunk : ReviewHunk?
  file_changes : ReviewHunk?
  position : ReviewHunkPosition?
  ready : Bool
  semantic_keys : Array[String]
  owner : @interop.ConversationKey
  dispatch : (Msg) -> Unit
}

///|
let review_hunk_bridge_target : Ref[ReviewHunkBridgeTarget?] = Ref(None)

///|
fn current_review_hunk_bridge_target(
  state : State,
  ctx : Ctx,
  dispatch : (Msg) -> Unit,
) -> ReviewHunkBridgeTarget? {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(review) &&
    state.owner is Some(owner) &&
    doc.visible_diff() is Some((original, modified)) &&
    viewer_state.document == Some(path) &&
    viewer_state.review_diff_inputs == Some((original, modified)) &&
    state.current_review_generation(review.selected, ctx)
    is Some(review_generation) else {
    return None
  }
  let (active_hunk, file_changes, position) = match
    state.active_review_hunk(ctx) {
    Some(active) => (Some(active.hunk), active.file_changes, active.position)
    None => (None, None, None)
  }
  Some({
    owner,
    change: review.selected,
    review_generation,
    surface_generation: state.review_hunk_surface_generation,
    surface: if state.semantic_review_input is Some(_) {
      ReviewSemanticSurface
    } else {
      ReviewLineSurface
    },
    semantic_input: state.semantic_review_input,
    active_hunk,
    file_changes,
    position,
    ready: state.review_navigation_ready(ctx),
    semantic_keys: semantic_sections(state.semantic_review_plan)
    .map(section => section.key)
    .filter(key => !state.semantic_review_collapsed.contains(key)),
    dispatch,
  })
}

///|
fn sync_review_hunk_bridge_target(
  state : State,
  ctx : Ctx,
  dispatch : (Msg) -> Unit,
) -> Unit {
  review_hunk_bridge_target.val = current_review_hunk_bridge_target(
    state, ctx, dispatch,
  )
  if mounted_diff_editor() is Some(editor) {
    publish_line_review_hunk_context(editor)
  }
}

///|
fn projected_review_hunk(
  hunks : Array[@viewer.DiffHunk],
  active_index : Int?,
  old_offset : Int?,
  new_offset : Int?,
) -> ReviewHunk? {
  guard active_index is Some(index) else { return None }
  guard index >= 0 && index < hunks.length() else { return None }
  let hunk = ReviewHunk::from_diff_hunk(hunks[index], old_offset, new_offset)
  if hunk.is_empty() {
    None
  } else {
    Some(hunk)
  }
}

///|
fn projected_review_file_changes(editor : @viewer.DiffEditor) -> ReviewHunk? {
  // The parked Line editor may never have been laid out for this file, so its
  // visual hunks can be empty even after the logical diff is ready. Only use
  // the current model pair's changes, excluding geometry-only alignments.
  guard editor.is_diff_up_to_date() && editor.get_diff() is Some(diff) else {
    return None
  }
  let old_ranges : Array[@common.LineRange] = []
  let new_ranges : Array[@common.LineRange] = []
  for change in diff.changes {
    guard change.kind is Visible else { continue }
    old_ranges.push(change.mapping.original)
    new_ranges.push(change.mapping.modified)
  }
  let file_changes = ReviewHunk(old_ranges~, new_ranges~)
  if file_changes.is_empty() {
    None
  } else {
    Some(file_changes)
  }
}

///|
fn publish_review_active_hunk(
  surface : ReviewHunkBridgeSurface,
  hunk : ReviewHunk?,
  file_changes : ReviewHunk?,
  position : ReviewHunkPosition?,
  ready~ : Bool,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == surface &&
    (
      target.ready != ready ||
      target.active_hunk != hunk ||
      (
        hunk is Some(_) &&
        (target.file_changes != file_changes || target.position != position)
      )
    ) else {
    return
  }
  review_hunk_bridge_target.val = Some({
    ..target,
    active_hunk: hunk,
    file_changes,
    position,
    ready,
  })
  (target.dispatch)(
    ReviewActiveHunkChanged(
      ready~,
      change=target.change,
      review_generation=target.review_generation,
      surface_generation=target.surface_generation,
      hunk~,
      file_changes~,
      position~,
    ),
  )
}

///|
fn publish_line_review_hunk_context(editor : @viewer.DiffEditor) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) else { return }
  let hunks = editor.get_hunks()
  let file_changes = projected_review_file_changes(editor)
  match target.surface {
    ReviewLineSurface => {
      let active_index = editor.get_active_hunk_index()
      publish_review_active_hunk(
        ready=editor.is_diff_up_to_date(),
        ReviewLineSurface,
        projected_review_hunk(hunks, active_index, Some(0), Some(0)),
        file_changes,
        ReviewHunkPosition::from_zero_based(active_index, hunks.length()),
      )
    }
    ReviewSemanticSurface =>
      publish_review_active_hunk(
        ready=target.ready,
        ReviewSemanticSurface,
        target.active_hunk,
        file_changes,
        target.position,
      )
  }
}

///|
fn publish_semantic_review_active_hunk(
  input : SemanticReviewInput,
  key : String,
  editor : @viewer.DiffEditor,
  section : @moon_diff_provider.SemanticReviewSection,
  active_index : Int?,
) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface == ReviewSemanticSurface &&
    target.semantic_input == Some(input) &&
    semantic_review_active_key.val == Some(key) else {
    return
  }
  let hunks = editor.get_hunks()
  let file_changes = mounted_diff_editor().bind(projected_review_file_changes)
  publish_review_active_hunk(
    ready=target.semantic_keys.all(key => {
      semantic_review_editors.get(key) is Some(entry) &&
      entry.editor.is_diff_up_to_date()
    }),
    ReviewSemanticSurface,
    projected_review_hunk(
      hunks,
      active_index,
      semantic_feedback_line_offset(section, SemanticReviewOriginal),
      semantic_feedback_line_offset(section, SemanticReviewModified),
    ),
    file_changes,
    semantic_review_hunk_position(key, active_index),
  )
}

///|
fn sync_review_hunk_actions(state : State) -> Unit {
  let target = review_hunk_bridge_target.val
  if target is Some(target) {
    reveal_pending_review_context(state, target)
  }
  if mounted_diff_editor() is Some(editor) {
    if target is Some(target) && target.surface is ReviewLineSurface {
      install_review_hunk_actions(state, target, editor, None)
    } else {
      editor.set_hunk_action_renderer(None)
    }
  }
  if target is Some(target) && target.surface is ReviewSemanticSurface {
    for key, entry in semantic_review_editors {
      install_review_hunk_actions(
        state,
        target,
        entry.editor,
        Some((key, entry.section)),
      )
    }
  }
}

///|
fn install_review_hunk_actions(
  state : State,
  target : ReviewHunkBridgeTarget,
  editor : @viewer.DiffEditor,
  section : (String, @moon_diff_provider.SemanticReviewSection)?,
) -> Unit {
  editor.set_hunk_action_renderer(
    Some(index => {
      guard editor.is_diff_up_to_date() else { return None }
      let (old_offset, new_offset) = match section {
        None => (Some(0), Some(0))
        Some((_, section)) =>
          (
            semantic_feedback_line_offset(section, SemanticReviewOriginal),
            semantic_feedback_line_offset(section, SemanticReviewModified),
          )
      }
      guard projected_review_hunk(
          editor.get_hunks(),
          Some(index),
          old_offset,
          new_offset,
        )
        is Some(hunk) else {
        return None
      }
      let status = state.review_hunk_state(target.change, hunk)
      let viewed = status is ReviewHunkViewed
      let button = @dom.document().create_element("button")
      button.set_attribute("type", "button")
      if state.is_change_reviewed(target.change) &&
        mounted_diff_editor().bind(projected_review_file_changes) is None {
        button.set_attribute("disabled", "")
      }
      button.set_attribute("class", "review-hunk-marker")
      button.set_attribute(
        "aria-label",
        if viewed {
          if viewer_locale() is SimplifiedChinese {
            "取消第 \{index + 1} 个差异块的已查看标记"
          } else {
            "Unmark hunk \{index + 1} viewed"
          }
        } else if viewer_locale() is SimplifiedChinese {
          "将第 \{index + 1} 个差异块标为已查看"
        } else {
          "Mark hunk \{index + 1} viewed"
        },
      )
      button.set_attribute(
        "aria-pressed",
        match status {
          ReviewHunkViewed => "true"
          ReviewHunkPartial => "mixed"
          ReviewHunkUnviewed => "false"
        },
      )
      button.set_attribute(
        "title",
        if viewed {
          ui(viewer_locale(), MarkHunkUnviewed)
        } else {
          ui(viewer_locale(), MarkHunkViewed)
        },
      )
      button.append_child(
        @dom.document()
        .create_text_node(
          match status {
            ReviewHunkViewed => "✓"
            ReviewHunkPartial => "−"
            ReviewHunkUnviewed => ""
          },
        )
        .as_node(),
      )
      // Restoring a button's focus after a state refresh must not let the
      // section's editor-focus bridge replace the outer scroll selection.
      button.add_event_listener("focusin", event => event.stop_propagation())
      button.add_event_listener("click", event => {
        event.stop_propagation()
        guard review_hunk_bridge_target.val is Some(current) &&
          current.change == target.change &&
          current.review_generation == target.review_generation &&
          current.surface_generation == target.surface_generation else {
          return
        }
        if section is Some((key, _)) {
          semantic_review_active_key.val = Some(key)
        }
        editor.select_hunk(index)
        let position = match section {
          None =>
            ReviewHunkPosition::from_zero_based(
              Some(index),
              editor.get_hunks().length(),
            )
          Some((key, _)) => semantic_review_hunk_position(key, Some(index))
        }
        (current.dispatch)(
          ToggleReviewHunk(
            change=current.change,
            review_generation=current.review_generation,
            surface_generation=current.surface_generation,
            hunk~,
            file_changes=mounted_diff_editor().bind(
              projected_review_file_changes,
            ),
            position~,
          ),
        )
      })
      button.set_attribute("data-hunk-action", "viewed")
      let actions = @dom.document().create_element("div")
      actions.set_attribute("class", "review-hunk-actions")
      actions.set_attribute("tabindex", "-1")
      actions.add_event_listener("focusin", event => event.stop_propagation())
      actions.append_child(button.as_node())
      if state.review_context_selection(target.change, hunk) is Some(selection) {
        append_review_context_action(actions, state, target, selection)
      }
      Some(actions)
    }),
  )
}

///|
/// Semantic editors expand to their full height; the outer scroll plane owns
/// reading position. Pick one global hunk using its actual rendered geometry.
fn track_semantic_review_scroll(host : @dom.Element) -> Unit {
  guard review_hunk_bridge_target.val is Some(target) &&
    target.surface is ReviewSemanticSurface else {
    return
  }
  let offset = host.get_bounding_client_rect().get_top() +
    host.get_client_height() * 0.5
  let mut nearest : (String, Int, Double)? = None
  for key in semantic_review_order {
    guard semantic_review_editors.get(key) is Some(entry) &&
      entry.host.get_client_height() > 0.0 else {
      continue
    }
    let origin = entry.host.get_bounding_client_rect().get_top()
    for index, _ in entry.editor.get_hunks() {
      if entry.editor.get_hunk_viewport_bounds(index) is Some((top, bottom)) {
        let distance = if offset < origin + top {
          origin + top - offset
        } else {
          (offset - origin - bottom).max(0.0)
        }
        if nearest is None ||
          (nearest is Some((_, _, previous)) && distance < previous) {
          nearest = Some((key, index, distance))
        }
      }
    }
  }
  if nearest is Some((key, index, _)) &&
    semantic_review_editors.get(key) is Some(entry) {
    semantic_review_active_key.val = Some(key)
    entry.editor.select_hunk(index)
    if target.semantic_input is Some(input) {
      publish_semantic_review_active_hunk(
        input,
        key,
        entry.editor,
        entry.section,
        Some(index),
      )
    }
  }
}
