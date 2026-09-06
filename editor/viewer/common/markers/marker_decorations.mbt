// Per-model marker decorations ported from the inner `MarkerDecorations` class,
// vscode/src/vs/editor/common/services/markerDecorationsService.ts:132
//
// ModelDecorationOptions plan Phase 3: the class now stores through the model's
// interval-tree decoration storage (`model.delta_decorations`), replacing the
// prior synthetic-id array (the plan-D3 deferral this migration closes).

///|
/// Per-model marker decorations, `MarkerDecorations`
/// (`markerDecorationsService.ts:132`). The `BidirectionalMap<IMarker, id>` is
/// represented as an entry list. Monaco compares stable marker references;
/// the local marker bridge recreates values, so updates pair structurally equal
/// entries one occurrence at a time. This preserves duplicate multiplicity.
priv struct MarkerDecorations {
  model : @model.TextModel
  mut entries : Array[(Marker, String)]
  mut disposed : Bool
  mut generation : Int
}

///|
/// Builds an empty per-model decoration map bound to `model`.
fn MarkerDecorations::MarkerDecorations(
  model : @model.TextModel,
) -> MarkerDecorations {
  { model, entries: [], disposed: false, generation: 0, }
}

///|
/// The ctor's dispose hook (`markerDecorationsService.ts:140-143`): remove
/// this owner's decorations from the model and clear the map.
fn MarkerDecorations::dispose(self : MarkerDecorations) -> Unit {
  if !self.disposed {
    self.disposed = true
    self.generation += 1
    self.clear()
  }
}

///|
/// Clears the current decoration ids without ending this model owner's
/// lifetime. A whole-model content flush destroys the model's decoration tree;
/// the retained owner uses this reset before seeding fresh ids from the marker
/// store. It is deliberately not `dispose`: `set_value` does not release or
/// reacquire the model registration.
fn MarkerDecorations::reset(self : MarkerDecorations) -> Unit {
  if !self.disposed {
    self.generation += 1
    self.clear()
  }
}

///|
fn MarkerDecorations::clear(self : MarkerDecorations) -> Unit {
  let old_ids = self.entries.map(e => e.1)
  self.entries = []
  let _ = self.model.delta_decorations(old_ids, [])
}

///|
/// `update` (`markerDecorationsService.ts:146`): `diffSets` over the current
/// and new marker sets; early-return `false` when nothing changed
/// (load-bearing — it stops the change event, hence any re-render loop);
/// otherwise `deltaDecorations` the removed ids against the added markers'
/// (range, options) pairs and record the returned ids.
fn MarkerDecorations::update(
  self : MarkerDecorations,
  markers : Array[Marker],
) -> Bool {
  if self.disposed {
    return false
  }
  self.generation += 1
  let generation = self.generation
  // Pair each incoming marker with at most one structurally equal live entry.
  // A set-style `contains` diff loses multiplicity: shrinking two identical
  // diagnostics to one would otherwise retain both decorations. Monaco's
  // identity-keyed map distinguishes those marker objects, so this stable
  // multiset pairing is the local equivalent.
  let matched_entries = Array::make(self.entries.length(), false)
  let added : Array[Marker] = []
  for marker in markers {
    let matched_index = for index in 0..<self.entries.length() {
      if !matched_entries[index] && self.entries[index].0 == marker {
        break index
      }
    } nobreak {
      -1
    }
    if matched_index >= 0 {
      matched_entries[matched_index] = true
    } else {
      added.push(marker)
    }
  }
  let retained = [ for i, entry in self.entries if matched_entries[i] => entry ]
  let old_ids = [
    for i, entry in self.entries if !matched_entries[i] => entry.1
  ]
  if added.length() == 0 && old_ids.length() == 0 {
    return false
  }
  let new_decorations : Array[@model.ModelDeltaDecoration] = added.map(marker => {
    let range = create_decoration_range(self.model, marker)
    { range, options: create_decoration_option(marker), }
  })
  let ids = self.model.delta_decorations(old_ids, new_decorations)
  // `delta_decorations` fires the model event before it returns. A listener
  // may synchronously release this owner or flush the model; do not resurrect
  // ids after that terminal/reset transition.
  if self.disposed || self.generation != generation {
    let newer_ids = self.entries.map(entry => entry.1)
    let stale_ids = ids.filter(id => !newer_ids.contains(id))
    let _ = self.model.delta_decorations(stale_ids, [])
    return false
  }
  self.entries = retained
  for index in 0..<ids.length() {
    self.entries.push((added[index], ids[index]))
  }
  true
}

///|
/// `getMarkers` (`markerDecorationsService.ts:179`): `(range, marker)` for
/// each live decoration, the range resolved from the model's storage.
fn MarkerDecorations::get_markers(
  self : MarkerDecorations,
) -> Array[(@base_common.Range, Marker)] {
  let res : Array[(@base_common.Range, Marker)] = []
  for entry in self.entries {
    let (marker, id) = entry
    if self.model.get_decoration_range(id) is Some(range) {
      res.push((range, marker))
    }
  }
  res
}
