///|
/// Geometry snapshots, independent of DOM, PDF.js and device pixel density.
priv struct Rect {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq)

///|
priv struct Point {
  x : Double
  y : Double
}

///|
fn Rect::intersection(self : Rect, other : Rect) -> Rect? {
  let x = Double::max(self.x, other.x)
  let y = Double::max(self.y, other.y)
  let width = Double::min(self.x + self.width, other.x + other.width) - x
  let height = Double::min(self.y + self.height, other.y + other.height) - y
  if width > 0 && height > 0 {
    Some({ x, y, width, height, })
  } else {
    None
  }
}

///|
fn Rect::contains(self : Rect, point : Point, inclusive~ : Bool) -> Bool {
  point.x >= self.x &&
  point.y >= self.y &&
  (if inclusive {
    point.x <= self.x + self.width && point.y <= self.y + self.height
  } else {
    point.x < self.x + self.width && point.y < self.y + self.height
  })
}

///|
fn Rect::clamp_point(self : Rect, point : Point) -> Point {
  {
    x: Double::max(self.x, Double::min(self.x + self.width, point.x)),
    y: Double::max(self.y, Double::min(self.y + self.height, point.y)),
  }
}

///|
/// A four-CSS-pixel threshold distinguishes clicks from free selection. Once
/// dragging begins it stays a drag, even when the pointer returns to its origin.
fn drag_rect(start : Point, end : Point, selecting~ : Bool) -> Rect? {
  let dx = end.x - start.x
  let dy = end.y - start.y
  if selecting || dx * dx + dy * dy >= 16 {
    Some({
      x: Double::min(start.x, end.x),
      y: Double::min(start.y, end.y),
      width: dx.abs(),
      height: dy.abs(),
    })
  } else {
    None
  }
}

///|
/// Map a subrectangle between two coordinate spaces with independent X/Y scale.
fn Rect::mapped(self : Rect, from~ : Rect, to~ : Rect) -> Rect {
  let sx = to.width / from.width
  let sy = to.height / from.height
  {
    x: to.x + (self.x - from.x) * sx,
    y: to.y + (self.y - from.y) * sy,
    width: self.width * sx,
    height: self.height * sy,
  }
}

///|
fn within_pixel_limit(rect : Rect, scale : Double) -> Bool {
  let width = @math.ceil(rect.width * scale)
  let height = @math.ceil(rect.height * scale)
  width > 0 &&
  height > 0 &&
  width * height <= 16777216 &&
  width <= 16384 &&
  height <= 16384
}

///|
fn png_within_limit(url : String) -> Bool {
  // Canvas exports padded base64; retain the conservative 5 MiB estimate.
  (url.length() - 22).to_double() * 3 / 4 <= 5 * 1024 * 1024
}
