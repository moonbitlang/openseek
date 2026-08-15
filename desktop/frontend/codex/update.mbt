// Codex's complete update boundary. The OpenSeek shell supplies only the
// focused host channel and its external-link command; every app-server state
// transition remains inside this package.

///|
pub fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  channel : @interop.ChannelId,
  open_external : (String) -> @cmd.Cmd,
) -> (@cmd.Cmd, State) {
  match msg {
    Refresh => {
      let (command, next) = state.refresh(dispatch, channel)
      (command, { ..next, notice: "" })
    }
    Composer(msg) => state.update_composer(dispatch, channel, msg)
    SymbolSearchDue(owner~, generation~) =>
      state.begin_completion_search(
        dispatch,
        channel,
        CodexSymbols,
        owner,
        generation,
      )
    FilesIndexed(owner~, files~, truncated~) =>
      (@cmd.none, state.with_files(owner, files, truncated))
    FilesFailed(owner~) => (@cmd.none, state.with_file_failure(owner))
    SkillsLoaded(cwd~, skills~) => (@cmd.none, state.with_skills(cwd, skills))
    SkillsFailed(cwd~) => (@cmd.none, state.with_skill_failure(cwd))
    SymbolsLoaded(owner~, generation~, items~) =>
      (@cmd.none, state.with_symbols(owner, generation, items))
    SymbolsFailed(owner~, generation~) =>
      (@cmd.none, state.with_symbols(owner, generation, []))
    ModelChanged(value) => (@cmd.none, { ..state, selected_model: value })
    GitLoaded(thread_id~, reply~) =>
      (@cmd.none, state.with_git_reply(thread_id, reply))
    ToggleGitDetails =>
      (@cmd.none, { ..state, git_details_open: !state.git_details_open })
    CloseGitDetails => (@cmd.none, state.with_git_details_closed())
    ToggleWorktreeMode =>
      if state.can_choose_worktree() {
        (@cmd.none, { ..state, placement: state.placement.toggled() })
      } else {
        (@cmd.none, state)
      }
    StartDraft(id~, cwd~) => {
      let previous = state.active_draft().map(draft => draft.id)
      let next = state.select_draft(id, cwd)
      let commands : Array[@cmd.Cmd] = []
      if !cwd.trim().is_empty() {
        commands.push(next.open_draft(dispatch, channel, id, cwd))
      }
      if previous is Some(previous) && previous != id {
        commands.push(state.close_draft(channel, previous))
      }
      (@cmd.batch(commands), next)
    }
    OpenThread(thread_id) => {
      let commands : Array[@cmd.Cmd] = [
        state.open_thread(dispatch, channel, thread_id),
      ]
      if state.active_draft() is Some(draft) {
        commands.push(state.close_draft(channel, draft.id))
      }
      (
        @cmd.batch(commands),
        {
          ..state,
          git_details_open: false,
          write_access: CodexNeedsResume,
          requested_thread: Some(thread_id),
          // Composer state belongs to the selected task. Until per-task drafts
          // are persisted, switching tasks deliberately starts clean.
          draft: "",
          mentions: [],
          completion: state.completion.dismissed(),
          pending_turn_delivery: None,
          loading: true,
          notice: "",
        },
      )
    }
    ArchiveThread(thread_id) =>
      (
        state.archive(dispatch, channel, thread_id, false),
        { ..state, archive_confirm: None, loading: true, notice: "" },
      )
    UnarchiveThread(thread_id) =>
      (
        state.unarchive(dispatch, channel, thread_id),
        { ..state, loading: true, notice: "" },
      )
    RepairWorktree =>
      if state.has_missing_worktree() {
        (
          state.repair_worktree(dispatch, channel),
          { ..state, loading: true, notice: "" },
        )
      } else {
        (@cmd.none, state)
      }
    ConfirmArchiveDiscard =>
      match state.archive_confirm {
        Some(confirm) =>
          (
            state.archive(dispatch, channel, confirm.thread_id, true),
            { ..state, archive_confirm: None, loading: true, notice: "" },
          )
        None => (@cmd.none, state)
      }
    CancelArchiveDiscard => (@cmd.none, { ..state, archive_confirm: None })
    WriterAcquired(thread_id) =>
      if state.active_thread() is Some(active) && active.id == thread_id {
        let next = {
          ..state,
          write_access: CodexWritable,
          loading: false,
          notice: "",
        }
        (next.send(dispatch, channel), { ..next, loading: true })
      } else {
        (@cmd.none, state)
      }
    WriterConflict(thread_id) =>
      if state.active_thread() is Some(active) && active.id == thread_id {
        (
          @cmd.none,
          {
            ..state,
            write_access: CodexActiveElsewhere,
            pending_turn_delivery: None,
            loading: false,
            notice: "This Codex task is active in another client. Its history is available here, but sending is read-only until that client releases it.",
          },
        )
      } else {
        (@cmd.none, state)
      }
    TurnDeliveryUnknown(thread_id~, message~, worktree~) =>
      if state.active_thread() is Some(active) &&
        active.id == thread_id &&
        state.pending_turn_delivery is Some(pending) &&
        pending.thread_id == thread_id {
        let next = match worktree {
          Some(worktree) => state.with_created_worktree(worktree)
          None => state
        }
        let next = {
          ..next,
          loading: true,
          notice: "Codex turn delivery could not be confirmed (" +
          message +
          "); refreshing this task before Send is enabled.",
        }
        (next.reconcile_turn_delivery(dispatch, channel, thread_id), next)
      } else {
        (@cmd.none, state)
      }
    Stop => (state.interrupt(dispatch, channel), state)
    Login =>
      (state.login(dispatch, channel), { ..state, loading: true, notice: "" })
    CancelLogin =>
      (
        state.cancel_login(dispatch, channel),
        { ..state, loading: true, notice: "" },
      )
    Logout =>
      (state.logout(dispatch, channel), { ..state, loading: true, notice: "" })
    RequestAnswer(request_key~, question_id~, answer~) =>
      (@cmd.none, state.with_request_answer(request_key, question_id, answer))
    Respond(request_key~, decision~) =>
      (state.respond(dispatch, channel, request_key, decision), state)
    Reply(kind~, value~) => {
      // A request that can mutate the selected task belongs to the draft or
      // stored thread that launched it. Reject it before touching loading,
      // input, placement, or filesystem ownership when selection moved on.
      if !state.accepts_reply(kind) {
        return (@cmd.none, state)
      }
      let mut next = if kind.settles_foreground() {
        { ..state, loading: false }
      } else {
        state
      }
      let mut cmd = @cmd.none
      match kind {
        CodexStatusReply => next = next.with_status(value)
        CodexRequestsReply => next = next.with_requests(value)
        CodexAccountReply => next = next.with_account(value)
        CodexModelsReply => next = next.with_models(value)
        CodexThreadsReply(archived, _) =>
          next = next.with_threads(value, archived)
        CodexDraftOpenReply(draft_id) => {
          next = next.with_open_draft(draft_id, value).loading_context(false)
          cmd = @cmd.batch([
            next.load_files(dispatch, channel),
            next.load_skills(dispatch, channel, force_reload=false),
          ])
        }
        CodexThreadReply(requested_thread) => {
          next = next.with_thread_reply(value, requested_thread~)
          // A malformed or mismatched snapshot leaves the requested id in
          // place. Only a verified selection may retarget Files/Terminal.
          if next.requested_thread is None {
            next = { ..next, write_access: CodexNeedsResume }
            next = next.loading_context(false)
            cmd = @cmd.batch([
              next.refresh_git(dispatch, channel),
              next.load_files(dispatch, channel),
              next.load_skills(dispatch, channel, force_reload=false),
            ])
          }
        }
        CodexDraftThreadReply(_) => {
          next = next.with_thread_reply(value)
          // Install the real id before starting the turn so every app-server
          // notification observes the stored selection. The preserved draft
          // and placement now flow through the ordinary Local/Worktree send.
          next = {
            ..next.with_pending_turn_delivery(),
            write_access: CodexWritable,
            loading: false,
          }
          next = next.loading_context(false)
          cmd = @cmd.batch([
            next.send(dispatch, channel),
            next.refresh_git(dispatch, channel),
            next.load_files(dispatch, channel),
            next.load_skills(dispatch, channel, force_reload=false),
          ])
          next = { ..next, loading: true }
        }
        CodexTurnReply(_) => next = next.with_turn_reply(value)
        CodexTurnReconcileReply(thread_id) =>
          next = next.with_reconciled_turn_reply(value, thread_id)
        CodexWorktreeTurnReply(_, worktree) => {
          next = next.with_created_worktree(worktree).with_turn_reply(value)
          cmd = @cmd.batch([
            next.refresh_git(dispatch, channel),
            next.load_files(dispatch, channel),
            next.load_skills(dispatch, channel, force_reload=false),
          ])
        }
        CodexWorktreeRepairReply(_, worktree) => {
          next = next.with_created_worktree(worktree)
          cmd = @cmd.batch([
            next.refresh_git(dispatch, channel),
            next.load_files(dispatch, channel),
            next.load_skills(dispatch, channel, force_reload=false),
          ])
        }
        CodexLoginReply => {
          next = next.with_login(value)
          if next.auth_url is Some(url) {
            cmd = open_external(url)
          }
        }
        CodexArchiveReply(thread_id) =>
          if value is Object(fields) &&
            @jsonx.json_text(fields, "kind") is Some("needs_force") {
            let refusal : @protocol.ArchiveNeedsForceReply = @json.from_json(
              value,
            ) catch {
              _ => {
                next = {
                  ..next,
                  notice: "Codex archive: malformed dirty-worktree reply",
                }
                return (@cmd.none, next)
              }
            }
            next = { ..next, archive_confirm: Some({ thread_id, refusal }) }
          } else {
            // App-server has archived the task. A last-second dirty checkout
            // can be retained, but the task still leaves the active catalog.
            let retained = value is Object(fields) &&
              @jsonx.json_text(fields, "kind")
              is Some("archived_worktree_retained")
            next = next.without_thread(thread_id)
            if retained {
              next = {
                ..next,
                notice: "Codex task archived, but its worktree was retained because new local changes appeared during archiving.",
              }
            }
            let (refresh, refreshed) = next.refresh_catalog(dispatch, channel)
            cmd = refresh
            next = refreshed
          }
        CodexUnarchiveReply(thread_id) => {
          next = next.without_archived_thread(thread_id)
          let (refresh, refreshed) = next.refresh_catalog(dispatch, channel)
          cmd = refresh
          next = refreshed
        }
        CodexCompactReply(original) | CodexReviewReply(original) => {
          if next.draft == original {
            next = { ..next, draft: "" }
          }
          next = { ..next, completion: next.completion.dismissed() }
        }
        CodexMutationReply => {
          let (refresh, refreshed) = next.refresh(dispatch, channel)
          cmd = refresh
          next = refreshed
        }
        CodexApprovalReply =>
          // `serverRequest/resolved` authoritatively removes the request.
          ()
      }
      (cmd, next)
    }
    Failed(kind~, message~) => {
      if !state.accepts_reply(kind) {
        return (@cmd.none, state)
      }
      let subject = match kind {
        CodexStatusReply => "Codex status"
        CodexRequestsReply => "Codex requests"
        CodexAccountReply => "Codex account"
        CodexModelsReply => "Codex models"
        CodexThreadsReply(false, _) => "Codex threads"
        CodexThreadsReply(true, _) => "Archived Codex threads"
        CodexDraftOpenReply(_) => "Codex draft"
        CodexThreadReply(_) | CodexDraftThreadReply(_) => "Codex thread"
        CodexTurnReply(_) | CodexWorktreeTurnReply(_, _) => "Codex turn"
        CodexTurnReconcileReply(_) => "Codex turn reconciliation"
        CodexWorktreeRepairReply(_, _) => "Codex worktree rebuild"
        CodexLoginReply => "Codex sign-in"
        CodexArchiveReply(_) => "Codex archive"
        CodexUnarchiveReply(_) => "Codex restore"
        CodexCompactReply(_) => "Codex compact"
        CodexReviewReply(_) => "Codex review"
        CodexMutationReply => "Codex action"
        CodexApprovalReply => "Codex response"
      }
      let next = if kind is CodexTurnReconcileReply(_) {
        {
          ..state,
          loading: false,
          notice: subject +
          ": " +
          message +
          ". Reopen the task to refresh it before retrying.",
        }
      } else if kind.settles_foreground() {
        {
          ..state,
          pending_turn_delivery: None,
          loading: false,
          notice: subject + ": " + message,
        }
      } else {
        { ..state, notice: subject + ": " + message }
      }
      (@cmd.none, next)
    }
    StatusChanged(value) => {
      let next = state.with_status(value)
      let next = if next.connection is CodexReady {
        next
      } else {
        { ..next, write_access: CodexNeedsResume }
      }
      let mut current = next
      let cmd = if next.connection is CodexReady {
        let (refresh, refreshed) = next.refresh(dispatch, channel)
        current = refreshed
        if next.active_thread() is Some(active) {
          let thread = if next.pending_turn_delivery is Some(pending) &&
            pending.thread_id == active.id {
            next.reconcile_turn_delivery(dispatch, channel, active.id)
          } else {
            next.open_thread(dispatch, channel, active.id)
          }
          @cmd.batch([refresh, thread])
        } else if next.active_draft() is Some(draft) && !draft.cwd.is_empty() {
          @cmd.batch([
            refresh,
            next.open_draft(dispatch, channel, draft.id, draft.cwd),
          ])
        } else {
          refresh
        }
      } else {
        @cmd.none
      }
      (cmd, current)
    }
    Notification(method_~, params~) => {
      let mut next = state.with_notification(method_, params)
      if method_ == "skills/changed" {
        let invalidated = next.loading_context(true)
        return (
          invalidated.load_skills(dispatch, channel, force_reload=false),
          invalidated,
        )
      }
      let cmd = if method_ == "account/updated" ||
        method_ == "account/login/completed" {
        CodexAccountReply.request(
          dispatch,
          channel,
          @commands.codex_account_read,
          { "refreshToken": false },
        )
      } else if method_ == "thread/archived" ||
        method_ == "thread/unarchived" ||
        method_ == "thread/name/updated" ||
        method_ == "thread/started" {
        let (refresh, refreshed) = next.refresh_catalog(dispatch, channel)
        next = refreshed
        refresh
      } else if method_ == "thread/settings/updated" &&
        next.active_thread() is Some(active) {
        // Re-read through the host so a cwd change cannot retarget Files,
        // Terminal, or language services from an unvalidated notification.
        // If a turn reply is also missing, the same read must first settle
        // that delivery frontier before Send can become available.
        if next.pending_turn_delivery is Some(pending) &&
          pending.thread_id == active.id {
          next.reconcile_turn_delivery(dispatch, channel, active.id)
        } else {
          next.open_thread(dispatch, channel, active.id)
        }
      } else if method_ == "turn/completed" {
        // A turn may check out another branch or create a PR. Refresh the same
        // compact status chip OpenSeek updates at its run boundary.
        next.refresh_git(dispatch, channel)
      } else {
        @cmd.none
      }
      (cmd, next)
    }
    ServerRequest(request_id~, method_~, params~) =>
      (@cmd.none, state.with_pending_request(request_id, method_, params))
  }
}

///|
/// Settle either source of a turn reply. `turn/start` returns a full turn,
/// while `turn/steer` may return only its id; notifications remain the
/// authoritative item lifecycle in both cases.
fn State::with_turn_reply(self : State, value : Json) -> State {
  let next = if value is Object(fields) &&
    fields.get("turn") is Some(turn) &&
    CodexTurn::decode(turn) is Some(turn) &&
    self.active_thread() is Some(active) {
    { ..self, selection: CodexStoredTask(active.with_turn(turn)), draft: "" }
  } else {
    { ..self, draft: "" }
  }
  {
    ..next,
    mentions: [],
    completion: next.completion.dismissed(),
    pending_turn_delivery: None,
  }
}

///|
test "Codex project add stays local until the first prompt" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let (_, draft) = update(
    dispatch,
    StartDraft(id="desktop-draft-1", cwd="/work/project"),
    State(),
    @interop.ChannelId::Local,
    open_external,
  )
  // The add action owns panels with a client-local id, but app-server still
  // has no thread for resume/archive/polling to touch.
  assert_eq(draft.active_id(), Some("desktop-draft-1"))
  assert_true(draft.active_thread() is None)
  assert_false(draft.can_prompt())

  let (_, opened) = update(
    dispatch,
    Reply(kind=CodexDraftOpenReply("desktop-draft-1"), value={
      "draftId": "desktop-draft-1",
      "cwd": "/work/project",
      "projectRoot": "/work/project",
    }),
    draft,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(opened.can_prompt())
  assert_eq(
    opened.worktree_launch_workspace(@interop.ChannelId::Local),
    @resource.of_path(@interop.ChannelId::Local, "/work/project"),
  )

  let (_, wants_worktree) = update(
    dispatch,
    ToggleWorktreeMode,
    opened,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(wants_worktree.placement is @composer.FreshWorktree)
  let (_, adopted) = update(
    dispatch,
    Reply(kind=CodexDraftThreadReply("desktop-draft-1"), value={
      "thread": {
        "id": "thread-real-1",
        "cwd": "/work/project",
        "projectRoot": "/work/project",
        "turns": [],
      },
    }),
    wants_worktree,
    @interop.ChannelId::Local,
    open_external,
  )
  // `thread/start` is adopted before worktree/turn completion. A later error
  // therefore retries this stored empty thread instead of making another.
  assert_eq(adopted.active_id(), Some("thread-real-1"))
  assert_true(adopted.active_thread() is Some(_))
  assert_true(adopted.placement is @composer.FreshWorktree)
  assert_true(adopted.loading)
}

///|
test "Codex cwd-less draft remains a Local first prompt" {
  let draft = State().select_draft("desktop-draft-local", "")
  assert_true(draft.can_prompt())
  assert_true(
    draft.worktree_launch_workspace(@interop.ChannelId::Local) is None,
  )
}

///|
test "cwd-less stored Codex tasks expose Terminal scratch without Files" {
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-scratch", "turns": [] },
  })
  assert_true(
    state.active_placement(@interop.ChannelId::Local)
    is Some(@interop.Scratch(root=None)),
  )
  assert_true(state.file_owner() is None)
}

///|
test "unknown Codex turn delivery refreshes before permitting retry" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let original = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "turns": [
          {
            "id": "turn-old",
            "status": "completed",
            "items": [
              {
                "id": "user-old",
                "type": "userMessage",
                "content": [{ "type": "text", "text": "older" }],
              },
            ],
          },
        ],
      },
    }),
    draft: "new prompt",
  }.with_pending_turn_delivery()
  let (_, refreshing) = update(
    dispatch,
    TurnDeliveryUnknown(
      thread_id="thread-1",
      message="connection closed",
      worktree=None,
    ),
    original,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(refreshing.pending_turn_delivery is Some(_))
  assert_true(refreshing.loading)
  assert_false(refreshing.can_prompt())

  let accepted_snapshot : Json = {
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-old",
          "status": "completed",
          "items": [
            {
              "id": "user-old",
              "type": "userMessage",
              "content": [{ "type": "text", "text": "older" }],
            },
          ],
        },
        {
          "id": "turn-new",
          "status": "inProgress",
          "items": [
            {
              "id": "user-new",
              "type": "userMessage",
              "content": [{ "type": "text", "text": "new prompt" }],
            },
          ],
        },
      ],
    },
  }
  let (_, recovered) = update(
    dispatch,
    Reply(kind=CodexTurnReconcileReply("thread-1"), value=accepted_snapshot),
    refreshing,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(recovered.draft_text(), "")
  assert_true(recovered.pending_turn_delivery is None)
  assert_false(recovered.loading)

  let undelivered = {
    ..original,
    pending_turn_delivery: original.pending_turn_delivery,
    loading: true,
  }
  let (_, retryable) = update(
    dispatch,
    Reply(kind=CodexTurnReconcileReply("thread-1"), value={
      "thread": {
        "id": "thread-1",
        "turns": [
          {
            "id": "turn-old",
            "status": "completed",
            "items": [
              {
                "id": "user-old",
                "type": "userMessage",
                "content": [{ "type": "text", "text": "older" }],
              },
            ],
          },
        ],
      },
    }),
    undelivered,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(retryable.draft_text(), "new prompt")
  assert_true(retryable.pending_turn_delivery is None)
  assert_true(retryable.can_prompt())
}

///|
test "Codex update handlers are pure and idempotent" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "cwd": "/work/project",
        "preview": "Package test",
        "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
      },
    }),
    draft: "inspect this",
    login_id: Some("login-1"),
    pending_requests: [
      {
        request_id: Json::string("request-1"),
        method_: "item/commandExecution/requestApproval",
        params: { "reason": "test" },
        answers: Map([]),
      },
    ],
  }
  let messages : Array[Msg] = [
    Refresh,
    Composer(@composer.ControllerDraftChanged("next draft")),
    ModelChanged("gpt-test"),
    ToggleGitDetails,
    CloseGitDetails,
    ToggleWorktreeMode,
    StartDraft(id="desktop-test", cwd="/work/project"),
    OpenThread("thread-1"),
    ArchiveThread("thread-1"),
    UnarchiveThread("thread-archived"),
    RepairWorktree,
    ConfirmArchiveDiscard,
    CancelArchiveDiscard,
    Composer(@composer.ControllerSubmitRequested),
    Stop,
    Login,
    CancelLogin,
    Logout,
    RequestAnswer(
      request_key=Json::string("request-1").stringify(),
      question_id="question-1",
      answer="yes",
    ),
    Respond(
      request_key=Json::string("request-1").stringify(),
      decision="accept",
    ),
    Reply(kind=CodexStatusReply, value={ "status": "ready" }),
    Reply(kind=CodexRequestsReply, value={ "data": [] }),
    Reply(kind=CodexAccountReply, value={
      "requiresOpenaiAuth": true,
      "account": Json::null(),
    }),
    Reply(kind=CodexModelsReply, value={ "data": [] }),
    Reply(kind=CodexThreadsReply(false, 0), value={ "data": [] }),
    Reply(kind=CodexThreadsReply(true, 0), value={ "data": [] }),
    Reply(kind=CodexThreadReply("thread-1"), value={
      "thread": { "id": "thread-1", "turns": [] },
    }),
    Reply(kind=CodexDraftThreadReply("desktop-test"), value={
      "thread": { "id": "thread-2", "turns": [] },
    }),
    Reply(kind=CodexTurnReply("thread-1"), value={
      "turn": { "id": "turn-2", "status": "inProgress" },
    }),
    Reply(
      kind=CodexWorktreeTurnReply("thread-1", {
        name: "wt-1",
        path: "/work/project/.worktrees/wt-1",
        present: true,
      }),
      value={ "turn": { "id": "turn-2", "status": "inProgress" } },
    ),
    Reply(
      kind=CodexWorktreeRepairReply("thread-1", {
        name: "wt-1",
        path: "/work/project/.worktrees/wt-1",
        present: true,
      }),
      value={},
    ),
    Reply(kind=CodexLoginReply, value={
      "loginId": "login-2",
      "authUrl": "https://example.test",
    }),
    Reply(kind=CodexArchiveReply("thread-1"), value={}),
    Reply(kind=CodexUnarchiveReply("thread-archived"), value={}),
    Reply(kind=CodexMutationReply, value={}),
    Reply(kind=CodexApprovalReply, value={}),
    Failed(kind=CodexTurnReply("thread-1"), message="test failure"),
    Failed(
      kind=CodexWorktreeRepairReply("thread-1", {
        name: "wt-1",
        path: "/work/project/.worktrees/wt-1",
        present: false,
      }),
      message="test failure",
    ),
    StatusChanged({ "status": "ready" }),
    Notification(method_="thread/name/updated", params={
      "threadId": "thread-1",
      "name": "Renamed",
    }),
    ServerRequest(
      request_id=Json::string("request-2"),
      method_="item/commandExecution/requestApproval",
      params={ "reason": "test" },
    ),
  ]
  for message in messages {
    let (_, once) = update(
      dispatch,
      message,
      state,
      @interop.ChannelId::Local,
      _ => @cmd.none,
    )
    let (_, twice) = update(
      dispatch,
      message,
      state,
      @interop.ChannelId::Local,
      _ => @cmd.none,
    )
    assert_true(once == twice)
  }
}

///|
test "Codex missing worktree waits for rebuild or archive confirmation" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/project/.worktrees/wt-1",
      "projectRoot": "/work/project",
      "openseekWorktree": {
        "name": "wt-1",
        "path": "/work/project/.worktrees/wt-1",
        "present": false,
      },
      "turns": [],
    },
  })
  assert_true(state.has_missing_worktree())
  assert_true(
    state.active_placement(@interop.ChannelId::Local)
    is Some(@interop.MissingWorktree(name="wt-1", ..)),
  )
  let (_, confirming) = update(
    dispatch,
    Reply(kind=CodexArchiveReply("thread-1"), value={
      "kind": "needs_force",
      "worktree": "wt-1",
      "dirty_paths": ["local.txt"],
      "dirty_path_count": 1,
    }),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  guard confirming.archive_confirm is Some(confirm) else {
    fail("dirty archive reply did not open confirmation")
  }
  assert_eq(confirm.thread_id, "thread-1")
  assert_eq(confirm.refusal.dirty_paths, ["local.txt"])
  let (_, cancelled) = update(
    dispatch,
    CancelArchiveDiscard,
    confirming,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(cancelled.archive_confirm is None)
  let rebuilt : CodexWorktree = {
    name: "wt-1",
    path: "/work/project/.worktrees/wt-1",
    present: true,
  }
  let (_, ready) = update(
    dispatch,
    Reply(kind=CodexWorktreeRepairReply("thread-1", rebuilt), value={}),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_false(ready.has_missing_worktree())
  assert_eq(
    ready
    .active_placement(@interop.ChannelId::Local)
    .bind(placement => placement.checkout_root())
    .map(uri => uri.path),
    Some("/work/project/.worktrees/wt-1"),
  )
}

///|
test "Codex history replies stay with the latest selected thread" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let listed = State().with_threads(
    {
      "data": [
        { "id": "thread-a", "preview": "Thread A" },
        { "id": "thread-b", "preview": "Thread B" },
      ],
    },
    false,
  )
  let (_, waiting_a) = update(
    dispatch,
    OpenThread("thread-a"),
    listed,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, waiting_b) = update(
    dispatch,
    OpenThread("thread-b"),
    waiting_a,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(waiting_b.requested_thread, Some("thread-b"))

  // A's slower success and failure both belong to the abandoned selection;
  // neither may settle B's loading state or replace its pending target.
  let (_, stale_success) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-a"), value={
      "thread": { "id": "thread-a", "turns": [] },
    }),
    waiting_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_success == waiting_b)
  let (_, stale_failure) = update(
    dispatch,
    Failed(kind=CodexThreadReply("thread-a"), message="late failure"),
    waiting_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_failure == waiting_b)

  let (_, selected_b) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-b"), value={
      "thread": { "id": "thread-b", "turns": [] },
    }),
    waiting_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(selected_b.active_id(), Some("thread-b"))
  assert_eq(selected_b.requested_thread, None)
  assert_false(selected_b.loading)

  // Once B is selected, even an A response arriving after B cannot rewind it.
  let (_, late_a) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-a"), value={
      "thread": { "id": "thread-a", "turns": [] },
    }),
    selected_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(late_a == selected_b)
}

///|
test "Codex draft and turn replies stay with their originating task" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let current_draft = {
    ..State().select_draft("draft-current", ""),
    draft: "keep current input",
    loading: true,
  }
  let (_, stale_draft) = update(
    dispatch,
    Reply(kind=CodexDraftThreadReply("draft-old"), value={
      "thread": { "id": "thread-old", "turns": [] },
    }),
    current_draft,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_draft == current_draft)
  let (_, stale_draft_failure) = update(
    dispatch,
    Failed(kind=CodexDraftThreadReply("draft-old"), message="late failure"),
    current_draft,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_draft_failure == current_draft)

  let current_thread = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-current", "turns": [] },
    }),
    draft: "keep current input",
    loading: true,
  }
  let (_, stale_turn) = update(
    dispatch,
    Reply(kind=CodexTurnReply("thread-old"), value={
      "turn": { "id": "turn-old", "status": "inProgress", "items": [] },
    }),
    current_thread,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_turn == current_thread)
  let (_, stale_worktree) = update(
    dispatch,
    Reply(
      kind=CodexWorktreeTurnReply("thread-old", {
        name: "old",
        path: "/old/worktree",
        present: true,
      }),
      value={
        "turn": { "id": "turn-old", "status": "inProgress", "items": [] },
      },
    ),
    current_thread,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_worktree == current_thread)
  let (_, stale_repair) = update(
    dispatch,
    Reply(
      kind=CodexWorktreeRepairReply("thread-old", {
        name: "old",
        path: "/old/worktree",
        present: true,
      }),
      value={},
    ),
    current_thread,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_repair == current_thread)
  let (_, stale_turn_failure) = update(
    dispatch,
    Failed(kind=CodexTurnReply("thread-old"), message="late failure"),
    current_thread,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_turn_failure == current_thread)
}

///|
test "Codex writer conflict is the active-elsewhere signal" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "turns": [] },
  })
  let (_, first) = update(
    dispatch,
    WriterConflict("thread-1"),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, repeated) = update(
    dispatch,
    WriterConflict("thread-1"),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(first.is_active_elsewhere())
  assert_false(first.is_running())
  assert_true(first == repeated)

  // Once the observed turn is idle, Send retries thread/resume instead of
  // leaving the task permanently disabled after one writer conflict.
  let retryable = { ..first, connection: CodexReady, draft: "try again" }
  let (_, retrying) = retryable.submit_composer(
    dispatch,
    @interop.ChannelId::Local,
  )
  assert_true(retrying.loading)

  let (_, stale) = update(
    dispatch,
    WriterConflict("thread-old"),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale == state)
}

///|
test "Codex task selection clears composer-local state" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-a", "cwd": "/work/a", "turns": [] },
    }),
    draft: "belongs to A",
    mentions: [CodexFileMention(name="a.mbt", path="src/a.mbt")],
  }
  let (_, next) = update(
    dispatch,
    OpenThread("thread-b"),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(next.draft, "")
  assert_true(next.mentions.is_empty())
  assert_true(next.completion.current() is None)
}

///|
test "background Codex metadata does not settle a foreground action" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State(loading=true)
  let (_, next) = update(
    dispatch,
    Reply(kind=CodexAccountReply, value={
      "requiresOpenaiAuth": true,
      "account": Json::null(),
    }),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(next.loading)
}

///|
test "newer Codex catalog refresh rejects an older pagination result" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, first) = update(
    dispatch,
    Refresh,
    State(),
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, second) = update(
    dispatch,
    Refresh,
    first,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, stale) = update(
    dispatch,
    Reply(kind=CodexThreadsReply(false, 1), value={
      "data": [{ "id": "stale", "preview": "Stale" }],
    }),
    second,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale == second)
  let (_, current) = update(
    dispatch,
    Reply(kind=CodexThreadsReply(false, 2), value={
      "data": [{ "id": "current", "preview": "Current" }],
    }),
    stale,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(current.threads[0].id, "current")
}

///|
test "Codex cwd notifications wait for an authorized thread read" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "cwd": "/work/old", "turns": [] },
  })
  let (_, notified) = update(
    dispatch,
    Notification(method_="thread/settings/updated", params={
      "threadId": "thread-1",
      "threadSettings": { "cwd": "/work/untrusted" },
    }),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(
    notified.active_thread().bind(thread => thread.cwd),
    Some("/work/old"),
  )
}

///|
test "Codex Git pill opens and closes its details" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/project",
      "gitInfo": { "branch": "feature" },
      "turns": [],
    },
  })
  let (_, opened) = update(
    dispatch,
    ToggleGitDetails,
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(opened.git_details_open())
  let (_, closed) = update(
    dispatch,
    CloseGitDetails,
    opened,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_false(closed.git_details_open())
}
