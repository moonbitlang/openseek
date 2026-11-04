///|
test "terminal control results do not consume or restore the user's editable draft" {
  let state = controls_fixture()
  let owner = @interop.Cloud(account=state.user_id.unwrap(), session="session")
  let before = state.conversations["session"]
  let action = @composer.FollowupSubmitted(
    identity={ owner, archive_generation: 0, },
    draft={ task: "output", mentions: [], images: [], },
    choice=@composer.SteerNow,
    attachments=[],
  )
  let (pending, _, _) = update(
    state,
    ControlAction(owner, action),
    @cmd.Emit(_ => @cmd.none),
    token="token",
    navigation=0,
  )
  let (pending, found) = pending.conversations["session"].with_command_result(
    before, "command",
  )
  assert_true(found)
  let input = pending.control_inputs[0]
  let accepted = pending.acknowledge_control(input.key)
  assert_eq(accepted.submission_sequence, before.submission_sequence)
  let rejected = accepted.reject_control(input.key, Some("rejected"))
  assert_eq(rejected.initial_submission, before.initial_submission)
}
