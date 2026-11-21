///|
priv suberror UnexpectedEditDefect {
  Boom
}

///|
async test "session_edit_refusal translates timeouts and leaves unknown defects" {
  let timed_out = try {
    @async.with_timeout(1, () => @async.sleep(50))
    ""
  } catch {
    error => session_edit_refusal(error)
  }
  assert_eq(
    timed_out, "the edited message was not saved in time; the original conversation was kept",
  )
  let propagated = try {
    ignore(session_edit_refusal(Boom))
    false
  } catch {
    UnexpectedEditDefect::Boom => true
    _ => false
  }
  assert_true(propagated)
}
