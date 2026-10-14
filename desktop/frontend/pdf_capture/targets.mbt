///|
/// The page cache owns only PDF.js/DOM lifetimes. Text grouping and hit testing
/// run in MoonBit; a ready page stores a closure over typed, page-relative data.
extern "js" fn create_targets(
  surface_id : String,
  changed : () -> Unit,
  index_page : (
    FixedArray[@js.Value],
    @js.Nullable[@js.Value],
    @js.Value,
    Double,
  ) -> (Double, Double, @js.Value) -> @js.Nullable[@js.Value],
) -> @js.Value =
  #| (surfaceId, changed, indexPage) => {
  #|   const host = document.getElementById(surfaceId), session = host.__officeViewerPdf;
  #|   const pages = new Map();
  #|   let alive = true;
  #|   const prepare = page => {
  #|     if (pages.has(page)) return pages.get(page);
  #|     const slot = { at: null };
  #|     pages.set(page, slot);
  #|     const number = Number(page.dataset.pageNumber);
  #|     (async () => {
  #|       const mapping = await session.mapping(number);
  #|       if (!mapping) { if (pages.get(page) === slot) pages.delete(page); return; }
  #|       const tree = await mapping.data.page.getStructTree().catch(() => null);
  #|       if (!alive || !page.isConnected || pages.get(page) !== slot) return;
  #|       const entries = mapping.entries.filter(e => e.div.isConnected).map(e =>
  #|         ({ item: e.item, index: e.index, markedId: e.markedId, bounds: e.div.getBoundingClientRect() }));
  #|       slot.at = indexPage(entries, tree, page.getBoundingClientRect(), mapping.view.viewport.rotation);
  #|       changed();
  #|     })().catch(() => { if (pages.get(page) === slot) pages.delete(page); });
  #|     return slot;
  #|   };
  #|   const rendered = event => {
  #|     const page = host.querySelector(`.page[data-page-number='${event.pageNumber}']`);
  #|     if (page) { pages.delete(page); prepare(page); }
  #|   };
  #|   session.bus.on('textlayerrendered', rendered);
  #|   for (const layer of host.querySelectorAll('.textLayer')) {
  #|     const page = layer.closest('.page');
  #|     if (page && layer.querySelector('span')) prepare(page);
  #|   }
  #|   return {
  #|     at(x,y) {
  #|       // Browser hit testing locates the page without measuring a long
  #|       // document on each pointer movement.
  #|       const page = document.elementFromPoint(x,y)?.closest('.page');
  #|       if (!page || !host.contains(page)) return null;
  #|       return prepare(page).at?.(x, y, page.getBoundingClientRect()) ?? null;
  #|     },
  #|     dispose() { alive = false; pages.clear(); session.bus.off('textlayerrendered', rendered); }
  #|   };
  #| }

///|
fn read_structure(value : @js.Value) -> @selection.Structure {
  let kind : @js.Optional[String] = value.get_with_string("type")
  let role : @js.Optional[String] = value.get_with_string("role")
  let id : @js.Optional[String] = value.get_with_string("id")
  let children : @js.Optional[FixedArray[@js.Value]] = value.get_with_string(
    "children",
  )
  {
    role: role.to_option(),
    content_id: if kind.to_option() == Some("content") {
      id.to_option()
    } else {
      None
    },
    children: children
    .to_option()
    .map(xs => xs.iter().map(read_structure).collect())
    .unwrap_or([]),
  }
}

///|
fn index_page(
  values : FixedArray[@js.Value],
  tree : @js.Nullable[@js.Value],
  bounds : @js.Value,
  rotation : Double,
) -> (Double, Double, @js.Value) -> @js.Nullable[@js.Value] {
  let page = read_rect(bounds)
  let entries = values
    .iter()
    .map(value => {
      let item : @js.Value = value.get_with_string("item")
      let transform : FixedArray[Double] = item.get_with_string("transform")
      let marked : @js.Nullable[String] = value.get_with_string("markedId")
      let entry : @selection.TextRun = {
        bounds: read_rect(value.get_with_string("bounds")).translated({
          x: -page.x,
          y: -page.y,
        }),
        index: value.get_with_string("index"),
        text: item.get_with_string("str"),
        font: item.get_with_string("fontName"),
        marked_id: marked.to_option(),
        has_eol: item.get_with_string("hasEOL"),
        vertical: @selection.vertical_text(transform[0], transform[1], rotation),
      }
      entry
    })
    .collect()
  let targets = @selection.targets(
    entries,
    tree.to_option().map(read_structure),
    page,
  )
  (x, y, bounds) => {
    let page = read_rect(bounds)
    let target = @selection.hit_target(targets, {
      x: x - page.x,
      y: y - page.y,
    })
    @js.Nullable::from_option(
      target.map(target => {
        let value = write_rect(
          target.bounds.translated({ x: page.x, y: page.y, }),
        )
        value.set_with_string("text", target.text)
        value
      }),
    )
  }
}
