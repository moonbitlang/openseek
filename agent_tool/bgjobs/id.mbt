///|
/// RFC 9562 UUIDv7: a 48-bit millisecond timestamp and 74 random bits.
/// A logical millisecond advances for same-tick allocation or clock rollback,
/// preserving runtime creation order without reading every historical record.
/// Randomness, rather than the clock or runtime generation, provides uniqueness
/// across processes/restarts. Fail before spawning/registering on entropy loss.
fn BgJobRuntime::next_id(self : BgJobRuntime) -> String raise {
  let (id, stamp) = @uuid.mint(@env.now(), self.last_id_ms, @env.rand(10))
  self.last_id_ms = Some(stamp)
  compact_id(id)
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

///|
/// Losslessly encode all 128 UUID bits as 22 URL-safe characters.
fn compact_id(id : @x_uuid.UUID) -> String {
  @base64.encode(id.to_bytes(), padding=false)
  .replace_all(old="+", new="-")
  .replace_all(old="/", new="_")
}

///|
test "compact job IDs preserve all UUIDv7 bits" {
  let original = "017f22e2-79b0-7cc3-98c4-dc0c0c07398f"
  let compact = compact_id(@x_uuid.from_hex(original))
  assert_eq(compact, "AX8i4nmwfMOYxNwMDAc5jw")
  let bytes = @base64.decode(compact + "==")
  assert_eq(@x_uuid.from_bytes(bytes).to_string(), original)
  let edge = compact_id(
    @x_uuid.from_hex("ffffffff-ffff-7fff-bfff-ffffffffffff"),
  )
  assert_eq(edge.length(), 22)
  assert_false(edge.contains("/") || edge.contains("+") || edge.contains("="))
  let decoded = @base64.decode(
    edge.replace_all(old="-", new="+").replace_all(old="_", new="/") + "==",
  )
  assert_eq(
    @x_uuid.from_bytes(decoded).to_string(),
    "ffffffff-ffff-7fff-bfff-ffffffffffff",
  )
}
