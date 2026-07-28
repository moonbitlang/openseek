///|
test "available update replies carry an optional unavailability reason" {
  assert_true(
    ToJson::to_json(
      Available(
        version="0.2.0",
        installable=false,
        unavailable_reason=Some("move the app to Applications"),
      ),
    )
    is {
      "kind": String("available"),
      "version": String("0.2.0"),
      "installable": False,
      "unavailable_reason": String("move the app to Applications"),
      ..
    },
  )
  assert_true(
    ToJson::to_json(
      Available(version="0.2.0", installable=true, unavailable_reason=None),
    )
    is {
      "kind": String("available"),
      "installable": True,
      "unavailable_reason": Null,
      ..
    },
  )
}
