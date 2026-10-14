///|
/// Geometry snapshots, independent of DOM, PDF.js and device pixel density.
pub(all) struct Rect {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
pub(all) struct Point {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
pub fn Rect::intersection(self : Rect, other : Rect) -> Rect? {
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
pub fn Rect::translated(self : Rect, offset : Point) -> Rect {
  { ..self, x: self.x + offset.x, y: self.y + offset.y, }
}

///|
pub fn Rect::contains(self : Rect, point : Point, inclusive~ : Bool) -> Bool {
  point.x >= self.x &&
  point.y >= self.y &&
  (if inclusive {
    point.x <= self.x + self.width && point.y <= self.y + self.height
  } else {
    point.x < self.x + self.width && point.y < self.y + self.height
  })
}

///|
pub fn Rect::clamp_point(self : Rect, point : Point) -> Point {
  {
    x: Double::max(self.x, Double::min(self.x + self.width, point.x)),
    y: Double::max(self.y, Double::min(self.y + self.height, point.y)),
  }
}

///|
/// A four-CSS-pixel threshold distinguishes clicks from free selection. Once
/// dragging begins it stays a drag, even when the pointer returns to its origin.
pub fn drag_rect(start : Point, end : Point, selecting~ : Bool) -> Rect? {
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
pub fn Rect::mapped(self : Rect, from~ : Rect, to~ : Rect) -> Rect {
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
pub struct Output {
  scale : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
/// Each density is the backing canvas's pixel/CSS ratio on one axis.
pub fn output_size(rect : Rect, densities : Array[Double]) -> Output? {
  guard densities is [first, .. rest] else { return None }
  let scale = rest.fold(init=first, Double::max)
  let width = @math.ceil(rect.width * scale)
  let height = @math.ceil(rect.height * scale)
  if width > 0 &&
    height > 0 &&
    width * height <= 16777216 &&
    width <= 16384 &&
    height <= 16384 {
    Some({ scale, width, height, })
  } else {
    None
  }
}

///|
pub fn png_within_limit(url : String) -> Bool {
  // Canvas exports padded base64; retain the conservative 5 MiB estimate.
  (url.length() - 22).to_double() * 3 / 4 <= 5 * 1024 * 1024
}

///|
pub(all) struct LinearTransform {
  a : Double
  b : Double
  c : Double
  d : Double
} derive(Eq, Debug)

///|
pub(all) struct LayerTransform {
  linear : LinearTransform
  opacity : Double
}

///|
pub struct BitmapPlacement {
  opacity : Double
  linear : LinearTransform
  origin : Point
} derive(Eq, Debug)

///|
/// The browser supplies the cumulative CSS linear transform and measured bounds.
/// Recover the origin from the four transformed corners (including rotation and
/// reflection); translation and transform-origin are already in the bounds.
pub fn bitmap_placement(
  layers : Array[LayerTransform],
  bounds : Rect,
  css_size : Point,
  pixels : Point,
  selection : Rect,
  scale : Double,
) -> BitmapPlacement {
  let mut linear : LinearTransform = { a: 1, b: 0, c: 0, d: 1, }
  let mut opacity = 1.0
  for layer in layers {
    let m = layer.linear
    linear = {
      a: m.a * linear.a + m.c * linear.b,
      b: m.b * linear.a + m.d * linear.b,
      c: m.a * linear.c + m.c * linear.d,
      d: m.b * linear.c + m.d * linear.d,
    }
    opacity *= layer.opacity
  }
  let x = bounds.x -
    Double::min(
      0,
      Double::min(
        linear.a * css_size.x,
        Double::min(
          linear.c * css_size.y,
          linear.a * css_size.x + linear.c * css_size.y,
        ),
      ),
    )
  let y = bounds.y -
    Double::min(
      0,
      Double::min(
        linear.b * css_size.x,
        Double::min(
          linear.d * css_size.y,
          linear.b * css_size.x + linear.d * css_size.y,
        ),
      ),
    )
  let sx = css_size.x / pixels.x * scale
  let sy = css_size.y / pixels.y * scale
  {
    opacity,
    linear: {
      a: linear.a * sx,
      b: linear.b * sx,
      c: linear.c * sy,
      d: linear.d * sy,
    },
    origin: { x: (x - selection.x) * scale, y: (y - selection.y) * scale, },
  }
}

///|
pub extend Rect with Eq::{equal, not_equal}

///|
pub extend Point with Eq::{equal, not_equal}

///|
pub extend Output with Eq::{equal, not_equal}

///|
pub extend LinearTransform with Eq::{equal, not_equal}

///|
pub extend BitmapPlacement with Eq::{equal, not_equal}

///|
pub extend Rect with @debug.Debug::{to_repr}

///|
pub extend Point with @debug.Debug::{to_repr}

///|
pub extend Output with @debug.Debug::{to_repr}

///|
pub extend LinearTransform with @debug.Debug::{to_repr}

///|
pub extend BitmapPlacement with @debug.Debug::{to_repr}
