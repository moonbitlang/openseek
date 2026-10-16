///|
pub(all) enum Format {
  Word
  Excel
  Pdf
} derive(Eq)

///|
pub fn Format::name(self : Format) -> String {
  match self {
    Word => "docx"
    Excel => "xlsx"
    Pdf => "pdf"
  }
}

///|
/// Each rectangle belongs to a rendered page or worksheet, rather than the
/// viewport, so feedback can be measured again after scrolling and zooming.
pub(all) struct Region {
  index : Int32
  page : Int32?
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq)

///|
pub(all) struct Capture {
  format : Format
  url : String
  source : Json
  regions : Array[Region]
  rotation : Int32?
  text : String?
  sheet : String?
  range : String?
} derive(Eq)

///|
fn from_pdf(capture : @pdf_capture.Capture) -> Capture {
  {
    format: Pdf,
    url: capture.url,
    source: capture.source,
    regions: capture.regions.map(region => {
      index: region.page - 1,
      page: Some(region.page),
      x: region.x,
      y: region.y,
      width: region.width,
      height: region.height,
    }),
    rotation: Some(capture.rotation),
    text: capture.text,
    sheet: None,
    range: None,
  }
}

///|
pub fn Capture::selection_rects(
  self : Capture,
  surface : @dom.Element,
) -> Array[@dom.DOMRect] {
  let host = @js.Value::cast_from(surface)
  let nodes = elements(
    host,
    if self.format == Word {
      ".word-page"
    } else {
      "section[data-sheet]"
    },
  )
  self.regions.filter_map(region => {
    let element = if self.format == Pdf {
      region.page.bind(page => query(host, ".page[data-page-number='\{page}']"))
    } else {
      nodes.get(region.index)
    }
    guard element is Some(element) else { return None }
    let b = bounds(element)
    guard b.width > 0 && b.height > 0 else { return None }
    let rect = if self.rotation is Some(original) {
      let current : @js.Nullable[@js.Value] = host.get_with_string(
        "__officeViewerPdf",
      )
      guard current.to_option() is Some(session) else { return None }
      let viewer : @js.Value = session.get_with_string("viewer")
      let rotation : Int32 = viewer.get_with_string("pagesRotation")
      let pdf_region : @pdf_capture.Region = {
        page: region.page.unwrap_or(region.index + 1),
        x: region.x,
        y: region.y,
        width: region.width,
        height: region.height,
      }
      let r = pdf_region.rotated((rotation - original + 360) % 360)
      { x: r.x, y: r.y, width: r.width, height: r.height, }
    } else {
      { x: region.x, y: region.y, width: region.width, height: region.height, }
    }
    Some(
      @js.globalThis.new_with_string("DOMRect", [
        b.x + rect.x * b.width,
        b.y + rect.y * b.height,
        rect.width * b.width,
        rect.height * b.height,
      ]),
    )
  })
}

///|
pub extend Format with Eq::{equal, not_equal}

///|
pub extend Region with Eq::{equal, not_equal}

///|
pub extend Capture with Eq::{equal, not_equal}
