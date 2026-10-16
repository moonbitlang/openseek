///|
fn finish_capture(
  url : String,
  identity : String,
  pieces : Array[CapturePiece],
  rotation : Int32,
  text : String?,
  failure~ : String,
  too_large~ : String,
  selected? : @selection.Rect,
) -> Result[Capture, String] {
  guard url.has_prefix("data:image/png;base64,") else { return Err(failure) }
  guard @selection.png_within_limit(url) else { return Err(too_large) }
  let document = @json.parse(identity) catch { _ => return Err(failure) }
  let regions : Array[Region] = []
  let source_regions : Array[Json] = []
  for piece in pieces {
    let crop = if selected is Some(selected) {
      match piece.crop.intersection(selected) {
        Some(crop) => crop
        None => continue
      }
    } else {
      piece.crop
    }
    let page = piece.page
    let bounds = piece.page_bounds
    let normalized = crop.mapped(from=bounds, to={
      x: 0,
      y: 0,
      width: 1,
      height: 1,
    })
    regions.push({
      page,
      x: normalized.x,
      y: normalized.y,
      width: normalized.width,
      height: normalized.height,
    })
    guard piece.pdf_start is Some(start) else { return Err(failure) }
    guard piece.pdf_end is Some(end) else { return Err(failure) }
    source_regions.push({
      "page": Json(page),
      "geometry": {
        "space": "pdf-page-user-space",
        "unit": "user-unit",
        "bbox": [
          Json(Double::min(start[0], end[0])),
          Json(Double::min(start[1], end[1])),
          Json(Double::max(start[0], end[0])),
          Json(Double::max(start[1], end[1])),
        ],
      },
    })
  }
  Ok({
    url,
    source: { "document": document, "regions": Json(source_regions) },
    regions,
    rotation,
    text,
  })
}
