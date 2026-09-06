// Browser-side calls into the Desktop's curated Codex catalog. Every command
// returns parsed JSON to update; Codex never exposes account tokens or an
// arbitrary app-server method proxy to this page.

///|
fn[Payload : ToJson, Response : FromJson + ToJson] CodexReplyKind::request(
  self : CodexReplyKind,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Response]],
  payload : Payload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : Response = @interop.codex_request(channel, command, payload) catch {
        error => {
          let message = @interop.bridge_error_text(error)
          scheduler.add(dispatch(Failed(kind=self, message~)))
          return
        }
      }
      let value = ToJson::to_json(reply)
      scheduler.add(dispatch(Reply(kind=self, value~)))
    })
  })
}

///|
/// Read one complete active or archived catalog. App-server deliberately
/// pages `thread/list`; the sidebar must follow `nextCursor` instead of making
/// old tasks disappear once an account has more than one page.
fn CodexCatalogReplyContext::run(
  self : CodexCatalogReplyContext,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let rows : Array[Json] = []
      let seen_cursors : Array[String] = []
      let mut cursor : String? = None
      for ;; {
        let page : @protocol.CodexDataReply = @interop.codex_request(
          channel,
          @commands.codex_thread_list,
          { limit: 100, archived: self.archived, cursor, },
        ) catch {
          error => {
            scheduler.add(
              dispatch(
                Failed(
                  kind=CodexThreadsReply(self),
                  message=@interop.bridge_error_text(error),
                ),
              ),
            )
            return
          }
        }
        for row in page.data {
          rows.push(row)
        }
        let next_cursor = match page.next_cursor {
          Some(next) if !next.is_empty() => Some(next)
          _ => None
        }
        guard next_cursor is Some(next) else { break }
        if seen_cursors.contains(next) {
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexThreadsReply(self),
                message="Codex thread list repeated cursor " + next,
              ),
            ),
          )
          return
        }
        seen_cursors.push(next)
        cursor = Some(next)
      }
      scheduler.add(
        dispatch(Reply(kind=CodexThreadsReply(self), value={ "data": rows })),
      )
    })
  })
}

///|
/// Refresh both halves of the Codex sidebar catalog without also reloading
/// account and model metadata after every archive or name notification.
fn State::refresh_catalog(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  let (activity_frontier, activity) = self.activity.reserve_snapshot()
  let next = {
    ..self,
    activity,
    live_catalog_generation: self.live_catalog_generation + 1,
    archived_catalog_generation: self.archived_catalog_generation + 1,
  }
  (
    @cmd.batch([
      CodexCatalogReplyContext::{
        archived: false,
        generation: next.live_catalog_generation,
        activity_frontier,
      }.run(dispatch, channel),
      CodexCatalogReplyContext::{
        archived: true,
        generation: next.archived_catalog_generation,
        activity_frontier,
      }.run(dispatch, channel),
    ]),
    next,
  )
}

///|
pub fn State::refresh(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  // The global sidebar is the conversation switcher for both products, so it
  // shows the Codex account's interactive history instead of silently hiding
  // threads outside OpenSeek's currently selected workspace. New threads
  // still receive that workspace as their cwd in `start_thread` below.
  let (catalog, next) = self.refresh_catalog(dispatch, channel)
  (
    @cmd.batch([
      CodexStatusReply.request(
        dispatch,
        channel,
        @commands.codex_status,
        @protocol.NoPayload,
      ),
      CodexAccountReply.request(
        dispatch,
        channel,
        @commands.codex_account_read,
        { refresh_token: false, },
      ),
      CodexRequestsReply.request(
        dispatch,
        channel,
        @commands.codex_server_request_list,
        @protocol.NoPayload,
      ),
      CodexModelsReply.request(dispatch, channel, @commands.codex_model_list, {
        limit: 100,
        include_hidden: false,
      }),
      catalog,
    ]),
    next,
  )
}

///|
fn State::open_draft(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  draft_id : String,
  cwd : String,
) -> @cmd.Cmd {
  // A queued add action may be overtaken by another project row. Only the
  // draft still selected by the model may acquire host filesystem authority.
  guard self.active_draft() is Some(draft) &&
    draft.id == draft_id &&
    draft.cwd == cwd else {
    return @cmd.none
  }
  CodexDraftOpenReply(draft_id).request(
    dispatch,
    channel,
    @commands.codex_draft_open,
    { draft_id, cwd, },
  )
}

///|
fn State::close_draft(
  self : State,
  channel : @interop.ChannelId,
  draft_id : String,
) -> @cmd.Cmd {
  guard self.active_draft() is Some(draft) && draft.id == draft_id else {
    return @cmd.none
  }
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        try
          @interop.codex_request(channel, @commands.codex_draft_close, @protocol.CodexDraftClosePayload::{
            draft_id,
          })
        catch {
          _ => @protocol.Acknowledged
        } noraise {
          value => value
        },
      )
    })
  })
}

///|
/// Everything needed for the first half of Send. `thread/start` is deliberately
/// its own command: the reply must install the real thread in the model before
/// `turn/start` can emit notifications, otherwise those notifications could
/// arrive while the page still selects the client-local draft and be dropped.
priv struct CodexDraftThreadRequest {
  draft_id : String
  cwd : String?
  model : String
  permission_mode : @protocol.CodexPermissionMode
}

///|
fn CodexDraftThreadRequest::run(
  self : CodexDraftThreadRequest,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, self.draft_id),
        () => {
          // The native host ties cwd authority to this already-open draft and
          // strips this Desktop-only field before forwarding thread/start.
          let thread_reply : @protocol.CodexThreadReply = @interop.codex_request(
            channel,
            @commands.codex_thread_start,
            {
              cwd: self.cwd,
              model: if self.model.is_empty() {
                None
              } else {
                Some(self.model)
              },
              draft_id: Some(self.draft_id),
              permission_mode: self.permission_mode,
            },
          ) catch {
            error => {
              scheduler.add(
                dispatch(
                  Failed(
                    kind=CodexDraftThreadReply(self.draft_id),
                    message=@interop.bridge_error_text(error),
                  ),
                ),
              )
              return
            }
          }
          guard thread_reply.thread is Object(thread_fields) &&
            @jsonx.json_text(thread_fields, "id") is Some(_) else {
            scheduler.add(
              dispatch(
                Failed(
                  kind=CodexDraftThreadReply(self.draft_id),
                  message="malformed Codex thread.start reply",
                ),
              ),
            )
            return
          }
          ignore(
            try
              @interop.codex_request(channel, @commands.codex_draft_close, {
                draft_id: self.draft_id,
              })
            catch {
              _ => @protocol.Acknowledged
            } noraise {
              value => value
            },
          )
          scheduler.add(
            dispatch(
              Reply(
                kind=CodexDraftThreadReply(self.draft_id),
                value=ToJson::to_json(thread_reply),
              ),
            ),
          )
        },
      ) catch {
        error =>
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexDraftThreadReply(self.draft_id),
                message="Codex thread start failed: \{error}",
              ),
            ),
          )
      }
    })
  })
}

///|
fn State::start_draft_thread(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.active_draft() is Some(draft) &&
    (draft.cwd.is_empty() || draft.project_root is Some(_)) &&
    !self.input_empty() else {
    return @cmd.none
  }
  CodexDraftThreadRequest::{
    draft_id: draft.id,
    cwd: draft.project_root,
    model: self.selected_model.trim().to_owned(),
    permission_mode: self.permission_mode(),
  }.run(dispatch, channel)
}

///|
fn State::open_thread(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  thread_id : String,
) -> (@cmd.Cmd, CodexActivityFrontier, State) {
  // The host keeps this read-only across both legacy inline histories and
  // paginated histories. Selecting a row never resumes the task or claims its
  // writer merely to render the transcript.
  let (activity_frontier, activity) = self.activity.reserve_snapshot()
  (
    CodexThreadReply(thread_id, activity_frontier).request(
      dispatch,
      channel,
      @commands.codex_thread_history_read,
      { thread_id, },
    ),
    activity_frontier,
    { ..self, activity, },
  )
}

///|
/// Re-read the selected checkout's current branch and pull request. App-server
/// `gitInfo` is creation-time metadata; this host operation is the same GitHub
/// lookup used by OpenSeek's composer and therefore follows branch changes
/// made during a Codex turn.
fn State::refresh_git(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  guard self.active_thread() is Some(active) && active.cwd is Some(cwd) else {
    return (@cmd.none, self)
  }
  let thread_id = active.id
  let generation = self.git_request_generation + 1
  (
    @cmd.custom_cmd(scheduler => {
      @js.async_run(() => {
        let reply : @protocol.GitPullRequestReply = @interop.bridge_request(
          channel,
          @commands.git_pull_request,
          { session: thread_id, cwd: Some(cwd), branch_hint: active.branch, },
        ) catch {
          // Git/gh decoration never blocks the conversation. Keep app-server's
          // captured branch label when the live lookup is unavailable.
          _ => return
        }
        scheduler.add(
          dispatch(
            GitLoaded(thread_id~, generation~, requested_cwd=cwd, reply~),
          ),
        )
      })
    }),
    { ..self, git_request_generation: generation, },
  )
}

///|
/// Resume an idle stored task immediately before starting its next turn.
/// Running tasks steer directly because their rollout can still be empty when
/// `turn/start` has reported `inProgress` but has not persisted its first item.
fn State::resume_for_send(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) else { return @cmd.none }
  let thread_id = active.id
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _reply : @protocol.CodexThreadReply = @interop.codex_request(
        channel,
        @commands.codex_thread_resume,
        { thread_id, permission_mode: self.permission_mode(), },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexResumeReply(thread_id),
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(ResumeSucceeded(thread_id)))
    })
  })
}

///|
fn State::send(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) else { return @cmd.none }
  guard !self.input_empty() else { return @cmd.none }
  let inputs = self.turn_inputs()
  if self.active_turn_id() is Some(turn_id) {
    CodexTurnSteerReply(active.id).request(
      dispatch,
      channel,
      @commands.codex_turn_steer,
      { thread_id: active.id, input: inputs, expected_turn_id: turn_id, },
    )
  } else {
    if self.placement.wants_fresh() && active.turns.is_empty() {
      let workspace = active.project_root.unwrap_or_else(() => {
        active.cwd.unwrap_or("")
      })
      return self.start_turn_in_new_worktree(
        dispatch, channel, active, workspace, inputs,
      )
    }
    let model = self.selected_model.trim().to_owned()
    let effort = self.selected_effort.trim().to_owned()
    CodexTurnStartReply(active.id).request(
      dispatch,
      channel,
      @commands.codex_turn_start,
      {
        thread_id: active.id,
        input: inputs,
        model: if model.is_empty() {
          None
        } else {
          Some(model)
        },
        effort: if effort.is_empty() {
          None
        } else {
          Some(effort)
        },
        // A sibling frontend may have received the host's registry commit
        // while this send was waiting for thread/resume. Reassert that exact
        // binding instead of relying on another client's `turn/start` to
        // update app-server cwd first.
        cwd: self.registry_turn_cwd(),
        permission_mode: self.permission_mode(),
      },
    )
  }
}

///|
/// Build the exact app-server input array once for the start/steer request.
fn State::turn_inputs(self : State) -> Array[Json] {
  let text = self.prompt_text()
  let inputs : Array[Json] = []
  if !text.is_empty() {
    inputs.push({ "type": "text", "text": text })
  }
  for mention in self.mentions {
    if self.mention_input(mention) is Some(input) {
      inputs.push(input)
    }
  }
  inputs
}

///|
/// The shared first-send placement flow's Codex adapter: invoke the same
/// owner-aware `worktree.create` used by OpenSeek, then differ only at the
/// final backend call by starting an app-server turn with that exact cwd.
/// The whole chain occupies this thread's ordered lane so a repeated Send
/// cannot overtake the create or start it just requested.
fn State::start_turn_in_new_worktree(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  active : CodexThread,
  workspace : String,
  inputs : Array[Json],
) -> @cmd.Cmd {
  let thread_id = active.id
  let model = self.selected_model.trim().to_owned()
  let effort = self.selected_effort.trim().to_owned()
  let permission_mode = self.permission_mode()
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, thread_id),
        () => {
          let result : @protocol.WorktreeCreateResult = @interop.bridge_request(
            channel,
            @commands.worktree_create,
            { workspace, session: None, codex_thread: Some(thread_id), },
          ) catch {
            error => {
              let message = @interop.bridge_error_text(error)
              scheduler.add(
                dispatch(Failed(kind=CodexTurnStartReply(thread_id), message~)),
              )
              return
            }
          }
          let reply = match result {
            @protocol.WorktreeCreatedReply(reply) => reply
            @protocol.WorktreeCreateError(message) => {
              scheduler.add(
                dispatch(
                  Failed(
                    kind=CodexTurnStartReply(thread_id),
                    message="worktree setup failed: " + message,
                  ),
                ),
              )
              return
            }
          }
          guard CodexWorktree::from_create_reply(reply, thread_id)
            is Some(worktree) else {
            scheduler.add(
              dispatch(
                Failed(
                  kind=CodexTurnStartReply(thread_id),
                  message="malformed worktree.create reply",
                ),
              ),
            )
            return
          }
          let reply : @protocol.CodexTurnReply = @interop.codex_request(
            channel,
            @commands.codex_turn_start,
            {
              thread_id,
              input: inputs,
              model: if model.is_empty() {
                None
              } else {
                Some(model)
              },
              effort: if effort.is_empty() {
                None
              } else {
                Some(effort)
              },
              cwd: Some(worktree.path),
              permission_mode,
            },
          ) catch {
            error => {
              let message = @interop.bridge_error_text(error)
              scheduler.add(
                dispatch(
                  Failed(
                    kind=CodexWorktreeTurnReply(thread_id, worktree),
                    message~,
                  ),
                ),
              )
              return
            }
          }
          scheduler.add(
            dispatch(
              Reply(
                kind=CodexWorktreeTurnReply(thread_id, worktree),
                value=ToJson::to_json(reply),
              ),
            ),
          )
        },
      ) catch {
        // The lane only wakes its waiters and the body handles every request
        // error. Its generic type still permits a failure, so keep an actual
        // unexpected lane fault visible instead of dropping the draft.
        error =>
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexTurnStartReply(thread_id),
                message="worktree start failed: \{error}",
              ),
            ),
          )
      }
    })
  })
}

///|
/// Keep the human-readable `$name` invocation in the text while also sending
/// app-server's native skill input below. The native item injects the exact
/// selected SKILL.md path; the marker preserves ordinary Codex prompt
/// semantics and makes stored user input understandable on its own.
fn State::prompt_text(self : State) -> String {
  let markers : Array[String] = []
  for mention in self.mentions {
    if mention.ref_ is @mention_context.Skill(name~) {
      markers.push("$" + name)
    }
  }
  let task = self.draft.trim().to_owned()
  if markers.is_empty() {
    task
  } else if task.is_empty() {
    markers.join(" ")
  } else {
    markers.join(" ") + " " + task
  }
}

///|
fn State::mention_input(self : State, mention : @composer.Mention) -> Json? {
  match mention.ref_ {
    @mention_context.File(path~) => {
      let name = match [..path.split("/")] {
        [] => path
        [.., last] => last.to_owned()
      }
      Some({ "type": "mention", "name": name, "path": path })
    }
    @mention_context.Skill(name~) => {
      guard self.active_context() is Some(context) &&
        self.skills is CodexSkillsReady(cwd, skills) &&
        cwd == context.cwd else {
        return Some({
          "type": "text",
          "text": @mention_context.encode([mention.ref_], ""),
        })
      }
      for skill in skills {
        if skill.name == name {
          return Some({ "type": "skill", "name": name, "path": skill.path })
        }
      }
      Some({
        "type": "text",
        "text": @mention_context.encode([mention.ref_], ""),
      })
    }
    @mention_context.Symbol(..)
    | @mention_context.SemanticSearch(_)
    | @mention_context.Annotation(..) =>
      Some({
        "type": "text",
        "text": @mention_context.encode([mention.ref_], ""),
      })
  }
}

///|
/// Load Codex's own installed skills for the selected cwd. The Desktop host
/// revalidates the thread/cwd pair before forwarding `skills/list`, so a
/// browser page cannot use this request to scan another directory.
fn State::load_skills(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  force_reload~ : Bool,
) -> @cmd.Cmd {
  guard self.active_context() is Some(owner) else { return @cmd.none }
  let thread_id = owner.thread_id
  let cwd = owner.cwd
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.CodexDataReply = @interop.codex_request(
        channel,
        @commands.codex_skills_list,
        { thread_id, cwd, force_reload, },
      ) catch {
        _ => {
          scheduler.add(dispatch(SkillsFailed(cwd~)))
          return
        }
      }
      match CodexSkill::decode_list(ToJson::to_json(reply), cwd) {
        Some(skills) => scheduler.add(dispatch(SkillsLoaded(cwd~, skills~)))
        None => scheduler.add(dispatch(SkillsFailed(cwd~)))
      }
    })
  })
}

///|
fn State::compact(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  original : String,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) else { return @cmd.none }
  CodexCompactReply(active.id, original).request(
    dispatch,
    channel,
    @commands.codex_thread_compact,
    { thread_id: active.id, },
  )
}

///|
fn State::review(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  original : String,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) else { return @cmd.none }
  CodexReviewReply(active.id, original).request(
    dispatch,
    channel,
    @commands.codex_review_start,
    { thread_id: active.id, target: { kind_: "uncommittedChanges", }, },
  )
}

///|
fn State::interrupt(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) &&
    self.active_turn_id() is Some(turn_id) else {
    return @cmd.none
  }
  CodexInterruptReply.request(
    dispatch,
    channel,
    @commands.codex_turn_interrupt,
    { thread_id: active.id, turn_id, },
  )
}

///|
fn State::archive(
  _self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  thread_id : String,
  force : Bool,
) -> @cmd.Cmd {
  CodexArchiveReply(thread_id).request(
    dispatch,
    channel,
    @commands.codex_thread_archive,
    { thread_id, force, },
  )
}

///|
fn State::unarchive(
  _self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  thread_id : String,
) -> @cmd.Cmd {
  CodexUnarchiveReply(thread_id).request(
    dispatch,
    channel,
    @commands.codex_thread_unarchive,
    { thread_id, },
  )
}

///|
/// Recreate a missing Desktop-owned checkout through the same idempotent
/// `worktree.create` operation as the first-send path. The retained registry
/// row selects the original name and branch; no new Codex turn is started.
fn State::repair_worktree(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.active_thread() is Some(active) &&
    active.worktree is Some(worktree) &&
    !worktree.present &&
    active.project_root is Some(workspace) else {
    return @cmd.none
  }
  let thread_id = active.id
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result : @protocol.WorktreeCreateResult = @interop.bridge_request(
        channel,
        @commands.worktree_create,
        { workspace, session: None, codex_thread: Some(thread_id), },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexWorktreeRepairReply(thread_id, worktree),
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      let reply = match result {
        @protocol.WorktreeCreatedReply(reply) => reply
        @protocol.WorktreeCreateError(message) => {
          scheduler.add(
            dispatch(
              Failed(
                kind=CodexWorktreeRepairReply(thread_id, worktree),
                message="worktree setup failed: " + message,
              ),
            ),
          )
          return
        }
      }
      guard CodexWorktree::from_create_reply(reply, thread_id) is Some(rebuilt) else {
        scheduler.add(
          dispatch(
            Failed(
              kind=CodexWorktreeRepairReply(thread_id, worktree),
              message="malformed worktree.create reply",
            ),
          ),
        )
        return
      }
      scheduler.add(
        dispatch(
          Reply(kind=CodexWorktreeRepairReply(thread_id, rebuilt), value={}),
        ),
      )
    })
  })
}

///|
fn State::login(
  _self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  CodexLoginReply.request(
    dispatch,
    channel,
    @commands.codex_account_login_start,
    {
      kind_: "chatgpt",
      // The hosted success page is chatgpt.com's "open the Codex app"
      // bounce; SeekMoon is the app the user should return to, so keep the
      // local loopback page, which ends with "you can close this tab" and
      // navigates nowhere.
      use_hosted_login_success_page: false,
      app_brand: "codex",
    },
  )
}

///|
fn State::logout(
  _self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  CodexLogoutReply.request(
    dispatch,
    channel,
    @commands.codex_account_logout,
    @protocol.NoPayload,
  )
}

///|
fn State::cancel_login(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  guard self.login_id is Some(login_id) else { return @cmd.none }
  CodexCancelLoginReply(login_id).request(
    dispatch,
    channel,
    @commands.codex_account_login_cancel,
    { login_id, },
  )
}

///|
fn State::respond(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request_key : String,
  decision : Json,
) -> @cmd.Cmd {
  let mut selected : CodexPendingRequest? = None
  for request in self.pending_requests {
    if request.request_id.stringify() == request_key &&
      self.active_thread() is Some(active) &&
      request.thread_id == active.id {
      selected = Some(request)
      break
    }
  }
  guard selected is Some(request) && request.response(decision) is Some(result) else {
    return @cmd.none
  }
  CodexApprovalReply.request(
    dispatch,
    channel,
    @commands.codex_server_request_respond,
    { request_id: request.request_id, result, },
  )
}
