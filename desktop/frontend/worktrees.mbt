// The worktree launch mode: a fresh conversation in a workspace can run in
// a host-named git worktree instead of the workspace root — its own
// execution environment, bound 1:1 to the conversation. The composer
// carries the mode toggle; the first submit
// creates the worktree and starts the run in one command. Sidebar rows of
// worktree conversations wear a branch glyph, tooltipped with the name
// joined from the registry.

///|
/// One registry row of `worktree.list` / `worktree.changed`, reduced to
/// what the sidebar reads: the name (the glyph's tooltip), the bound
/// session (the join key), and whether the checkout still exists on disk.
priv struct WorktreeRow {
  name : String
  session : String?
  present : Bool
} derive(Eq)

///|
/// One workspace's worktree rows, keyed by the registry path the host also
/// uses in `worktree.changed`. `generation` is the request token the rows
/// were applied under — the staleness fence is per workspace, so a
/// broadcast for one workspace can never discard another's still-current
/// list reply.
priv struct WorkspaceWorktrees {
  workspace : @common.Uri
  rows : Array[WorktreeRow]
  generation : Int
} derive(Eq)

///|
/// The archive-discard confirmation: the host refused to archive because
/// the conversation's worktree holds uncommitted changes; confirming
/// retries the archive with force. `message` is the host's own refusal
/// text, which names the worktree.
priv struct ArchiveConfirm {
  channel : @interop.ChannelId
  session : String
  message : String
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
        { workspace: workspace.path },
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
            worktree_rows(reply.worktrees),
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
  selected_model : String,
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
      // The session is the create's idempotency key: a retry after a lost
      // reply gets the same worktree back instead of minting a second one.
      let reply : @protocol.WorktreeCreateReply = @interop.bridge_request(
        channel,
        @commands.worktree_create,
        { workspace: workspace.path, session },
      ) catch {
        error => {
          // Nothing started: reject the submission so the draft restores.
          scheduler.add(
            device_dispatch(
              StartRejected(
                session~,
                submission_id~,
                message="worktree setup failed: " +
                  @interop.bridge_error_text(error),
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
            StartRejected(
              session~,
              submission_id~,
              message="malformed worktree.create reply",
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
        device_dispatch(WorktreeCreated(workspace~, name=reply.name, session~)),
      )
      let start = start_payload(
        task,
        selected_model,
        max_steps,
        session,
        submission_id,
        workspace=Some(workspace),
      )
      request_agent_start(
        scheduler, dispatch, channel, start, session, submission_id,
      )
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
      let _ : @protocol.WorktreeCreateReply = @interop.bridge_request(
        channel,
        @commands.worktree_create,
        { workspace, session },
      ) catch {
        error => {
          scheduler.add(
            dispatch(WorktreeFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
    })
  })
}

///|
/// Reduce the typed registry rows shared by list replies and the host's
/// post-commit broadcast to what the sidebar reads, dropping blank names
/// and blank session ids a hand-edited registry file could carry.
fn worktree_rows(infos : Array[@protocol.WorktreeInfo]) -> Array[WorktreeRow] {
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
  Some(WorktreesChanged(worktree_rows(payload.worktrees), workspace~))
}

///|
/// The registry row for a durable session's worktree, if one binds it.
fn worktree_row_for(
  dev : DeviceState,
  workspace : @common.Uri?,
  session : String,
) -> WorktreeRow? {
  guard workspace is Some(workspace) else { return None }
  for group in dev.worktrees {
    guard group.workspace == workspace else { continue }
    for row in group.rows {
      if row.session is Some(bound) && bound == session {
        return Some(row)
      }
    }
  }
  None
}

///|
/// The worktree a durable session runs in — the sidebar glyph's data source.
fn worktree_name_for(
  dev : DeviceState,
  workspace : @common.Uri?,
  session : String,
) -> String? {
  worktree_row_for(dev, workspace, session).map(row => row.name)
}

///|
/// The active placement of a conversation inside its registered project.
/// `None` means that workspace's registry has not loaded on this connection,
/// so callers must refuse workspace-scoped actions rather than guessing the
/// project root. A locally-created conversation's provisional worktree name
/// is already enough to identify its group. Once loaded, an absent row means
/// `WorkspaceRoot`; a retained row whose checkout is gone stays
/// `MissingWorktree` until the user explicitly rebuilds it.
fn Model::checkout_placement(
  self : Model,
  conv : Conversation,
) -> @interop.CheckoutPlacement? {
  guard conv.workspace is Some(_) else { return Some(@interop.WorkspaceRoot) }
  let provisional = conv.worktree.map(name => @interop.Worktree(name~))
  guard self.device_state(conv.device) is Some(dev) else { return provisional }
  let workspace = conv.workspace
  guard workspace is Some(root) &&
    dev.worktrees.iter().any(group => group.workspace == root) else {
    return provisional
  }
  guard worktree_row_for(dev, workspace, conv.session_id) is Some(row) else {
    return Some(@interop.WorkspaceRoot)
  }
  if row.present {
    Some(@interop.Worktree(name=row.name))
  } else {
    Some(@interop.MissingWorktree(name=row.name))
  }
}

///|
fn DeviceState::with_worktrees(
  self : DeviceState,
  workspace : @common.Uri,
  rows : Array[WorktreeRow],
  generation~ : Int,
) -> DeviceState {
  let groups = self.worktrees.filter(group => group.workspace != workspace)
  groups.push({ workspace, rows, generation })
  { ..self, worktrees: groups }
}

///|
/// The token one workspace's rows were last applied under; a reply carrying
/// an older token is stale for that workspace alone.
fn DeviceState::worktree_generation(
  self : DeviceState,
  workspace : @common.Uri,
) -> Int {
  for group in self.worktrees {
    if group.workspace == workspace {
      return group.generation
    }
  }
  -1
}

///|
/// Whether the next submit should run the create-then-start chain: the
/// composer chose worktree mode, nothing is bound yet, and the
/// conversation has no durable history. Local overlay notices — exactly
/// what a rejected setup attempt leaves behind — deliberately do not
/// count: the retry after a failed create must re-enter the chain, never
/// silently fall back to the workspace root.
fn Conversation::wants_fresh_worktree(self : Conversation) -> Bool {
  self.worktree_mode && self.worktree is None && self.messages.length() == 0
}

///|
/// The composer's launch-mode chip: visible while the conversation can
/// still choose (a workspace conversation that has not begun), fixed to
/// the worktree's name once the chain has bound one.
fn worktree_mode_chip(
  dispatch : @cmd.Emit[Msg],
  conv : Conversation,
) -> @html.Html? {
  // Durable emptiness, not `has_begun`: a rejected setup attempt leaves a
  // local overlay notice, and hiding the toggle then would lock the user
  // into retrying the failing create with no way back to Local.
  guard conv.workspace is Some(_) && conv.messages.length() == 0 else {
    return None
  }
  if conv.worktree is Some(name) {
    return Some(
      @html.span(
        class="composer-worktree on",
        title="This chat runs in worktree \{name}",
        [icon(icon_worktree), @html.span(name)],
      ),
    )
  }
  let (class, label, title) = if conv.worktree_mode {
    (
      "composer-worktree on", "Worktree", "First prompt creates a git worktree and runs there — click for local",
    )
  } else {
    (
      "composer-worktree", "Local", "Runs in the workspace itself — click to run in a fresh git worktree",
    )
  }
  Some(
    @html.button(
      class~,
      type_="button",
      title~,
      on_click=dispatch(ToggleWorktreeMode),
      [icon(icon_worktree), @html.span(label)],
    ),
  )
}

///|
/// The banner above the composer when this conversation's worktree checkout
/// is missing. The host refuses every workspace operation in that state, so
/// the banner offers the two safe exits: rebuild the original checkout, or
/// archive the conversation. Committed work stays on the surviving branch.
fn missing_worktree_notice(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  name : String,
) -> @html.Html {
  @html.div(class="composer-notice", [
    @html.span(
      class="composer-notice-text",
      "Worktree \{name} has no checkout. Rebuild it to continue; commits on its branch are safe.",
    ),
    @html.button(
      class="composer-notice-btn",
      type_="button",
      title="Check the branch out again at .worktrees/\{name}",
      on_click=dispatch(RepairWorktree),
      "Rebuild it",
    ),
    @html.button(
      class="composer-notice-btn",
      type_="button",
      title="Archive this chat without rebuilding its worktree",
      on_click=dispatch(ArchiveSession(channel, session)),
      "Archive chat",
    ),
  ])
}

///|
/// The archive-discard dialog (the `update_confirm_modal` shape): archiving
/// takes the worktree with the conversation, and this is the one moment
/// uncommitted changes can be lost — only behind this explicit confirm.
fn archive_discard_modal(
  dispatch : @cmd.Emit[Msg],
  confirm : ArchiveConfirm,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelArchiveDiscard), [
    @html.div(class="modal", [
      @html.div(class="modal-title", "Archive this chat?"),
      @html.div(
        class="modal-body",
        "\{confirm.message}. Committed work stays on the worktree's branch; only uncommitted changes are discarded.",
      ),
      @html.div(class="modal-actions", [
        @html.button(on_click=dispatch(CancelArchiveDiscard), "Keep working"),
        @html.button(
          class="primary",
          on_click=dispatch(ConfirmArchiveDiscard),
          "Discard and archive",
        ),
      ]),
    ]),
  ])
}

// Tests for the worktree flow's pure pieces: the notification decoder and
// the update handlers that flag the launch mode, bind the chain's created
// environment, adopt registry rows, and stage removals.

///|
fn test_worktree_rows() -> Array[WorktreeRow] {
  [{ name: "wt", session: Some("desktop-wt"), present: true }]
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
  guard bridge_msg(@interop.ChannelId::Local, notification)
    is Some(FromDevice(_, WorktreesChanged(rows, workspace~))) else {
    fail("expected a worktree change")
  }
  assert_eq(workspace.path, "/proj")
  inspect(rows.length(), content="1")
  inspect(rows[0].name, content="wt")
  assert_eq(rows[0].session, Some("s1"))
  assert_true(rows[0].present)
  // A broadcast without its workspace is structurally unusable.
  assert_true(
    @protocol.Notification::from_wire("worktree.changed", { "worktrees": [] })
    is None,
  )
}

///|
test "proton subscribes to the worktree commit notification" {
  assert_true(proton_event_methods().contains(WorktreeChanged))
}

///|
test "the launch mode toggles only before the conversation begins" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(workspace),
  })
  let (_, on) = update(dispatch, ToggleWorktreeMode, model)
  assert_true(on.active().worktree_mode)
  let (_, off) = update(dispatch, ToggleWorktreeMode, on)
  assert_false(off.active().worktree_mode)
  // A begun conversation keeps its environment; the toggle is inert.
  let begun = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(workspace),
    messages: [{ kind: User, content: "hi" }],
  })
  let (_, still) = update(dispatch, ToggleWorktreeMode, begun)
  assert_false(still.active().worktree_mode)
  // A scratch conversation has no workspace to fork from.
  let (_, scratch) = update(dispatch, ToggleWorktreeMode, test_model())
  assert_false(scratch.active().worktree_mode)
}

///|
test "worktree created binds the composing conversation" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(workspace),
    worktree_mode: true,
  })
  let (_, bound) = update_dev(
    dispatch,
    WorktreeCreated(workspace~, name="wt-1", session="desktop-test"),
    model,
  )
  assert_true(bound.active().worktree is Some("wt-1"))
  assert_false(bound.active().worktree_mode)
  // A created notice for an unknown session changes nothing.
  let (_, unknown) = update_dev(
    dispatch,
    WorktreeCreated(workspace~, name="wt-2", session="desktop-else"),
    bound,
  )
  assert_true(unknown.active().worktree is Some("wt-1"))
}

///|
test "a missing checkout stays bound while rebuild and archive remain reachable" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let bound = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(workspace),
      worktree: Some("wt"),
    })
    .with_dev(dev => {
      ..dev,
      workspaces: [workspace],
      worktrees: [
        {
          workspace,
          rows: [{ name: "wt", session: Some("desktop-test"), present: true }],
          generation: 1,
        },
      ],
    })
  assert_true(
    bound.checkout_placement(bound.active())
    is Some(@interop.Worktree(name="wt")),
  )
  // The retained row carries `present: false`, whether an external deletion
  // or archive removed the checkout.
  let (_, gone) = update_dev(
    dispatch,
    WorktreesChanged(
      [{ name: "wt", session: Some("desktop-test"), present: false }],
      workspace~,
    ),
    bound,
  )
  assert_true(
    gone.checkout_placement(gone.active())
    is Some(@interop.MissingWorktree(name="wt")),
  )
  assert_true(
    terminal_ctx(gone).checkout is Some(@interop.MissingWorktree(name="wt")),
  )
  // Session-list reconstruction does not itself carry the worktree name; the
  // retained registry row still keeps its terminal group away from main.
  let resumed = gone.replace_conversation({ ..gone.active(), worktree: None })
  assert_true(
    terminal_ctx(resumed).checkout is Some(@interop.MissingWorktree(name="wt")),
  )
  // The binding is NOT dropped: the conversation must never silently read as
  // a plain workspace chat.
  assert_true(gone.active().worktree is Some("wt"))
  // Repair does not mutate optimistically: the registry broadcast is the
  // authority for the restored checkout.
  let (_, repairing) = update(dispatch, RepairWorktree, gone)
  assert_true(
    repairing.checkout_placement(repairing.active())
    is Some(@interop.MissingWorktree(name="wt")),
  )
  assert_true(repairing.active().worktree is Some("wt"))
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
    archiving.checkout_placement(archiving.active())
    is Some(@interop.MissingWorktree(name="wt")),
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
  assert_true(noop.active().worktree is Some("wt"))
  assert_true(
    noop.checkout_placement(noop.active()) is Some(@interop.Worktree(name="wt")),
  )
}

///|
test "a restored workspace conversation waits for placement before using root" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let unresolved = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(workspace),
    // `session.list` reconstructs durable conversations without a worktree
    // hint. Absence is not proof that this one belongs to the project root.
    worktree: None,
  })
  assert_true(unresolved.checkout_placement(unresolved.active()) is None)
  assert_true(terminal_ctx(unresolved).checkout is None)
  assert_eq(file_ctx(unresolved).owner.session, "")
  let generation = unresolved.dev().worktrees_request_generation
  let (_, retrying) = update(dispatch, RetryWorktreePlacement, unresolved)
  assert_eq(retrying.dev().worktrees_request_generation, generation + 1)
  assert_true(retrying.checkout_placement(retrying.active()) is None)
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
    loaded.checkout_placement(loaded.active()) is Some(@interop.WorkspaceRoot),
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
      workspace: Some(workspace),
      worktree_mode: true,
      task: "go",
    })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ workspace, rows: [], generation: 1 }],
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
    worktree_name_for(applied.dev(), Some(workspace), "desktop-wt")
    is Some("wt"),
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
    worktree_name_for(stale.dev(), Some(workspace), "desktop-wt") is Some("wt"),
  )
}

///|
test "a worktree list failure stays unresolved and ignores stale errors" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let unresolved = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(workspace),
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
  assert_true(failed.checkout_placement(failed.active()) is None)
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
    stale_failure.checkout_placement(stale_failure.active())
    is Some(@interop.WorkspaceRoot),
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
    workspaces: [a, b],
    worktrees_request_generation: 1,
  })
  let (_, changed) = update_dev(
    dispatch,
    WorktreesChanged(
      [{ name: "wt-a", session: Some("s-a"), present: true }],
      workspace=a,
    ),
    model,
  )
  let (_, both) = update_dev(
    dispatch,
    WorktreesLoaded(
      [{ name: "wt-b", session: Some("s-b"), present: true }],
      workspace=b,
      connection_generation=0,
      request_generation=1,
    ),
    changed,
  )
  assert_true(worktree_name_for(both.dev(), Some(a), "s-a") is Some("wt-a"))
  assert_true(worktree_name_for(both.dev(), Some(b), "s-b") is Some("wt-b"))
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
  assert_true(worktree_name_for(fenced.dev(), Some(a), "s-a") is Some("wt-a"))
}

///|
test "a worktree commit broadcast supersedes lists and unbinds removed names" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let cwd = @interop.ChannelId::Local.test_resource("/proj/.worktrees/wt")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(workspace),
      worktree: Some("wt"),
      cwd: Some(cwd),
      branch: Some("openseek/wt"),
    })
    .with_dev(dev => {
      ..dev,
      workspaces: [workspace],
      worktrees: [{ workspace, rows: test_worktree_rows(), generation: 1 }],
      worktrees_request_generation: 1,
    })
  let (_, changed) = update_dev(
    dispatch,
    WorktreesChanged([], workspace~),
    model,
  )
  inspect(changed.dev().worktrees_request_generation, content="2")
  assert_true(
    worktree_name_for(changed.dev(), Some(workspace), "desktop-wt") is None,
  )
  // The removed worktree's conversation is a plain workspace conversation
  // now — exactly what the host's registry prune did to the mapping — and
  // every placement derived from the dead checkout (cwd for open/launch,
  // the composer's branch chip) went with it.
  assert_true(changed.active().worktree is None)
  assert_true(changed.active().cwd is None)
  assert_true(changed.active().branch is None)
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
  assert_true(
    worktree_name_for(stale.dev(), Some(workspace), "desktop-wt") is None,
  )
}

///|
test "a failed worktree setup keeps the retry eligible" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(workspace),
      worktree_mode: true,
      task: "go",
    })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ workspace, rows: [], generation: 1 }],
    })
  let worktrees_generation = model.dev().worktrees_request_generation
  let (_, sent) = update(dispatch, Send, model)
  guard sent.active().input_ledger is [entry] else {
    fail("expected the submission in the ledger")
  }
  let (_, rejected) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id=entry.submission_id,
      message="worktree setup failed: boom",
    ),
    sent,
  )
  // The rejection leaves a local overlay notice — which must NOT disqualify
  // the retry: the next submit re-enters the create-then-start chain
  // instead of silently running in the workspace root.
  assert_true(rejected.active().overlay.length() > 0)
  assert_true(rejected.active().worktree_mode)
  assert_true(rejected.active().wants_fresh_worktree())
  // Every rejected workspace start refreshes the registry. Besides keeping a
  // failed setup honest, this is how an externally deleted checkout becomes
  // the typed missing state without restarting the app.
  assert_eq(
    rejected.dev().worktrees_request_generation,
    worktrees_generation + 1,
  )
  // And the escape hatch stays open: the toggle still switches the chat
  // back to Local despite the overlay notice.
  let (_, switched) = update(dispatch, ToggleWorktreeMode, rejected)
  assert_false(switched.active().worktree_mode)
}

///|
test "a remote removal closes this client's discard dialog" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(workspace),
      worktree: Some("wt"),
    })
    .with_dev(dev => {
      ..dev,
      workspaces: [workspace],
      worktrees: [{ workspace, rows: test_worktree_rows(), generation: 1 }],
    })
  let (_, staged) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", message="dirty"),
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
  assert_true(swept.active().worktree is None)
}

///|
test "a dirty archive stages the discard dialog and confirm retries forced" {
  let dispatch = test_dispatch()
  // The host's refusal stages the dialog with its own message.
  let (_, staged) = update_dev(
    dispatch,
    ArchiveNeedsForce(
      session="desktop-test",
      message="worktree wt-1 has uncommitted changes; archiving discards them",
    ),
    test_model(),
  )
  guard staged.archive_confirm is Some(confirm) else {
    fail("refusal staged no dialog")
  }
  inspect(confirm.session, content="desktop-test")
  assert_true(confirm.message.contains("wt-1"))
  // Cancel stands down without any request.
  let (_, cancelled) = update(dispatch, CancelArchiveDiscard, staged)
  assert_true(cancelled.archive_confirm is None)
  // Confirm fires the forced retry (the archive generations advance, as on
  // a plain archive click) and closes the dialog.
  let (_, restaged) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", message="dirty"),
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
    "deepseek-v4-pro",
    "1000",
    "desktop-wt",
    "sub-1",
    workspace=Some(workspace),
  )
  // The typed wire shape has no worktree field at all; the workspace hint
  // is the only placement the start carries.
  assert_true(
    payload.to_json() is Object(fields) && fields.get("worktree") is None,
  )
  assert_eq(payload.workspace, Some("/proj"))
}
