///|
test "default answer and Amdahl boundary cases" {
  let initial = initial_model()
  assert_eq(hundredths(speedup(initial)), "3.33")
  assert_eq(speedup({ serial_percent: 0, workers: 64, }), 64.0)
  assert_eq(speedup({ serial_percent: 100, workers: 64, }), 1.0)
  assert_eq(speedup({ serial_percent: 20, workers: 1, }), 1.0)
  assert_eq(hundredths(1.05), "1.05")
}

///|
test "local controls validate input and reset the full state" {
  let initial = initial_model()
  assert_true(update(initial, Serial("not a number")) == initial)
  assert_true(update(initial, Workers("")) == initial)
  assert_eq(update(initial, Serial("-1")).serial_percent, 0)
  assert_eq(update(initial, Serial("101")).serial_percent, 100)
  assert_eq(update(initial, Workers("0")).workers, 1)
  let changed = update(update(initial, Serial("50")), Workers("1000"))
  assert_eq(changed.serial_percent, 50)
  assert_eq(changed.workers, 64)
  assert_true(update(changed, Reset) == initial)
}
