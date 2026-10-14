///|
/// Normalized page coordinates keep feedback attached through scrolling and zoom.
pub(all) struct Region {
  page : Int32
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq)

///|
pub(all) struct Capture {
  url : String
  // PDF identity and geometry in unrotated PDF user space, independent of zoom.
  source : Json
  regions : Array[Region]
  rotation : Int32
  text : String?
} derive(Eq)

///|
pub extend Region with Eq::{equal, not_equal}

///|
pub extend Capture with Eq::{equal, not_equal}

///|
/// Rotate normalized page coordinates clockwise with the displayed PDF page.
pub fn Region::rotated(self : Region, degrees : Int32) -> Region {
  match degrees {
    90 =>
      {
        ..self,
        x: 1.0 - self.y - self.height,
        y: self.x,
        width: self.height,
        height: self.width,
      }
    180 =>
      { ..self, x: 1.0 - self.x - self.width, y: 1.0 - self.y - self.height, }
    270 =>
      {
        ..self,
        x: self.y,
        y: 1.0 - self.x - self.width,
        width: self.height,
        height: self.width,
      }
    _ => self
  }
}
