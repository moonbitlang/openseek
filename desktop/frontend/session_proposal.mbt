///|
/// The host's approval kind for a conversation another one proposed. It is
/// answered from its own row above the composer, never as the composer's
/// question: unanswered while open, answered while the host starts it. The
/// host stops listing it once the conversation exists, or when it was
/// dismissed, withdrawn or failed.
const SessionStartApproval : String = "session.start"

///|
fn PendingApproval::is_proposal(self : PendingApproval) -> Bool {
  self.tool_name == SessionStartApproval
}

///|
/// The rows of `conversation`'s proposals, in the host's order.
fn Model::proposals(
  self : Model,
  conversation : Conversation,
) -> Array[@composer.SessionProposal] {
  guard self.device_state(conversation.device)
    is Some({ approval_snapshot: Some(snapshot), .. }) else {
    return []
  }
  snapshot.approvals
  .iter()
  .filter(item => {
    item.session == conversation.session_id && item.approval.is_proposal()
  })
  .map(item => {
    let proposal : @composer.SessionProposal = {
      id: item.approval.id,
      title: item.approval.detail,
      brief: item.approval.body.unwrap_or(""),
      starting: item.approval.answered,
    }
    proposal
  })
  .to_array()
}

///|
/// Answer an open proposal of the active conversation. The host takes the
/// first answer and its next snapshot carries it to every client, so a
/// repeated click, or an answer from another client, is refused quietly.
fn Model::answer_proposal(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  id : String,
  allow : Bool,
) -> @cmd.Cmd {
  guard self.active_conversation() is Some(conv) &&
    self
    .proposals(conv)
    .any(proposal => proposal.id == id && !proposal.starting) else {
    return @cmd.none
  }
  approve_openseek(
    locale=self.locale,
    dispatch,
    conv.device,
    conv.session_id,
    id,
    None,
    allow~,
    settled_when_refused=true,
  )
}
