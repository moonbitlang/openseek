///|
/// The verdict a row carries for `id`, or `None` when it carries none.
fn probe_verdict(model : Model, id : String) -> (Bool, String)? {
  match model.custom_model_probe.get(id) {
    Some(Probed(ok~, detail~)) => Some((ok, detail))
    _ => None
  }
}

///|
/// The connection test runs after the save, so its verdict belongs to the row:
/// by the time the reply arrives the editor is gone. These drive the messages
/// directly, which is where that hand-off happens.
fn submit_custom_model(id : String) -> Model {
  let added = update_msg(
      test_dispatch(),
      CustomModelAdd,
      initial_model(desktop=false),
    ).1
  let named = update_msg(test_dispatch(), CustomModelIdChanged(id), added).1
  update_msg(test_dispatch(), CustomModelSubmit, named).1
}

///|
test "saving closes the editor and marks the row as probing" {
  let model = submit_custom_model("gemini-4-hydrogen")
  // The editor gives way to the row immediately: the write does not wait for
  // the endpoint to answer.
  assert_true(model.custom_model is None)
  assert_true(
    model.custom_model_probe.get("gemini-4-hydrogen") is Some(Probing),
  )
}

///|
test "the probe verdict lands on the entry's row" {
  let saved = submit_custom_model("gemini-4-hydrogen")
  let ok = update_msg(
      test_dispatch(),
      CustomModelProbed(id="gemini-4-hydrogen", ok=true, detail="Connected."),
      saved,
    ).1
  assert_eq(probe_verdict(ok, "gemini-4-hydrogen"), Some((true, "Connected.")))
  // An unreachable endpoint keeps the entry: the save already happened, and the
  // row is where the user fixes the endpoint.
  let failed = update_msg(
      test_dispatch(),
      CustomModelProbeFailed(id="gemini-4-hydrogen", message="no route"),
      saved,
    ).1
  assert_eq(
    probe_verdict(failed, "gemini-4-hydrogen"),
    Some((false, "no route")),
  )
}

///|
test "editing or deleting an entry drops its verdict" {
  let saved = submit_custom_model("gemini-4-hydrogen")
  let probed = update_msg(
      test_dispatch(),
      CustomModelProbed(id="gemini-4-hydrogen", ok=true, detail="Connected."),
      saved,
    ).1
  let edited = update_msg(
      test_dispatch(),
      CustomModelEdit("gemini-4-hydrogen"),
      probed,
    ).1
  assert_true(probe_verdict(edited, "gemini-4-hydrogen") is None)
  let deleted = update_msg(
      test_dispatch(),
      CustomModelDelete("gemini-4-hydrogen"),
      probed,
    ).1
  assert_true(probe_verdict(deleted, "gemini-4-hydrogen") is None)
}
