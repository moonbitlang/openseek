///|
pub fn PartFingerprint::to_int(self : PartFingerprint) -> Int32 {
  match self {
    None => 0
    ContentWidgets => 1
    OverflowingContentWidgets => 2
    OverflowGuard => 3
    OverlayWidgets => 4
    OverflowingOverlayWidgets => 5
    ScrollableElement => 6
    TextArea => 7
    ViewLines => 8
    Minimap => 9
    ViewLinesGpu => 10
  }
}

///|
fn PartFingerprint::from_int(value : Int32) -> PartFingerprint {
  match value {
    1 => ContentWidgets
    2 => OverflowingContentWidgets
    3 => OverflowGuard
    4 => OverlayWidgets
    5 => OverflowingOverlayWidgets
    6 => ScrollableElement
    7 => TextArea
    8 => ViewLines
    9 => Minimap
    10 => ViewLinesGpu
    _ => None
  }
}

///|
/// `PartFingerprints.write` (viewPart.ts:48-60). Monaco stamps inside each
/// part's constructor; the merged View stamps every part root right after
/// construction (view.mbt).
fn PartFingerprint::write(
  target : @rdom.Element,
  part_id : PartFingerprint,
) -> Unit {
  target.set_attribute("data-mprt", part_id.to_int().to_string())
}

///|
fn PartFingerprint::read(target : @rdom.Element) -> PartFingerprint {
  PartFingerprint::from_int(read_data_mprt(target))
}

///|
/// `collect` (viewPart.ts:62-81): the root-first fingerprint path from
/// `child` up to (excluding) `stop_at`, as bytes mirroring the source's
/// `Uint8Array`. The walk visits elements only (`parentElement`), stopping at
/// the document body like the source.
pub fn PartFingerprint::collect(
  child : @rdom.Element?,
  stop_at : @rdom.Element,
) -> Bytes {
  let result : Array[Byte] = []
  let mut node = child
  while node is Some(el) && !is_document_body(el) {
    if el.is_same_node(stop_at.as_node()) {
      break
    }
    result.push(PartFingerprint::read(el).to_int().to_byte())
    node = parent_element(el)
  }
  Bytes::makei(result.length(), i => result[result.length() - i - 1])
}

///|
/// FFI gap-fills (no `ownerDocument.body` / null-distinguishing
/// `getAttribute` / `parentElement` bindings in the vendored `@rdom`).
extern "js" fn is_document_body(el : @rdom.Element) -> Bool =
  #| (el) => el === el.ownerDocument.body

///|
extern "js" fn read_data_mprt(el : @rdom.Element) -> Int32 =
  #| (el) => {
  #|   const r = el.getAttribute("data-mprt");
  #|   return r === null ? 0 : (parseInt(r, 10) | 0);
  #| }

///|
fn parent_element(el : @rdom.Element) -> @rdom.Element? {
  match el.get_parent_node().to_option() {
    Some(node) => node.to_element()
    None => None
  }
}
