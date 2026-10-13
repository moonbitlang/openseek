// Ported from `vscode/src/vs/base/browser/ui/scrollbar/scrollableElement.ts`
// in the checked-in source, lines 23-152.

///|
#warnings("-unused_field")
priv struct MouseWheelClassifierItem {
  timestamp : Double
  delta_x : Double
  delta_y : Double
  mut score : Double
}

///|
fn MouseWheelClassifierItem::MouseWheelClassifierItem(
  timestamp : Double,
  delta_x : Double,
  delta_y : Double,
) -> MouseWheelClassifierItem {
  { timestamp, delta_x, delta_y, score: 0.0, }
}

///|
struct MouseWheelClassifier {
  capacity : Int32
  memory : Array[MouseWheelClassifierItem]
  mut front : Int32
  mut rear : Int32
}

///|
fn MouseWheelClassifier::MouseWheelClassifier() -> MouseWheelClassifier {
  { capacity: 5, memory: [], front: -1, rear: -1, }
}

///|
pub fn MouseWheelClassifier::is_physical_mouse_wheel(
  self : MouseWheelClassifier,
) -> Bool {
  if self.front == -1 && self.rear == -1 {
    return false
  }
  let mut remaining_influence = 1.0
  let mut score = 0.0
  let mut iteration = 1
  let mut index = self.rear
  while true {
    let influence = if index == self.front {
      remaining_influence
    } else {
      1.0 / (1 << iteration).to_double()
    }
    remaining_influence -= influence
    score += self.memory[index].score * influence
    if index == self.front {
      break
    }
    index = (self.capacity + index - 1) % self.capacity
    iteration += 1
  }
  score <= 0.5
}

///|
pub fn MouseWheelClassifier::accept_standard_wheel_event(
  self : MouseWheelClassifier,
  event : StandardWheelEvent,
) -> Unit {
  let page_zoom_factor = if classifier_is_chrome() {
    classifier_page_zoom_factor()
  } else {
    1.0
  }
  self.accept(
    @base_browser.wall_clock_now_ms(),
    event.delta_x * page_zoom_factor,
    event.delta_y * page_zoom_factor,
  )
}

///|
fn MouseWheelClassifier::accept(
  self : MouseWheelClassifier,
  timestamp : Double,
  delta_x : Double,
  delta_y : Double,
) -> Unit {
  let item = MouseWheelClassifierItem::MouseWheelClassifierItem(
    timestamp, delta_x, delta_y,
  )
  let previous_item : MouseWheelClassifierItem? = if self.front == -1 &&
    self.rear == -1 {
    self.memory.push(item)
    self.front = 0
    self.rear = 0
    None
  } else {
    let previous = self.memory[self.rear]
    self.rear = (self.rear + 1) % self.capacity
    if self.rear == self.front {
      self.front = (self.front + 1) % self.capacity
    }
    if self.rear < self.memory.length() {
      self.memory[self.rear] = item
    } else {
      self.memory.push(item)
    }
    Some(previous)
  }
  item.score = self.compute_score(item, previous_item)
}

///|
fn MouseWheelClassifier::compute_score(
  self : MouseWheelClassifier,
  item : MouseWheelClassifierItem,
  previous_item : MouseWheelClassifierItem?,
) -> Double {
  if item.delta_x.abs() > 0.0 && item.delta_y.abs() > 0.0 {
    return 1.0
  }
  let mut score = 0.5
  if !self.is_almost_int(item.delta_x) || !self.is_almost_int(item.delta_y) {
    score += 0.25
  }
  match previous_item {
    Some(previous) => {
      let abs_delta_x = item.delta_x.abs()
      let abs_delta_y = item.delta_y.abs()
      let abs_previous_delta_x = previous.delta_x.abs()
      let abs_previous_delta_y = previous.delta_y.abs()
      let min_delta_x = abs_delta_x.min(abs_previous_delta_x).max(1.0)
      let min_delta_y = abs_delta_y.min(abs_previous_delta_y).max(1.0)
      let max_delta_x = abs_delta_x.max(abs_previous_delta_x)
      let max_delta_y = abs_delta_y.max(abs_previous_delta_y)
      let is_same_modulo = double_remainder(max_delta_x, min_delta_x) == 0.0 &&
        double_remainder(max_delta_y, min_delta_y) == 0.0
      if is_same_modulo {
        score -= 0.5
      }
    }
    None => ()
  }
  score.max(0.0).min(1.0)
}

///|
fn MouseWheelClassifier::is_almost_int(
  self : MouseWheelClassifier,
  value : Double,
) -> Bool {
  let _ = self
  let epsilon = 2.220446049250313e-16 * 100.0
  (value.round() - value).abs() < 0.01 + epsilon
}

///|
let mouse_wheel_classifier_instance : MouseWheelClassifier = MouseWheelClassifier()

///|
pub fn global_mouse_wheel_classifier() -> MouseWheelClassifier {
  mouse_wheel_classifier_instance
}

///|
extern "js" fn double_remainder(left : Double, right : Double) -> Double =
  #| (left, right) => left % right

///|
extern "js" fn classifier_is_chrome() -> Bool =
  #| () => !!globalThis.navigator?.userAgentData?.brands?.some(
  #|   brand => brand.brand === 'Google Chrome'
  #| ) || /Chrome\//.test(globalThis.navigator?.userAgent ?? '')

///|
// The viewer has no configured browser zoom level, so VS Code's
// `getZoomFactor(window)` resolves to its source default of 1.
extern "js" fn classifier_page_zoom_factor() -> Double =
  #| () => 1
