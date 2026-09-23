///|
test "reminder_checklist renders numbered statuses and falls back to None" {
  guard @plan.reminder_checklist({
      "steps": [
        { "title": "read the failing test", "status": "completed" },
        { "title": "fix the parser", "status": "in_progress" },
      ],
    })
    is Some(lines) else {
    fail("expected a checklist")
  }
  assert_eq(
    lines,
    (
      #|1. [completed] read the failing test
      #|2. [in_progress] fix the parser
    ),
  )
  // A cleared plan and undecodable arguments both yield None.
  assert_true(@plan.reminder_checklist({ "steps": [] }) is None)
  assert_true(@plan.reminder_checklist({ "nonsense": true }) is None)
}

///|
test "plan definition exposes the expected name and schema shape" {
  let definition = @plan.definition()
  assert_eq(definition.name, "plan")
  guard definition.schema is JsonSchema({ "required": ["steps"], .. }) else {
    fail("expected steps to be required")
  }
  guard definition.execute is Sync(_) else { fail("expected a Sync executor") }
}
