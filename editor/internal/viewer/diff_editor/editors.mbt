///|
/// Owns the two ordinary code-editor kernels used by one diff editor. This is
/// the local counterpart of VS Code's DiffEditorEditors: pane construction,
/// option mapping, model-pair installation, focus, layout, and disposal are
/// centralized here instead of being duplicated by individual diff features.
pub struct DiffEditorEditors {
  original : @code_widget.CodeEditorWidget
  modified : @code_widget.CodeEditorWidget
  owned_services : @code_widget.CodeEditorServices?
  model_pair_commit : DiffEditorModelPairCommitBarrier
  mut disposed : Bool
}

///|
/// The explicit transaction boundary around the two synchronous kernel
/// `set_model` calls. `committed_generation` advances only after both panes
/// contain the same requested pair, so no diff-owned observer can ever treat a
/// half-installed pair as committed state.
struct DiffEditorModelPairCommitBarrier {
  mut is_committing : Bool
  mut committed_generation : Int
}

///|
let diff_markdown_comment_lane_reserved_px : Int = 16

///|
/// Diff panes never install the folding contribution. Reserve its 16px lane
/// only for rich Markdown-comment controls; source-only panes need no reserve.
/// Feedback independently adds its own lane when enabled.
fn diff_pane_options(
  editor_options : @code_widget.CodeEditorOptions,
  diff_word_wrap : DiffWordWrap,
  render_markdown_comments : Bool,
  handle_mouse_wheel : Bool,
) -> @code_widget.CodeEditorOptions {
  (match diff_word_wrap {
    Inherit => editor_options
    Off => editor_options.with_soft_wrap(false)
  })
  .with_folding(false)
  .with_additional_line_decorations_width(
    if render_markdown_comments {
      diff_markdown_comment_lane_reserved_px
    } else {
      0
    },
  )
  .with_handle_mouse_wheel(handle_mouse_wheel)
}

///|
fn new_diff_editor_model_pair_commit_barrier() -> DiffEditorModelPairCommitBarrier {
  { is_committing: false, committed_generation: 0, }
}

///|
fn DiffEditorEditors::create(
  original_host : @rdom.Element,
  modified_host : @rdom.Element,
  services? : @code_widget.CodeEditorServices,
  editor_options : @code_widget.CodeEditorOptions,
  diff_word_wrap : DiffWordWrap,
  layout : DiffEditorLayout,
  render_markdown_comments : Bool,
  handle_mouse_wheel : Bool,
) -> DiffEditorEditors {
  let (shared_services, owned_services) = match services {
    Some(services) => (services, None)
    None => {
      let services = @code_widget.CodeEditorServices()
      (services, Some(services))
    }
  }
  let pane_options = diff_pane_options(
    editor_options, diff_word_wrap, render_markdown_comments, handle_mouse_wheel,
  )
  let editors : DiffEditorEditors = {
    original: @code_widget.CodeEditorWidget::create(
      original_host,
      services=shared_services,
      options=pane_options,
      contributions=@code_widget.CodeEditorContributionDescriptors::diff_pane(),
    ),
    modified: @code_widget.CodeEditorWidget::create(
      modified_host,
      services=shared_services,
      options=pane_options,
      contributions=@code_widget.CodeEditorContributionDescriptors::diff_pane(),
    ),
    owned_services,
    model_pair_commit: new_diff_editor_model_pair_commit_barrier(),
    disposed: false,
  }
  // Apply the initial policy before either kernel ever receives a model. This
  // also covers explicit Inline widgets mounted under display:none, where no
  // positive-size layout transaction will run until much later.
  editors.sync_markdown_comment_presentations(layout, render_markdown_comments)
  editors
}

///|
fn DiffEditorEditors::same_model(
  self : DiffEditorEditors,
  model : DiffEditorModelData?,
) -> Bool {
  match (self.original.get_model(), self.modified.get_model(), model) {
    (None, None, None) => true
    (Some(current_original), Some(current_modified), Some(next)) =>
      current_original.same(next.original) &&
      current_modified.same(next.modified)
    _ => false
  }
}

///|
fn DiffEditorEditors::set_model(
  self : DiffEditorEditors,
  model : DiffEditorModelData?,
) -> Unit {
  if self.disposed {
    return
  }
  if self.model_pair_commit.is_committing {
    // Diff-level callbacks are observers of the transaction, never a second
    // model-pair owner. Reject accidental internal reentry instead of adding a
    // scheduler or a second pair queue.
    return
  }
  if self.same_model(model) {
    return
  }
  commit_diff_editor_model_pair_transaction(self.model_pair_commit, () => {
    commit_diff_editor_model_pair(
      self.model_pair_commit,
      model,
      model => self.original.set_model(model),
      model => self.modified.set_model(model),
    )
  })
}

///|
fn commit_diff_editor_model_pair_transaction(
  barrier : DiffEditorModelPairCommitBarrier,
  body : () -> Unit,
) -> Unit {
  if barrier.is_committing {
    return
  }
  barrier.is_committing = true
  body()
  barrier.is_committing = false
}

///|
fn commit_diff_editor_model_pair(
  barrier : DiffEditorModelPairCommitBarrier,
  model : DiffEditorModelData?,
  set_original : (@model.TextModel?) -> Unit,
  set_modified : (@model.TextModel?) -> Unit,
) -> Unit {
  match model {
    Some(model) => {
      set_original(Some(model.original))
      set_modified(Some(model.modified))
    }
    None => {
      set_original(None)
      set_modified(None)
    }
  }
  // This is the commit publication point: both synchronous setters have
  // returned while the barrier remains closed to observers.
  barrier.committed_generation += 1
}

///|
fn DiffEditorEditors::is_committing_model_pair(
  self : DiffEditorEditors,
) -> Bool {
  self.model_pair_commit.is_committing
}

///|
fn DiffEditorEditors::committed_model_generation(
  self : DiffEditorEditors,
) -> Int {
  self.model_pair_commit.committed_generation
}

///|
fn DiffEditorEditors::update_options(
  self : DiffEditorEditors,
  editor_options : @code_widget.CodeEditorOptions,
  diff_word_wrap : DiffWordWrap,
  layout : DiffEditorLayout,
  render_markdown_comments : Bool,
  handle_mouse_wheel : Bool,
) -> Unit {
  if self.disposed {
    return
  }
  let pane_options = diff_pane_options(
    editor_options, diff_word_wrap, render_markdown_comments, handle_mouse_wheel,
  )
  // Pinned DiffEditorEditors always updates both kernels. Inline's clipped
  // original must never wrap: deleted text wraps with the modified editor and
  // paired original ViewZones supply the continuation height.
  let original_options = if layout == Inline {
    pane_options.with_soft_wrap(false)
  } else {
    pane_options
  }
  self.original.update_host_options(original_options)
  self.modified.update_host_options(pane_options)
}

///|
/// Rich Markdown comments are ordinary pane contributions in SideBySide. In
/// Inline the modified pane remains the presentation surface, while the
/// clipped original stays a real source/line-number editor with no rich DOM.
fn DiffEditorEditors::sync_markdown_comment_presentations(
  self : DiffEditorEditors,
  layout : DiffEditorLayout,
  enabled : Bool,
) -> Unit {
  if self.disposed {
    return
  }
  self.original.set_markdown_comment_presentation_enabled(
    enabled && layout == SideBySide,
  )
  self.modified.set_markdown_comment_presentation_enabled(enabled)
}

///|
fn DiffEditorEditors::layout(
  self : DiffEditorEditors,
  _layout : DiffEditorLayout,
) -> Unit {
  if !self.disposed {
    // Both panes expose current geometry before either completion callback can
    // reconcile zones. Painting them here also avoids a second native frame
    // when the host's drag already runs in the shared coordinator.
    self.original.layout(postpone_rendering=true)
    self.modified.layout(postpone_rendering=true)
    self.original.render()
    self.modified.render()
  }
}

///|
fn DiffEditorEditors::focus(self : DiffEditorEditors) -> Unit {
  if !self.disposed {
    self.modified.focus()
  }
}

///|
fn DiffEditorEditors::dispose(self : DiffEditorEditors) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.original.dispose()
  self.modified.dispose()
  match self.owned_services {
    Some(services) => services.dispose()
    None => ()
  }
}
