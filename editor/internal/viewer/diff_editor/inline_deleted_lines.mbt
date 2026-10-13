// Inline deleted hunks are ordinary CodeEditorWidget-managed ViewZones whose
// content is rendered by the kernel's native detached-line pipeline. This
// layer only projects canonical DocumentDiff changes into zone placement and
// UTF-16 decoration inputs; it never tokenizes or measures text itself.

///|
fn inline_original_decorations(
  change : @diff.DetailedLineRangeMapping,
) -> Array[@code_widget.CodeEditorRenderLinesDecoration] {
  let decorations : Array[@code_widget.CodeEditorRenderLinesDecoration] = []
  match change.inner_changes {
    Some(inner_changes) =>
      for inner in inner_changes {
        if !inner.original.is_empty() {
          decorations.push({
            range: inner.original,
            class_name: "diff-editor-inline-char-delete",
          })
        }
      }
    None => ()
  }
  decorations
}

///|
fn inline_deleted_zone_anchor(change : @diff.DetailedLineRangeMapping) -> Int32 {
  (change.modified.start_line_number - 1).max(0)
}

///|
priv struct InlineDeletedViewZones {
  original_specs : Array[@code_widget.ManagedCodeEditorViewZoneSpec]
  modified_specs : Array[@code_widget.ManagedCodeEditorViewZoneSpec]
  zones : Array[InlineDeletedZone]
}

///|
struct InlineDeletedZone {
  _unit : Unit
}

///|
fn configure_inline_deleted_roots(
  dom_node : @rdom.Element,
  margin_dom_node : @rdom.Element,
  change : @diff.DetailedLineRangeMapping,
) -> Unit {
  dom_node.set_attribute("class", "view-lines diff-editor-inline-deleted-block")
  dom_node.set_attribute(
    "data-original-line-start",
    change.original.start_line_number.to_string(),
  )
  dom_node.set_attribute(
    "data-original-line-end-exclusive",
    change.original.end_line_number_exclusive.to_string(),
  )
  margin_dom_node.set_attribute("class", "diff-editor-inline-deleted-margin")
}

///|
fn inline_alignment_spacer_spec(
  after_line_number : Int32,
  height_in_px : Double,
  pane_class : String,
  ordinal~ : Int32,
) -> @code_widget.ManagedCodeEditorViewZoneSpec {
  let document = @rdom.document()
  let node = document.create_element("div")
  node.set_attribute(
    "class",
    "moonbit-diff-editor-alignment-spacer \{pane_class}",
  )
  node.set_attribute("aria-hidden", "true")
  // Spacers and deleted code can share an anchor. Use their common alignment
  // order so ignored source rows stay before the following deleted code.
  ManagedCodeEditorViewZoneSpec(after_line_number, height_in_px, node, ordinal~)
}

///|
/// Inline's companion height is signed geometry. Ordinarily the modified
/// range is visible and its positive height becomes blank old-number rows in
/// the original strip. A rich Markdown comment instead hides several modified
/// source lines and replaces them with one foreign ViewZone. When that atomic
/// hidden-source delta lands inside a canonical hunk, the hunk's net modified
/// height can be negative. The opposite pane must then receive the magnitude;
/// dropping it would leave every following context line vertically shifted.
fn inline_companion_spacer_heights(
  modified_height_in_px : Double,
) -> (Double, Double) {
  if modified_height_in_px > 0.01 {
    (modified_height_in_px, 0.0)
  } else if modified_height_in_px < -0.01 {
    (0.0, -modified_height_in_px)
  } else {
    (0.0, 0.0)
  }
}

///|
fn configure_inline_deleted_markers(
  renderer : @code_widget.CodeEditorWidget,
  margin_dom_node : @rdom.Element,
  rendered : @code_widget.CodeEditorRenderedLines,
  render_indicators : Bool,
) -> Unit {
  margin_dom_node.set_inner_html("")
  if !render_indicators {
    return
  }
  let layout = renderer.get_layout_info()
  let view_line_count = rendered.view_line_count()
  if view_line_count <= 0 {
    return
  }
  let line_height = rendered.height_in_px() / view_line_count.to_double()
  for index in 0..<view_line_count {
    let marker = @rdom.document().create_element("div")
    marker.set_attribute(
      "class", "delete-sign codicon codicon-diff-remove diff-editor-inline-delete-sign",
    )
    marker.set_attribute("aria-hidden", "true")
    marker.set_attribute("data-rendered-deleted-row", index.to_string())
    marker.set_attribute(
      "style",
      "position:absolute;top:\{index.to_double() * line_height}px;right:0;width:\{layout.decorations_width}px;height:\{line_height}px;line-height:\{line_height}px;",
    )
    margin_dom_node.append_child(marker.as_node())
  }
}

///|
fn inline_deleted_view_zone_specs(
  renderer : @code_widget.CodeEditorWidget,
  original_model : @model.TextModel,
  alignments : Array[LineRangeAlignment],
  render_indicators : Bool,
) -> InlineDeletedViewZones {
  let original_specs : Array[@code_widget.ManagedCodeEditorViewZoneSpec] = []
  let modified_specs : Array[@code_widget.ManagedCodeEditorViewZoneSpec] = []
  let zones : Array[InlineDeletedZone] = []
  for alignment_index, alignment in alignments {
    guard alignment.diff is Some(change) else {
      let delta = alignment.modified_height_in_px -
        alignment.original_height_in_px
      if delta > 0.01 {
        original_specs.push(
          inline_alignment_spacer_spec(
            alignment.original_range.end_line_number_exclusive - 1,
            delta,
            "moonbit-diff-editor-inline-original-alignment-spacer",
            ordinal=alignment_index,
          ),
        )
      } else if delta < -0.01 {
        modified_specs.push(
          inline_alignment_spacer_spec(
            alignment.modified_range.end_line_number_exclusive - 1,
            -delta,
            "moonbit-diff-editor-inline-modified-alignment-spacer",
            ordinal=alignment_index,
          ),
        )
      }
      continue
    }

    if !alignment.original_range.is_empty() {
      match
        renderer.render_lines(
          original_model,
          alignment.original_range,
          decorations=inline_original_decorations(change),
          line_class_name="diff-editor-inline-deleted-line",
          render_margin_line_numbers=false,
        ) {
        Some(rendered) => {
          configure_inline_deleted_roots(
            rendered.dom_node(),
            rendered.margin_dom_node(),
            change,
          )
          configure_inline_deleted_markers(
            renderer,
            rendered.margin_dom_node(),
            rendered,
            render_indicators,
          )
          let line_height = rendered.height_in_px() /
            rendered.view_line_count().to_double()
          for
            model_line_index, view_line_count in rendered.model_line_view_counts() {
            if view_line_count > 1 {
              original_specs.push(
                inline_alignment_spacer_spec(
                  alignment.original_range.start_line_number + model_line_index,
                  (view_line_count - 1).to_double() * line_height,
                  "moonbit-diff-editor-inline-original-continuation-spacer",
                  ordinal=alignment_index,
                ),
              )
            }
          }
          modified_specs.push(
            ManagedCodeEditorViewZoneSpec(
              inline_deleted_zone_anchor(change),
              rendered.height_in_px(),
              rendered.dom_node(),
              margin_dom_node=rendered.margin_dom_node(),
              min_width_in_px=rendered.min_width_in_px(),
              ordinal=alignment_index,
              suppress_mouse_down=false,
            ),
          )
          zones.push({ _unit: (), })
        }
        None => ()
      }
    }

    // The original editor is clipped to its real line-number strip. Positive
    // companion height creates blank old-number rows beside inserted code. A
    // negative net height can occur when a multi-line Markdown source block is
    // hidden and its compact rich ViewZone is charged to this canonical hunk;
    // balance that signed delta in modified instead of discarding it. For a
    // pure deletion both heights are zero.
    let (original_companion_height, modified_compensation_height) = inline_companion_spacer_heights(
      alignment.modified_height_in_px,
    )
    if original_companion_height > 0.01 {
      original_specs.push(
        inline_alignment_spacer_spec(
          alignment.original_range.end_line_number_exclusive - 1,
          original_companion_height,
          "moonbit-diff-editor-inline-original-companion-spacer",
          ordinal=alignment_index,
        ),
      )
    }
    if modified_compensation_height > 0.01 {
      modified_specs.push(
        inline_alignment_spacer_spec(
          alignment.modified_range.end_line_number_exclusive - 1,
          modified_compensation_height,
          "moonbit-diff-editor-inline-modified-companion-spacer",
          ordinal=alignment_index,
        ),
      )
    }
  }
  { original_specs, modified_specs, zones, }
}
