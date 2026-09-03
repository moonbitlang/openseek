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
      (command, { ..next, notice: "", })
    }
    ComposerAction(action) =>
      state.apply_composer_action(dispatch, channel, action)
    SkillsLoaded(cwd~, skills~) => (@cmd.none, state.with_skills(cwd, skills))
    SkillsFailed(cwd~) => (@cmd.none, state.with_skill_failure(cwd))
    ModelChanged(value) => (@cmd.none, state.with_selected_model(value))
    EffortChanged(value) => (@cmd.none, state.with_selected_effort(value))
    TogglePermissionMenu =>
      if state.can_choose_permission() {
        (
          @cmd.none,
          {
            ..state,
            permission_picker: state.permission_picker.toggle(),
            git_details_open: false,
          },
        )
      } else {
        (@cmd.none, state)
      }
    DismissPermissionMenu =>
      (
        @cmd.none,
        { ..state, permission_picker: state.permission_picker.close(), },
      )
    ChoosePermission(mode) =>
      if state.can_choose_permission() {
        (
          @cmd.none,
          {
            ..state,
            permission_picker: state.permission_picker.choose(mode),
            git_details_open: false,
          },
        )
      } else {
        (@cmd.none, state)
      }
    ConfirmFullAccess =>
      if state.can_choose_permission() {
        (
          @cmd.none,
          {
            ..state,
            permission_picker: state.permission_picker.confirm_full_access(),
          },
        )
      } else {
        (
          @cmd.none,
          { ..state, permission_picker: state.permission_picker.close(), },
        )
      }
    CancelFullAccess =>
      (
        @cmd.none,
        {
          ..state,
          permission_picker: state.permission_picker.cancel_full_access(),
        },
      )
    GitLoaded(thread_id~, generation~, requested_cwd~, reply~) =>
      (
        @cmd.none,
        state.with_git_reply(thread_id, generation, requested_cwd, reply),
      )
    WorktreeChanged(thread_id~, project_root~, name~, path~, present~) => {
      let applies = state.active_thread() is Some(active) &&
        active.id == thread_id
      let next = state.with_worktree_change(
        thread_id, project_root, name, path, present,
      )
      if present && applies {
        // Mint the same request fence as every other checkout transition, so
        // a Git answer for the prior placement cannot decorate this one.
        let (git, refreshed) = next.refresh_git(dispatch, channel)
        (
          @cmd.batch([
            git,
            refreshed.load_skills(dispatch, channel, force_reload=false),
          ]),
          refreshed,
        )
      } else {
        (@cmd.none, next)
      }
    }
    ToggleGitDetails =>
      (
        @cmd.none,
        {
          ..state,
          git_details_open: !state.git_details_open,
          permission_picker: state.permission_picker.close(),
        },
      )
    CloseGitDetails => (@cmd.none, state.with_git_details_closed())
    ToggleWorktreeMode =>
      if state.can_choose_worktree() {
        (@cmd.none, { ..state, placement: state.placement.toggled(), })
      } else {
        (@cmd.none, state)
      }
    StartDraft(id~, cwd~) => {
      let previous = state.active_draft().map(draft => draft.id)
      let mut next = state.select_draft(id, cwd)
      let commands : Array[@cmd.Cmd] = []
      if !cwd.trim().is_empty() {
        commands.push(next.open_draft(dispatch, channel, id, cwd))
        next = next.begin_foreground(CodexDraftOpenReply(id))
      }
      if previous is Some(previous) && previous != id {
        commands.push(state.close_draft(channel, previous))
      }
      (@cmd.batch(commands), next)
    }
    AbandonDraft => {
      guard state.active_draft() is Some(draft) else {
        return (@cmd.none, state)
      }
      // The unified model chip moved this fresh conversation to another
      // agent. Release the host-side draft authorization and deselect, so
      // the sidebar drops its composing "New chat" row instead of keeping a
      // stale draft the user has already walked away from.
      let commands : Array[@cmd.Cmd] = []
      if !draft.cwd.is_empty() {
        commands.push(state.close_draft(channel, draft.id))
      }
      (
        @cmd.batch(commands),
        {
          ..state,
          selection: CodexNoTask,
          draft: "",
          mentions: [],
          submitted_first_prompt: None,
          pending_steers: [],
          placement: @composer.LocalCheckout,
          foreground: None,
          loading: false,
          notice: "",
        },
      )
    }
    OpenThread(thread_id) =>
      if state.active_thread() is Some(active) &&
        active.id == thread_id &&
        (
          state.requested_thread is None ||
          state.requested_thread == Some(thread_id)
        ) {
        // Clicking the selected sidebar row is navigation at the root shell,
        // not a request to reacquire history. Preserve its local composer and
        // any foreground Stop authority.
        (@cmd.none, state)
      } else {
        let (read, activity_frontier, reading) = state.open_thread(
          dispatch, channel, thread_id,
        )
        let commands : Array[@cmd.Cmd] = [read]
        if state.active_draft() is Some(draft) {
          commands.push(state.close_draft(channel, draft.id))
        }
        (
          @cmd.batch(commands),
          {
            ..reading,
            git_details_open: false,
            requested_thread: Some(thread_id),
            // These fields are the adapter's last canonical submission snapshot.
            // The shared component keeps each task's unsent local draft under
            // its own identity, exactly as it does for OpenSeek conversations.
            draft: "",
            mentions: [],
            submitted_first_prompt: None,
            pending_steers: [],
            notice: "",
          }.begin_foreground(CodexThreadReply(thread_id, activity_frontier)),
        )
      }
    ArchiveThread(thread_id) =>
      (
        state.archive(dispatch, channel, thread_id, false),
        { ..state, archive_confirm: None, }.begin_foreground(
          CodexArchiveReply(thread_id),
        ),
      )
    UnarchiveThread(thread_id) =>
      (
        state.unarchive(dispatch, channel, thread_id),
        state.begin_foreground(CodexUnarchiveReply(thread_id)),
      )
    RepairWorktree =>
      match state.active_thread() {
        Some(active) if active.worktree is Some(worktree) && !worktree.present =>
          (
            state.repair_worktree(dispatch, channel),
            state.begin_foreground(
              CodexWorktreeRepairReply(active.id, worktree),
            ),
          )
        _ => (@cmd.none, state)
      }
    ConfirmArchiveDiscard =>
      match state.archive_confirm {
        Some(confirm) =>
          (
            state.archive(dispatch, channel, confirm.thread_id, true),
            { ..state, archive_confirm: None, }.begin_foreground(
              CodexArchiveReply(confirm.thread_id),
            ),
          )
        None => (@cmd.none, state)
      }
    CancelArchiveDiscard => (@cmd.none, { ..state, archive_confirm: None, })
    ResumeSucceeded(thread_id) =>
      if state.active_thread() is Some(active) &&
        active.id == thread_id &&
        state.owns_foreground(CodexResumeReply(thread_id)) {
        let next = {
          ..state.settle_foreground(CodexResumeReply(thread_id)),
          notice: "",
        }.begin_foreground(CodexTurnStartReply(thread_id))
        (next.send(dispatch, channel), next)
      } else {
        (@cmd.none, state)
      }
    Stop => (state.interrupt(dispatch, channel), state)
    Login =>
      (state.login(dispatch, channel), state.begin_foreground(CodexLoginReply))
    CancelLogin =>
      if state.login_id is Some(login_id) {
        (
          state.cancel_login(dispatch, channel),
          state.begin_foreground(CodexCancelLoginReply(login_id)),
        )
      } else {
        (@cmd.none, state)
      }
    Logout =>
      (
        state.logout(dispatch, channel),
        state.begin_foreground(CodexLogoutReply),
      )
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
      let mut next = state.settle_foreground(kind)
      let mut cmd = @cmd.none
      match kind {
        CodexStatusReply => next = next.with_status(value)
        CodexRequestsReply => next = next.with_requests(value)
        CodexAccountReply => next = next.with_account(value)
        CodexModelsReply => next = next.with_models(value)
        CodexThreadsReply(context) =>
          next = next.with_threads(
            value,
            context.archived,
            context.activity_frontier,
          )
        CodexDraftOpenReply(draft_id) => {
          next = next.with_open_draft(draft_id, value).loading_context(false)
          cmd = @cmd.batch([
            next.load_skills(dispatch, channel, force_reload=false),
          ])
        }
        CodexThreadReply(requested_thread, activity_frontier) => {
          next = next.with_thread_reply(
            value,
            CodexHistoryRead(requested_thread, activity_frontier),
          )
          // A malformed or mismatched snapshot leaves the requested id in
          // place. Only a verified selection may retarget Files/Terminal.
          if next.requested_thread is None &&
            next.active_thread() is Some(active) &&
            active.id == requested_thread {
            next = next.loading_context(false)
            let (git, refreshed) = next.refresh_git(dispatch, channel)
            next = refreshed
            cmd = @cmd.batch([
              git,
              next.load_skills(dispatch, channel, force_reload=false),
            ])
          }
        }
        CodexResumeReply(_) => ()
        CodexDraftThreadReply(_) => {
          next = next.with_thread_reply(value, CodexThreadStart)
          // Install the real id before starting the turn so every app-server
          // notification observes the stored selection. The preserved draft
          // and placement now flow through the ordinary Local/Worktree send.
          next = next.loading_context(false)
          let (git, refreshed) = next.refresh_git(dispatch, channel)
          next = refreshed
          cmd = @cmd.batch([
            next.send(dispatch, channel),
            git,
            next.load_skills(dispatch, channel, force_reload=false),
          ])
          if next.active_thread() is Some(active) {
            next = next.begin_foreground(CodexTurnStartReply(active.id))
          }
        }
        CodexTurnStartReply(_) => next = next.with_turn_start_reply(value)
        CodexTurnSteerReply(_) => next = next.with_turn_steer_reply(value)
        CodexWorktreeTurnReply(_, worktree) => {
          next = next
            .with_created_worktree(worktree)
            .with_turn_start_reply(value)
          let (git, refreshed) = next.refresh_git(dispatch, channel)
          next = refreshed
          cmd = @cmd.batch([
            git,
            next.load_skills(dispatch, channel, force_reload=false),
          ])
        }
        CodexWorktreeRepairReply(_, worktree) => {
          next = next.with_created_worktree(worktree)
          let (git, refreshed) = next.refresh_git(dispatch, channel)
          next = refreshed
          cmd = @cmd.batch([
            git,
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
            next = { ..next, archive_confirm: Some({ thread_id, refusal, }), }
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
        CodexCompactReply(_, original) | CodexReviewReply(_, original) =>
          if next.draft == original {
            next = { ..next, draft: "", }
          }
        CodexInterruptReply | CodexCancelLoginReply(_) | CodexLogoutReply => {
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
        CodexThreadsReply(context) =>
          if context.archived {
            "Archived Codex threads"
          } else {
            "Codex threads"
          }
        CodexDraftOpenReply(_) => "Codex draft"
        CodexThreadReply(_, _) | CodexDraftThreadReply(_) => "Codex thread"
        CodexTurnStartReply(_)
        | CodexTurnSteerReply(_)
        | CodexWorktreeTurnReply(_, _) => "Codex turn"
        CodexWorktreeRepairReply(_, _) => "Codex worktree rebuild"
        CodexLoginReply => "Codex sign-in"
        CodexArchiveReply(_) => "Codex archive"
        CodexUnarchiveReply(_) => "Codex restore"
        CodexCompactReply(_, _) => "Codex compact"
        CodexReviewReply(_, _) => "Codex review"
        CodexResumeReply(_) => "Codex resume"
        CodexInterruptReply => "Codex interrupt"
        CodexCancelLoginReply(_) => "Codex sign-in cancellation"
        CodexLogoutReply => "Codex sign-out"
        CodexApprovalReply => "Codex response"
      }
      let owns_foreground = state.owns_foreground(kind)
      let settled = if owns_foreground {
        match kind {
          CodexWorktreeTurnReply(_, worktree) =>
            state.with_created_worktree(worktree).settle_foreground(kind)
          CodexTurnSteerReply(thread_id) =>
            state.without_sending_steer(thread_id).settle_foreground(kind)
          _ => state.settle_foreground(kind)
        }
      } else {
        state
      }
      // A definite request error leaves the editable draft intact and removes
      // only the transient transcript preview. The error itself is rendered
      // directly; no read, retry, or delivery inference follows it.
      let settled = if owns_foreground &&
        (
          kind is CodexDraftThreadReply(_) ||
          kind is CodexTurnStartReply(_) ||
          kind is CodexWorktreeTurnReply(_, _)
        ) {
        { ..settled, submitted_first_prompt: None, }
      } else {
        settled
      }
      let next = if owns_foreground {
        { ..settled, notice: subject + ": " + message, }
      } else {
        { ..state, notice: subject + ": " + message, }
      }
      (@cmd.none, next)
    }
    StatusChanged(value) => {
      let next = state.with_status(value)
      let mut current = next
      let cmd = if next.connection is CodexReady {
        let (refresh, refreshed) = next.refresh(dispatch, channel)
        current = refreshed
        // A disconnect invalidates the old history request's activity epoch.
        // Retry its pending target before refreshing the still-rendered prior
        // selection; `open_thread` captures the new epoch in the reply kind.
        if next.requested_thread is Some(thread_id) {
          let (read, _, reading) = current.open_thread(
            dispatch, channel, thread_id,
          )
          current = reading
          @cmd.batch([refresh, read])
        } else if next.active_thread() is Some(active) {
          let (read, _, reading) = current.open_thread(
            dispatch,
            channel,
            active.id,
          )
          current = reading
          @cmd.batch([refresh, read])
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
    Notification(method_~, params~, generation~) => {
      // Receipt reconciliation must inspect the pre-notification item set;
      // applying the item first would make every new id look like a duplicate.
      let mut next = state
        .with_observed_steer_item(method_, params)
        .with_notification(method_, params, generation)
      if !next.can_choose_permission() {
        next = { ..next, permission_picker: next.permission_picker.close(), }
      }
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
          { refresh_token: false, },
        )
      } else if method_ == "thread/archived" ||
        method_ == "thread/unarchived" ||
        method_ == "thread/name/updated" ||
        method_ == "thread/started" {
        let (refresh, refreshed) = next.refresh_catalog(dispatch, channel)
        next = refreshed
        refresh
      } else if method_ == "turn/completed" {
        // A turn may check out another branch or create a PR. Refresh the same
        // compact status chip OpenSeek updates at its run boundary.
        let (git, refreshed) = next.refresh_git(dispatch, channel)
        next = refreshed
        git
      } else {
        @cmd.none
      }
      (cmd, next)
    }
    ServerRequest(request_id~, method_~, params~, generation~) =>
      (
        @cmd.none,
        state.with_pending_request(request_id, method_, params, generation),
      )
  }
}

///|
/// Settle a `turn/start` reply. Its canonical turn, when present, replaces the
/// first-input preview through the ordinary observed-item boundary.
fn State::with_turn_start_reply(self : State, value : Json) -> State {
  let next = if value is Object(fields) &&
    fields.get("turn") is Some(turn) &&
    CodexTurn::decode(turn) is Some(turn) &&
    self.active_thread() is Some(active) {
    { ..self, selection: CodexStoredTask(active.with_turn(turn)), draft: "", }
  } else {
    { ..self, draft: "", }
  }
  let next = match next.active_thread() {
    Some(active) if active.turns.iter().any(turn => turn.is_running()) =>
      { ..next, activity: next.activity.started(active.id), }
    _ => next
  }
  { ..next, mentions: [], submission_sequence: next.submission_sequence + 1, }.with_observed_first_prompt()
}

///|
/// Settle a `turn/steer` reply. Acceptance keeps the display receipt until a
/// canonical User item is known. A compatible full-turn reply may already
/// contain that item, so reconcile its new ids before installing the turn.
fn State::with_turn_steer_reply(self : State, value : Json) -> State {
  let accepted = self.with_accepted_steer(value)
  let next = if value is Object(fields) &&
    fields.get("turn") is Some(turn) &&
    CodexTurn::decode(turn) is Some(turn) &&
    accepted.active_thread() is Some(active) {
    let reconciled = accepted.with_observed_steer_turn(turn)
    {
      ..reconciled,
      selection: CodexStoredTask(active.with_turn(turn)),
      draft: "",
    }
  } else {
    { ..accepted, draft: "", }
  }
  { ..next, mentions: [], submission_sequence: next.submission_sequence + 1, }.with_observed_first_prompt()
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
  let submit = ComposerAction(
    @composer.DraftSubmitted(
      identity=wants_worktree.composer_identity(@interop.ChannelId::Local),
      draft={ task: "inspect this", mentions: [], },
    ),
  )
  let (_, submitting) = update(
    dispatch,
    submit,
    wants_worktree,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, submitting_again) = update(
    dispatch,
    submit,
    wants_worktree,
    @interop.ChannelId::Local,
    open_external,
  )
  // Submit changes pure state immediately: the local User row and Starting
  // status do not wait for thread creation or worktree setup.
  assert_true(submitting == submitting_again)
  assert_true(submitting.waiting_for_first_user_item())
  let starting_items = submitting.transcript_items()
  assert_eq(starting_items.length(), 1)
  assert_true(starting_items[0].kind is @transcript.User(_))
  assert_eq(starting_items[0].text(), Some("inspect this"))
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
    submitting,
    @interop.ChannelId::Local,
    open_external,
  )
  // `thread/start` is adopted before worktree/turn completion. A later error
  // therefore retries this stored empty thread instead of making another.
  assert_eq(adopted.active_id(), Some("thread-real-1"))
  assert_true(adopted.active_thread() is Some(_))
  assert_true(adopted.placement is @composer.FreshWorktree)
  assert_true(adopted.loading)
  assert_true(adopted.waiting_for_first_user_item())
  assert_eq(adopted.transcript_items().length(), 1)

  let worktree : CodexWorktree = {
    name: "wt-1",
    path: "/work/project/.worktrees/wt-1",
    present: true,
  }
  let (_, acknowledged) = update(
    dispatch,
    Reply(kind=CodexWorktreeTurnReply("thread-real-1", worktree), value={
      "turn": {
        "id": "turn-1",
        "status": "inProgress",
        "itemsView": "notLoaded",
      },
    }),
    adopted,
    @interop.ChannelId::Local,
    open_external,
  )
  // An ACK may omit its items. The accepted draft leaves the textarea but its
  // local transcript row stays until the real User item arrives.
  assert_eq(acknowledged.draft_text(), "")
  assert_true(acknowledged.waiting_for_first_user_item())
  assert_eq(acknowledged.transcript_items().length(), 1)

  // A fast follow-up may steer as soon as the start RPC exposes the running
  // turn, before the first prompt's canonical User item reaches this client.
  // FIFO reserves the next unseen User item for that older first-prompt receipt
  // and must not consume this steer receipt prematurely.
  let (_, early_steer) = update(
    dispatch,
    ComposerAction(
      @composer.DraftSubmitted(
        identity=acknowledged.composer_identity(@interop.ChannelId::Local),
        draft={ task: "steer early", mentions: [], },
      ),
    ),
    acknowledged,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(early_steer.pending_steers.length(), 1)

  let (_, observed) = update(
    dispatch,
    Notification(
      method_="item/started",
      params={
        "threadId": "thread-real-1",
        "turnId": "turn-1",
        "item": {
          "id": "user-1",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "inspect this" }],
        },
      },
      generation=1,
    ),
    early_steer,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_false(observed.waiting_for_first_user_item())
  let observed_items = observed.transcript_items()
  assert_eq(observed.pending_steers.length(), 1)
  assert_eq(observed_items.length(), 2)
  assert_true(observed_items[0].kind is @transcript.User(_))
  assert_eq(observed_items[0].text(), Some("inspect this"))
  assert_true(observed_items[1].kind is @transcript.User(_))
  assert_eq(observed_items[1].text(), Some("steer early"))

  let (_, steered) = update(
    dispatch,
    Notification(
      method_="item/started",
      params={
        "threadId": "thread-real-1",
        "turnId": "turn-1",
        "item": {
          "id": "user-steer-1",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "steer early" }],
        },
      },
      generation=2,
    ),
    observed,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(steered.pending_steers.is_empty())
  assert_eq(steered.transcript_items().length(), 2)
}

///|
test "Codex full steer replies replace their local receipt" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let state = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "turns": [
          {
            "id": "turn-1",
            "status": "inProgress",
            "items": [
              {
                "id": "initial-user",
                "type": "userMessage",
                "content": [{ "type": "text", "text": "initial" }],
              },
            ],
          },
        ],
      },
    }),
    connection: CodexReady,
  }
  let (_, sending) = update(
    dispatch,
    ComposerAction(
      @composer.DraftSubmitted(
        identity=state.composer_identity(@interop.ChannelId::Local),
        draft={ task: "steer once", mentions: [], },
      ),
    ),
    state,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(sending.pending_steers.length(), 1)
  let reply = Reply(kind=CodexTurnSteerReply("thread-1"), value={
    "turn": {
      "id": "turn-1",
      "status": "inProgress",
      "itemsView": "full",
      "items": [
        {
          "id": "initial-user",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "initial" }],
        },
        {
          "id": "steer-user-1",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "steer once" }],
        },
      ],
    },
  })
  let (_, once) = update(
    dispatch,
    reply,
    sending,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, twice) = update(
    dispatch,
    reply,
    sending,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(once == twice)
  assert_true(once.pending_steers.is_empty())
  let items = once.transcript_items()
  assert_eq(items.length(), 2)
  assert_eq(items[0].text(), Some("initial"))
  assert_eq(items[1].text(), Some("steer once"))
}

///|
test "Codex steer failure preserves an older first-prompt receipt" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let state = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
      },
    }),
    connection: CodexReady,
    submitted_first_prompt: Some({ task: "initial", mentions: [], }),
  }
  let (_, sending_first) = update(
    dispatch,
    ComposerAction(
      @composer.DraftSubmitted(
        identity=state.composer_identity(@interop.ChannelId::Local),
        draft={ task: "accepted steer", mentions: [], },
      ),
    ),
    state,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, accepted_first) = update(
    dispatch,
    Reply(kind=CodexTurnSteerReply("thread-1"), value={ "turnId": "turn-1" }),
    sending_first,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, sending_second) = update(
    dispatch,
    ComposerAction(
      @composer.DraftSubmitted(
        identity=accepted_first.composer_identity(@interop.ChannelId::Local),
        draft={ task: "rejected steer", mentions: [], },
      ),
    ),
    accepted_first,
    @interop.ChannelId::Local,
    open_external,
  )
  let failure = Failed(
    kind=CodexTurnSteerReply("thread-1"),
    message="steer rejected",
  )
  let (_, failed) = update(
    dispatch,
    failure,
    sending_second,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, failed_again) = update(
    dispatch,
    failure,
    sending_second,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(failed == failed_again)
  assert_true(failed.waiting_for_first_user_item())
  assert_eq(failed.pending_steers.length(), 1)
  assert_true(failed.pending_steers[0].delivery is CodexSteerAccepted)
  assert_eq(failed.draft_text(), "rejected steer")

  let (_, observed_initial) = update(
    dispatch,
    Notification(
      method_="item/started",
      params={
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": {
          "id": "initial-user",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "initial" }],
        },
      },
      generation=1,
    ),
    failed,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_false(observed_initial.waiting_for_first_user_item())
  assert_eq(observed_initial.pending_steers.length(), 1)

  let (_, observed_steer) = update(
    dispatch,
    Notification(
      method_="item/started",
      params={
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": {
          "id": "steer-user-1",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "accepted steer" }],
        },
      },
      generation=2,
    ),
    observed_initial,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(observed_steer.pending_steers.is_empty())
}

///|
test "Codex steer receipts reconcile duplicate text by item id and FIFO" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let state = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "turns": [
          {
            "id": "turn-1",
            "status": "inProgress",
            "items": [
              {
                "id": "initial-user",
                "type": "userMessage",
                "content": [{ "type": "text", "text": "same text" }],
              },
            ],
          },
        ],
      },
    }),
    connection: CodexReady,
  }
  let submit = ComposerAction(
    @composer.DraftSubmitted(
      identity=state.composer_identity(@interop.ChannelId::Local),
      draft={ task: "same text", mentions: [], },
    ),
  )
  let (_, sending_first) = update(
    dispatch,
    submit,
    state,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(sending_first.pending_steers.length(), 1)
  assert_eq(sending_first.pending_steers[0].submission_id, 1)
  assert_true(sending_first.pending_steers[0].delivery is CodexSteerSending)
  assert_eq(sending_first.transcript_items().length(), 2)

  let (_, accepted_first) = update(
    dispatch,
    Reply(kind=CodexTurnSteerReply("thread-1"), value={ "turnId": "turn-1" }),
    sending_first,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(accepted_first.pending_steers[0].delivery is CodexSteerAccepted)
  let (_, sending_second) = update(
    dispatch,
    ComposerAction(
      @composer.DraftSubmitted(
        identity=accepted_first.composer_identity(@interop.ChannelId::Local),
        draft={ task: "same text", mentions: [], },
      ),
    ),
    accepted_first,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(sending_second.pending_steers.length(), 2)
  assert_eq(sending_second.pending_steers[1].submission_id, 2)
  assert_eq(sending_second.transcript_items().length(), 3)

  let (_, failed_second) = update(
    dispatch,
    Failed(kind=CodexTurnSteerReply("thread-1"), message="steer rejected"),
    sending_second,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(failed_second.pending_steers.length(), 1)
  assert_eq(failed_second.pending_steers[0].submission_id, 1)
  assert_true(failed_second.pending_steers[0].delivery is CodexSteerAccepted)
  assert_eq(failed_second.draft_text(), "same text")

  let first_started = Notification(
    method_="item/started",
    params={
      "threadId": "thread-1",
      "turnId": "turn-1",
      "item": {
        "id": "steer-user-1",
        "type": "userMessage",
        "content": [{ "type": "text", "text": "same text" }],
      },
    },
    generation=1,
  )
  let (_, observed_first) = update(
    dispatch,
    first_started,
    sending_second,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, observed_first_again) = update(
    dispatch,
    first_started,
    sending_second,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(observed_first == observed_first_again)
  assert_eq(observed_first.pending_steers.length(), 1)
  assert_eq(observed_first.pending_steers[0].submission_id, 2)
  assert_eq(observed_first.transcript_items().length(), 3)

  // `item/completed` repeats the same canonical id after `item/started`; it
  // updates that item and must not consume the second identical local receipt.
  let (_, completed_first) = update(
    dispatch,
    Notification(
      method_="item/completed",
      params={
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": {
          "id": "steer-user-1",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "same text" }],
        },
      },
      generation=2,
    ),
    observed_first,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(completed_first.pending_steers.length(), 1)
  assert_eq(completed_first.pending_steers[0].submission_id, 2)

  let (_, observed_second) = update(
    dispatch,
    Notification(
      method_="item/started",
      params={
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": {
          "id": "steer-user-2",
          "type": "userMessage",
          "content": [{ "type": "text", "text": "same text" }],
        },
      },
      generation=3,
    ),
    completed_first,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(observed_second.pending_steers.is_empty())
  let items = observed_second.transcript_items()
  assert_eq(items.length(), 3)
  assert_true(items.iter().all(item => item.kind is @transcript.User(_)))
  assert_true(items.iter().all(item => item.text() == Some("same text")))
}

///|
test "abandoning a draft deselects it and clears its composer state" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let (_, drafting) = update(
    dispatch,
    StartDraft(id="desktop-draft-1", cwd="/work/project"),
    State(),
    @interop.ChannelId::Local,
    open_external,
  )
  let typed = { ..drafting, draft: "half a prompt", }
  let (_, dropped) = update(
    dispatch,
    AbandonDraft,
    typed,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_false(dropped.composing_draft())
  assert_eq(dropped.active_id(), None)
  inspect(dropped.draft_text(), content="")
  // Without a draft there is nothing to abandon; the message is a no-op.
  let (_, unchanged) = update(
    dispatch,
    AbandonDraft,
    State(),
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(unchanged.active_id() is None)
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
test "Codex permission picker confirms full access and freezes while running" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let idle = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "turns": [] },
  })
  assert_eq(idle.permission_mode(), @protocol.AutoReview)
  let (_, opened) = update(
    dispatch,
    TogglePermissionMenu,
    idle,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(opened.permission_picker is CodexPermissionOpen(_))
  let (_, requested) = update(
    dispatch,
    ChoosePermission(@protocol.RequestApproval),
    opened,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(requested.permission_mode(), @protocol.RequestApproval)
  let (_, warning) = update(
    dispatch,
    ChoosePermission(@protocol.FullAccess),
    requested,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(
    warning.permission_picker is CodexPermissionConfirmingFullAccess(_),
  )
  assert_eq(warning.permission_mode(), @protocol.RequestApproval)
  let (_, cancelled) = update(
    dispatch,
    CancelFullAccess,
    warning,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(cancelled.permission_mode(), @protocol.RequestApproval)
  let (_, warning) = update(
    dispatch,
    ChoosePermission(@protocol.FullAccess),
    cancelled,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, confirmed) = update(
    dispatch,
    ConfirmFullAccess,
    warning,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(confirmed.permission_mode(), @protocol.FullAccess)

  let running = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  let (_, unchanged1) = update(
    dispatch,
    ChoosePermission(@protocol.RequestApproval),
    running,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, unchanged2) = update(
    dispatch,
    ChoosePermission(@protocol.RequestApproval),
    running,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(unchanged1 == unchanged2)
  assert_eq(unchanged1.permission_mode(), @protocol.AutoReview)
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
  assert_true(state.terminal_available(@interop.ChannelId::Local))
  assert_true(state.active_context() is None)
}

///|
test "Codex turn connection errors settle immediately without a history read" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let original = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-1", "turns": [] },
    }),
    draft: "new prompt",
    submitted_first_prompt: Some({ task: "new prompt", mentions: [], }),
  }.begin_foreground(CodexTurnStartReply("thread-1"))
  let (_, failed) = update(
    dispatch,
    Failed(
      kind=CodexTurnStartReply("thread-1"),
      message="SeekMoon connection lost",
    ),
    original,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(failed.draft_text(), "new prompt")
  assert_false(failed.loading)
  assert_true(failed.foreground is None)
  assert_true(failed.can_prompt())
  assert_eq(failed.notice, "Codex turn: SeekMoon connection lost")
  assert_false(failed.waiting_for_first_user_item())
  assert_eq(failed.transcript_items().length(), 1)

  let worktree : CodexWorktree = {
    name: "wt-1",
    path: "/work/project/.worktrees/wt-1",
    present: true,
  }
  let (_, worktree_failed) = update(
    dispatch,
    Failed(
      kind=CodexWorktreeTurnReply("thread-1", worktree),
      message="SeekMoon connection lost",
    ),
    original,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(worktree_failed.placement is @composer.BoundWorktree("wt-1"))
  assert_eq(worktree_failed.draft_text(), "new prompt")
  assert_eq(worktree_failed.notice, "Codex turn: SeekMoon connection lost")
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
        request_id: Json("request-1"),
        thread_id: "thread-1",
        method_: "item/commandExecution/requestApproval",
        params: { "threadId": "thread-1", "reason": "test" },
        answers: Map([]),
      },
    ],
  }
  let composer_identity = state.composer_identity(@interop.ChannelId::Local)
  let messages : Array[Msg] = [
    Refresh,
    ComposerAction(
      @composer.SlashCommand(identity=composer_identity, command="unknown"),
    ),
    ModelChanged("gpt-test"),
    EffortChanged("high"),
    TogglePermissionMenu,
    DismissPermissionMenu,
    ChoosePermission(@protocol.RequestApproval),
    ChoosePermission(@protocol.AutoReview),
    ChoosePermission(@protocol.FullAccess),
    ConfirmFullAccess,
    CancelFullAccess,
    WorktreeChanged(
      thread_id="thread-1",
      project_root="/work/project",
      name="wt-1",
      path="/work/project/.worktrees/wt-1",
      present=true,
    ),
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
    Stop,
    Login,
    CancelLogin,
    Logout,
    RequestAnswer(
      request_key=Json("request-1").stringify(),
      question_id="question-1",
      answer="yes",
    ),
    Respond(request_key=Json("request-1").stringify(), decision="accept"),
    Reply(kind=CodexStatusReply, value={ "status": "ready" }),
    Reply(kind=CodexRequestsReply, value={ "data": [], "generation": 0 }),
    Reply(kind=CodexAccountReply, value={
      "requiresOpenaiAuth": true,
      "account": Json::null(),
    }),
    Reply(kind=CodexModelsReply, value={ "data": [] }),
    Reply(
      kind=CodexThreadsReply({
        archived: false,
        generation: 0,
        activity_frontier: State().activity.frontier(),
      }),
      value={ "data": [] },
    ),
    Reply(
      kind=CodexThreadsReply({
        archived: true,
        generation: 0,
        activity_frontier: State().activity.frontier(),
      }),
      value={ "data": [] },
    ),
    Reply(kind=CodexThreadReply("thread-1", State().activity.frontier()), value={
      "thread": { "id": "thread-1", "turns": [] },
    }),
    Reply(kind=CodexDraftThreadReply("desktop-test"), value={
      "thread": { "id": "thread-2", "turns": [] },
    }),
    Reply(kind=CodexTurnStartReply("thread-1"), value={
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
    Reply(kind=CodexInterruptReply, value={}),
    Reply(kind=CodexApprovalReply, value={}),
    Failed(kind=CodexTurnStartReply("thread-1"), message="test failure"),
    Failed(
      kind=CodexWorktreeRepairReply("thread-1", {
        name: "wt-1",
        path: "/work/project/.worktrees/wt-1",
        present: false,
      }),
      message="test failure",
    ),
    StatusChanged({ "status": "ready" }),
    Notification(
      method_="thread/name/updated",
      params={ "threadId": "thread-1", "name": "Renamed" },
      generation=0,
    ),
    ServerRequest(
      request_id=Json("request-2"),
      method_="item/commandExecution/requestApproval",
      params={ "threadId": "thread-1", "reason": "test" },
      generation=1,
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
test "Codex worktree broadcasts bind every frontend with the task open" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/project",
      "projectRoot": "/work/project",
      "turns": [],
    },
  })
  // An ordinary app-server cwd is not a native registry authorization and
  // therefore remains an omitted turn/start override.
  assert_true(state.registry_turn_cwd() is None)
  let message = WorktreeChanged(
    thread_id="thread-1",
    project_root="/work/project",
    name="wt-1",
    path="/work/project/.worktrees/wt-1",
    present=true,
  )
  let (_, once) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  let (_, twice) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  assert_true(once == twice)
  assert_true(once.placement is @composer.BoundWorktree("wt-1"))
  assert_eq(
    once
    .active_placement(@interop.ChannelId::Local)
    .bind(placement => placement.checkout_root())
    .map(root => root.path),
    Some("/work/project/.worktrees/wt-1"),
  )
  // If this frontend was already waiting for thread/resume, its subsequent
  // ordinary turn/start must carry the registry path explicitly rather than
  // racing another frontend to update app-server's default cwd.
  assert_eq(once.registry_turn_cwd(), Some("/work/project/.worktrees/wt-1"))
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
  // A retained registry row names the checkout for Repair, but a missing path
  // is never sent back to app-server as a runnable cwd.
  assert_true(state.registry_turn_cwd() is None)
  assert_false(state.terminal_available(@interop.ChannelId::Local))
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
test "Codex Git replies stay with the latest checkout request" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let main_cwd = "/workspace/openseek"
  let worktree_cwd = "/workspace/.codex/worktrees/wt-3/openseek"
  let opened = State().with_thread_reply(
    {
      "thread": {
        "id": "thread-1",
        "cwd": main_cwd,
        "projectRoot": main_cwd,
        "gitInfo": { "branch": "docs/desktop-ux-guidelines" },
        "turns": [],
      },
    },
    CodexImportedSnapshot,
  )
  // Opening the thread starts the lookup against the main checkout.
  let (_, main_pending) = opened.refresh_git(
    dispatch,
    @interop.ChannelId::Local,
  )
  assert_eq(main_pending.git_request_generation, 1)

  // Fresh-worktree creation retargets the same thread and starts a newer
  // lookup. Neither request is executed in this pure update test; their
  // messages below deliberately arrive in the opposite order.
  let worktree : CodexWorktree = {
    name: "wt-3",
    path: worktree_cwd,
    present: true,
  }
  let retargeted = main_pending.with_created_worktree(worktree)
  let (_, worktree_pending) = retargeted.refresh_git(
    dispatch,
    @interop.ChannelId::Local,
  )
  assert_eq(worktree_pending.git_request_generation, 2)

  let worktree_reply = GitLoaded(
    thread_id="thread-1",
    generation=2,
    requested_cwd=worktree_cwd,
    reply={
      pull_request: Some({
        number: 759,
        title: "Worktree pull request",
        state: "open",
        draft: false,
        url: "https://github.com/moonbitlang/openseek/pull/759",
        base: "main",
        additions: 1,
        deletions: 0,
        changed_files: 1,
        checks: None,
      }),
      compare_url: None,
      branch: Some("openseek/wt-3"),
    },
  )
  let (_, applied) = update(
    dispatch,
    worktree_reply,
    worktree_pending,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, applied_again) = update(
    dispatch,
    worktree_reply,
    worktree_pending,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  // The handler is pure: the same state and message produce the same result.
  assert_true(applied_again == applied)
  assert_eq(applied.git_status.unwrap().pull_request.unwrap().number, 759)

  let main_reply = GitLoaded(
    thread_id="thread-1",
    generation=1,
    requested_cwd=main_cwd,
    reply={
      pull_request: Some({
        number: 1079,
        title: "Main checkout pull request",
        state: "open",
        draft: false,
        url: "https://github.com/moonbitlang/openseek/pull/1079",
        base: "main",
        additions: 2,
        deletions: 0,
        changed_files: 1,
        checks: None,
      }),
      compare_url: None,
      branch: Some("docs/desktop-ux-guidelines"),
    },
  )
  let (_, stale) = update(
    dispatch,
    main_reply,
    applied,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  // The main-checkout reply arrives last but cannot replace the worktree's
  // newer answer.
  assert_true(stale == applied)
  assert_eq(stale.git_status.unwrap().pull_request.unwrap().number, 759)

  let wrong_cwd_reply = GitLoaded(
    thread_id="thread-1",
    generation=2,
    requested_cwd=main_cwd,
    reply={
      pull_request: None,
      compare_url: None,
      branch: Some("wrong-checkout"),
    },
  )
  let (_, wrong_cwd) = update(
    dispatch,
    wrong_cwd_reply,
    worktree_pending,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(wrong_cwd == worktree_pending)
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
    State().activity.frontier(),
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
    Reply(kind=CodexThreadReply("thread-a", listed.activity.frontier()), value={
      "thread": { "id": "thread-a", "turns": [] },
    }),
    waiting_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_success == waiting_b)
  let (_, stale_failure) = update(
    dispatch,
    Failed(
      kind=CodexThreadReply("thread-a", listed.activity.frontier()),
      message="late failure",
    ),
    waiting_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_failure == waiting_b)

  let (_, selected_b) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-b", listed.activity.frontier()), value={
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
    Reply(kind=CodexThreadReply("thread-a", listed.activity.frontier()), value={
      "thread": { "id": "thread-a", "turns": [] },
    }),
    selected_b,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(late_a == selected_b)
}

///|
test "Codex reconnect preserves a pending history target for a new epoch" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let selected = State()
    .with_threads(
      {
        "data": [
          { "id": "thread-a", "preview": "Thread A" },
          { "id": "thread-b", "preview": "Thread B" },
        ],
      },
      false,
      State().activity.frontier(),
    )
    .with_thread_reply(
      { "thread": { "id": "thread-a", "turns": [] } },
      CodexImportedSnapshot,
    )
  let ready = { ..selected, connection: CodexReady, }
  let old_frontier = ready.activity.frontier()
  let (_, opening) = update(
    dispatch,
    OpenThread("thread-b"),
    ready,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, disconnected) = update(
    dispatch,
    StatusChanged({ "status": "starting" }),
    opening,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(disconnected.requested_thread, Some("thread-b"))
  assert_true(
    disconnected.activity.frontier().connection_epoch !=
    old_frontier.connection_epoch,
  )

  // The dead connection's reply is inert. Ready retries thread-b with the
  // new frontier, whose reply can settle the pending selection normally.
  let reply : Json = { "thread": { "id": "thread-b", "turns": [] } }
  let (_, stale) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-b", old_frontier), value=reply),
    disconnected,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale == disconnected)
  let (_, reconnected) = update(
    dispatch,
    StatusChanged({ "status": "ready" }),
    disconnected,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(reconnected.requested_thread, Some("thread-b"))
  let (_, opened) = update(
    dispatch,
    Reply(
      kind=CodexThreadReply("thread-b", reconnected.activity.frontier()),
      value=reply,
    ),
    reconnected,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(opened.active_id(), Some("thread-b"))
  assert_eq(opened.requested_thread, None)
  assert_false(opened.loading)
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
    Reply(kind=CodexTurnStartReply("thread-old"), value={
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
    Failed(kind=CodexTurnStartReply("thread-old"), message="late failure"),
    current_thread,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale_turn_failure == current_thread)
}

///|
test "Codex observed running task steers without resume" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let observed = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
      },
    }),
    connection: CodexReady,
    draft: "follow up",
  }
  assert_true(observed.is_running())
  let (_, steering) = observed.submit_composer(
    dispatch,
    @interop.ChannelId::Local,
  )
  assert_true(steering.owns_foreground(CodexTurnSteerReply("thread-1")))
}

///|
test "Codex idle stored task resumes before starting a turn" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let idle = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-1", "turns": [] },
    }),
    connection: CodexReady,
    draft: "follow up",
  }
  let (_, resuming) = idle.submit_composer(dispatch, @interop.ChannelId::Local)
  assert_true(resuming.owns_foreground(CodexResumeReply("thread-1")))
  let message = ResumeSucceeded("thread-1")
  let (_, once) = update(
    dispatch,
    message,
    resuming,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, twice) = update(
    dispatch,
    message,
    resuming,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(once.owns_foreground(CodexTurnStartReply("thread-1")))
  assert_true(once == twice)
}

///|
test "Codex task selection clears the adapter submission snapshot" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-a", "cwd": "/work/a", "turns": [] },
    }),
    draft: "belongs to A",
    mentions: [{ ref_: @mention_context.File(path="src/a.mbt"), range: None, }],
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
}

///|
test "reopening the selected Codex task preserves its foreground state" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": {
        "id": "thread-a",
        "cwd": "/work/a",
        "turns": [{ "id": "turn-a", "status": "inProgress", "items": [] }],
      },
    }),
    draft: "unsent follow-up",
  }.begin_foreground(CodexTurnSteerReply("thread-a"))
  let message = OpenThread("thread-a")
  let (_, once) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  let (_, twice) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  assert_true(once == state)
  assert_true(twice == state)
}

///|
test "archiving the selected Codex task settles its owned foreground work" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-a", "cwd": "/work/a", "turns": [] },
    }),
    draft: "pending prompt",
    pending_requests: [
      {
        request_id: Json("approval-a"),
        thread_id: "thread-a",
        method_: "item/commandExecution/requestApproval",
        params: { "threadId": "thread-a" },
        answers: Map([]),
      },
    ],
  }.begin_foreground(CodexTurnStartReply("thread-a"))
  let message = Notification(
    method_="thread/archived",
    params={ "threadId": "thread-a" },
    generation=1,
  )
  let (_, once) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  let (_, twice) = update(dispatch, message, state, @interop.ChannelId::Local, _ => {
    @cmd.none
  })
  assert_true(once.active_thread() is None)
  assert_false(once.loading)
  assert_true(once.foreground is None)
  assert_true(once.pending_requests.is_empty())
  assert_true(once == twice)
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
test "Codex approval reply cannot settle an active turn" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "turns": [] },
  }).begin_foreground(CodexTurnStartReply("thread-1"))
  let (_, after_approval) = update(
    dispatch,
    Reply(kind=CodexApprovalReply, value={}),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(after_approval.loading)
  assert_true(
    after_approval.foreground == Some(CodexTurnForeground("thread-1")),
  )
  let (_, after_turn) = update(
    dispatch,
    Reply(kind=CodexTurnStartReply("thread-1"), value={
      "turn": { "id": "turn-1", "status": "inProgress" },
    }),
    after_approval,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_false(after_turn.loading)
  assert_true(after_turn.foreground is None)
}

///|
test "Codex request generations reject stale snapshots" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "turns": [] },
  })
  let (_, notified) = update(
    dispatch,
    ServerRequest(
      request_id=Json("request-new"),
      method_="item/commandExecution/requestApproval",
      params={ "threadId": "thread-1" },
      generation=2,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, stale) = update(
    dispatch,
    Reply(kind=CodexRequestsReply, value={ "data": [], "generation": 1 }),
    notified,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(stale.pending_requests.length(), 1)
  assert_eq(stale.pending_requests[0].thread_id, "thread-1")
  assert_eq(stale.request_generation, 2)
}

///|
test "Codex approvals cannot be edited from another thread" {
  let state = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-1", "turns": [] },
    }),
    pending_requests: [
      {
        request_id: Json("request-2"),
        thread_id: "thread-2",
        method_: "item/tool/requestUserInput",
        params: { "threadId": "thread-2", "questions": [{ "id": "scope" }] },
        answers: Map([]),
      },
    ],
  }
  let unchanged = state.with_request_answer(
    Json("request-2").stringify(),
    "scope",
    "all",
  )
  assert_true(unchanged.pending_requests[0].answers.is_empty())
}

///|
test "Codex composer reverse-request actions keep their task identity" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = {
    ..State::from_thread_snapshot({
      "thread": { "id": "thread-1", "turns": [] },
    }),
    pending_requests: [
      {
        request_id: Json("request-1"),
        thread_id: "thread-1",
        method_: "item/tool/requestUserInput",
        params: { "threadId": "thread-1", "questions": [{ "id": "scope" }] },
        answers: Map([]),
      },
    ],
  }
  let identity = state.composer_identity(@interop.ChannelId::Local)
  let (_, answered) = update(
    dispatch,
    ComposerAction(
      @composer.CodexRequestAnswerChanged(
        identity~,
        request_key=Json("request-1").stringify(),
        question_id="scope",
        answer="all",
      ),
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(answered.pending_requests[0].answers.get("scope"), Some("all"))
  let (_, unchanged) = update(
    dispatch,
    ComposerAction(
      @composer.CodexRequestAnswerChanged(
        identity={
          owner: { channel: @interop.ChannelId::Local, session: "thread-2", },
          archive_generation: 0,
        },
        request_key=Json("request-1").stringify(),
        question_id="scope",
        answer="other",
      ),
    ),
    answered,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(unchanged.pending_requests[0].answers.get("scope"), Some("all"))
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
    Reply(
      kind=CodexThreadsReply({
        archived: false,
        generation: 1,
        activity_frontier: first.activity.frontier(),
      }),
      value={ "data": [{ "id": "stale", "preview": "Stale" }] },
    ),
    second,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(stale == second)
  let (_, current) = update(
    dispatch,
    Reply(
      kind=CodexThreadsReply({
        archived: false,
        generation: 2,
        activity_frontier: second.activity.frontier(),
      }),
      value={ "data": [{ "id": "current", "preview": "Current" }] },
    ),
    stale,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(current.threads[0].id, "current")
}

///|
test "Codex list and history snapshots follow request order" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let listed = State().with_threads(
    { "data": [{ "id": "thread-a", "preview": "Thread A" }] },
    false,
    State().activity.frontier(),
  )
  let (_, refreshing) = update(
    dispatch,
    Refresh,
    listed,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let catalog_frontier = refreshing.activity.frontier()
  let (_, opening) = update(
    dispatch,
    OpenThread("thread-a"),
    refreshing,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let read_frontier = opening.activity.frontier()
  let (_, idle) = update(
    dispatch,
    Reply(kind=CodexThreadReply("thread-a", read_frontier), value={
      "thread": { "id": "thread-a", "status": { "type": "idle" }, "turns": [] },
    }),
    opening,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, stale_active) = update(
    dispatch,
    Reply(
      kind=CodexThreadsReply({
        archived: false,
        generation: 1,
        activity_frontier: catalog_frontier,
      }),
      value={
        "data": [
          {
            "id": "thread-a",
            "preview": "Thread A",
            "status": { "type": "active" },
          },
        ],
      },
    ),
    idle,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(
    stale_active.activity.presentation("thread-a") is @conversation.NoRunMark,
  )

  // A subsequently requested catalog is newer than the history read and may
  // authoritatively recover running state even if no notification was seen.
  let (_, reloading) = update(
    dispatch,
    Refresh,
    stale_active,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, current_active) = update(
    dispatch,
    Reply(
      kind=CodexThreadsReply({
        archived: false,
        generation: 2,
        activity_frontier: reloading.activity.frontier(),
      }),
      value={
        "data": [
          {
            "id": "thread-a",
            "preview": "Thread A",
            "status": { "type": "active" },
          },
        ],
      },
    ),
    reloading,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(
    current_active.activity.presentation("thread-a")
    is @conversation.RunningMark,
  )
}

///|
test "archived Codex catalog removes a selected task in either reply order" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let snapshot = State::from_thread_snapshot({
    "thread": { "id": "thread-a", "cwd": "/work/a", "turns": [] },
  })
  let selected = snapshot.begin_foreground(
    CodexThreadReply("thread-a", snapshot.activity.frontier()),
  )
  let live = Reply(
    kind=CodexThreadsReply({
      archived: false,
      generation: 0,
      activity_frontier: selected.activity.frontier(),
    }),
    value={ "data": [] },
  )
  let archived = Reply(
    kind=CodexThreadsReply({
      archived: true,
      generation: 0,
      activity_frontier: selected.activity.frontier(),
    }),
    value={
      "data": [{ "id": "thread-a", "cwd": "/work/a", "preview": "Archived A" }],
    },
  )
  let (_, live_first) = update(
    dispatch,
    live,
    selected,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(live_first.active_thread() is Some(_))
  let (_, archived_second) = update(
    dispatch,
    archived,
    live_first,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(archived_second.active_thread() is None)
  assert_true(archived_second.threads.is_empty())
  assert_eq(archived_second.archived_threads.length(), 1)
  assert_false(archived_second.loading)

  let (_, archived_first) = update(
    dispatch,
    archived,
    selected,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, live_second) = update(
    dispatch,
    live,
    archived_first,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(live_second.active_thread() is None)
  assert_true(live_second.threads.is_empty())
  assert_eq(live_second.archived_threads.length(), 1)
}

///|
test "Codex settings notifications do not retarget the selected task" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "cwd": "/work/old", "turns": [] },
  })
  let (_, notified) = update(
    dispatch,
    Notification(
      method_="thread/settings/updated",
      params={
        "threadId": "thread-1",
        "threadSettings": { "cwd": "/work/untrusted" },
      },
      generation=0,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  // OpenSeek already owns every setting it sends with `turn/start`. The
  // app-server notification is informational and must not change the
  // Files/Terminal placement.
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
