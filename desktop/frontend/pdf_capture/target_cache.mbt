///|
priv struct PageTargets {
  page : @js.Value
  generation : Int32
  mut targets : Array[@selection.Target]?
}

///|
/// Effect-local cache: never stored in an application model or passed to JS.
priv struct TargetCache {
  host : @js.Value
  session : @js.Value
  pages : Map[Int32, PageTargets]
  mut generation : Int32
  mut alive : Bool
}

///|
fn TargetCache::current(
  self : TargetCache,
  number : Int32,
  slot : PageTargets,
) -> Bool {
  self.alive &&
  self.pages.get(number) is Some(current) &&
  current.generation == slot.generation &&
  (slot.page.get_with_string("isConnected") : Bool)
}

///|
fn TargetCache::discard(
  self : TargetCache,
  number : Int32,
  slot : PageTargets,
) -> Unit {
  if self.pages.get(number) is Some(current) &&
    current.generation == slot.generation {
    self.pages.remove(number)
  }
}

///|
fn TargetCache::index(
  self : TargetCache,
  number : Int32,
  slot : PageTargets,
  mapping : @js.Value,
  tree : @js.Nullable[@js.Value],
  changed : () -> Unit,
) -> Unit {
  if !self.current(number, slot) {
    return
  }
  let entries : FixedArray[@js.Value] = mapping.get_with_string("entries")
  let view : @js.Value = mapping.get_with_string("view")
  let viewport : @js.Value = view.get_with_string("viewport")
  slot.targets = Some(
    index_page(
      entries,
      tree,
      browser_bounds(slot.page),
      viewport.get_with_string("rotation"),
    ),
  )
  changed()
}

///|
fn TargetCache::prepare(
  self : TargetCache,
  page : @js.Value,
  changed : () -> Unit,
) -> PageTargets {
  let number = browser_page_number(page)
  if self.pages.get(number) is Some(slot) && browser_same(slot.page, page) {
    return slot
  }
  self.generation += 1
  let slot : PageTargets = { page, generation: self.generation, targets: None, }
  self.pages.set(number, slot)
  let failed = (_ : @js.Value) => self.discard(number, slot)
  // Promise callbacks are MoonBit closures; only the native then/catch APIs
  // cross the bridge. A retired generation can never publish into a new page.
  let ok = browser_attempt(() => {
    let promise : @js.Value = self.session.apply_with_string("mapping", [number])
    let mapped = (mapping : @js.Value) => {
      guard browser_present(mapping) is Some(mapping) else {
        self.discard(number, slot)
        return
      }
      if !self.current(number, slot) {
        return
      }
      let data : @js.Value = mapping.get_with_string("data")
      let pdf_page : @js.Value = data.get_with_string("page")
      let structure : @js.Value = pdf_page.apply_with_string(
        "getStructTree",
        ([] : FixedArray[@js.Value]),
      )
      let recovered : @js.Value = structure.apply_with_string("catch", [
        (_ : @js.Value) => (@js.Nullable::null() : @js.Nullable[@js.Value]),
      ])
      let indexed : @js.Value = recovered.apply_with_string("then", [
        (tree : @js.Nullable[@js.Value]) => {
          self.index(number, slot, mapping, tree, changed)
        },
      ])
      ignore((indexed.apply_with_string("catch", [failed]) : @js.Value))
    }
    let pending : @js.Value = promise.apply_with_string("then", [mapped])
    ignore((pending.apply_with_string("catch", [failed]) : @js.Value))
  })
  if !ok {
    self.discard(number, slot)
  }
  slot
}

///|
fn TargetCache::at(
  self : TargetCache,
  x : Double,
  y : Double,
  changed : () -> Unit,
) -> @selection.Target? {
  let found : @js.Nullable[@js.Value] = browser_document().apply_with_string(
    "elementFromPoint",
    [x, y],
  )
  guard found.to_option() is Some(element) else { return None }
  let closest : @js.Nullable[@js.Value] = element.apply_with_string("closest", [
    ".page",
  ])
  guard closest.to_option() is Some(page) else { return None }
  guard (self.host.apply_with_string("contains", [page]) : Bool) else {
    return None
  }
  guard self.prepare(page, changed).targets is Some(targets) else {
    return None
  }
  let bounds = browser_bounds(page)
  @selection.hit_target(targets, { x: x - bounds.x, y: y - bounds.y, }).map(target => {
    ..target,
    bounds: target.bounds.translated({ x: bounds.x, y: bounds.y, }),
  })
}
