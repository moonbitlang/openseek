// The worktree launch mode: a fresh conversation in a workspace can run in
// a host-named git worktree instead of the workspace root — its own
// execution environment, bound 1:1 to the conversation. The composer
// carries the mode toggle; the first submit
// creates the worktree and starts the run in one command. Sidebar rows of
// worktree conversations wear a branch glyph, tooltipped with the name
// joined from the registry.

///|
/// One registry row of `worktree.list` / `worktree.changed`, reduced to
/// what the sidebar and file root projection read: the name (the glyph's
/// tooltip), the distinct OpenSeek/Codex owner ids, its concrete checkout
/// path, and whether that checkout still exists on disk.
priv struct WorktreeRow {
  name : String
  session : String?
  codex_thread : String?
  // The host's concrete checkout root, already bound to its device channel.
  path : @common.Uri?
  present : Bool
} derive(Eq)

///|
/// One project's worktree rows, keyed by the registry path the host also
/// uses in `worktree.changed`. `generation` is the request token the rows
/// were applied under — the staleness fence is per project, so a
/// broadcast for one project can never discard another's still-current
/// list reply.
priv struct ProjectWorktrees {
  project : @common.Uri
  rows : Array[WorktreeRow]
  generation : Int
} derive(Eq)

///|
/// The archive-discard confirmation: the host refused to archive because
/// the conversation's worktree holds uncommitted changes; confirming
/// retries the archive with force. The structured refusal names the worktree
/// and carries a bounded path preview without exposing arbitrary host errors.
priv struct ArchiveConfirm {
  channel : @interop.ChannelId
  session : String
  refusal : @protocol.ArchiveNeedsForceReply
} derive(Eq)

///|
fn fetch_worktrees(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  workspace : @common.Uri,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.WorktreesReply = @interop.bridge_request(
        channel,
        @commands.worktree_list,
        { workspace: workspace.path, },
      ) catch {
        error => {
          // A failed list is not an empty registry: until a real reply arrives
          // the client cannot safely decide whether a durable conversation is
          // rooted in the project or one of its worktrees.
          scheduler.add(
            dispatch(
              WorktreesFailed(
                workspace~,
                connection_generation~,
                request_generation~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          WorktreesLoaded(
            worktree_rows(channel, reply.worktrees),
            workspace~,
            connection_generation~,
            request_generation~,
          ),
        ),
      )
    })
  })
}

///|
/// The worktree launch mode's first start: create the environment (the
/// host names it), bind the composing conversation, then fire the same
/// `agent.start` a plain submit would — one command, so a create failure
/// settles through the ordinary start-rejection path and restores the
/// draft.
fn start_in_new_worktree(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  task : String,
  submission_id : String,
  selected_model : EngineModel,
  reasoning : OpenSeekReasoning,
  max_steps : String,
  session : String,
  workspace : @common.Uri,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // The whole chain holds this session's command lane, not just the
      // start: two of these started together would run independent creates,
      // and whichever reply came back first would start its run first.
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, session),
        () => {
          // The session is the create's idempotency key: a retry after a lost
          // reply gets the same worktree back instead of minting a second one.
          let result : @protocol.WorktreeCreateResult = @interop.bridge_request(
            channel,
            @commands.worktree_create,
            {
              workspace: workspace.path,
              session: Some(session),
              codex_thread: None,
            },
          ) catch {
            _ => {
              // Nothing started: reject the submission so the draft restores.
              scheduler.add(
                device_dispatch(
                  WorktreeSetupFailed(
                    session~,
                    submission_id~,
                    message="Couldn’t create the worktree because the desktop host did not respond. Retry, or switch this chat to Local.",
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
                device_dispatch(
                  WorktreeSetupFailed(
                    session~,
                    submission_id~,
                    message="Couldn’t create the worktree. " + message,
                  ),
                ),
              )
              return
            }
          }
          // The host generates the name; the reply carries it so the chain
          // knows what to bind.
          guard !reply.name.is_empty() else {
            scheduler.add(
              device_dispatch(
                WorktreeSetupFailed(
                  session~,
                  submission_id~,
                  message="Couldn’t create the worktree because the host returned an incomplete reply. Retry, or switch this chat to Local.",
                ),
              ),
            )
            return
          }
          // Bind the conversation's local state before the start settles, so
          // the chip and a retried submit both know the environment. The
          // canonical registry list still arrives as `worktree.changed` from
          // the commit seam, and the start itself carries no worktree — the
          // host routes the bound session's cwd through the registry.
          scheduler.add(
            device_dispatch(
              WorktreeCreated(workspace~, name=reply.name, session~),
            ),
          )
          let start = start_payload(
            task,
            selected_model,
            reasoning,
            max_steps,
            session,
            submission_id,
            workspace~,
          )
          request_agent_start(
            scheduler, dispatch, channel, start, session, submission_id,
          )
        },
      ) catch {
        // Unreachable: the lane only ever wakes its waiters, never fails
        // them, and the work it runs is `noraise`. The type cannot say so.
        _ => ()
      }
    })
  })
}

///|
/// The workspace a goal command must create a worktree in before it may be
/// sent, or `None` when it can go straight out.
///
/// A goal is the first thing that pins an unstarted conversation's placement:
/// the host spawns its engine to receive the command, and the goal's own
/// durable card then makes `wants_fresh_worktree` false. Sent straight
/// through, that leaves the engine in the workspace root and silently retires
/// the launch mode before the first prompt ever runs — so the mode has to act
/// here exactly as it does on that first prompt.
fn Conversation::goal_creates_worktree(self : Conversation) -> @common.Uri? {
  guard self.wants_fresh_worktree() else { return None }
  match self.workspace {
    Project(root~) => Some(root)
    Worktree(..) => None
  }
}

///|
/// Set (or clear) the standing goal of a conversation whose worktree launch
/// mode has not bound an environment yet: create and bind it first, exactly
/// as the first prompt would, then send the goal into it.
///
/// Sending the goal straight through would spawn this session's engine in the
/// workspace root, and the durable goal card it commits would then make
/// `wants_fresh_worktree` false — so the user's first real prompt would
/// silently run in the main checkout with the launch mode they chose quietly
/// discarded. A goal is not a turn, but it is the first thing that pins the
/// session's placement, so it has to establish the environment too.
fn set_goal_in_new_worktree(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  workspace : @common.Uri,
  engine_model : EngineModel,
  reasoning : OpenSeekReasoning,
  max_steps : String,
  command : String,
  text : String?,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // The whole chain holds this session's goal lane, not just the send.
      // Two of these started together would otherwise run independent
      // creates, and whichever reply came back first would send its goal
      // first — so a Clear issued after a Set could be overtaken by it, which
      // is the very inversion the lane exists to prevent.
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, session),
        () => {
          // The session is the create's idempotency key, exactly as on the start
          // path: a retry after a lost reply gets the same worktree back.
          let result : @protocol.WorktreeCreateResult = @interop.bridge_request(
            channel,
            @commands.worktree_create,
            {
              workspace: workspace.path,
              session: Some(session),
              codex_thread: None,
            },
          ) catch {
            _ => {
              // The goal itself definitely never went out, so its draft comes
              // back either way. What differs is the *worktree*: a create whose
              // reply was lost may well have bound this session host-side, and
              // saying "setup failed" would let the composer offer Local again
              // over a durable binding — after which an ordinary start still
              // runs in that worktree. Say which happened, and let the registry
              // settle the placement (see `Model::checkout_placement`).
              scheduler.add(
                device_dispatch(
                  GoalRejected(
                    session~,
                    command~,
                    draft=text,
                    message="Couldn’t confirm worktree creation because the desktop host did not respond. This chat may already be bound to the new worktree; the goal was not sent.",
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
                device_dispatch(
                  GoalRejected(
                    session~,
                    command~,
                    draft=text,
                    message="Couldn’t create the worktree. " + message,
                  ),
                ),
              )
              return
            }
          }
          guard !reply.name.is_empty() else {
            scheduler.add(
              device_dispatch(
                GoalRejected(
                  session~,
                  command~,
                  draft=text,
                  message="Couldn’t create the worktree because the host returned an incomplete reply. The goal was not sent.",
                ),
              ),
            )
            return
          }
          // Bind before the goal settles, so the chip and a retried submit both
          // know the environment. The canonical registry list still arrives as
          // `worktree.changed`; the goal carries no worktree, because the host
          // routes a bound session's cwd through its registry.
          scheduler.add(
            device_dispatch(
              WorktreeCreated(workspace~, name=reply.name, session~),
            ),
          )
          let payload = goal_payload(
            session, engine_model, reasoning, max_steps, workspace, text,
          )
          request_agent_goal(
            scheduler, dispatch, channel, payload, session, command, text,
          )
        },
      ) catch {
        // Unreachable: the lane only ever wakes its waiters, never fails
        // them, and the work it runs is `noraise`. The type cannot say so.
        _ => ()
      }
    })
  })
}

///|
/// Rebuild a checkout that was deleted outside the app. The host repairs the
/// existing registry entry on its surviving branch, so this restores the
/// conversation's real environment; the canonical rows arrive as
/// `worktree.changed` from the commit seam.
fn repair_worktree_cmd(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  workspace : String,
  session : String,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result : @protocol.WorktreeCreateResult = @interop.bridge_request(
        channel,
        @commands.worktree_create,
        { workspace, session: Some(session), codex_thread: None, },
      ) catch {
        _ => {
          scheduler.add(
            dispatch(
              WorktreeFailed(
                "Couldn’t repair the worktree because the desktop host did not respond. Retry, or archive this chat.",
              ),
            ),
          )
          return
        }
      }
      if result is @protocol.WorktreeCreateError(message) {
        scheduler.add(
          dispatch(WorktreeFailed("Couldn’t repair the worktree. " + message)),
        )
      }
    })
  })
}

///|
/// Reduce the typed registry rows shared by list replies and the host's
/// post-commit broadcast to what the sidebar reads, dropping blank names
/// and blank session ids a hand-edited registry file could carry.
fn worktree_rows(
  channel : @interop.ChannelId,
  infos : Array[@protocol.WorktreeInfo],
) -> Array[WorktreeRow] {
  let rows : Array[WorktreeRow] = []
  for info in infos {
    guard !info.name.is_empty() else { continue }
    rows.push({
      name: info.name,
      session: if info.session is Some(id) && !id.is_empty() {
        Some(id)
      } else {
        None
      },
      path: @resource.of_path(channel, info.path),
      codex_thread: if info.codex_thread is Some(id) && !id.is_empty() {
        Some(id)
      } else {
        None
      },
      present: info.present,
    })
  }
  rows
}

///|
/// The `worktree.changed` notification: the workspace it belongs to plus its
/// canonical post-commit rows.
fn worktree_changed_msg(
  channel : @interop.ChannelId,
  payload : @protocol.WorktreeChangedPayload,
) -> DeviceMsg? {
  guard @resource.of_path(channel, payload.workspace) is Some(workspace) else {
    return None
  }
  Some(WorktreesChanged(worktree_rows(channel, payload.worktrees), workspace~))
}

///|
/// The registry row for a durable session's worktree, if one binds it.
fn DeviceState::worktree_row(
  self : DeviceState,
  project : @common.Uri,
  session : String,
) -> WorktreeRow? {
  for group in self.worktrees {
    guard group.project == project else { continue }
    for row in group.rows {
      if row.session is Some(bound) && bound == session {
        return Some(row)
      }
    }
  }
  None
}

///|
/// Reconcile one durable session's conversation workspace with this device's
/// current project/worktree registry. Before a project's rows load, retain an
/// already-known local Worktree binding; once rows are present, their session
/// mapping is authoritative and an absent row means Project.
fn DeviceState::conversation_workspace(
  self : DeviceState,
  project : @common.Uri,
  session : String,
  current : Workspace,
) -> Workspace {
  for group in self.worktrees {
    guard group.project == project else { continue }
    for row in group.rows {
      if row.session == Some(session) {
        return Worktree(project~, name=row.name)
      }
    }
    return Project(root=project)
  }
  if current is Worktree(project=known, ..) && known == project {
    current
  } else {
    Project(root=project)
  }
}

///|
/// The worktree a durable session runs in — the sidebar glyph's data source.
fn worktree_name_for(
  dev : DeviceState,
  project : @common.Uri,
  session : String,
) -> String? {
  dev.worktree_row(project, session).map(row => row.name)
}

///|
/// Resolve every directory fact for a conversation from its durable workspace
/// and the owning host's current registry. `None` means the registry or bridge
/// has not supplied enough information yet; callers must park path-based work
/// instead of falling back to the project's main checkout.
fn Model::conversation_placement(
  self : Model,
  conv : Conversation,
) -> @interop.CheckoutPlacement? {
  match conv.workspace {
    Project(root~) => {
      guard self.device_state(conv.device) is Some(dev) &&
        dev.worktrees.iter().any(group => group.project == root) else {
        return None
      }
      Some(@interop.WorkspaceRoot(root~))
    }
    Worktree(project~, name=_) => {
      // The durable name is not a directory. Wait for the registry row before
      // exposing a live placement so no file or terminal request can combine
      // that name with the project's main checkout.
      guard self.device_state(conv.device) is Some(dev) else { return None }
      guard dev.worktrees.iter().any(group => group.project == project) else {
        return None
      }
      guard dev.worktree_row(project, conv.session_id) is Some(row) else {
        // The registry is authoritative once loaded. A missing binding means
        // the host unbound this session and the update path will transition
        // the conversation to Project in the same message.
        return None
      }
      if row.present {
        row.path.map(root => @interop.Worktree(project~, name=row.name, root~))
      } else {
        Some(@interop.MissingWorktree(project~, name=row.name))
      }
    }
  }
}

///|
/// The path projection of `conversation_placement`. This method does not own
/// another root; it only keeps path-only call sites from unpacking the enum.
fn Model::conversation_root(self : Model, conv : Conversation) -> @common.Uri? {
  self.conversation_placement(conv).bind(placement => placement.checkout_root())
}

///|
fn DeviceState::with_worktrees(
  self : DeviceState,
  project : @common.Uri,
  rows : Array[WorktreeRow],
  generation~ : Int,
) -> DeviceState {
  let groups = self.worktrees.filter(group => group.project != project)
  groups.push({ project, rows, generation, })
  { ..self, worktrees: groups, }
}

///|
/// The token one workspace's rows were last applied under; a reply carrying
/// an older token is stale for that workspace alone.
fn DeviceState::worktree_generation(
  self : DeviceState,
  project : @common.Uri,
) -> Int {
  for group in self.worktrees {
    if group.project == project {
      return group.generation
    }
  }
  -1
}

///|
/// Whether the next submit should run the create-then-start chain: the
/// composer chose worktree mode, nothing is bound yet, and the conversation
/// has no durable history. Durable emptiness is the whole test, so a rejected
/// setup attempt leaves it intact: the retry after a failed create must
/// re-enter the chain, never silently fall back to the workspace root.
fn Conversation::wants_fresh_worktree(self : Conversation) -> Bool {
  self.worktree_mode &&
  self.workspace is Project(..) &&
  self.messages.length() == 0
}

///|
/// Whether the composer may still choose where this conversation runs.
///
/// Durable emptiness, not `has_begun`: a rejected setup attempt leaves a
/// restored draft behind, and hiding the toggle then would lock the user into
/// retrying the failing create with no way back to Local.
///
/// A command already sent settles it, though — that command *is* the choice
/// being exercised. Both the start and the goal chains create the worktree
/// and bind it asynchronously, and neither re-reads the mode when the reply
/// lands, so flipping the chip during that window would not move what is in
/// flight. It would only leave the chip disagreeing with where the
/// conversation is being pinned.
fn Model::can_choose_launch_mode(self : Model, conv : Conversation) -> Bool {
  guard conv.workspace is Project(root~) &&
    conv.messages.length() == 0 &&
    conv.run is NoRun(..) &&
    conv.goal_pending is None else {
    return false
  }
  // The registry, not the provisional Project variant, decides whether this
  // session has already become a worktree. A create whose reply was lost can
  // leave the conversation as Project while the host is already bound, and
  // offering Local over that would put the chip at odds with the next start.
  //
  // Only a positive binding closes the choice. An unloaded registry answers
  // `None`, and absence of evidence is not evidence of binding — the mode is
  // a local preference the create path re-reads when it sends, so refusing it
  // before the list arrives would take the choice away for a reason that is
  // only ever "not known yet".
  !(self.device_state(conv.device) is Some(dev) &&
  dev.worktree_row(root, conv.session_id) is Some(_))
}

///|
/// The composer's launch-mode chip: visible while the conversation can
/// still choose (a workspace conversation that has not begun), fixed to
/// the worktree's name once the chain has bound one.
fn Model::worktree_control(
  self : Model,
  conv : Conversation,
) -> @composer.WorktreeControl? {
  guard conv.messages.length() == 0 else { return None }
  let choice = match conv.workspace {
    Worktree(name~, ..) => @composer.BoundWorktree(name)
    Project(_) if conv.worktree_mode => @composer.FreshWorktree
    Project(_) => @composer.LocalCheckout
  }
  Some({ choice, enabled: self.can_choose_launch_mode(conv), })
}

// Tests for the worktree flow's pure pieces: the notification decoder and
// the update handlers that flag the launch mode, bind the chain's created
// environment, adopt registry rows, and stage removals.

///|
fn test_worktree_rows() -> Array[WorktreeRow] {
  [
    {
      name: "wt",
      session: Some("desktop-wt"),
      codex_thread: None,
      path: None,
      present: true,
    },
  ]
}

///|
fn test_archive_refusal(
  worktree? : String = "wt-1",
  dirty_paths? : Array[String] = ["desktop/lepus"],
  dirty_path_count? : Int = 1,
) -> @protocol.ArchiveNeedsForceReply {
  { worktree, dirty_paths, dirty_path_count, }
}

///|
test "worktree commit decoder carries the workspace and its rows" {
  let row : Json = {
    "name": "wt",
    "branch": "openseek/wt",
    "base": "main",
    "session": "s1",
    "path": "/proj/.worktrees/wt",
    "present": true,
  }
  guard @protocol.Notification::from_wire("worktree.changed", {
      "workspace": "/proj",
      "worktrees": [row],
    })
    is Some(notification) else {
    fail("known notification was rejected")
  }
  guard notification_msg(@interop.ChannelId::Local, notification)
    is Some(FromDevice(_, WorktreesChanged(rows, workspace~))) else {
    fail("expected a worktree change")
  }
  assert_eq(workspace.path, "/proj")
  inspect(rows.length(), content="1")
  inspect(rows[0].name, content="wt")
  assert_eq(rows[0].session, Some("s1"))
  assert_true(rows[0].path is Some({ path: "/proj/.worktrees/wt", .. }))
  assert_true(rows[0].present)
  // A broadcast without its workspace is structurally unusable.
  assert_true(
    @protocol.Notification::from_wire("worktree.changed", { "worktrees": [] })
    is None,
  )
}

///|
test "the launch mode toggles only before the conversation begins" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Project(root=workspace),
  })
  let (_, on) = update(dispatch, ToggleWorktreeMode, model)
  assert_true(on.active().worktree_mode)
  // The chip decides only this conversation. The workspace's own default
  // for future chats is a durable setting edited on its settings page, and
  // the chip must not silently rewrite it.
  assert_true(on.dev().workspace_settings.is_empty())
  // Replaying the same event from the same model is pure.
  let (_, replayed) = update(dispatch, ToggleWorktreeMode, model)
  assert_true(replayed.active().worktree_mode)
  let (_, off) = update(dispatch, ToggleWorktreeMode, on)
  assert_false(off.active().worktree_mode)
  // A begun conversation keeps its environment; the toggle is inert.
  let begun = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Project(root=workspace),
    messages: [{ kind: User("hi"), ts: None, sequence: None, }],
  })
  let (_, still) = update(dispatch, ToggleWorktreeMode, begun)
  assert_false(still.active().worktree_mode)
  // A conversation already bound to a worktree has nothing left to choose.
  let bound = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Worktree(project=workspace, name="wt"),
  })
  let (_, still_bound) = update(dispatch, ToggleWorktreeMode, bound)
  assert_false(still_bound.active().worktree_mode)
}

///|
test "new conversations inherit only their workspace's launch default" {
  let dispatch = test_dispatch()
  let preferred = @interop.ChannelId::Local.test_resource("/preferred")
  let other = @interop.ChannelId::Local.test_resource("/other")
  let preferred_model = test_model().with_dev(dev => {
    ..dev.with_workspace_settings(preferred, true, generation=1),
    active_project: Some(preferred),
  })
  let (_, inherited) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "preferred-chat", }),
    preferred_model,
  )
  assert_eq(inherited.active().workspace, Project(root=preferred))
  assert_true(inherited.active().worktree_mode)
  let other_model = preferred_model.with_dev(dev => {
    ..dev,
    active_project: Some(other),
  })
  let (_, other_chat) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "other-chat", }),
    other_model,
  )
  assert_eq(other_chat.active().workspace, Project(root=other))
  assert_false(other_chat.active().worktree_mode)
  // The mirror is per device state: the same path on a device this page
  // does not hold answers the safe Local default.
  let remote_workspace = @interop.ChannelId::Remote("device-a").test_resource(
    "/preferred",
  )
  assert_false(
    preferred_model.default_worktree_mode(
      @interop.ChannelId::Remote("device-a"),
      remote_workspace,
    ),
  )
}

///|
test "a repeated rotation keeps an existing conversation's launch choice" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let existing = {
    ..test_conversation(),
    workspace: Project(root=workspace),
    worktree_mode: false,
  }
  let model = test_model()
    .replace_conversation(existing)
    .with_dev(dev => {
      ..dev.with_workspace_settings(workspace, true, generation=1),
      active_project: Some(workspace),
    })
  let (_, replayed) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-test", }),
    model,
  )
  assert_false(replayed.active().worktree_mode)
}

///|
#warnings("-alert_unstable")
test "the launch mode stops being a choice once a placement is in flight" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let composing : Conversation = {
    ..test_conversation(),
    workspace: Project(root=workspace),
    worktree_mode: true,
  }
  // `worktree.create` is out. The chain read the mode when it was sent and
  // will bind whatever comes back, so a flip now could not move it — it would
  // only leave the chip disagreeing with where the session is being pinned.
  // Neither of these adds a message, which is why durable emptiness alone was
  // not enough to close the window.
  for
    pinned in [
      {
        ..composing,
        goal_pending: Some({ id: "goal-1", request: Clearing, since: 0, }),
      },
      { ..composing, run: Starting(submission_id="s-1"), },
    ] {
    let (_, kept) = update(
      dispatch,
      ToggleWorktreeMode,
      test_model().replace_conversation(pinned),
    )
    assert_true(kept.active().worktree_mode)
    // And the typed component state says which mode is being established
    // without offering an action that cannot do anything.
    guard test_model().worktree_control(pinned) is Some(control) else {
      fail("expected worktree control state")
    }
    assert_true(control.choice is @composer.FreshWorktree)
    assert_false(control.enabled)
  }
  // Still a choice while nothing is out.
  let (_, free) = update(
    dispatch,
    ToggleWorktreeMode,
    test_model().replace_conversation(composing),
  )
  assert_false(free.active().worktree_mode)
  guard test_model().worktree_control(composing) is Some(offered) else {
    fail("expected worktree control state")
  }
  assert_true(offered.enabled)
}

///|
test "a worktree the registry says is bound closes the choice" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let composing : Conversation = {
    ..test_conversation(),
    workspace: Project(root=workspace),
    worktree_mode: true,
  }
  // A create whose reply was lost leaves the local binding empty while the
  // host is already bound. Offering Local over that would put the chip at
  // odds with where the next start actually runs.
  let bound = {
    ..test_model().replace_conversation(composing),
    devices: [
      {
        ..test_model().focused_device().unwrap(),
        worktrees: [
          {
            project: workspace,
            generation: 1,
            rows: [
              {
                name: "wt-1",
                session: Some("desktop-test"),
                path: None,
                codex_thread: None,
                present: true,
              },
            ],
          },
        ],
      },
    ],
  }
  assert_false(bound.can_choose_launch_mode(composing))
  let (_, kept) = update(dispatch, ToggleWorktreeMode, bound)
  assert_true(kept.active().worktree_mode)
  // An unloaded registry is not evidence of binding: the mode is a local
  // preference the create path re-reads when it sends.
  assert_true(
    test_model()
    .replace_conversation(composing)
    .can_choose_launch_mode(composing),
  )
}

///|
test "worktree created binds the composing conversation" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
      worktree_mode: true,
    })
    .with_dev(dev => dev.with_workspace_settings(workspace, true, generation=1))
  let (_, bound) = update_dev(
    dispatch,
    WorktreeCreated(workspace~, name="wt-1", session="desktop-test"),
    model,
  )
  assert_true(bound.active().worktree_name() is Some("wt-1"))
  assert_false(bound.active().worktree_mode)
  // Binding one conversation leaves the workspace's own default alone.
  assert_true(bound.default_worktree_mode(Local, workspace))
  // A created notice for an unknown session changes nothing.
  let (_, unknown) = update_dev(
    dispatch,
    WorktreeCreated(workspace~, name="wt-2", session="desktop-else"),
    bound,
  )
  assert_true(unknown.active().worktree_name() is Some("wt-1"))
}

///|
test "a missing checkout stays bound while rebuild and archive remain reachable" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let worktree_root = @interop.ChannelId::Local.test_resource(
    "/proj/.worktrees/wt",
  )
  let bound = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        {
          project: workspace,
          rows: [
            {
              name: "wt",
              session: Some("desktop-test"),
              path: Some(worktree_root),
              codex_thread: None,
              present: true,
            },
          ],
          generation: 1,
        },
      ],
    })
  assert_true(
    bound.conversation_placement(bound.active())
    is Some(@interop.Worktree(name="wt", ..)),
  )
  // Model the production path with an active changed-file review. Placement
  // health must park host work without replacing this real owner or document.
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let review_path = @pathx.Relative("src/reviewed.mbt")
  let review_change : @fileeditor.ChangedFile = {
    path: review_path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let review_docs : Map[@pathx.Relative, @fileeditor.Doc] = Map([])
  review_docs[review_path] = {
    name: "reviewed.mbt",
    state: TabLoaded(
      content="working",
      absolute=@interop.ChannelId::Local.test_resource("/proj/src/reviewed.mbt"),
      sig="7:1",
    ),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("HEAD"),
      view_mode: ReviewSource,
      selected: review_change,
    }),
    stale: false,
  }
  let review_dock = @dock.open_file(
    { ..bound.dock, owner: Some(owner), },
    review_path,
  )
  let bound = {
    ..bound,
    right_panel_open: true,
    dock: review_dock,
    file_panel: {
      ..bound.file_panel,
      owner: Some(owner),
      docs: review_docs,
      changes: ChangeListReady(
        repository=true,
        files=[review_change],
        refreshing=false,
        refresh_again=false,
      ),
      changes_generation: 2,
      changes_head: Some("head"),
      changes_head_known: true,
      review_generation: 3,
    },
  }
  // The retained row carries `present: false`, whether an external deletion
  // or archive removed the checkout.
  let (_, gone) = update_dev(
    dispatch,
    WorktreesChanged(
      [
        {
          name: "wt",
          session: Some("desktop-test"),
          path: None,
          codex_thread: None,
          present: false,
        },
      ],
      workspace~,
    ),
    bound,
  )
  assert_true(
    gone.conversation_placement(gone.active())
    is Some(@interop.MissingWorktree(name="wt", ..)),
  )
  assert_true(file_ctx(gone).owner == owner)
  assert_false(gone.file_panel.review_recovery_pending)
  assert_true(gone.file_panel.placement.is_parked())
  assert_true(
    gone.file_panel.docs.get(review_path)
    is Some(
      {
        review: Some({ generation: 4, baseline: ReviewContent("HEAD"), .. }),
        ..
      }
    ),
  )
  let missing_epoch = gone.file_panel.request_epoch
  // The authoritative present row repairs placement without rerooting the
  // panel through an empty owner; the review remains ready for its fresh
  // Changes snapshot to restart any interrupted side.
  let (_, restored) = update_dev(
    dispatch,
    WorktreesChanged(
      [
        {
          name: "wt",
          session: Some("desktop-test"),
          codex_thread: None,
          path: Some(worktree_root),
          present: true,
        },
      ],
      workspace~,
    ),
    gone,
  )
  assert_true(file_ctx(restored).owner == owner)
  assert_false(restored.file_panel.review_recovery_pending)
  assert_false(restored.file_panel.placement.is_parked())
  assert_eq(restored.file_panel.request_epoch, missing_epoch)
  assert_true(
    restored.file_panel.docs.get(review_path)
    is Some({ review: Some({ generation: 4, .. }), stale: true, .. }),
  )
  assert_true(
    terminal_ctx(gone).placement
    is Some(@interop.MissingWorktree(name="wt", ..)),
  )
  // Session-list reconstruction does not itself carry the worktree name; the
  // retained registry row still keeps its terminal group away from main.
  let resumed = gone.replace_conversation({
    ..gone.active(),
    workspace: gone
    .dev()
    .conversation_workspace(workspace, "desktop-test", Project(root=workspace)),
  })
  assert_true(
    terminal_ctx(resumed).placement
    is Some(@interop.MissingWorktree(name="wt", ..)),
  )
  // The binding is NOT dropped: the conversation must never silently read as
  // a plain workspace chat.
  assert_true(gone.active().worktree_name() is Some("wt"))
  // Repair does not mutate optimistically: the registry broadcast is the
  // authority for the restored checkout.
  let (_, repairing) = update(dispatch, RepairWorktree, gone)
  assert_true(
    repairing.conversation_placement(repairing.active())
    is Some(@interop.MissingWorktree(name="wt", ..)),
  )
  assert_true(repairing.active().worktree_name() is Some("wt"))
  // Archive is the other exit. Like every update handler, applying the same
  // message to the same input produces the same model, and the binding stays
  // until the host moves the conversation out of the live list.
  let (_, archiving) = update(
    dispatch,
    ArchiveSession(@interop.ChannelId::Local, "desktop-test"),
    gone,
  )
  let (_, archiving_again) = update(
    dispatch,
    ArchiveSession(@interop.ChannelId::Local, "desktop-test"),
    gone,
  )
  assert_true(
    archiving.conversation_placement(archiving.active())
    is Some(@interop.MissingWorktree(name="wt", ..)),
  )
  assert_eq(
    archiving.dev().sessions_request_generation,
    archiving_again.dev().sessions_request_generation,
  )
  assert_eq(
    archiving.dev().archived_request_generation,
    archiving_again.dev().archived_request_generation,
  )
  // Repair is inert for a healthy conversation, so a stale click cannot
  // rebuild a worktree that is fine.
  let (_, noop) = update(dispatch, RepairWorktree, bound)
  assert_true(noop.active().worktree_name() is Some("wt"))
  assert_true(
    noop.conversation_placement(noop.active())
    is Some(@interop.Worktree(name="wt", ..)),
  )
}

///|
test "a restored workspace conversation waits for placement before using root" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let unresolved = test_model().replace_conversation({
    ..test_conversation()
    // `session.list` reconstructs durable conversations as Project until the
    // corresponding registry identifies a worktree binding.
    ,
    workspace: Project(root=workspace),
  })
  assert_true(unresolved.conversation_placement(unresolved.active()) is None)
  assert_true(terminal_ctx(unresolved).placement is None)
  // Placement is a separate typed fence; preserving the real identity lets
  // open review state survive while every host-backed action remains parked.
  assert_eq(file_ctx(unresolved).owner.session, "desktop-test")
  let generation = unresolved.dev().worktrees_request_generation
  let (_, retrying) = update(dispatch, RetryWorktreePlacement, unresolved)
  assert_eq(retrying.dev().worktrees_request_generation, generation + 1)
  assert_true(retrying.conversation_placement(retrying.active()) is None)
  let (_, loaded) = update_dev(
    dispatch,
    WorktreesLoaded(
      [],
      workspace~,
      connection_generation=0,
      request_generation=1,
    ),
    unresolved,
  )
  assert_true(
    loaded.conversation_placement(loaded.active())
    is Some(@interop.WorkspaceRoot(..)),
  )
  assert_eq(file_ctx(loaded).owner.session, "desktop-test")
}

///|
test "a worktree mode submit opens the run like any other" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
      worktree_mode: true,
      task: "go",
    })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ project: workspace, rows: [], generation: 1, }],
    })
  let (_, sent) = update(dispatch, Send, model)
  assert_true(sent.active().run is Starting(..))
  inspect(sent.active().task, content="")
  // The mode survives until the chain's create binds a name, so a rejected
  // create (which restores the draft) can retry in the same mode.
  assert_true(sent.active().worktree_mode)
}

///|
test "worktrees loaded respects the request generation fence" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().with_dev(dev => {
    ..dev,
    worktrees_request_generation: 2,
  })
  let (_, applied) = update_dev(
    dispatch,
    WorktreesLoaded(
      test_worktree_rows(),
      workspace~,
      connection_generation=0,
      request_generation=2,
    ),
    model,
  )
  assert_true(
    worktree_name_for(applied.dev(), workspace, "desktop-wt") is Some("wt"),
  )
  let (_, stale) = update_dev(
    dispatch,
    WorktreesLoaded(
      [],
      workspace~,
      connection_generation=0,
      request_generation=1,
    ),
    applied,
  )
  assert_true(
    worktree_name_for(stale.dev(), workspace, "desktop-wt") is Some("wt"),
  )
}

///|
test "a worktree list failure stays unresolved and ignores stale errors" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let unresolved = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Project(root=workspace),
  })
  let (_, failed) = update_dev(
    dispatch,
    WorktreesFailed(
      workspace~,
      connection_generation=0,
      request_generation=1,
      message="offline",
    ),
    unresolved,
  )
  assert_true(failed.conversation_placement(failed.active()) is None)
  assert_eq(failed.notifications.length(), 1)
  assert_true(failed.notifications[0].message.contains("offline"))
  let (_, loaded) = update_dev(
    dispatch,
    WorktreesLoaded(
      [],
      workspace~,
      connection_generation=0,
      request_generation=2,
    ),
    failed,
  )
  let (_, stale_failure) = update_dev(
    dispatch,
    WorktreesFailed(
      workspace~,
      connection_generation=0,
      request_generation=1,
      message="late",
    ),
    loaded,
  )
  assert_eq(stale_failure.notifications.length(), 1)
  assert_true(
    stale_failure.conversation_placement(stale_failure.active())
    is Some(@interop.WorkspaceRoot(..)),
  )
}

///|
test "a broadcast for one workspace never fences a sibling's reply" {
  let dispatch = test_dispatch()
  let a = @interop.ChannelId::Local.test_resource("/a")
  let b = @interop.ChannelId::Local.test_resource("/b")
  // One fan-out round (token 1) has replies for /a and /b in flight; /a's
  // broadcast lands between them. /b's still-current reply must apply.
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [a, b],
    worktrees_request_generation: 1,
  })
  let (_, changed) = update_dev(
    dispatch,
    WorktreesChanged(
      [
        {
          name: "wt-a",
          session: Some("s-a"),
          codex_thread: None,
          path: None,
          present: true,
        },
      ],
      workspace=a,
    ),
    model,
  )
  let (_, both) = update_dev(
    dispatch,
    WorktreesLoaded(
      [
        {
          name: "wt-b",
          session: Some("s-b"),
          codex_thread: None,
          path: None,
          present: true,
        },
      ],
      workspace=b,
      connection_generation=0,
      request_generation=1,
    ),
    changed,
  )
  assert_true(worktree_name_for(both.dev(), a, "s-a") is Some("wt-a"))
  assert_true(worktree_name_for(both.dev(), b, "s-b") is Some("wt-b"))
  // /a's own in-flight round-1 reply IS fenced by its broadcast.
  let (_, fenced) = update_dev(
    dispatch,
    WorktreesLoaded(
      [],
      workspace=a,
      connection_generation=0,
      request_generation=1,
    ),
    both,
  )
  assert_true(worktree_name_for(fenced.dev(), a, "s-a") is Some("wt-a"))
}

///|
test "a worktree commit broadcast supersedes lists and unbinds removed names" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let placed = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt"),
      branch: Some("openseek/wt"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        { project: workspace, rows: test_worktree_rows(), generation: 1, },
      ],
      worktrees_request_generation: 1,
    })
  // The durable worktree name has no registry row bound to this session, so
  // the conversation has no live checkout yet. Open Quick Open there, giving
  // the broadcast a running search to fence.
  let (_, model) = update(dispatch, QuickOpenOpen(@quick_open.Files), placed)
  assert_eq(model.conversation_root(model.active()), None)
  assert_true(model.quick_open.is_open())
  let changed_msg = WorktreesChanged([], workspace~)
  let (_, repeated) = update_dev(dispatch, changed_msg, model)
  let (_, changed) = update_dev(dispatch, changed_msg, model)
  assert_true(changed.quick_open == repeated.quick_open)
  inspect(changed.dev().worktrees_request_generation, content="2")
  assert_true(worktree_name_for(changed.dev(), workspace, "desktop-wt") is None)
  // The removed worktree's conversation is a plain workspace conversation
  // now — exactly what the host's registry prune did to the mapping — and
  // every placement derived from the dead checkout (the file root and the
  // composer's branch chip) went with it.
  assert_true(changed.active().workspace is Project(_))
  assert_true(changed.active().branch is None)
  assert_eq(changed.conversation_root(changed.active()), Some(workspace))
  // A root arrived under the open palette, so the post-message reconciliation
  // restarts its run against the project it can actually search. The package
  // owns what that restart does; the shell owns only that it happens at all.
  assert_true(changed.quick_open.is_open())
  assert_true(changed.quick_open != model.quick_open)
  let (_, stale) = update_dev(
    dispatch,
    WorktreesLoaded(
      test_worktree_rows(),
      workspace~,
      connection_generation=0,
      request_generation=1,
    ),
    changed,
  )
  assert_true(worktree_name_for(stale.dev(), workspace, "desktop-wt") is None)
}

///|
test "a failed worktree setup is an actionable toast and keeps retry eligible" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
      worktree_mode: true,
      task: "go",
    })
    .with_dev(dev => {
      ..dev.with_workspace_settings(workspace, true, generation=1),
      worktrees: [{ project: workspace, rows: [], generation: 1, }],
    })
  let worktrees_generation = model.dev().worktrees_request_generation
  let (_, sent) = update(dispatch, Send, model)
  guard sent.active().pending_prompt is Some(entry) else {
    fail("expected the submission to be in flight")
  }
  let message = "Couldn’t create the worktree. Submodules did not finish initializing within 10 seconds. Increase the checkout timeout in Workspace Settings or leave submodules uninitialized."
  let failed = WorktreeSetupFailed(
    session="desktop-test",
    submission_id=entry.submission_id,
    message~,
  )
  // Same input, same model: the setup handler is pure even though its command
  // schedules toast expiry and a placement refresh.
  let (_, repeated) = update_dev(dispatch, failed, sent)
  let (_, rejected) = update_dev(dispatch, failed, sent)
  assert_eq(repeated.active().task, rejected.active().task)
  // The draft came back *and* the submission is no longer in flight: a setup
  // that never reached `agent.start` leaves nothing waiting for a receipt.
  assert_true(repeated.active().pending_prompt is None)
  assert_eq(repeated.notifications.length(), 1)
  assert_eq(repeated.notifications[0].message, message)
  assert_eq(
    repeated.dev().worktrees_request_generation,
    rejected.dev().worktrees_request_generation,
  )
  // Setup never reached an agent, so the explanation is a toast rather than
  // an agent-style transcript error. The exact prompt returns to the composer.
  assert_eq(rejected.active().task, "go")
  assert_eq(rejected.notifications.length(), 1)
  assert_eq(rejected.notifications[0].message, message)
  // The next submit re-enters the create-then-start chain instead of silently
  // running in the workspace root.
  assert_true(rejected.active().worktree_mode)
  assert_true(rejected.active().wants_fresh_worktree())
  // Every rejected workspace start refreshes the registry. Besides keeping a
  // failed setup honest, this is how an externally deleted checkout becomes
  // the typed missing state without restarting the app.
  assert_eq(
    rejected.dev().worktrees_request_generation,
    worktrees_generation + 1,
  )
  // And the escape hatch stays open: the toggle still switches the chat back
  // to Local without touching the workspace's own default.
  let (_, switched) = update(dispatch, ToggleWorktreeMode, rejected)
  assert_false(switched.active().worktree_mode)
  assert_true(switched.default_worktree_mode(Local, workspace))
}

///|
test "a remote removal closes this client's discard dialog" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        { project: workspace, rows: test_worktree_rows(), generation: 1, },
      ],
    })
  let (_, staged) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", refusal=test_archive_refusal()),
    model,
  )
  assert_true(staged.archive_confirm is Some(_))
  // A broadcast for an unrelated workspace leaves the dialog alone…
  let other = @interop.ChannelId::Local.test_resource("/other")
  let (_, unrelated) = update_dev(
    dispatch,
    WorktreesChanged([], workspace=other),
    staged,
  )
  assert_true(unrelated.archive_confirm is Some(_))
  // …but the session's own mapping disappearing (a protocol client explicitly
  // removed it) closes the dialog: its confirm would be stale.
  let (_, swept) = update_dev(
    dispatch,
    WorktreesChanged([], workspace~),
    unrelated,
  )
  assert_true(swept.archive_confirm is None)
  assert_true(swept.active().workspace is Project(_))
}

///|
test "worktree broadcasts and reconnect snapshots update an open Codex task" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/project")
  let worktree = @interop.ChannelId::Local.test_resource(
    "/work/project/.worktrees/wt-1",
  )
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/work/project",
      "projectRoot": "/work/project",
      "turns": [],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }
  let rows = [
    {
      name: "wt-1",
      session: None,
      codex_thread: Some("codex-thread-1"),
      path: Some(worktree),
      present: true,
    },
  ]
  let broadcast = WorktreesChanged(rows, workspace~)
  let (_, once) = update_dev(dispatch, broadcast, model)
  let (_, twice) = update_dev(dispatch, broadcast, model)
  assert_true(once.codex == twice.codex)
  assert_true(once.dev() == twice.dev())
  assert_true(once.conversations == twice.conversations)
  assert_true(once.archive_confirm == twice.archive_confirm)
  assert_true(
    once.codex.active_placement(@interop.ChannelId::Local)
    is Some(@interop.Worktree(name="wt-1", ..)),
  )
  assert_eq(
    once.codex
    .active_placement(@interop.ChannelId::Local)
    .bind(placement => placement.checkout_root())
    .map(root => root.path),
    Some("/work/project/.worktrees/wt-1"),
  )
  // A client reconnecting after this broadcast was emitted cannot replay it.
  // Its accepted `worktree.list` snapshot must produce the same Codex state.
  let reconnect = WorktreesLoaded(
    rows,
    workspace~,
    connection_generation=0,
    request_generation=1,
  )
  let (_, reconnected_once) = update_dev(dispatch, reconnect, model)
  let (_, reconnected_twice) = update_dev(dispatch, reconnect, model)
  assert_true(reconnected_once.codex == reconnected_twice.codex)
  assert_true(reconnected_once.dev() == reconnected_twice.dev())
  assert_true(reconnected_once.conversations == reconnected_twice.conversations)
  assert_true(
    reconnected_once.archive_confirm == reconnected_twice.archive_confirm,
  )
  assert_true(reconnected_once.codex == once.codex)
  assert_true(
    reconnected_once.codex.active_placement(@interop.ChannelId::Local)
    is Some(@interop.Worktree(name="wt-1", ..)),
  )
  assert_eq(
    reconnected_once.codex
    .active_placement(@interop.ChannelId::Local)
    .bind(placement => placement.checkout_root())
    .map(root => root.path),
    Some("/work/project/.worktrees/wt-1"),
  )
}

///|
test "a removed worktree's probes cannot repopulate the composer" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        { project: workspace, rows: test_worktree_rows(), generation: 1, },
      ],
    })
  // A branch probe answers, which is also what starts the pull-request lookup:
  // both are now on record, and the second is still in flight.
  let stale_diffstat : DiffStat = {
    added: 12,
    removed: 3,
    files: 2,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, described) = update_dev(
    dispatch,
    branch_reply("feature/x", diffstat=stale_diffstat),
    model,
  )
  assert_true(described.active().branch is Some("feature/x"))
  assert_eq(described.active().diffstat, Some(stale_diffstat))
  assert_true(described.active().pull_request is Some(_))
  // The checkout is removed while a refresh of each is outstanding.
  let (_, swept) = update_dev(
    dispatch,
    WorktreesChanged([], workspace~),
    described,
  )
  assert_true(swept.active().workspace is Project(_))
  assert_true(swept.active().branch is None)
  assert_true(swept.active().pull_request is None)
  // Their answers arrive afterwards, describing a directory that is gone. A
  // generation left where it was would take both back.
  let (_, late_branch) = update_dev(dispatch, branch_reply("feature/x"), swept)
  assert_true(late_branch.active().branch is None)
  let (_, late_lookup) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      pull_request=test_pull_request(),
    ),
    late_branch,
  )
  assert_true(late_lookup.active().pull_request is None)
  // A reconnect list is equally authoritative. If another client removed the
  // binding during the connection gap, the first fresh empty list must perform
  // the same Git reset and generation fence as the broadcast above.
  let list_reply = WorktreesLoaded(
    [],
    workspace~,
    connection_generation=0,
    request_generation=2,
  )
  let (_, listed) = update_dev(dispatch, list_reply, described)
  let (_, replayed) = update_dev(dispatch, list_reply, described)
  assert_true(listed.active().workspace is Project(_))
  assert_true(listed.active().branch is None)
  assert_true(listed.active().diffstat is None)
  assert_true(listed.active().pull_request is None)
  assert_eq(
    listed.active().branch_generation,
    replayed.active().branch_generation,
  )
  assert_eq(
    listed.active().pull_request_generation,
    replayed.active().pull_request_generation,
  )
  let (_, late_branch) = update_dev(dispatch, branch_reply("feature/x"), listed)
  assert_true(late_branch.active().branch is None)
  let (_, late_lookup) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      pull_request=test_pull_request(),
    ),
    late_branch,
  )
  assert_true(late_lookup.active().pull_request is None)
}

///|
test "a dirty archive stages the discard dialog and confirm retries forced" {
  let dispatch = test_dispatch()
  // The host's refusal stages the dialog with its own message.
  let (_, staged) = update_dev(
    dispatch,
    ArchiveNeedsForce(
      session="desktop-test",
      refusal=test_archive_refusal(
        dirty_paths=["desktop/lepus", "editor/tokenizer.mbt"],
        dirty_path_count=4,
      ),
    ),
    test_model(),
  )
  guard staged.archive_confirm is Some(confirm) else {
    fail("refusal staged no dialog")
  }
  inspect(confirm.session, content="desktop-test")
  assert_eq(confirm.refusal.worktree, "wt-1")
  assert_eq(confirm.refusal.dirty_paths[0], "desktop/lepus")
  let warning = @composer.WorktreeArchiveDialog::{
    refusal: confirm.refusal,
    conversation_noun: "chat",
    cancel: @cmd.none,
    confirm: @cmd.none,
  }.message()
  assert_true(warning.contains("desktop/lepus"))
  assert_true(warning.contains("and 2 more"))
  // Cancel stands down without any request.
  let (_, cancelled) = update(dispatch, CancelArchiveDiscard, staged)
  assert_true(cancelled.archive_confirm is None)
  // Confirm fires the forced retry (the archive generations advance, as on
  // a plain archive click) and closes the dialog.
  let (_, restaged) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", refusal=test_archive_refusal()),
    cancelled,
  )
  let before = restaged.dev().archived_request_generation
  let (_, confirmed) = update(dispatch, ConfirmArchiveDiscard, restaged)
  assert_true(confirmed.archive_confirm is None)
  assert_eq(confirmed.dev().archived_request_generation, before + 1)
  // Confirming with nothing staged is inert.
  let (_, inert) = update(dispatch, ConfirmArchiveDiscard, confirmed)
  assert_true(inert.archive_confirm is None)
}

///|
test "a start payload never names a worktree" {
  // Creation is the binding; the host routes a bound session's cwd through
  // its registry, so the start wire shape has no worktree field to leak.
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let payload = start_payload(
    "go",
    DsPro,
    ReasoningMax,
    "1000",
    "desktop-wt",
    "sub-1",
    workspace~,
  )
  // The typed wire shape has no worktree field at all; the workspace hint
  // is the only placement the start carries.
  assert_true(
    payload.to_json() is Object(fields) && fields.get("worktree") is None,
  )
  assert_eq(payload.workspace, Some("/proj"))
  assert_eq(payload.thinking, Some(ThinkingMax))
  let unknown_model = start_payload(
    "go",
    Other("kimi-k2.5"),
    ReasoningMax,
    "1000",
    "desktop-kimi",
    "sub-2",
    workspace~,
  )
  assert_true(unknown_model.thinking is None)
}
