// A conversation another one proposed: never the composer's question, and a
// row above the composer whose state follows the host's approval snapshot.

///|
fn proposal_approval(
  session : String,
  id : String,
  answered~ : Bool,
) -> RecoveredApproval {
  {
    session,
    approval: {
      id,
      run_id: None,
      tool_name: "session.start",
      detail: "Focus helper",
      body: Some("Extract the focus helper."),
      answered,
    },
  }
}

///|
test "an open proposal is a row, never the composer's question" {
  let model = test_model()
  let session = model.active().session_id
  let (_, listed) = update_dev(
    test_dispatch(),
    ApprovalsChanged({
      generation: 1,
      approvals: [proposal_approval(session, "msg-1", answered=false)],
    }),
    model,
  )
  assert_true(
    listed.proposals(listed.active())
    is [
      {
        id: "msg-1",
        title: "Focus helper",
        brief: "Extract the focus helper.",
        starting: false,
      },
    ],
  )
  assert_true(listed.active().pending_approval is None)
  assert_true(
    listed.restore_message_approvals().active().pending_approval is None,
  )
}

///|
test "a proposal row follows the host's answer" {
  let model = test_model()
  let session = model.active().session_id
  let (_, listed) = update_dev(
    test_dispatch(),
    ApprovalsChanged({
      generation: 1,
      approvals: [proposal_approval(session, "msg-1", answered=false)],
    }),
    model,
  )
  // The click only asks; the row changes when the host has decided.
  let (_, asked) = update(
    test_dispatch(),
    ProposalAnswered(id="msg-1", allow=true),
    listed,
  )
  assert_true(asked.proposals(asked.active()) is [{ starting: false, .. }])
  // The host lists a proposal it is starting as answered, for every client.
  let (_, starting) = update_dev(
    test_dispatch(),
    ApprovalsChanged({
      generation: 2,
      approvals: [proposal_approval(session, "msg-1", answered=true)],
    }),
    asked,
  )
  assert_true(starting.proposals(starting.active()) is [{ starting: true, .. }])
  assert_true(starting.active().pending_approval is None)
  // It stops listing it once the conversation exists, or it was dismissed,
  // withdrawn or failed.
  let (_, gone) = update_dev(
    test_dispatch(),
    ApprovalsChanged({ generation: 3, approvals: [], }),
    starting,
  )
  assert_true(gone.proposals(gone.active()).is_empty())
}
