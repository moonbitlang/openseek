// Ported from `vscode/src/vs/base/common/scrollable.ts` and
// `vscode/src/vs/editor/common/viewLayout/viewLayout.ts` at
// checked-in source.

///|
pub(all) struct ScrollDimensions {
  width : Double
  scroll_width : Double
  height : Double
  scroll_height : Double
} derive(Eq, Debug)

///|
pub(all) struct ScrollDimensionsUpdate {
  width : Double?
  scroll_width : Double?
  height : Double?
  scroll_height : Double?
} derive(Eq, Debug)

///|
pub(all) struct ScrollPosition {
  scroll_left : Double
  scroll_top : Double
} derive(Eq, Debug)

///|
pub(all) struct ScrollPositionUpdate {
  scroll_left : Double?
  scroll_top : Double?
} derive(Eq, Debug)

///|
pub(all) struct SmoothScrollPosition {
  scroll_left : Double
  scroll_top : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
/// Monaco `ScrollEvent` plus the compatibility facts existing viewer callers
/// consume. Old/new geometry and all six change flags are exact source data.
pub(all) struct ScrollChange {
  position : ScrollPosition
  delta_left : Double
  delta_top : Double
  left_changed : Bool
  top_changed : Bool
  dimensions_changed : Bool
  in_smooth_scrolling : Bool
  old_width : Double
  old_scroll_width : Double
  old_scroll_left : Double
  width : Double
  scroll_width : Double
  scroll_left : Double
  old_height : Double
  old_scroll_height : Double
  old_scroll_top : Double
  height : Double
  scroll_height : Double
  scroll_top : Double
  width_changed : Bool
  scroll_width_changed : Bool
  scroll_left_changed : Bool
  height_changed : Bool
  scroll_height_changed : Bool
  scroll_top_changed : Bool
} derive(Eq, Debug)

///|
/// Complete Monaco `ScrollState` (`scrollable.ts:43-179`). Raw positions are
/// retained before validation so a later dimension expansion can recover a
/// position that was temporarily clamped.
pub struct ScrollState {
  force_integer_values : Bool
  raw_scroll_left : Double
  raw_scroll_top : Double
  width : Double
  scroll_width : Double
  scroll_left : Double
  height : Double
  scroll_height : Double
  scroll_top : Double
} derive(Eq, Debug)

///|
pub fn ScrollState::ScrollState(
  force_integer_values~ : Bool,
  width : Double,
  scroll_width : Double,
  scroll_left : Double,
  height : Double,
  scroll_height : Double,
  scroll_top : Double,
) -> ScrollState {
  let mut width = width
  let mut scroll_width = scroll_width
  let mut scroll_left = scroll_left
  let mut height = height
  let mut scroll_height = scroll_height
  let mut scroll_top = scroll_top
  if force_integer_values {
    width = truncate_double(width)
    scroll_width = truncate_double(scroll_width)
    scroll_left = truncate_double(scroll_left)
    height = truncate_double(height)
    scroll_height = truncate_double(scroll_height)
    scroll_top = truncate_double(scroll_top)
  }
  let raw_scroll_left = scroll_left
  let raw_scroll_top = scroll_top
  if width < 0.0 {
    width = 0.0
  }
  if scroll_left + width > scroll_width {
    scroll_left = scroll_width - width
  }
  if scroll_left < 0.0 {
    scroll_left = 0.0
  }
  if height < 0.0 {
    height = 0.0
  }
  if scroll_top + height > scroll_height {
    scroll_top = scroll_height - height
  }
  if scroll_top < 0.0 {
    scroll_top = 0.0
  }
  {
    force_integer_values,
    raw_scroll_left,
    raw_scroll_top,
    width,
    scroll_width,
    scroll_left,
    height,
    scroll_height,
    scroll_top,
  }
}

///|
pub fn ScrollState::equals(self : ScrollState, other : ScrollState) -> Bool {
  self.raw_scroll_left == other.raw_scroll_left &&
  self.raw_scroll_top == other.raw_scroll_top &&
  self.width == other.width &&
  self.scroll_width == other.scroll_width &&
  self.scroll_left == other.scroll_left &&
  self.height == other.height &&
  self.scroll_height == other.scroll_height &&
  self.scroll_top == other.scroll_top
}

///|
pub fn ScrollState::with_scroll_dimensions(
  self : ScrollState,
  update : ScrollDimensionsUpdate,
  use_raw_scroll_positions : Bool,
) -> ScrollState {
  ScrollState(
    force_integer_values=self.force_integer_values,
    update.width.unwrap_or(self.width),
    update.scroll_width.unwrap_or(self.scroll_width),
    if use_raw_scroll_positions {
      self.raw_scroll_left
    } else {
      self.scroll_left
    },
    update.height.unwrap_or(self.height),
    update.scroll_height.unwrap_or(self.scroll_height),
    if use_raw_scroll_positions {
      self.raw_scroll_top
    } else {
      self.scroll_top
    },
  )
}

///|
pub fn ScrollState::with_scroll_position(
  self : ScrollState,
  update : ScrollPositionUpdate,
) -> ScrollState {
  ScrollState(
    force_integer_values=self.force_integer_values,
    self.width,
    self.scroll_width,
    update.scroll_left.unwrap_or(self.raw_scroll_left),
    self.height,
    self.scroll_height,
    update.scroll_top.unwrap_or(self.raw_scroll_top),
  )
}

///|
fn ScrollState::smooth_position(self : ScrollState) -> SmoothScrollPosition {
  {
    scroll_left: self.scroll_left,
    scroll_top: self.scroll_top,
    width: self.width,
    height: self.height,
  }
}

///|
pub fn ScrollState::create_scroll_event(
  self : ScrollState,
  previous : ScrollState,
  in_smooth_scrolling : Bool,
) -> ScrollChange {
  let width_changed = self.width != previous.width
  let scroll_width_changed = self.scroll_width != previous.scroll_width
  let scroll_left_changed = self.scroll_left != previous.scroll_left
  let height_changed = self.height != previous.height
  let scroll_height_changed = self.scroll_height != previous.scroll_height
  let scroll_top_changed = self.scroll_top != previous.scroll_top
  {
    position: { scroll_left: self.scroll_left, scroll_top: self.scroll_top, },
    delta_left: self.scroll_left - previous.scroll_left,
    delta_top: self.scroll_top - previous.scroll_top,
    left_changed: scroll_left_changed,
    top_changed: scroll_top_changed,
    dimensions_changed: width_changed ||
    scroll_width_changed ||
    height_changed ||
    scroll_height_changed,
    in_smooth_scrolling,
    old_width: previous.width,
    old_scroll_width: previous.scroll_width,
    old_scroll_left: previous.scroll_left,
    width: self.width,
    scroll_width: self.scroll_width,
    scroll_left: self.scroll_left,
    old_height: previous.height,
    old_scroll_height: previous.scroll_height,
    old_scroll_top: previous.scroll_top,
    height: self.height,
    scroll_height: self.scroll_height,
    scroll_top: self.scroll_top,
    width_changed,
    scroll_width_changed,
    scroll_left_changed,
    height_changed,
    scroll_height_changed,
    scroll_top_changed,
  }
}

///|
pub struct SmoothScrollingUpdate {
  scroll_left : Double
  scroll_top : Double
  is_done : Bool
} derive(Eq, Debug)

///|
pub fn SmoothScrollingUpdate::SmoothScrollingUpdate(
  scroll_left : Double,
  scroll_top : Double,
  is_done : Bool,
) -> SmoothScrollingUpdate {
  { scroll_left, scroll_top, is_done, }
}

///|
/// Monaco `SmoothScrollingOperation` (`scrollable.ts:431-514`).
pub struct SmoothScrollingOperation {
  from : SmoothScrollPosition
  mut to : SmoothScrollPosition
  duration : Double
  start_time : Double
  mut animation_frame_disposable : @base_common.Disposable?
  mut scroll_left_animation : (Double) -> Double
  mut scroll_top_animation : (Double) -> Double
}

///|
pub fn SmoothScrollingOperation::SmoothScrollingOperation(
  from : SmoothScrollPosition,
  to : SmoothScrollPosition,
  start_time : Double,
  duration : Double,
) -> SmoothScrollingOperation {
  let operation : SmoothScrollingOperation = {
    from,
    to,
    duration,
    start_time,
    animation_frame_disposable: None,
    scroll_left_animation: completion => completion,
    scroll_top_animation: completion => completion,
  }
  operation.init_animations()
  operation
}

///|
fn SmoothScrollingOperation::init_animations(
  self : SmoothScrollingOperation,
) -> Unit {
  self.scroll_left_animation = init_scroll_animation(
    self.from.scroll_left,
    self.to.scroll_left,
    self.to.width,
  )
  self.scroll_top_animation = init_scroll_animation(
    self.from.scroll_top,
    self.to.scroll_top,
    self.to.height,
  )
}

///|
/// `_initAnimation` (`scrollable.ts:458-473`), including the strict `> 2.5`
/// boundary, 0.75 viewport stops, and 0.33 composed cut.
fn init_scroll_animation(
  from : Double,
  to : Double,
  viewport_size : Double,
) -> (Double) -> Double {
  let delta = (from - to).abs()
  if delta > 2.5 * viewport_size {
    let (stop1, stop2) = if from < to {
      (from + 0.75 * viewport_size, to - 0.75 * viewport_size)
    } else {
      (from - 0.75 * viewport_size, to + 0.75 * viewport_size)
    }
    create_composed(
      create_ease_out_cubic(from, stop1),
      create_ease_out_cubic(stop2, to),
      0.33,
    )
  } else {
    create_ease_out_cubic(from, to)
  }
}

///|
pub fn SmoothScrollingOperation::dispose(
  self : SmoothScrollingOperation,
) -> Unit {
  if self.animation_frame_disposable is Some(disposable) {
    disposable.dispose()
    self.animation_frame_disposable = None
  }
}

///|
pub fn SmoothScrollingOperation::accept_scroll_dimensions(
  self : SmoothScrollingOperation,
  state : ScrollState,
) -> Unit {
  let target = state.with_scroll_position({
    scroll_left: Some(self.to.scroll_left),
    scroll_top: Some(self.to.scroll_top),
  })
  self.to = target.smooth_position()
  self.init_animations()
}

///|
pub fn SmoothScrollingOperation::tick_at(
  self : SmoothScrollingOperation,
  now : Double,
) -> SmoothScrollingUpdate {
  let completion = (now - self.start_time) / self.duration
  if completion < 1.0 {
    {
      scroll_left: (self.scroll_left_animation)(completion),
      scroll_top: (self.scroll_top_animation)(completion),
      is_done: false,
    }
  } else {
    {
      scroll_left: self.to.scroll_left,
      scroll_top: self.to.scroll_top,
      is_done: true,
    }
  }
}

///|
pub fn SmoothScrollingOperation::combine(
  self : SmoothScrollingOperation,
  from : SmoothScrollPosition,
  to : SmoothScrollPosition,
  duration : Double,
  now : Double,
) -> SmoothScrollingOperation {
  let _ = self
  SmoothScrollingOperation::start(from, to, duration, now)
}

///|
pub fn SmoothScrollingOperation::start(
  from : SmoothScrollPosition,
  to : SmoothScrollPosition,
  duration : Double,
  now : Double,
) -> SmoothScrollingOperation {
  // Pretend the animation already started for a quicker response.
  SmoothScrollingOperation(from, to, now - 10.0, duration + 10.0)
}

///|
fn create_ease_out_cubic(from : Double, to : Double) -> (Double) -> Double {
  let delta = to - from
  completion => from + delta * ease_out_cubic(completion)
}

///|
fn create_composed(
  first : (Double) -> Double,
  second : (Double) -> Double,
  cut : Double,
) -> (Double) -> Double {
  completion => {
    if completion < cut {
      first(completion / cut)
    } else {
      second((completion - cut) / (1.0 - cut))
    }
  }
}

///|
fn ease_in_cubic(value : Double) -> Double {
  value * value * value
}

///|
fn ease_out_cubic(value : Double) -> Double {
  1.0 - ease_in_cubic(1.0 - value)
}

///|
/// Complete Monaco `Scrollable` state machine (`scrollable.ts:225-395`). The
/// scheduler and clock are injected so this package remains DOM/FFI-free.
struct Scrollable {
  mut smooth_scroll_duration : Double
  schedule_at_next_animation_frame : (() -> Unit) -> @base_common.Disposable
  now : () -> Double
  mut state : ScrollState
  mut smooth_scrolling : SmoothScrollingOperation?
  mut operation_generation : Int
  on_scroll_emitter : @base_common.Emitter[ScrollChange]
}

///|
pub fn Scrollable::Scrollable(
  force_integer_values~ : Bool,
  smooth_scroll_duration? : Double = 0.0,
  schedule_at_next_animation_frame? : (() -> Unit) -> @base_common.Disposable = no_animation_scheduler,
  now? : () -> Double = zero_clock,
) -> Scrollable {
  {
    smooth_scroll_duration,
    schedule_at_next_animation_frame,
    now,
    state: ScrollState(force_integer_values~, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    smooth_scrolling: None,
    operation_generation: 0,
    on_scroll_emitter: Emitter(),
  }
}

///|
pub fn Scrollable::on_scroll(
  self : Scrollable,
  listener : (ScrollChange) -> Unit,
) -> @base_common.Disposable {
  self.on_scroll_emitter.event(listener)
}

///|
pub fn Scrollable::dispose(self : Scrollable) -> Unit {
  self.cancel_smooth_scrolling()
  self.on_scroll_emitter.dispose()
}

///|
pub fn Scrollable::set_smooth_scroll_duration(
  self : Scrollable,
  duration : Double,
) -> Unit {
  self.smooth_scroll_duration = duration
}

///|
pub fn Scrollable::validate_scroll_position(
  self : Scrollable,
  update : ScrollPositionUpdate,
) -> ScrollPosition {
  let state = self.state.with_scroll_position(update)
  { scroll_left: state.scroll_left, scroll_top: state.scroll_top, }
}

///|
pub fn Scrollable::dimensions(self : Scrollable) -> ScrollDimensions {
  {
    width: self.state.width,
    scroll_width: self.state.scroll_width,
    height: self.state.height,
    scroll_height: self.state.scroll_height,
  }
}

///|
pub fn Scrollable::set_scroll_dimensions(
  self : Scrollable,
  update : ScrollDimensionsUpdate,
  use_raw_scroll_positions : Bool,
) -> ScrollChange? {
  let new_state = self.state.with_scroll_dimensions(
    update, use_raw_scroll_positions,
  )
  let change = self.set_state(
    new_state,
    in_smooth_scrolling=self.smooth_scrolling is Some(_),
  )
  if self.smooth_scrolling is Some(operation) {
    operation.accept_scroll_dimensions(self.state)
  }
  change
}

///|
pub fn Scrollable::set_dimensions(
  self : Scrollable,
  dimensions : ScrollDimensions,
) -> ScrollChange? {
  self.set_scroll_dimensions(
    {
      width: Some(dimensions.width),
      scroll_width: Some(dimensions.scroll_width),
      height: Some(dimensions.height),
      scroll_height: Some(dimensions.scroll_height),
    },
    true,
  )
}

///|
pub fn Scrollable::future_position(self : Scrollable) -> ScrollPosition {
  match self.smooth_scrolling {
    Some(operation) =>
      {
        scroll_left: operation.to.scroll_left,
        scroll_top: operation.to.scroll_top,
      }
    None => self.position()
  }
}

///|
pub fn Scrollable::position(self : Scrollable) -> ScrollPosition {
  { scroll_left: self.state.scroll_left, scroll_top: self.state.scroll_top, }
}

///|
pub fn Scrollable::set_position_now(
  self : Scrollable,
  update : ScrollPositionUpdate,
) -> ScrollChange? {
  let new_state = self.state.with_scroll_position(update)
  self.cancel_smooth_scrolling()
  self.set_state(new_state, in_smooth_scrolling=false)
}

///|
pub fn Scrollable::set_position(
  self : Scrollable,
  position : ScrollPosition,
) -> ScrollChange? {
  self.set_position_now({
    scroll_left: Some(position.scroll_left),
    scroll_top: Some(position.scroll_top),
  })
}

///|
pub fn Scrollable::set_position_smooth(
  self : Scrollable,
  update : ScrollPositionUpdate,
  reuse_animation? : Bool = false,
) -> Unit {
  if self.smooth_scroll_duration == 0.0 {
    self.set_position_now(update) |> ignore
    return
  }
  match self.smooth_scrolling {
    Some(operation) => {
      let update : ScrollPositionUpdate = {
        scroll_left: Some(
          update.scroll_left.unwrap_or(operation.to.scroll_left),
        ),
        scroll_top: Some(update.scroll_top.unwrap_or(operation.to.scroll_top)),
      }
      let valid_target = self.state
        .with_scroll_position(update)
        .smooth_position()
      if operation.to.scroll_left == valid_target.scroll_left &&
        operation.to.scroll_top == valid_target.scroll_top {
        return
      }
      let new_operation = if reuse_animation {
        SmoothScrollingOperation(
          operation.from,
          valid_target,
          operation.start_time,
          operation.duration,
        )
      } else {
        operation.combine(
          self.state.smooth_position(),
          valid_target,
          self.smooth_scroll_duration,
          (self.now)(),
        )
      }
      operation.dispose()
      self.operation_generation += 1
      self.smooth_scrolling = Some(new_operation)
    }
    None => {
      let valid_target = self.state
        .with_scroll_position(update)
        .smooth_position()
      self.operation_generation += 1
      self.smooth_scrolling = Some(
        SmoothScrollingOperation::start(
          self.state.smooth_position(),
          valid_target,
          self.smooth_scroll_duration,
          (self.now)(),
        ),
      )
    }
  }
  self.schedule_smooth_scrolling_frame()
}

///|
pub fn Scrollable::has_pending_scroll_animation(self : Scrollable) -> Bool {
  self.smooth_scrolling is Some(_)
}

///|
fn Scrollable::schedule_smooth_scrolling_frame(self : Scrollable) -> Unit {
  let generation = self.operation_generation
  let disposable = (self.schedule_at_next_animation_frame)(() => {
    guard self.operation_generation == generation else { return }
    guard self.smooth_scrolling is Some(operation) else { return }
    operation.animation_frame_disposable = None
    self.perform_smooth_scrolling()
  })
  match self.smooth_scrolling {
    Some(operation) if self.operation_generation == generation =>
      operation.animation_frame_disposable = Some(disposable)
    _ => disposable.dispose()
  }
}

///|
fn Scrollable::perform_smooth_scrolling(self : Scrollable) -> Unit {
  guard self.smooth_scrolling is Some(operation) else { return }
  let generation = self.operation_generation
  let update = operation.tick_at((self.now)())
  let new_state = self.state.with_scroll_position({
    scroll_left: Some(update.scroll_left),
    scroll_top: Some(update.scroll_top),
  })
  self.set_state(new_state, in_smooth_scrolling=true) |> ignore
  guard self.operation_generation == generation &&
    self.smooth_scrolling is Some(_) else {
    return
  }
  if update.is_done {
    operation.dispose()
    self.smooth_scrolling = None
    return
  }
  self.schedule_smooth_scrolling_frame()
}

///|
fn Scrollable::set_state(
  self : Scrollable,
  new_state : ScrollState,
  in_smooth_scrolling~ : Bool,
) -> ScrollChange? {
  let old_state = self.state
  if old_state.equals(new_state) {
    return None
  }
  self.state = new_state
  let change = self.state.create_scroll_event(old_state, in_smooth_scrolling)
  self.on_scroll_emitter.fire(change)
  Some(change)
}

///|
fn Scrollable::cancel_smooth_scrolling(self : Scrollable) -> Unit {
  if self.smooth_scrolling is Some(operation) {
    operation.dispose()
  }
  self.operation_generation += 1
  self.smooth_scrolling = None
}

///|
pub fn Scrollable::scroll_by(
  self : Scrollable,
  delta_left? : Double = 0.0,
  delta_top? : Double = 0.0,
) -> ScrollChange? {
  let position = self.position()
  self.set_position_now({
    scroll_left: Some(position.scroll_left + delta_left),
    scroll_top: Some(position.scroll_top + delta_top),
  })
}

///|
/// Monaco `EditorScrollDimensions` (`viewLayout.ts:19-71`).
pub struct EditorScrollDimensions {
  width : Double
  content_width : Double
  scroll_width : Double
  height : Double
  content_height : Double
  scroll_height : Double
} derive(Eq, Debug)

///|
pub fn EditorScrollDimensions::EditorScrollDimensions(
  width : Double,
  content_width : Double,
  height : Double,
  content_height : Double,
) -> EditorScrollDimensions {
  let width = truncate_double(width).max(0.0)
  let content_width = truncate_double(content_width).max(0.0)
  let height = truncate_double(height).max(0.0)
  let content_height = truncate_double(content_height).max(0.0)
  {
    width,
    content_width,
    scroll_width: width.max(content_width),
    height,
    content_height,
    scroll_height: height.max(content_height),
  }
}

///|
pub(all) struct ContentSizeChange {
  old_content_width : Double
  old_content_height : Double
  content_width : Double
  content_height : Double
} derive(Eq, Debug)

///|
/// Complete Monaco `EditorScrollable` (`viewLayout.ts:73-154`).
struct EditorScrollable {
  scrollable : Scrollable
  mut editor_dimensions : EditorScrollDimensions
  content_size_emitter : @base_common.Emitter[ContentSizeChange]
}

///|
pub fn EditorScrollable::EditorScrollable(
  smooth_scroll_duration : Double,
  schedule_at_next_animation_frame : (() -> Unit) -> @base_common.Disposable,
  now : () -> Double,
) -> EditorScrollable {
  {
    scrollable: Scrollable(
      force_integer_values=true,
      smooth_scroll_duration~,
      schedule_at_next_animation_frame~,
      now~,
    ),
    editor_dimensions: EditorScrollDimensions(0.0, 0.0, 0.0, 0.0),
    content_size_emitter: Emitter(),
  }
}

///|
pub fn EditorScrollable::get_scrollable(self : EditorScrollable) -> Scrollable {
  self.scrollable
}

///|
pub fn EditorScrollable::on_did_scroll(
  self : EditorScrollable,
  listener : (ScrollChange) -> Unit,
) -> @base_common.Disposable {
  self.scrollable.on_scroll(listener)
}

///|
pub fn EditorScrollable::on_did_content_size_change(
  self : EditorScrollable,
  listener : (ContentSizeChange) -> Unit,
) -> @base_common.Disposable {
  self.content_size_emitter.event(listener)
}

///|
pub fn EditorScrollable::set_smooth_scroll_duration(
  self : EditorScrollable,
  duration : Double,
) -> Unit {
  self.scrollable.set_smooth_scroll_duration(duration)
}

///|
pub fn EditorScrollable::validate_scroll_position(
  self : EditorScrollable,
  update : ScrollPositionUpdate,
) -> ScrollPosition {
  self.scrollable.validate_scroll_position(update)
}

///|
pub fn EditorScrollable::editor_dimensions(
  self : EditorScrollable,
) -> EditorScrollDimensions {
  self.editor_dimensions
}

///|
pub fn EditorScrollable::dimensions(
  self : EditorScrollable,
) -> ScrollDimensions {
  self.scrollable.dimensions()
}

///|
pub fn EditorScrollable::set_editor_dimensions(
  self : EditorScrollable,
  dimensions : EditorScrollDimensions,
) -> ScrollChange? {
  if self.editor_dimensions == dimensions {
    return None
  }
  let old_dimensions = self.editor_dimensions
  self.editor_dimensions = dimensions
  let change = self.scrollable.set_scroll_dimensions(
    {
      width: Some(dimensions.width),
      scroll_width: Some(dimensions.scroll_width),
      height: Some(dimensions.height),
      scroll_height: Some(dimensions.scroll_height),
    },
    true,
  )
  if old_dimensions.content_width != dimensions.content_width ||
    old_dimensions.content_height != dimensions.content_height {
    self.content_size_emitter.fire({
      old_content_width: old_dimensions.content_width,
      old_content_height: old_dimensions.content_height,
      content_width: dimensions.content_width,
      content_height: dimensions.content_height,
    })
  }
  change
}

///|
pub fn EditorScrollable::future_position(
  self : EditorScrollable,
) -> ScrollPosition {
  self.scrollable.future_position()
}

///|
pub fn EditorScrollable::position(self : EditorScrollable) -> ScrollPosition {
  self.scrollable.position()
}

///|
pub fn EditorScrollable::set_position_now(
  self : EditorScrollable,
  update : ScrollPositionUpdate,
) -> ScrollChange? {
  self.scrollable.set_position_now(update)
}

///|
pub fn EditorScrollable::set_position_smooth(
  self : EditorScrollable,
  update : ScrollPositionUpdate,
) -> Unit {
  self.scrollable.set_position_smooth(update)
}

///|
pub fn EditorScrollable::has_pending_scroll_animation(
  self : EditorScrollable,
) -> Bool {
  self.scrollable.has_pending_scroll_animation()
}

///|
pub fn EditorScrollable::scroll_by(
  self : EditorScrollable,
  delta_left? : Double = 0.0,
  delta_top? : Double = 0.0,
) -> ScrollChange? {
  self.scrollable.scroll_by(delta_left~, delta_top~)
}

///|
pub fn EditorScrollable::dispose(self : EditorScrollable) -> Unit {
  self.scrollable.dispose()
  self.content_size_emitter.dispose()
}

///|
fn truncate_double(value : Double) -> Double {
  // JavaScript's `value | 0` performs ToInt32, not a saturating Double->Int
  // conversion. Keep the modulo/wrap explicit so the common package has the
  // same result on every MoonBit target, including the signed-32-bit edges.
  // NaN and both infinities become zero under ToInt32. Normalize negative zero
  // too, so the retained dimensions have one canonical zero representation.
  javascript_to_int32(value).to_double()
}

///|
fn no_animation_scheduler(_callback : () -> Unit) -> @base_common.Disposable {
  @base_common.Disposable::from(() => ())
}

///|
fn zero_clock() -> Double {
  0.0
}

///|
pub extend ContentSizeChange with Debug::{to_repr}

///|
pub extend ContentSizeChange with Eq::{equal, not_equal}

///|
pub extend EditorScrollDimensions with Debug::{to_repr}

///|
pub extend EditorScrollDimensions with Eq::{equal, not_equal}

///|
pub extend ScrollChange with Debug::{to_repr}

///|
pub extend ScrollChange with Eq::{equal, not_equal}

///|
pub extend ScrollDimensions with Debug::{to_repr}

///|
pub extend ScrollDimensions with Eq::{equal, not_equal}

///|
pub extend ScrollDimensionsUpdate with Debug::{to_repr}

///|
pub extend ScrollDimensionsUpdate with Eq::{equal, not_equal}

///|
pub extend ScrollPosition with Debug::{to_repr}

///|
pub extend ScrollPosition with Eq::{equal, not_equal}

///|
pub extend ScrollPositionUpdate with Debug::{to_repr}

///|
pub extend ScrollPositionUpdate with Eq::{equal, not_equal}

///|
pub extend ScrollState with Debug::{to_repr}

///|
pub extend ScrollState with Eq::{equal, not_equal}

///|
pub extend SmoothScrollPosition with Debug::{to_repr}

///|
pub extend SmoothScrollPosition with Eq::{equal, not_equal}

///|
pub extend SmoothScrollingUpdate with Debug::{to_repr}

///|
pub extend SmoothScrollingUpdate with Eq::{equal, not_equal}
