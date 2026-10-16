///|
test "corrupt markers never prove settlement or a reboot" {
  assert_false(cleared_marker(None, None))
  for
    (clean, acknowledged) in [
      (Some(Json::null()), None),
      (Some({}), None),
      (None, Some(Json::null())),
      (
        None,
        Some({
          "reason": "host_reboot",
          "previous_boot": "same",
          "current_boot": "same",
        }),
      ),
    ] {
    let rejected = try {
      ignore(cleared_marker(clean, acknowledged))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_true(
    cleared_marker(
      Some({ "owner": { "instance_id": "i", "process": {} } }),
      None,
    ),
  )
  assert_true(
    cleared_marker(
      None,
      Some({
        "reason": "host_reboot",
        "previous_boot": "old",
        "current_boot": "new",
      }),
    ),
  )
}
