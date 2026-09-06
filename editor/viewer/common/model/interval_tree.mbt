// Reachable subset of Monaco/VS Code's decoration interval tree.
//
// Source: vscode/src/vs/editor/common/model/intervalTree.ts
// (checked-in vscode submodule).
//
// The red-black tree is based on the "Introduction to Algorithms" by Cormen,
// Leiserson and Rivest. Node offsets right of a subtree are stored
// delta-compressed (`delta` on each node applies to its right subtree), and
// `max_end` augments each node for interval-overlap search.
//
// Placement decision (plan `monaco-decoration-system-port.md`, Phase 1): the
// tree folds into `viewer/common/model` (the mirror of Monaco's
// `common/model/`) instead of a carved sibling package — the node's `options`
// field is this package's `ModelDecorationOptions`, so a sibling package would cycle.
//
// Deviations (plan Deviations 1):
// - The edit cluster (`acceptReplace`, `nodeAcceptEdit`, `searchForEditing`,
//   `noOverlapReplace`, `adjustMarkerBeforeColumn`, `MarkerMoveSemantics`) is
//   not ported: the readonly viewer never edits a model. The delta machinery
//   those edits fed (`delta`, `normalizeDelta`, the safe-delta bounds) stays —
//   it is interwoven with the ported insert/delete/rotation paths.
// - The `ClassName` squiggly constants are defined here like the source file
//   does; the plan's "reuse `@markers` constants" is dependency-infeasible
//   (`markers` imports `model`).
// - `parent`/`left`/`right` are `IntervalNode?` fields behind unwrap
//   accessors because MoonBit cannot construct a self-referential literal;
//   `None` only occurs pre-link and after `detach()` (the source's `null!`).
// - `affects_font` is carried in the metadata byte (it is baked into the
//   layout) but never set: font decorations are out of scope (plan
//   out-of-scope list), so `set_options` passes `false` where the source
//   reads `options.affectsFont ?? false`.

///|
/// `ClassName` (`intervalTree.ts:14-22`) — the squiggly marker class names the
/// tree recognizes for the `is_for_validation` bit. Only the three consulted
/// by `set_options` are defined here; the other four enum entries
/// (hint/unnecessary/inline-unnecessary/inline-deprecated) have no consumer in
/// this file and already exist as the marker service's class-name strings
/// (`@markers`, which imports this package).
const CLASS_NAME_EDITOR_INFO_DECORATION : String = "squiggly-info"

///|
const CLASS_NAME_EDITOR_WARNING_DECORATION : String = "squiggly-warning"

///|
const CLASS_NAME_EDITOR_ERROR_DECORATION : String = "squiggly-error"

///|
/// `NodeColor` (`intervalTree.ts:24-27`).
priv enum NodeColor {
  Black
  Red
} derive(Eq)

///|
/// `Constants` bit layout of the packed `metadata` byte
/// (`intervalTree.ts:29-56`).
const COLOR_MASK : Int = 0b00000001

///|
const COLOR_MASK_INVERSE : Int = 0b11111110

///|
const COLOR_OFFSET : Int = 0

///|
const IS_VISITED_MASK : Int = 0b00000010

///|
const IS_VISITED_MASK_INVERSE : Int = 0b11111101

///|
const IS_VISITED_OFFSET : Int = 1

///|
const IS_FOR_VALIDATION_MASK : Int = 0b00000100

///|
const IS_FOR_VALIDATION_MASK_INVERSE : Int = 0b11111011

///|
const IS_FOR_VALIDATION_OFFSET : Int = 2

///|
const STICKINESS_MASK_INVERSE : Int = 0b11100111

///|
const STICKINESS_OFFSET : Int = 3

///|
const COLLAPSE_ON_REPLACE_EDIT_MASK_INVERSE : Int = 0b11011111

///|
const COLLAPSE_ON_REPLACE_EDIT_OFFSET : Int = 5

///|
const IS_MARGIN_MASK : Int = 0b01000000

///|
const IS_MARGIN_MASK_INVERSE : Int = 0b10111111

///|
const IS_MARGIN_OFFSET : Int = 6

///|
const AFFECTS_FONT_MASK : Int = 0b10000000

///|
const AFFECTS_FONT_MASK_INVERSE : Int = 0b01111111

///|
const AFFECTS_FONT_OFFSET : Int = 7

///|
/// Delta safety bounds (`intervalTree.ts:58-78`). Deletion hands deltas off
/// between nodes, so they can grow far beyond any real offset; past these
/// bounds the tree schedules a `normalize_delta` pass. The source picks
/// ±(1<<30) as the v8 SMI bound; the same constant keeps MoonBit's 32-bit
/// `Int` arithmetic overflow-free for real document offsets.
const MIN_SAFE_DELTA : Int = -(1 << 30)

///|
const MAX_SAFE_DELTA : Int = 1 << 30

///|
/// Stable identities for interval nodes. TypeScript's object `===` is part of
/// the tree algorithm; MoonBit's `physical_equal` is only an optimization hint
/// and cannot carry that semantic contract across targets.
let interval_node_identity_counter : Ref[Int] = Ref(0)

///|
fn next_interval_node_identity() -> Int {
  interval_node_identity_counter.val += 1
  interval_node_identity_counter.val
}

///|
/// `getNodeColor` (`intervalTree.ts:81-83`).
fn get_node_color(node : IntervalNode) -> NodeColor {
  if (node.metadata & COLOR_MASK) >> COLOR_OFFSET == 1 {
    Red
  } else {
    Black
  }
}

///|
/// `setNodeColor` (`intervalTree.ts:84-88`).
fn set_node_color(node : IntervalNode, color : NodeColor) -> Unit {
  let color_bit = match color {
    Black => 0
    Red => 1
  }
  node.metadata = (node.metadata & COLOR_MASK_INVERSE) |
    (color_bit << COLOR_OFFSET)
}

///|
/// `getNodeIsVisited` (`intervalTree.ts:89-91`).
fn get_node_is_visited(node : IntervalNode) -> Bool {
  (node.metadata & IS_VISITED_MASK) >> IS_VISITED_OFFSET == 1
}

///|
/// `setNodeIsVisited` (`intervalTree.ts:92-96`).
fn set_node_is_visited(node : IntervalNode, value : Bool) -> Unit {
  node.metadata = (node.metadata & IS_VISITED_MASK_INVERSE) |
    ((if value { 1 } else { 0 }) << IS_VISITED_OFFSET)
}

///|
/// `getNodeIsForValidation` (`intervalTree.ts:97-99`).
fn get_node_is_for_validation(node : IntervalNode) -> Bool {
  (node.metadata & IS_FOR_VALIDATION_MASK) >> IS_FOR_VALIDATION_OFFSET == 1
}

///|
/// `setNodeIsForValidation` (`intervalTree.ts:100-104`).
fn set_node_is_for_validation(node : IntervalNode, value : Bool) -> Unit {
  node.metadata = (node.metadata & IS_FOR_VALIDATION_MASK_INVERSE) |
    ((if value { 1 } else { 0 }) << IS_FOR_VALIDATION_OFFSET)
}

///|
/// `getNodeIsInGlyphMargin` (`intervalTree.ts:105-107`).
fn get_node_is_in_glyph_margin(node : IntervalNode) -> Bool {
  (node.metadata & IS_MARGIN_MASK) >> IS_MARGIN_OFFSET == 1
}

///|
/// `setNodeIsInGlyphMargin` (`intervalTree.ts:108-112`).
fn set_node_is_in_glyph_margin(node : IntervalNode, value : Bool) -> Unit {
  node.metadata = (node.metadata & IS_MARGIN_MASK_INVERSE) |
    ((if value { 1 } else { 0 }) << IS_MARGIN_OFFSET)
}

///|
/// `getNodeAffectsFont` (`intervalTree.ts:113-115`). The bit is carried but
/// never set (font decorations out of scope).
fn get_node_affects_font(node : IntervalNode) -> Bool {
  (node.metadata & AFFECTS_FONT_MASK) >> AFFECTS_FONT_OFFSET == 1
}

///|
/// `setNodeAffectsFont` (`intervalTree.ts:116-120`).
fn set_node_affects_font(node : IntervalNode, value : Bool) -> Unit {
  node.metadata = (node.metadata & AFFECTS_FONT_MASK_INVERSE) |
    ((if value { 1 } else { 0 }) << AFFECTS_FONT_OFFSET)
}

///|
/// `_setNodeStickiness` (`intervalTree.ts:124-128`).
fn set_node_stickiness_int(node : IntervalNode, stickiness : Int) -> Unit {
  node.metadata = (node.metadata & STICKINESS_MASK_INVERSE) |
    (stickiness << STICKINESS_OFFSET)
}

///|
/// `setCollapseOnReplaceEdit` (`intervalTree.ts:132-136`).
fn set_collapse_on_replace_edit(node : IntervalNode, value : Bool) -> Unit {
  node.metadata = (node.metadata & COLLAPSE_ON_REPLACE_EDIT_MASK_INVERSE) |
    ((if value { 1 } else { 0 }) << COLLAPSE_ON_REPLACE_EDIT_OFFSET)
}

///|
/// `IntervalNode` (`intervalTree.ts:141-235`). `metadata` packs color,
/// visited, isForValidation, stickiness, collapseOnReplaceEdit, isMargin, and
/// affectsFont. Link fields are `IntervalNode?` behind unwrap accessors (see
/// header deviation note); everything else matches the source field list.
priv struct IntervalNode {
  identity : Int
  mut metadata : Int
  mut parent_ : IntervalNode?
  mut left_ : IntervalNode?
  mut right_ : IntervalNode?
  mut start : Int
  mut end : Int
  mut delta : Int
  mut max_end : Int
  id : String
  mut owner_id : Int
  mut options : ModelDecorationOptions?
  mut cached_version_id : Int
  mut cached_absolute_start : Int
  mut cached_absolute_end : Int
  mut range : @base_common.Range?
}

///|
fn IntervalNode::parent(self : IntervalNode) -> IntervalNode {
  self.parent_.unwrap()
}

///|
fn IntervalNode::set_parent(self : IntervalNode, v : IntervalNode) -> Unit {
  self.parent_ = Some(v)
}

///|
fn IntervalNode::left(self : IntervalNode) -> IntervalNode {
  self.left_.unwrap()
}

///|
fn IntervalNode::set_left(self : IntervalNode, v : IntervalNode) -> Unit {
  self.left_ = Some(v)
}

///|
fn IntervalNode::right(self : IntervalNode) -> IntervalNode {
  self.right_.unwrap()
}

///|
fn IntervalNode::set_right(self : IntervalNode, v : IntervalNode) -> Unit {
  self.right_ = Some(v)
}

///|
/// `IntervalNode` constructor (`intervalTree.ts:166-195`).
fn IntervalNode::IntervalNode(
  id : String,
  start : Int,
  end : Int,
) -> IntervalNode {
  let node : IntervalNode = {
    identity: next_interval_node_identity(),
    metadata: 0,
    parent_: None,
    left_: None,
    right_: None,
    start,
    end,
    // FORCE_OVERFLOWING_TEST: delta = start
    delta: 0,
    max_end: end,
    id,
    owner_id: 0,
    options: None,
    cached_version_id: 0,
    cached_absolute_start: start,
    cached_absolute_end: end,
    range: None,
  }
  node.set_parent(node)
  node.set_left(node)
  node.set_right(node)
  set_node_color(node, Red)
  set_node_is_for_validation(node, false)
  set_node_is_in_glyph_margin(node, false)
  set_node_stickiness_int(
    node,
    TrackedRangeStickiness::NeverGrowsWhenTypingAtEdges.to_int(),
  )
  set_collapse_on_replace_edit(node, false)
  set_node_affects_font(node, false)
  set_node_is_visited(node, false)
  node
}

///|
/// Whether two handles name the same stable interval-tree node.
fn IntervalNode::same(self : IntervalNode, other : IntervalNode) -> Bool {
  self.identity == other.identity
}

///|
fn same_interval_node(left : IntervalNode, right : IntervalNode) -> Bool {
  left.same(right)
}

///|
/// `reset` (`intervalTree.ts:197-205`).
fn IntervalNode::reset(
  self : IntervalNode,
  version_id : Int,
  start : Int,
  end : Int,
  range : @base_common.Range?,
) -> Unit {
  self.start = start
  self.end = end
  self.max_end = end
  self.cached_version_id = version_id
  self.cached_absolute_start = start
  self.cached_absolute_end = end
  self.range = range
}

///|
/// `setOptions` (`intervalTree.ts:207-219`). Derives the packed metadata bits
/// from the decoration options. `affectsFont` is passed `false` — font
/// decorations are out of scope (see header).
fn IntervalNode::set_options(
  self : IntervalNode,
  options : ModelDecorationOptions,
) -> Unit {
  self.options = Some(options)
  let class_name = options.class_name
  set_node_is_for_validation(
    self,
    class_name == CLASS_NAME_EDITOR_ERROR_DECORATION ||
    class_name == CLASS_NAME_EDITOR_WARNING_DECORATION ||
    class_name == CLASS_NAME_EDITOR_INFO_DECORATION,
  )
  set_node_is_in_glyph_margin(self, options.glyph_margin_class_name is Some(_))
  set_node_stickiness_int(self, options.stickiness.to_int())
  set_collapse_on_replace_edit(self, options.collapse_on_replace_edit)
  set_node_affects_font(self, false)
}

///|
/// `setCachedOffsets` (`intervalTree.ts:221-228`).
fn IntervalNode::set_cached_offsets(
  self : IntervalNode,
  absolute_start : Int,
  absolute_end : Int,
  cached_version_id : Int,
) -> Unit {
  if self.cached_version_id != cached_version_id {
    self.range = None
  }
  self.cached_version_id = cached_version_id
  self.cached_absolute_start = absolute_start
  self.cached_absolute_end = absolute_end
}

///|
/// `detach` (`intervalTree.ts:230-234`).
fn IntervalNode::detach(self : IntervalNode) -> Unit {
  self.parent_ = None
  self.left_ = None
  self.right_ = None
}

///|
/// `SENTINEL` (`intervalTree.ts:237-241`): the shared self-linked black nil
/// node. Like the source it is deliberately mutable — deletion temporarily
/// parents it into the tree and `reset_sentinel` re-zeros it.
let sentinel : IntervalNode = init_sentinel()

///|
fn init_sentinel() -> IntervalNode {
  let node = IntervalNode("", 0, 0)
  set_node_color(node, Black)
  node
}

///|
/// `IntervalTree` (`intervalTree.ts:243-346`).
priv struct IntervalTree {
  mut root : IntervalNode
  mut request_normalize_delta : Bool
}

///|
fn IntervalTree::IntervalTree() -> IntervalTree {
  { root: sentinel, request_normalize_delta: false, }
}

///|
/// `intervalSearch` (`intervalTree.ts:253-258`).
fn IntervalTree::interval_search(
  self : IntervalTree,
  start : Int,
  end : Int,
  filter_owner_id : Int,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  cached_version_id : Int,
  only_margin_decorations : Bool,
) -> Array[IntervalNode] {
  if same_interval_node(self.root, sentinel) {
    return []
  }
  interval_search(
    self, start, end, filter_owner_id, filter_out_validation, filter_font_decorations,
    cached_version_id, only_margin_decorations,
  )
}

///|
/// `search` (`intervalTree.ts:260-265`).
fn IntervalTree::search(
  self : IntervalTree,
  filter_owner_id : Int,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  cached_version_id : Int,
  only_margin_decorations : Bool,
) -> Array[IntervalNode] {
  if same_interval_node(self.root, sentinel) {
    return []
  }
  search(
    self, filter_owner_id, filter_out_validation, filter_font_decorations, cached_version_id,
    only_margin_decorations,
  )
}

///|
/// `collectNodesFromOwner` (`intervalTree.ts:270-272`). Will not set
/// `cached_absolute_start` nor `cached_absolute_end` on the returned nodes!
fn IntervalTree::collect_nodes_from_owner(
  self : IntervalTree,
  owner_id : Int,
) -> Array[IntervalNode] {
  collect_nodes_from_owner(self, owner_id)
}

///|
/// `insert` (`intervalTree.ts:281-284`).
fn IntervalTree::insert(self : IntervalTree, node : IntervalNode) -> Unit {
  ignore(rb_tree_insert(self, node))
  self.normalize_delta_if_necessary()
}

///|
/// `delete` (`intervalTree.ts:286-289`).
fn IntervalTree::delete(self : IntervalTree, node : IntervalNode) -> Unit {
  rb_tree_delete(self, node)
  self.normalize_delta_if_necessary()
}

///|
/// `resolveNode` (`intervalTree.ts:291-304`): walk to the root summing
/// right-child deltas, then cache the absolute offsets on the node.
fn IntervalTree::resolve_node(
  self : IntervalTree,
  node : IntervalNode,
  cached_version_id : Int,
) -> Unit {
  let initial_node = node
  let mut node = node
  let mut delta = 0
  while !same_interval_node(node, self.root) {
    if same_interval_node(node, node.parent().right()) {
      delta += node.parent().delta
    }
    node = node.parent()
  }
  let node_start = initial_node.start + delta
  let node_end = initial_node.end + delta
  initial_node.set_cached_offsets(node_start, node_end, cached_version_id)
}

///|
/// `_normalizeDeltaIfNecessary` (`intervalTree.ts:339-345`).
fn IntervalTree::normalize_delta_if_necessary(self : IntervalTree) -> Unit {
  if !self.request_normalize_delta {
    return
  }
  self.request_normalize_delta = false
  normalize_delta(self)
}

// #region Delta Normalization

///|
/// `normalizeDelta` (`intervalTree.ts:349-385`): iterative in-order visit
/// pushing accumulated deltas into the node offsets.
fn normalize_delta(t : IntervalTree) -> Unit {
  let mut node = t.root
  let mut delta = 0
  while !same_interval_node(node, sentinel) {
    if !same_interval_node(node.left(), sentinel) &&
      !get_node_is_visited(node.left()) {
      // go left
      node = node.left()
      continue
    }
    if !same_interval_node(node.right(), sentinel) &&
      !get_node_is_visited(node.right()) {
      // go right
      delta += node.delta
      node = node.right()
      continue
    }

    // handle current node
    node.start += delta
    node.end += delta
    node.delta = 0
    recompute_max_end(node)
    set_node_is_visited(node, true)

    // going up from this node
    set_node_is_visited(node.left(), false)
    set_node_is_visited(node.right(), false)
    if same_interval_node(node, node.parent().right()) {
      delta -= node.parent().delta
    }
    node = node.parent()
  }
  set_node_is_visited(t.root, false)
}

// #endregion

// #region Searching

///|
/// `collectNodesFromOwner` (`intervalTree.ts:638-674`).
fn collect_nodes_from_owner(
  t : IntervalTree,
  owner_id : Int,
) -> Array[IntervalNode] {
  let mut node = t.root
  let result : Array[IntervalNode] = []
  while !same_interval_node(node, sentinel) {
    if get_node_is_visited(node) {
      // going up from this node
      set_node_is_visited(node.left(), false)
      set_node_is_visited(node.right(), false)
      node = node.parent()
      continue
    }
    if !same_interval_node(node.left(), sentinel) &&
      !get_node_is_visited(node.left()) {
      // go left
      node = node.left()
      continue
    }

    // handle current node
    if node.owner_id == owner_id {
      result.push(node)
    }
    set_node_is_visited(node, true)
    if !same_interval_node(node.right(), sentinel) &&
      !get_node_is_visited(node.right()) {
      // go right
      node = node.right()
      continue
    }
  }
  set_node_is_visited(t.root, false)
  result
}

///|
/// `search` (`intervalTree.ts:711-773`): full in-order walk applying the four
/// include filters and caching absolute offsets.
fn search(
  t : IntervalTree,
  filter_owner_id : Int,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  cached_version_id : Int,
  only_margin_decorations : Bool,
) -> Array[IntervalNode] {
  let mut node = t.root
  let mut delta = 0
  let mut node_start = 0
  let mut node_end = 0
  let result : Array[IntervalNode] = []
  while !same_interval_node(node, sentinel) {
    if get_node_is_visited(node) {
      // going up from this node
      set_node_is_visited(node.left(), false)
      set_node_is_visited(node.right(), false)
      if same_interval_node(node, node.parent().right()) {
        delta -= node.parent().delta
      }
      node = node.parent()
      continue
    }
    if !same_interval_node(node.left(), sentinel) &&
      !get_node_is_visited(node.left()) {
      // go left
      node = node.left()
      continue
    }

    // handle current node
    node_start = delta + node.start
    node_end = delta + node.end
    node.set_cached_offsets(node_start, node_end, cached_version_id)
    let mut should_include = true
    if filter_owner_id != 0 &&
      node.owner_id != 0 &&
      node.owner_id != filter_owner_id {
      should_include = false
    }
    if filter_out_validation && get_node_is_for_validation(node) {
      should_include = false
    }
    if filter_font_decorations && get_node_affects_font(node) {
      should_include = false
    }
    if only_margin_decorations && !get_node_is_in_glyph_margin(node) {
      should_include = false
    }
    if should_include {
      result.push(node)
    }
    set_node_is_visited(node, true)
    if !same_interval_node(node.right(), sentinel) &&
      !get_node_is_visited(node.right()) {
      // go right
      delta += node.delta
      node = node.right()
      continue
    }
  }
  set_node_is_visited(t.root, false)
  result
}

///|
/// `intervalSearch` (`intervalTree.ts:775-866`): augmented-tree overlap
/// search with the `max_end` prune (case b), the `start > end` prune (case
/// a), delta accumulation, and the four include filters.
fn interval_search(
  t : IntervalTree,
  interval_start : Int,
  interval_end : Int,
  filter_owner_id : Int,
  filter_out_validation : Bool,
  filter_font_decorations : Bool,
  cached_version_id : Int,
  only_margin_decorations : Bool,
) -> Array[IntervalNode] {
  // https://en.wikipedia.org/wiki/Interval_tree#Augmented_tree
  // Now, it is known that two intervals A and B overlap only when both
  // A.low <= B.high and A.high >= B.low. When searching the trees for
  // nodes overlapping with a given interval, you can immediately skip:
  //  a) all nodes to the right of nodes whose low value is past the end of the given interval.
  //  b) all nodes that have their maximum 'high' value below the start of the given interval.
  let mut node = t.root
  let mut delta = 0
  let mut node_max_end = 0
  let mut node_start = 0
  let mut node_end = 0
  let result : Array[IntervalNode] = []
  while !same_interval_node(node, sentinel) {
    if get_node_is_visited(node) {
      // going up from this node
      set_node_is_visited(node.left(), false)
      set_node_is_visited(node.right(), false)
      if same_interval_node(node, node.parent().right()) {
        delta -= node.parent().delta
      }
      node = node.parent()
      continue
    }
    if !get_node_is_visited(node.left()) {
      // first time seeing this node
      node_max_end = delta + node.max_end
      if node_max_end < interval_start {
        // cover case b) from above
        // there is no need to search this node or its children
        set_node_is_visited(node, true)
        continue
      }
      if !same_interval_node(node.left(), sentinel) {
        // go left
        node = node.left()
        continue
      }
    }

    // handle current node
    node_start = delta + node.start
    if node_start > interval_end {
      // cover case a) from above
      // there is no need to search this node or its right subtree
      set_node_is_visited(node, true)
      continue
    }
    node_end = delta + node.end
    if node_end >= interval_start {
      // There is overlap
      node.set_cached_offsets(node_start, node_end, cached_version_id)
      let mut should_include = true
      if filter_owner_id != 0 &&
        node.owner_id != 0 &&
        node.owner_id != filter_owner_id {
        should_include = false
      }
      if filter_out_validation && get_node_is_for_validation(node) {
        should_include = false
      }
      if filter_font_decorations && get_node_affects_font(node) {
        should_include = false
      }
      if only_margin_decorations && !get_node_is_in_glyph_margin(node) {
        should_include = false
      }
      if should_include {
        result.push(node)
      }
    }
    set_node_is_visited(node, true)
    if !same_interval_node(node.right(), sentinel) &&
      !get_node_is_visited(node.right()) {
      // go right
      delta += node.delta
      node = node.right()
      continue
    }
  }
  set_node_is_visited(t.root, false)
  result
}

// #endregion

// #region Insertion

///|
/// `rbTreeInsert` (`intervalTree.ts:871-928`): CLRS insert plus repair;
/// rotations carry the delta transfer.
fn rb_tree_insert(t : IntervalTree, new_node : IntervalNode) -> IntervalNode {
  if same_interval_node(t.root, sentinel) {
    new_node.set_parent(sentinel)
    new_node.set_left(sentinel)
    new_node.set_right(sentinel)
    set_node_color(new_node, Black)
    t.root = new_node
    return t.root
  }
  tree_insert(t, new_node)
  recompute_max_end_walk_to_root(new_node.parent())

  // repair tree
  let mut x = new_node
  while !same_interval_node(x, t.root) && get_node_color(x.parent()) == Red {
    if same_interval_node(x.parent(), x.parent().parent().left()) {
      let y = x.parent().parent().right()
      if get_node_color(y) == Red {
        set_node_color(x.parent(), Black)
        set_node_color(y, Black)
        set_node_color(x.parent().parent(), Red)
        x = x.parent().parent()
      } else {
        if same_interval_node(x, x.parent().right()) {
          x = x.parent()
          left_rotate(t, x)
        }
        set_node_color(x.parent(), Black)
        set_node_color(x.parent().parent(), Red)
        right_rotate(t, x.parent().parent())
      }
    } else {
      let y = x.parent().parent().left()
      if get_node_color(y) == Red {
        set_node_color(x.parent(), Black)
        set_node_color(y, Black)
        set_node_color(x.parent().parent(), Red)
        x = x.parent().parent()
      } else {
        if same_interval_node(x, x.parent().left()) {
          x = x.parent()
          right_rotate(t, x)
        }
        set_node_color(x.parent(), Black)
        set_node_color(x.parent().parent(), Red)
        left_rotate(t, x.parent().parent())
      }
    }
  }
  set_node_color(t.root, Black)
  new_node
}

///|
/// `treeInsert` (`intervalTree.ts:930-969`): delta-relative descent in
/// `intervalCompare` order, subtracting the accumulated delta at link time.
fn tree_insert(t : IntervalTree, z : IntervalNode) -> Unit {
  let mut delta = 0
  let mut x = t.root
  let z_absolute_start = z.start
  let z_absolute_end = z.end
  for ;; {
    let cmp = interval_compare(
      z_absolute_start,
      z_absolute_end,
      x.start + delta,
      x.end + delta,
    )
    if cmp < 0 {
      // this node should be inserted to the left
      // => it is not affected by the node's delta
      if same_interval_node(x.left(), sentinel) {
        z.start -= delta
        z.end -= delta
        z.max_end -= delta
        x.set_left(z)
        break
      } else {
        x = x.left()
      }
      // this node should be inserted to the right
      // => it is not affected by the node's delta
    } else if same_interval_node(x.right(), sentinel) {
      z.start -= delta + x.delta
      z.end -= delta + x.delta
      z.max_end -= delta + x.delta
      x.set_right(z)
      break
    } else {
      delta += x.delta
      x = x.right()
    }
  }
  z.set_parent(x)
  z.set_left(sentinel)
  z.set_right(sentinel)
  set_node_color(z, Red)
}

// #endregion

// #region Deletion

///|
/// `rbTreeDelete` (`intervalTree.ts:973-1155`): RB-DELETE except z and y are
/// not swapped in case c) — what's pointed at by z is always deleted. Deltas
/// are handed off in the three shapes, then RB-DELETE-FIXUP runs both sides.
fn rb_tree_delete(t : IntervalTree, z : IntervalNode) -> Unit {
  // RB-DELETE except we don't swap z and y in case c)
  // i.e. we always delete what's pointed at by z.
  let (x, y) = if same_interval_node(z.left(), sentinel) {
    let x = z.right()
    let y = z

    // x's delta is no longer influenced by z's delta
    x.delta += z.delta
    if x.delta < MIN_SAFE_DELTA || x.delta > MAX_SAFE_DELTA {
      t.request_normalize_delta = true
    }
    x.start += z.delta
    x.end += z.delta
    (x, y)
  } else if same_interval_node(z.right(), sentinel) {
    (z.left(), z)
  } else {
    let y = leftest(z.right())
    let x = y.right()

    // y's delta is no longer influenced by z's delta,
    // but we don't want to walk the entire right-hand-side subtree of x.
    // we therefore maintain z's delta in y, and adjust only x
    x.start += y.delta
    x.end += y.delta
    x.delta += y.delta
    if x.delta < MIN_SAFE_DELTA || x.delta > MAX_SAFE_DELTA {
      t.request_normalize_delta = true
    }
    y.start += z.delta
    y.end += z.delta
    y.delta = z.delta
    if y.delta < MIN_SAFE_DELTA || y.delta > MAX_SAFE_DELTA {
      t.request_normalize_delta = true
    }
    (x, y)
  }
  if same_interval_node(y, t.root) {
    t.root = x
    set_node_color(x, Black)
    z.detach()
    reset_sentinel()
    recompute_max_end(x)
    t.root.set_parent(sentinel)
    return
  }
  let y_was_red = get_node_color(y) == Red
  if same_interval_node(y, y.parent().left()) {
    y.parent().set_left(x)
  } else {
    y.parent().set_right(x)
  }
  if same_interval_node(y, z) {
    x.set_parent(y.parent())
  } else {
    if same_interval_node(y.parent(), z) {
      x.set_parent(y)
    } else {
      x.set_parent(y.parent())
    }
    y.set_left(z.left())
    y.set_right(z.right())
    y.set_parent(z.parent())
    set_node_color(y, get_node_color(z))
    if same_interval_node(z, t.root) {
      t.root = y
    } else if same_interval_node(z, z.parent().left()) {
      z.parent().set_left(y)
    } else {
      z.parent().set_right(y)
    }
    if !same_interval_node(y.left(), sentinel) {
      y.left().set_parent(y)
    }
    if !same_interval_node(y.right(), sentinel) {
      y.right().set_parent(y)
    }
  }
  z.detach()
  if y_was_red {
    recompute_max_end_walk_to_root(x.parent())
    if !same_interval_node(y, z) {
      recompute_max_end_walk_to_root(y)
      recompute_max_end_walk_to_root(y.parent())
    }
    reset_sentinel()
    return
  }
  recompute_max_end_walk_to_root(x)
  recompute_max_end_walk_to_root(x.parent())
  if !same_interval_node(y, z) {
    recompute_max_end_walk_to_root(y)
    recompute_max_end_walk_to_root(y.parent())
  }

  // RB-DELETE-FIXUP
  let mut x = x
  while !same_interval_node(x, t.root) && get_node_color(x) == Black {
    if same_interval_node(x, x.parent().left()) {
      let mut w = x.parent().right()
      if get_node_color(w) == Red {
        set_node_color(w, Black)
        set_node_color(x.parent(), Red)
        left_rotate(t, x.parent())
        w = x.parent().right()
      }
      if get_node_color(w.left()) == Black && get_node_color(w.right()) == Black {
        set_node_color(w, Red)
        x = x.parent()
      } else {
        if get_node_color(w.right()) == Black {
          set_node_color(w.left(), Black)
          set_node_color(w, Red)
          right_rotate(t, w)
          w = x.parent().right()
        }
        set_node_color(w, get_node_color(x.parent()))
        set_node_color(x.parent(), Black)
        set_node_color(w.right(), Black)
        left_rotate(t, x.parent())
        x = t.root
      }
    } else {
      let mut w = x.parent().left()
      if get_node_color(w) == Red {
        set_node_color(w, Black)
        set_node_color(x.parent(), Red)
        right_rotate(t, x.parent())
        w = x.parent().left()
      }
      if get_node_color(w.left()) == Black && get_node_color(w.right()) == Black {
        set_node_color(w, Red)
        x = x.parent()
      } else {
        if get_node_color(w.left()) == Black {
          set_node_color(w.right(), Black)
          set_node_color(w, Red)
          left_rotate(t, w)
          w = x.parent().left()
        }
        set_node_color(w, get_node_color(x.parent()))
        set_node_color(x.parent(), Black)
        set_node_color(w.left(), Black)
        right_rotate(t, x.parent())
        x = t.root
      }
    }
  }
  set_node_color(x, Black)
  reset_sentinel()
}

///|
/// `leftest` (`intervalTree.ts:1157-1162`).
fn leftest(node : IntervalNode) -> IntervalNode {
  let mut node = node
  while !same_interval_node(node.left(), sentinel) {
    node = node.left()
  }
  node
}

///|
/// `resetSentinel` (`intervalTree.ts:1164-1169`).
fn reset_sentinel() -> Unit {
  sentinel.set_parent(sentinel)
  sentinel.delta = 0 // optional
  sentinel.start = 0 // optional
  sentinel.end = 0 // optional
}

// #endregion

// #region Rotations

///|
/// `leftRotate` (`intervalTree.ts:1173-1201`).
fn left_rotate(t : IntervalTree, x : IntervalNode) -> Unit {
  let y = x.right() // set y.
  y.delta += x.delta // y's delta is no longer influenced by x's delta
  if y.delta < MIN_SAFE_DELTA || y.delta > MAX_SAFE_DELTA {
    t.request_normalize_delta = true
  }
  y.start += x.delta
  y.end += x.delta
  x.set_right(y.left()) // turn y's left subtree into x's right subtree.
  if !same_interval_node(y.left(), sentinel) {
    y.left().set_parent(x)
  }
  y.set_parent(x.parent()) // link x's parent to y.
  if same_interval_node(x.parent(), sentinel) {
    t.root = y
  } else if same_interval_node(x, x.parent().left()) {
    x.parent().set_left(y)
  } else {
    x.parent().set_right(y)
  }
  y.set_left(x) // put x on y's left.
  x.set_parent(y)
  recompute_max_end(x)
  recompute_max_end(y)
}

///|
/// `rightRotate` (`intervalTree.ts:1203-1231`).
fn right_rotate(t : IntervalTree, y : IntervalNode) -> Unit {
  let x = y.left()
  y.delta -= x.delta
  if y.delta < MIN_SAFE_DELTA || y.delta > MAX_SAFE_DELTA {
    t.request_normalize_delta = true
  }
  y.start -= x.delta
  y.end -= x.delta
  y.set_left(x.right())
  if !same_interval_node(x.right(), sentinel) {
    x.right().set_parent(y)
  }
  x.set_parent(y.parent())
  if same_interval_node(y.parent(), sentinel) {
    t.root = x
  } else if same_interval_node(y, y.parent().right()) {
    y.parent().set_right(x)
  } else {
    y.parent().set_left(x)
  }
  x.set_right(y)
  y.set_parent(x)
  recompute_max_end(y)
  recompute_max_end(x)
}

// #endregion

// #region max end computation

///|
/// `computeMaxEnd` (`intervalTree.ts:1236-1251`).
fn compute_max_end(node : IntervalNode) -> Int {
  let mut max_end = node.end
  if !same_interval_node(node.left(), sentinel) {
    max_end = max_end.max(node.left().max_end)
  }
  if !same_interval_node(node.right(), sentinel) {
    max_end = max_end.max(node.right().max_end + node.delta)
  }
  max_end
}

///|
/// `recomputeMaxEnd` (`intervalTree.ts:1253-1255`).
fn recompute_max_end(node : IntervalNode) -> Unit {
  node.max_end = compute_max_end(node)
}

///|
/// `recomputeMaxEndWalkToRoot` (`intervalTree.ts:1257-1270`).
fn recompute_max_end_walk_to_root(node : IntervalNode) -> Unit {
  let mut node = node
  while !same_interval_node(node, sentinel) {
    let max_end = compute_max_end(node)
    if node.max_end == max_end {
      // no need to go further
      return
    }
    node.max_end = max_end
    node = node.parent()
  }
}

// #endregion

// #region utils

///|
/// `intervalCompare` (`intervalTree.ts:1275-1280`): start-major, end-minor.
fn interval_compare(
  a_start : Int,
  a_end : Int,
  b_start : Int,
  b_end : Int,
) -> Int {
  if a_start == b_start {
    return a_end - b_end
  }
  a_start - b_start
}

// #endregion
