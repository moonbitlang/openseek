///|
priv suberror JobIdError {
  JobIdError(String)
}

///|
/// RFC 9562 UUIDv7: a 48-bit millisecond timestamp and 74 random bits.
/// A logical millisecond advances for same-tick allocation or clock rollback,
/// preserving runtime creation order without reading every historical record.
/// Randomness, rather than the clock or runtime generation, provides uniqueness
/// across processes/restarts. Fail before spawning/registering on entropy loss.
fn BgJobRuntime::next_id(self : BgJobRuntime) -> String raise {
  let (id, stamp) = mint_job_id(@env.now(), self.last_id_ms, @env.rand(10))
  self.last_id_ms = Some(stamp)
  id
}

///|
fn mint_job_id(
  now : UInt64,
  previous : UInt64?,
  entropy : Bytes?,
) -> (String, UInt64) raise {
  guard entropy is Some(bytes) && bytes.length() == 10 else {
    raise JobIdError(
      "Cannot allocate background job ID: secure entropy unavailable",
    )
  }
  let max_stamp = 0xffffffffffffUL
  guard now <= max_stamp &&
    previous.map(last => last < max_stamp).unwrap_or(true) else {
    raise JobIdError(
      "Cannot allocate background job ID: UUID timestamp exhausted",
    )
  }
  let stamp = match previous {
    Some(last) => if now > last { now } else { last + 1 }
    None => now
  }
  guard stamp <= max_stamp else {
    raise JobIdError(
      "Cannot allocate background job ID: UUID timestamp exhausted",
    )
  }
  let text = StringBuilder()
  for index in 0..<16 {
    if index == 4 || index == 6 || index == 8 || index == 10 {
      text.write_char('-')
    }
    let value = if index < 6 {
      ((stamp >> ((5 - index) * 8)) & 0xffUL).to_int()
    } else if index == 6 {
      (bytes[0].to_int() & 0x0f) | 0x70
    } else if index == 8 {
      (bytes[2].to_int() & 0x3f) | 0x80
    } else {
      bytes[index - 6].to_int()
    }
    if value < 0x10 {
      text.write_char('0')
    }
    text.write_string(value.to_string(radix=16))
  }
  (text.to_string(), stamp)
}

///|
test "UUIDv7 layout matches the RFC 9562 A.6 test vector" {
  let (id, stamp) = mint_job_id(
    0x017f22e279b0UL,
    None,
    Some(b"\xcc\xc3\x18\xc4\xdc\x0c\x0c\x07\x39\x8f"),
  )
  assert_eq(id, "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
  assert_eq(stamp, 0x017f22e279b0UL)
}

///|
test "UUID job order survives same-millisecond allocation and clock rollback" {
  let entropy = Some(b"0123456789")
  let (first, stamp) = mint_job_id(100UL, None, entropy)
  let (second, stamp) = mint_job_id(100UL, Some(stamp), entropy)
  let (third, stamp) = mint_job_id(50UL, Some(stamp), entropy)
  assert_true(first < second && second < third)
  assert_eq(stamp, 102UL)
}

///|
test "UUID allocation reports entropy failure and timestamp exhaustion" {
  for
    (now, previous, entropy) in [
      (1UL, None, None),
      (1UL, None, Some(b"short")),
      (0x1000000000000UL, None, Some(b"0123456789")),
      (1UL, Some(0xffffffffffffUL), Some(b"0123456789")),
    ] {
    try mint_job_id(now, previous, entropy) catch {
      JobIdError(_) => ()
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("invalid allocation must fail explicitly")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "previous runtime and legacy job IDs cannot read wait for or stop a new job" {
  let old_id = @async.with_task_group(group => {
    let old = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    old.start(program="sh", args=["-c", "printf old"], command="old")
  })
  @async.with_task_group(group => {
    let current = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    let new_id = current.start(program="sleep", args=["30"], command="new")
    assert_true(old_id != new_id)
    for stale_id in [old_id, "bg-1"] {
      assert_true(current.snapshot(stale_id) is None)
      assert_true(current.read_output(stale_id) is None)
      assert_false(current.stop(stale_id))
      try current.wait_any([stale_id]) catch {
        _ => ()
      } noraise {
        _ => fail("stale ID must not select the new job")
      }
    }
    assert_true(current.snapshot(new_id) is Some({ status: Running, .. }))
    assert_true(current.stop(new_id))
  })
}
