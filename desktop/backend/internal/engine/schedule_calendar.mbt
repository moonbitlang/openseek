///|
#borrow(parts)
extern "C" fn schedule_local_parts(
  seconds : Int64,
  parts : FixedArray[Int],
) -> Bool = "openseek_schedule_local_parts"

///|
#borrow(result)
extern "C" fn schedule_local_instant(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  dst : Int,
  result : FixedArray[Int64],
) -> Bool = "openseek_schedule_local_instant"

///|
fn schedule_weekday(date : @time.PlainDate) -> Int {
  match date.weekday() {
    Monday => 1
    Tuesday => 2
    Wednesday => 3
    Thursday => 4
    Friday => 5
    Saturday => 6
    Sunday => 7
  }
}

///|
// mktime normalizes nonexistent wall times. Round-trip each candidate so a
// spring-forward gap is skipped, and choose the earlier occurrence of a fold.
fn schedule_local_occurrence(
  date : @time.PlainDate,
  hour~ : Int,
  minute~ : Int,
) -> Int64? raise {
  let result : FixedArray[Int64] = [0]
  let parts : FixedArray[Int] = [0, 0, 0, 0, 0]
  let mut earliest : Int64? = None
  let mut converted = false
  for dst in [0, 1] {
    guard schedule_local_instant(
      date.year(),
      date.month(),
      date.day(),
      hour,
      minute,
      dst,
      result,
    ) else {
      continue
    }
    guard schedule_local_parts(result[0], parts) else {
      raise EngineError("Could not read the host's local time")
    }
    converted = true
    if parts[0] == date.year() &&
      parts[1] == date.month() &&
      parts[2] == date.day() &&
      parts[3] == hour &&
      parts[4] == minute {
      let at = result[0] * 1000
      earliest = Some(
        match earliest {
          Some(previous) => if previous < at { previous } else { at }
          None => at
        },
      )
    }
  }
  guard converted else {
    raise EngineError("Could not convert the scheduled local time")
  }
  earliest
}

///|
fn schedule_calendar_next(
  now : Int64,
  hour~ : Int,
  minute~ : Int,
  weekday? : Int,
) -> Int64 raise {
  let parts : FixedArray[Int] = [0, 0, 0, 0, 0]
  guard schedule_local_parts(now / 1000, parts) else {
    raise EngineError("Could not read the host's local time")
  }
  let today = @time.PlainDate::of(parts[0], parts[1], parts[2])
  // Include the following week if this week's time falls in a DST gap.
  for offset in 0..<=14 {
    let date = today.add_days(offset.to_int64())
    if weekday is Some(day) && schedule_weekday(date) != day {
      continue
    }
    if schedule_local_occurrence(date, hour~, minute~) is Some(at) && at > now {
      return at
    }
  }
  raise EngineError("Could not find the next scheduled local time")
}
