///| Faithful conformance port of vscode's `intervalTree.test.ts` (pinned
/// `vscode/` checked-in submodule):
/// `vscode/src/vs/editor/test/common/model/intervalTree.test.ts`.
///
/// Ported members: the op-driven harness (`Oracle`, `TestState`,
/// `testIntervalTree`), `assertTreeInvariants` (RB height rule, red-parent
/// rule, delta bounds, maxEnd consistency, in-order sortedness — run after
/// every mutating op like the source), gen01–gen18, `force delta overflow`,
/// and the 5 Cormen interval-search cases.
///
/// Not ported: the `nodeAcceptEdit` table — the interval tree's edit cluster
/// is not ported (readonly viewer, see `interval_tree.mbt`'s header).
///
/// Adaptations:
/// - The source's `getRandomInt` fuzz loop (`Math.random`, gated behind
///   `GENERATE_TESTS`) ports as a seeded xorshift32 PRNG with the fixed seed
///   set {11111, 22222, 33333, 44444, 55555} — deterministic in CI.
/// - `force delta overflow` constants (~9e14) exceed MoonBit's 32-bit `Int`;
///   they are scaled by 1e-6 (the test runs the plain insert + invariant
///   harness — the overflow it was sized for only triggers with the source's
///   commented-out FORCE_OVERFLOWING_TEST ctor line, replayed here by the
///   `forced_delta` harness variants).
/// - `Oracle.insert` (push + stable sort by (start, end)) is expressed as
///   insert-at-upper-bound, which is what a stable sort does to the appended
///   element.

// #region IntervalTree 1 — op-driven harness

///|
priv struct Interval {
  id : Int
  mut start : Int
  mut end : Int
}

///|
priv struct Oracle {
  intervals : Array[Interval]
}

///|
fn Oracle::new() -> Oracle {
  { intervals: [] }
}

///|
fn Oracle::insert(self : Oracle, interval : Interval) -> Interval {
  let mut idx = self.intervals.length()
  for i, existing in self.intervals {
    if existing.start > interval.start ||
      (existing.start == interval.start && existing.end > interval.end) {
      idx = i
      break
    }
  }
  self.intervals.insert(idx, interval)
  interval
}

///|
fn Oracle::delete(self : Oracle, interval : Interval) -> Unit {
  for i, existing in self.intervals {
    if existing.id == interval.id {
      let _ = self.intervals.remove(i)
      return
    }
  }
}

///|
fn Oracle::search(self : Oracle, start : Int, end : Int) -> Array[Interval] {
  let result : Array[Interval] = []
  for interval in self.intervals {
    if interval.start <= end && interval.end >= start {
      result.push(interval)
    }
  }
  result
}

///|
priv enum Op {
  Insert(Int, Int)
  Delete(Int)
  Change(Int, Int, Int)
  Search(Int, Int)
}

///|
priv struct TestState {
  oracle : Oracle
  tree : @model.IntervalTree
  tree_nodes : Array[@model.IntervalNode?]
  oracle_nodes : Array[Interval?]
  /// Replays the source ctor's commented-out `FORCE_OVERFLOWING_TEST:
  /// this.delta = start` line, which is how Monaco exercises the delta
  /// arithmetic in rotations/insert/delete/search through this same suite.
  forced_delta : Bool
}

///|
fn TestState::new(forced_delta? : Bool = false) -> TestState {
  {
    oracle: Oracle::new(),
    tree: IntervalTree(),
    tree_nodes: [],
    oracle_nodes: [],
    forced_delta,
  }
}

///|
fn TestState::accept_op(self : TestState, op : Op) -> Unit raise {
  match op {
    Insert(begin, end) => {
      // ids allocate sequentially (source: ++this._lastNodeId indexes the slot)
      let node = @model.IntervalNode("", begin, end)
      if self.forced_delta {
        node.delta = begin // FORCE_OVERFLOWING_TEST: this.delta = start
      }
      self.tree_nodes.push(Some(node))
      self.tree.insert(node)
      self.oracle_nodes.push(
        Some(
          self.oracle.insert({
            id: self.oracle_nodes.length(),
            start: begin,
            end,
          }),
        ),
      )
    }
    Delete(id) => {
      self.tree.delete(self.tree_nodes[id].unwrap())
      self.oracle.delete(self.oracle_nodes[id].unwrap())
      self.tree_nodes[id] = None
      self.oracle_nodes[id] = None
    }
    Change(id, begin, end) => {
      let node = self.tree_nodes[id].unwrap()
      self.tree.delete(node)
      node.reset(0, begin, end, None)
      self.tree.insert(node)
      let interval = self.oracle_nodes[id].unwrap()
      self.oracle.delete(interval)
      interval.start = begin
      interval.end = end
      let _ = self.oracle.insert(interval)
    }
    Search(begin, end) => {
      let actual_nodes = self.tree.interval_search(
        begin, end, 0, false, false, 0, false,
      )
      let actual = actual_nodes.map(n => {
        (n.cached_absolute_start, n.cached_absolute_end)
      })
      let expected = self.oracle.search(begin, end).map(i => (i.start, i.end))
      assert_pairs_eq(actual, expected)
      return
    }
  }
  assert_tree_invariants(self.tree)
  let actual = self.tree
    .get_all_in_order()
    .map(n => (n.cached_absolute_start, n.cached_absolute_end))
  let expected = self.oracle.intervals.map(i => (i.start, i.end))
  assert_pairs_eq(actual, expected)
}

///|
fn TestState::get_existing_node_id(self : TestState, index : Int) -> Int raise {
  let mut curr_index = -1
  for i in 0..<self.tree_nodes.length() {
    if self.tree_nodes[i] is None {
      continue
    }
    curr_index += 1
    if curr_index == index {
      return i
    }
  }
  fail("unexpected")
}

///|
fn test_interval_tree(ops : Array[Op]) -> Unit raise {
  let state = TestState::new()
  for op in ops {
    state.accept_op(op)
  }
}

///|
/// Every generated op list, for the FORCE_OVERFLOWING_TEST re-run.
fn gen_op_lists() -> Array[Array[Op]] {
  [
    [Insert(28, 35), Insert(52, 54), Insert(63, 69)],
    [Insert(80, 89), Insert(92, 100), Insert(99, 99)],
    [Insert(89, 96), Insert(71, 74), Delete(1)],
    [Insert(44, 46), Insert(85, 88), Delete(0)],
    [Insert(82, 90), Insert(69, 73), Delete(0), Delete(1)],
    [Insert(41, 63), Insert(98, 98), Insert(47, 51), Delete(2)],
    [Insert(24, 26), Insert(11, 28), Insert(27, 30), Insert(80, 85), Delete(1)],
    [Insert(100, 100), Insert(100, 100)],
    [Insert(58, 65), Insert(82, 96), Insert(58, 65)],
    [Insert(32, 40), Insert(25, 29), Insert(24, 32)],
    [Insert(25, 70), Insert(99, 100), Insert(46, 51), Insert(57, 57), Delete(2)],
    [Insert(20, 26), Insert(10, 18), Insert(99, 99), Insert(37, 59), Delete(2)],
    [Insert(3, 91), Insert(57, 57), Insert(35, 44), Insert(72, 81), Delete(2)],
    [Insert(58, 61), Insert(34, 35), Insert(56, 62), Insert(69, 78), Delete(0)],
    [
      Insert(63, 69),
      Insert(17, 24),
      Insert(3, 13),
      Insert(84, 94),
      Insert(18, 23),
      Insert(96, 98),
      Delete(1),
    ],
    [
      Insert(27, 27),
      Insert(42, 87),
      Insert(42, 49),
      Insert(69, 71),
      Insert(20, 27),
      Insert(8, 9),
      Insert(42, 49),
      Delete(1),
    ],
    [
      Insert(21, 23),
      Insert(83, 87),
      Insert(56, 58),
      Insert(1, 55),
      Insert(56, 59),
      Insert(58, 60),
      Insert(56, 65),
      Delete(1),
      Delete(0),
      Delete(6),
    ],
    [Insert(25, 25), Insert(67, 79), Delete(0), Search(65, 75)],
  ]
}

///|
test "gen01-gen18 under FORCE_OVERFLOWING_TEST (delta = start)" {
  for ops in gen_op_lists() {
    let state = TestState::new(forced_delta=true)
    for op in ops {
      state.accept_op(op)
    }
  }
}

///|
test "seeded fuzz under FORCE_OVERFLOWING_TEST (delta = start)" {
  let seeds : Array[UInt] = [11111, 22222, 33333]
  for seed in seeds {
    AutoTest::new(seed, forced_delta=true).run()
  }
}

///|
fn assert_pairs_eq(
  actual : Array[(Int, Int)],
  expected : Array[(Int, Int)],
) -> Unit raise {
  if actual != expected {
    fail("got \{Repr(actual)}, expected \{Repr(expected)}")
  }
}

// #endregion

// #region Assertion (intervalTree.test.ts:856-912)

///|
fn same_interval_node(
  left : @model.IntervalNode,
  right : @model.IntervalNode,
) -> Bool {
  left.same(right)
}

///|
fn assert_tree_invariants(t : @model.IntervalTree) -> Unit raise {
  assert_true(@model.get_node_color(@model.sentinel) is Black)
  assert_true(same_interval_node(@model.sentinel.parent(), @model.sentinel))
  assert_true(same_interval_node(@model.sentinel.left(), @model.sentinel))
  assert_true(same_interval_node(@model.sentinel.right(), @model.sentinel))
  assert_eq(@model.sentinel.start, 0)
  assert_eq(@model.sentinel.end, 0)
  assert_eq(@model.sentinel.delta, 0)
  assert_true(same_interval_node(t.root.parent(), @model.sentinel))
  assert_valid_tree(t)
}

///|
fn depth(n : @model.IntervalNode) -> Int raise {
  if same_interval_node(n, @model.sentinel) {
    // The leafs are black
    return 1
  }
  assert_eq(depth(n.left()), depth(n.right()))
  (if @model.get_node_color(n) is Black { 1 } else { 0 }) + depth(n.left())
}

///|
fn assert_valid_node(n : @model.IntervalNode, delta : Int) -> Unit raise {
  if same_interval_node(n, @model.sentinel) {
    return
  }
  let l = n.left()
  let r = n.right()
  if @model.get_node_color(n) is Red {
    assert_true(@model.get_node_color(l) is Black)
    assert_true(@model.get_node_color(r) is Black)
  }
  let mut expected_max_end = n.end
  if !same_interval_node(l, @model.sentinel) {
    assert_true(
      @model.interval_compare(
        l.start + delta,
        l.end + delta,
        n.start + delta,
        n.end + delta,
      ) <=
      0,
    )
    if l.max_end > expected_max_end {
      expected_max_end = l.max_end
    }
  }
  if !same_interval_node(r, @model.sentinel) {
    assert_true(
      @model.interval_compare(
        n.start + delta,
        n.end + delta,
        r.start + delta + n.delta,
        r.end + delta + n.delta,
      ) <=
      0,
    )
    if r.max_end + n.delta > expected_max_end {
      expected_max_end = r.max_end + n.delta
    }
  }
  assert_eq(n.max_end, expected_max_end)
  assert_valid_node(l, delta)
  assert_valid_node(r, delta + n.delta)
}

///|
fn assert_valid_tree(t : @model.IntervalTree) -> Unit raise {
  if same_interval_node(t.root, @model.sentinel) {
    return
  }
  assert_true(@model.get_node_color(t.root) is Black)
  assert_eq(depth(t.root.left()), depth(t.root.right()))
  assert_valid_node(t.root, 0)
}

// #endregion

// #region suite "generated"

///|
test "gen01" {
  test_interval_tree([Insert(28, 35), Insert(52, 54), Insert(63, 69)])
}

///|
test "gen02" {
  test_interval_tree([Insert(80, 89), Insert(92, 100), Insert(99, 99)])
}

///|
test "gen03" {
  test_interval_tree([Insert(89, 96), Insert(71, 74), Delete(1)])
}

///|
test "gen04" {
  test_interval_tree([Insert(44, 46), Insert(85, 88), Delete(0)])
}

///|
test "gen05" {
  test_interval_tree([Insert(82, 90), Insert(69, 73), Delete(0), Delete(1)])
}

///|
test "gen06" {
  test_interval_tree([Insert(41, 63), Insert(98, 98), Insert(47, 51), Delete(2)])
}

///|
test "gen07" {
  test_interval_tree([
    Insert(24, 26),
    Insert(11, 28),
    Insert(27, 30),
    Insert(80, 85),
    Delete(1),
  ])
}

///|
test "gen08" {
  test_interval_tree([Insert(100, 100), Insert(100, 100)])
}

///|
test "gen09" {
  test_interval_tree([Insert(58, 65), Insert(82, 96), Insert(58, 65)])
}

///|
test "gen10" {
  test_interval_tree([Insert(32, 40), Insert(25, 29), Insert(24, 32)])
}

///|
test "gen11" {
  test_interval_tree([
    Insert(25, 70),
    Insert(99, 100),
    Insert(46, 51),
    Insert(57, 57),
    Delete(2),
  ])
}

///|
test "gen12" {
  test_interval_tree([
    Insert(20, 26),
    Insert(10, 18),
    Insert(99, 99),
    Insert(37, 59),
    Delete(2),
  ])
}

///|
test "gen13" {
  test_interval_tree([
    Insert(3, 91),
    Insert(57, 57),
    Insert(35, 44),
    Insert(72, 81),
    Delete(2),
  ])
}

///|
test "gen14" {
  test_interval_tree([
    Insert(58, 61),
    Insert(34, 35),
    Insert(56, 62),
    Insert(69, 78),
    Delete(0),
  ])
}

///|
test "gen15" {
  test_interval_tree([
    Insert(63, 69),
    Insert(17, 24),
    Insert(3, 13),
    Insert(84, 94),
    Insert(18, 23),
    Insert(96, 98),
    Delete(1),
  ])
}

///|
test "gen16" {
  test_interval_tree([
    Insert(27, 27),
    Insert(42, 87),
    Insert(42, 49),
    Insert(69, 71),
    Insert(20, 27),
    Insert(8, 9),
    Insert(42, 49),
    Delete(1),
  ])
}

///|
test "gen17" {
  test_interval_tree([
    Insert(21, 23),
    Insert(83, 87),
    Insert(56, 58),
    Insert(1, 55),
    Insert(56, 59),
    Insert(58, 60),
    Insert(56, 65),
    Delete(1),
    Delete(0),
    Delete(6),
  ])
}

///|
test "gen18" {
  test_interval_tree([Insert(25, 25), Insert(67, 79), Delete(0), Search(65, 75)])
}

///|
test "force delta overflow" {
  // Search the IntervalNode ctor for FORCE_OVERFLOWING_TEST
  // to force that this test leads to a delta normalization.
  // (Source constants scaled by 1e-6 to fit 32-bit Int — see header.)
  test_interval_tree([
    Insert(686081138, 733009856),
    Insert(591031326, 591031326),
    Insert(940037682, 940037682),
    Insert(598413641, 598413641),
    Insert(800564156, 800564156),
    Insert(894198957, 894198957),
  ])
}

// #endregion

// #region seeded fuzz (source getRandomInt loop, fixed seeds)

///|
priv struct Rng {
  mut state : UInt
}

///|
fn Rng::next(self : Rng) -> UInt {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
/// `getRandomInt(min, max)`: inclusive on both ends.
fn Rng::int_in(self : Rng, min : Int, max : Int) -> Int {
  min +
  (self.next() % (max - min + 1).reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// `getRandomRange(min, max)`.
fn Rng::range_in(self : Rng, min : Int, max : Int) -> (Int, Int) {
  let begin = self.int_in(min, max)
  let length = if self.int_in(1, 10) <= 2 {
    // large range
    self.int_in(0, max - begin)
  } else {
    // small range
    self.int_in(0, if max - begin < 10 { max - begin } else { 10 })
  }
  (begin, begin + length)
}

///|
priv struct AutoTest {
  rng : Rng
  state : TestState
  mut insert_cnt : Int
  mut delete_cnt : Int
  mut change_cnt : Int
}

///|
fn AutoTest::new(seed : UInt, forced_delta? : Bool = false) -> AutoTest {
  let rng : Rng = { state: seed }
  let insert_cnt = rng.int_in(1, 30) // MIN_INSERTS..MAX_INSERTS
  let change_cnt = rng.int_in(10, 20) // MIN_CHANGE_CNT..MAX_CHANGE_CNT
  {
    rng,
    state: TestState::new(forced_delta~),
    insert_cnt,
    delete_cnt: 0,
    change_cnt,
  }
}

///|
fn AutoTest::run(self : AutoTest) -> Unit raise {
  while self.insert_cnt > 0 || self.delete_cnt > 0 || self.change_cnt > 0 {
    if self.insert_cnt > 0 {
      let (begin, end) = self.rng.range_in(1, 100)
      self.state.accept_op(Insert(begin, end))
      self.insert_cnt -= 1
      self.delete_cnt += 1
    } else if self.change_cnt > 0 {
      let idx = self.rng.int_in(0, self.delete_cnt - 1)
      let (begin, end) = self.rng.range_in(1, 100)
      self.state.accept_op(
        Change(self.state.get_existing_node_id(idx), begin, end),
      )
      self.change_cnt -= 1
    } else {
      let idx = self.rng.int_in(self.delete_cnt / 2, self.delete_cnt - 1)
      self.state.accept_op(Delete(self.state.get_existing_node_id(idx)))
      self.delete_cnt -= 1
    }

    // Let's also search for something...
    let (begin, end) = self.rng.range_in(1, 100)
    self.state.accept_op(Search(begin, end))
  }
}

///|
test "seeded fuzz (getRandomInt loop, seeds 11111/22222/33333/44444/55555)" {
  let seeds : Array[UInt] = [11111, 22222, 33333, 44444, 55555]
  for seed in seeds {
    AutoTest::new(seed).run()
  }
}

// #endregion

// #region suite "searching" (the Cormen tree)

///|
fn create_cormen_tree() -> @model.IntervalTree {
  let r = @model.IntervalTree()
  let data = [
    (16, 21),
    (8, 9),
    (25, 30),
    (5, 8),
    (15, 23),
    (17, 19),
    (26, 26),
    (0, 3),
    (6, 10),
    (19, 20),
  ]
  for interval in data {
    let (start, end) = interval
    let node = @model.IntervalNode("", start, end)
    r.insert(node)
  }
  r
}

///|
fn assert_interval_search(
  t : @model.IntervalTree,
  start : Int,
  end : Int,
  expected : Array[(Int, Int)],
) -> Unit raise {
  let actual_nodes = t.interval_search(start, end, 0, false, false, 0, false)
  let actual = actual_nodes.map(n => {
    (n.cached_absolute_start, n.cached_absolute_end)
  })
  assert_pairs_eq(actual, expected)
}

///|
test "cormen 1->2" {
  assert_interval_search(create_cormen_tree(), 1, 2, [(0, 3)])
}

///|
test "cormen 4->8" {
  assert_interval_search(create_cormen_tree(), 4, 8, [(5, 8), (6, 10), (8, 9)])
}

///|
test "cormen 10->15" {
  assert_interval_search(create_cormen_tree(), 10, 15, [(6, 10), (15, 23)])
}

///|
test "cormen 21->25" {
  assert_interval_search(create_cormen_tree(), 21, 25, [
    (15, 23),
    (16, 21),
    (25, 30),
  ])
}

///|
test "cormen 24->24" {
  assert_interval_search(create_cormen_tree(), 24, 24, [])
}

// #endregion
