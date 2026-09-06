///|
/// Below this many steps a child cannot do useful work (read a few files
/// and submit), so `reserve` refuses the request rather than launching a
/// doomed run. Requests come from per-kind constants, not the model — this
/// floor is a guard against a miswired constant, and against a
/// pathological negative request reaching a child's `--max-steps`.
let min_useful_subrun_steps : Int = 8

///|
/// The per-turn subrun call allowance shared by every MODEL-initiated
/// subrun tool in a session (the callable review).
///
/// This is a runaway backstop, not a cost scheduler. Each child is already
/// individually bounded by its kind's step ceiling and wall deadline; what
/// nothing else bounds is how many children one turn can launch — and goal
/// runs execute unattended for hours, where a confused model in a
/// delegation loop would otherwise spawn children indefinitely. A step
/// pool was tried first and starved the wrong child: shared steps let
/// early calls truncate later ones to crumbs, and a truncated child dies
/// at its ceiling reporting nothing — the worst spend of all. Every
/// granted call now runs at its full requested ceiling.
///
/// Engine-initiated subruns (the goal-met gate) bypass this allowance
/// entirely: the model's delegation habits must not be able to starve the
/// audit of its own met claim.
///
/// The owner is the CLI layer: it creates one budget per session, passes
/// it to every subrun tool definition, and calls `reset_turn` at each turn
/// start. Enforcement is reserve-BEFORE-launch.
struct SubrunBudget {
  max_calls_per_turn : Int
  mut used_calls : Int
}

///|
/// The default cap is deliberately generous — ten delegations funds heavy
/// legitimate use (dogfood turns used three) while still cutting off a
/// runaway loop within one turn.
pub fn SubrunBudget::SubrunBudget(
  max_calls_per_turn? : Int = 10,
) -> SubrunBudget {
  { max_calls_per_turn, used_calls: 0, }
}

///|
/// Start a new parent turn: the allowance refills.
pub fn SubrunBudget::reset_turn(self : SubrunBudget) -> Unit {
  self.used_calls = 0
}

///|
/// Reserve one launch slot BEFORE spawning a child. Returns the child's
/// step ceiling — always the full `requested_steps` — or `None` when the
/// per-turn call count is spent or the request is below the useful floor.
/// A granted call is never truncated: the caller's per-kind ceiling is the
/// only step bound the child sees.
pub fn SubrunBudget::reserve(
  self : SubrunBudget,
  requested_steps : Int,
) -> Int? {
  if requested_steps < min_useful_subrun_steps {
    return None
  }
  if self.used_calls >= self.max_calls_per_turn {
    return None
  }
  self.used_calls += 1
  Some(requested_steps)
}

///|
test "the call count is the only ceiling and grants are never truncated" {
  let budget = SubrunBudget(max_calls_per_turn=2)
  // Full grant every time, regardless of how much earlier calls asked for.
  assert_true(budget.reserve(1_000) is Some(1_000))
  assert_true(budget.reserve(100) is Some(100))
  // The third call is refused: slots, not steps, are the resource.
  assert_true(budget.reserve(8) is None)
}

///|
test "reset_turn refills the allowance" {
  let budget = SubrunBudget(max_calls_per_turn=1)
  assert_true(budget.reserve(20) is Some(20))
  assert_true(budget.reserve(20) is None)
  budget.reset_turn()
  assert_true(budget.reserve(20) is Some(20))
}

///|
test "a request below the useful floor is refused without spending a slot" {
  let budget = SubrunBudget(max_calls_per_turn=1)
  assert_true(budget.reserve(-50) is None)
  assert_true(budget.reserve(0) is None)
  assert_true(budget.reserve(min_useful_subrun_steps - 1) is None)
  // The refusals consumed nothing.
  assert_true(budget.reserve(min_useful_subrun_steps) is Some(8))
}

///|
test "the default cap funds heavy legitimate use" {
  let budget = SubrunBudget()
  for _i in 0..<10 {
    assert_true(budget.reserve(100) is Some(100))
  }
  assert_true(budget.reserve(100) is None)
}
