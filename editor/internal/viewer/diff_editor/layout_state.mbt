///|
/// DOM-independent layout policy shared by the widget and deterministic
/// boundary tests. The requested layout is never mutated by responsive
/// fallback, so a pane that grows from 900px to 901px returns to side-by-side.
pub struct DiffEditorLayoutState {
  mut options : DiffEditorOptions
  mut width : Double
  mut actual_layout : DiffEditorLayout
  mut split_ratio : Double
}

///|
fn DiffEditorLayoutState::DiffEditorLayoutState(
  options : DiffEditorOptions,
) -> DiffEditorLayoutState {
  let state : DiffEditorLayoutState = {
    options,
    width: 0.0,
    actual_layout: options.layout,
    split_ratio: options.split_ratio,
  }
  state
}

///|
fn DiffEditorLayoutState::recompute_actual_layout(
  self : DiffEditorLayoutState,
) -> Unit {
  self.actual_layout = match self.options.layout {
    Inline => Inline
    SideBySide =>
      if self.options.automatic_inline &&
        self.width <= self.options.automatic_inline_width {
        Inline
      } else {
        SideBySide
      }
  }
}

///|
fn DiffEditorLayoutState::layout(
  self : DiffEditorLayoutState,
  width : Double,
) -> Bool {
  let previous = self.actual_layout
  self.width = width.max(0.0)
  self.recompute_actual_layout()
  previous != self.actual_layout
}

///|
fn DiffEditorLayoutState::update_options(
  self : DiffEditorLayoutState,
  options : DiffEditorOptions,
  recompute_layout~ : Bool = true,
) -> Bool {
  let previous = self.actual_layout
  let configured_split_changed = options.split_ratio != self.options.split_ratio
  self.options = options
  if configured_split_changed {
    self.split_ratio = options.split_ratio
  }
  if recompute_layout {
    self.recompute_actual_layout()
  }
  previous != self.actual_layout
}

///|
fn DiffEditorLayoutState::set_split_from_pointer(
  self : DiffEditorLayoutState,
  offset : Double,
) -> Bool {
  if !self.options.sash_enabled || self.width <= 0.0 {
    return false
  }
  let next = (offset / self.width).clamp(min=0.1, max=0.9)
  if next == self.split_ratio {
    return false
  }
  self.split_ratio = next
  true
}

///|
pub fn DiffEditorLayoutState::pane_widths(
  self : DiffEditorLayoutState,
) -> (Double, Double) {
  match self.actual_layout {
    Inline => (0.0, self.width)
    SideBySide => {
      let original = self.width * self.split_ratio
      (original, self.width - original)
    }
  }
}
