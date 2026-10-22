///|
fn session_start_proposal(
  snapshot : @protocol.SessionStartsSnapshot,
  request_id : String,
) -> @protocol.SessionStartProposal raise @host.PayloadError {
  guard snapshot.proposals
    .iter()
    .find_first(proposal => proposal.request_id == request_id)
    is Some(proposal) else {
    raise PayloadError("unknown session start suggestion")
  }
  proposal
}

///|
async fn ApiState::save_session_start(
  self : ApiState,
  source : String,
  proposal : @protocol.SessionStartProposal,
  workspace? : String,
  result~ : Bool = false,
) -> @protocol.SessionStartsSnapshot {
  @engine.with_session_starts(
    self.manager,
    source,
    snapshot => self.publish(SessionStartsChanged(snapshot)),
    store => {
      let snapshot = store.snapshot()
      ignore(session_start_proposal(snapshot, proposal.request_id))
      store.save(
        snapshot.proposals.map(current => {
          if current.request_id == proposal.request_id {
            proposal
          } else {
            current
          }
        }),
      )
    },
    workspace?,
    allow_archived=result,
  )
}

///|
priv enum SessionStartReceipt {
  Uncommitted
  Committed(archived~ : Bool)
}

///|
async fn ApiState::session_start_receipt(
  self : ApiState,
  source : String,
  proposal : @protocol.SessionStartProposal,
  workspace? : String,
) -> SessionStartReceipt {
  guard proposal.target_session is Some(target) else { return Uncommitted }
  let archived = target != source &&
    @engine.session_start_target_archived(target, proposal.workspace)
  let payload : @protocol.LoadSessionPayload = {
    session: target,
    workspace: if target == source {
      workspace
    } else {
      Some(proposal.workspace)
    },
  }
  let loaded = if archived {
    @engine.load_archived_session(self.manager, payload)
  } else {
    @engine.load_session(self.manager, payload)
  }
  if message_committed(loaded.session, "session-start-" + proposal.id) {
    Committed(archived~)
  } else {
    Uncommitted
  }
}

///|
async fn ApiState::complete_session_start(
  self : ApiState,
  source : String,
  proposal : @protocol.SessionStartProposal,
  archived~ : Bool = false,
  workspace? : String,
) -> @protocol.SessionStartsSnapshot {
  if !archived && proposal.target_session is Some(target) && target != source {
    @engine.initialize_session_title(self.manager, {
      session: target,
      workspace: proposal.workspace,
      title: proposal.title,
    })
    publish_session_changed(self, "created", target, proposal.workspace)
  }
  self.save_session_start(
    source,
    {
      ..proposal,
      status: if proposal.target_session == Some(source) {
        "here"
      } else {
        "started"
      },
      error: None,
    },
    workspace?,
    result=true,
  )
}

///|
async fn ApiState::session_starts_list(
  self : ApiState,
  source : String,
  workspace? : String,
  archived~ : Bool = false,
) -> @protocol.SessionStartsSnapshot {
  let snapshot = @engine.session_starts_list(
    self.manager,
    source,
    workspace?,
    archived~,
  )
  if archived {
    return snapshot
  }
  let workspace = snapshot.workspace
  for initial in snapshot.proposals {
    guard initial.status == "starting" else { continue }
    // Return live pending work immediately. Only a free operation lock can
    // identify an interrupted decision that needs recovery after restart.
    ignore(
      @engine.try_with_session_start_decision(
        source,
        initial.id,
        () => {
          let latest = @engine.session_starts_list(
            self.manager,
            source,
            workspace?,
            archived~,
          )
          let proposal = session_start_proposal(latest, initial.request_id)
          guard proposal.status == "starting" else { return }
          try {
            match self.session_start_receipt(source, proposal, workspace?) {
              Committed(archived~) =>
                ignore(
                  self.complete_session_start(
                    source,
                    proposal,
                    archived~,
                    workspace?,
                  ),
                )
              Uncommitted =>
                ignore(
                  self.save_session_start(
                    source,
                    {
                      ..proposal,
                      status: "failed",
                      error: Some(
                        "The host stopped before the task was confirmed. Retry to continue with the same session.",
                      ),
                    },
                    workspace?,
                    result=true,
                  ),
                )
            }
          } catch {
            error =>
              ignore(
                self.save_session_start(
                  source,
                  {
                    ..proposal,
                    status: "failed",
                    error: Some(error.to_string()),
                  },
                  workspace?,
                  result=true,
                ),
              )
          }
        },
        workspace?,
      ),
    )
  }
  @engine.session_starts_list(self.manager, source, workspace?, archived~)
}

///|
async fn ApiState::propose_session_start(
  self : ApiState,
  source : String,
  request : @protocol.SessionStartRequest,
) -> @protocol.SessionStartProposal {
  guard @pathx.Absolute::from_uri_path(request.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(_) else {
    raise @mcp.ToolError("workspace is not a registered project")
  }
  @engine.with_session_starts(
    self.manager,
    source,
    snapshot => self.publish(SessionStartsChanged(snapshot)),
    store => {
      let snapshot = store.snapshot()
      if snapshot.proposals
        .iter()
        .find_first(proposal => proposal.request_id == request.request_id)
        is Some(existing) {
        guard store.request(request.request_id) == Some(request) else {
          raise @mcp.ToolError(
            "request_id was reused with different session start arguments",
          )
        }
        return existing
      }
      let proposal = request.proposal(@uuid.mint())
      ignore(store.save([..snapshot.proposals, proposal]))
      proposal
    },
  )
}

///|
async fn ApiState::session_starts_decide(
  self : ApiState,
  decision : @protocol.SessionStartDecision,
) -> @protocol.SessionStartsSnapshot {
  let source_snapshot = @engine.session_starts_list(
    self.manager,
    decision.session,
    workspace?=decision.workspace,
  )
  let workspace = source_snapshot.workspace
  let initial = session_start_proposal(source_snapshot, decision.request_id)
  // An admitted choice is host-owned through its durable receipt even if the
  // transport disconnects. Only this proposal's operation lock spans the wait.
  @async.protect_from_cancel(() => {
    @engine.with_session_start_decision(
      decision.session,
      initial.id,
      () => {
        let snapshot = @engine.session_starts_list(
          self.manager,
          decision.session,
          workspace?,
        )
        let proposal = session_start_proposal(snapshot, decision.request_id)
        if ["started", "here", "dismissed"].contains(proposal.status) {
          return snapshot
        }
        let receipt = self.session_start_receipt(
          decision.session,
          proposal,
          workspace?,
        ) catch {
          error =>
            return self.save_session_start(
              decision.session,
              {
                ..proposal,
                status: if decision.action == "dismiss" {
                  "dismissed"
                } else {
                  "failed"
                },
                error: if decision.action == "dismiss" {
                  None
                } else {
                  Some(error.to_string())
                },
              },
              workspace?,
              result=decision.action != "dismiss",
            )
        }
        if receipt is Committed(archived~) {
          return self.complete_session_start(
            decision.session,
            proposal,
            archived~,
            workspace?,
          )
        }
        if decision.action == "dismiss" {
          return self.save_session_start(
            decision.session,
            { ..proposal, status: "dismissed", error: None, },
            workspace?,
          )
        }
        let target = proposal.target_session.unwrap_or(
          if decision.action == "here" {
            decision.session
          } else {
            "s" + proposal.id
          },
        )
        guard (target == decision.session) == (decision.action == "here") else {
          raise @host.PayloadError("retry the previously selected destination")
        }
        let model = if decision.action == "start" {
          decision.model.unwrap_or(proposal.model)
        } else {
          proposal.model
        }
        let workspace_mode = if decision.action == "start" {
          decision.workspace_mode.unwrap_or(proposal.workspace_mode)
        } else {
          proposal.workspace_mode
        }
        if decision.action == "start" &&
          workspace_mode == "local" &&
          @pathx.Absolute::from_uri_path(proposal.workspace) is Some(workspace) &&
          @worktree.tree_base(workspace, target) is Some(_) {
          raise @host.PayloadError(
            "This session already has a worktree. Retry using worktree mode.",
          )
        }
        let starting : @protocol.SessionStartProposal = {
          ..proposal,
          model,
          workspace_mode,
          status: "starting",
          target_session: Some(target),
          error: None,
        }
        ignore(self.save_session_start(decision.session, starting, workspace?))
        try {
          if decision.action == "here" {
            let here_options = if decision.here is Some(options) {
              options
            } else {
              let settings = @engine.settings_status(self.manager)
              {
                model: None,
                thinking: None,
                approval: None,
                max_steps: None,
                followup_behavior: settings.followup_behavior,
              }
            }
            self.deliver_session_input(
              decision.session,
              proposal.task,
              "session-start-" + proposal.id,
              here_options~,
              workspace?,
            )
          } else {
            self.start_proposed_session(starting, target)
          }
          self.complete_session_start(decision.session, starting, workspace?)
        } catch {
          error =>
            self.save_session_start(
              decision.session,
              { ..starting, status: "failed", error: Some(error.to_string()), },
              workspace?,
              result=true,
            )
        }
      },
      workspace?,
    )
  })
}

///|
async fn ApiState::start_proposed_session(
  self : ApiState,
  proposal : @protocol.SessionStartProposal,
  target : String,
) -> Unit {
  let mode = proposal.workspace_mode
  if mode == "worktree" {
    ignore(
      @worktree.create(
        self.manager.worktree_host(),
        proposal.workspace,
        @worktree.WorktreeOwner::openseek(target),
        worktrees => {
          publish_worktree_changed(self, proposal.workspace, worktrees)
        },
      ),
    )
  }
  // Subscribe before admission: `accepted` alone is never the folded link.
  @async.with_task_group(group => {
    let events : @async.Queue[MessageDeliveryInput] = Queue(kind=Blocking(64))
    let subscription = self.subscribe(
      events,
      map=notification => {
        match notification {
          SessionEvent(commit) if commit.session == target =>
            Some(Event(notification))
          AgentFinished(_) | AgentError(_) | AgentConnected(_) =>
            Some(Event(notification))
          _ => None
        }
      },
      on_lag=_ => group.spawn_bg(no_wait=true, () => events.put(Resync)),
    )
    defer subscription.close()
    let id = "session-start-" + proposal.id
    let submitted = @engine.submit_session_start(
      self.manager,
      self.sink(),
      {
        session: target,
        task: proposal.task,
        images: [],
        submission_id: Some(id),
        workspace: Some(proposal.workspace),
        model: proposal.model,
        thinking: proposal.thinking,
        approval: None,
        max_steps: proposal.max_steps,
      },
      result => group.spawn_bg(no_wait=true, () => events.put(Receipt(result))),
    )
    defer submitted.close()
    for ;; {
      match events.get() {
        Event(SessionEvent(commit)) if commit.event.item is User(user) &&
          user.submission_id == Some(id) => break
        Event(AgentFinished(finished)) if finished.run_id == submitted.run_id => {
          let loaded = @engine.load_session(self.manager, {
            session: target,
            workspace: Some(proposal.workspace),
          })
          guard message_committed(loaded.session, id) else {
            raise @host.PayloadError(
              "session ended before confirming the initial task",
            )
          }
          break
        }
        Receipt(result) => {
          let loaded = @engine.load_session(self.manager, {
            session: target,
            workspace: Some(proposal.workspace),
          })
          if message_committed(loaded.session, id) {
            break
          }
          raise @host.PayloadError(
            if result is Dropped {
              "engine dropped the initial task before confirming it"
            } else {
              "engine stopped before confirming the initial task"
            },
          )
        }
        Event(AgentConnected(_)) => {
          let loaded = @engine.load_session(self.manager, {
            session: target,
            workspace: Some(proposal.workspace),
          })
          guard message_committed(loaded.session, id) else {
            raise @host.PayloadError(
              "engine restarted before confirming the initial task",
            )
          }
          break
        }
        Resync => {
          subscription.resume_delivery()
          let loaded = @engine.load_session(self.manager, {
            session: target,
            workspace: Some(proposal.workspace),
          })
          if message_committed(loaded.session, id) {
            break
          }
          if submitted.result() is Some(_) {
            raise @host.PayloadError(
              "engine stopped before confirming the initial task",
            )
          }
        }
        _ => ()
      }
    }
  })
}
