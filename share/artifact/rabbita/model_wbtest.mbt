///|
test "default answer and Amdahl boundary cases" {
  let initial = initial_model()
  assert_eq(hundredths(speedup(initial)), "3.33")
  assert_eq(speedup({ ..initial, serial_percent: 0, workers: 64, }), 64.0)
  assert_eq(speedup({ ..initial, serial_percent: 100, workers: 64, }), 1.0)
  assert_eq(speedup({ ..initial, workers: 1, }), 1.0)
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

///|
test "chart selection uses the same speedup model as the controls" {
  let initial = initial_model()
  let chart = speedup_chart(initial) catch { error => fail("\{error}") }
  let mut found = false
  for point in chart.points() {
    if point.data_x == 16.0 {
      let selected = update(initial, Chart(Click(Some(point))))
      assert_eq(selected.workers, 16)
      assert_true((point.data_y - speedup(selected)).abs() < 0.000001)
      found = true
      break
    }
  }
  assert_true(found)
}
