///|
#cfg(not(platform="windows"))
fn schedule_utc(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
) -> Int64 raise {
  @time.date_time(year, month, day, hour~, minute~).to_unix_second() * 1000
}

///|
fn schedule_wall(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
) -> Int64 raise {
  guard schedule_local_occurrence(
      @time.PlainDate::of(year, month, day),
      hour~,
      minute~,
    )
    is Some(at) else {
    fail("test wall time must exist")
  }
  at
}

///|
// Keep this test isolated from tests that change the process timezone.
async test "calendar schedules preserve wall time across dates and restarts" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let daily : @protocol.ScheduleTiming = Daily(hour=9, minute=30)
  let before = schedule_wall(2026, 12, 31, 9, 29)
  let due = schedule_wall(2026, 12, 31, 9, 30)
  assert_eq(schedule_next(daily, before), Some(due))
  assert_eq(schedule_next(daily, due), Some(schedule_wall(2027, 1, 1, 9, 30)))
  let weekly : @protocol.ScheduleTiming = Weekly(weekday=1, hour=9, minute=30)
  assert_eq(schedule_next(weekly, due), Some(schedule_wall(2027, 1, 4, 9, 30)))
  let state = recover_schedules(
    { entries: [schedule_fixture("daily", before, daily)], runs: [], },
    due,
  )
  assert_eq(state.entries[0].next_at, Some(schedule_wall(2027, 1, 1, 9, 30)))
  assert_eq(
    schedule_next(daily, schedule_wall(2028, 2, 28, 10, 0)),
    Some(schedule_wall(2028, 2, 29, 9, 30)),
  )
}

///|
// Windows' CRT accepts a different TZ syntax; test IANA DST rules on Unix.
#cfg(not(platform="windows"))
async test "calendar schedules skip DST gaps and execute folds only once" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("TZ")
  @sys.set_env_var("TZ", "America/New_York")
  defer {
    match previous {
      Some(value) => @sys.set_env_var("TZ", value)
      None => @sys.unset_env_var("TZ")
    }
    ignore(schedule_local_parts(0, [0, 0, 0, 0, 0]))
  }
  let gap : @protocol.ScheduleTiming = Daily(hour=2, minute=30)
  assert_eq(
    schedule_next(gap, schedule_utc(2026, 3, 8, 5, 0)),
    Some(schedule_utc(2026, 3, 9, 6, 30)),
  )
  let sunday : @protocol.ScheduleTiming = Weekly(weekday=7, hour=2, minute=30)
  assert_eq(
    schedule_next(sunday, schedule_utc(2026, 3, 8, 5, 0)),
    Some(schedule_utc(2026, 3, 15, 6, 30)),
  )
  let fold : @protocol.ScheduleTiming = Daily(hour=1, minute=30)
  assert_eq(
    schedule_next(fold, schedule_utc(2026, 11, 1, 4, 0)),
    Some(schedule_utc(2026, 11, 1, 5, 30)),
  )
  // Between the first and second 01:30, tomorrow is the next occurrence.
  assert_eq(
    schedule_next(fold, schedule_utc(2026, 11, 1, 6, 0)),
    Some(schedule_utc(2026, 11, 2, 6, 30)),
  )
}
