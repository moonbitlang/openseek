// Messages emitted by one connected device channel.

///|
/// One device channel's messages — its connection lifecycle, its
/// notification stream, and every generation-fenced reply. The arms are
/// the same handlers `update_msg` held before the channel split; `channel`
/// names the device the message came from.
fn update_device_msg(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  msg : DeviceMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  match msg {
    InstalledSkillsLoaded(items) =>
      if channel == model.focused {
        (@cmd.none, { ..model, installed_skills: items })
      } else {
        (@cmd.none, model)
      }
    InstalledSkillsFailed(message) =>
      if channel == model.focused {
        (@cmd.none, { ..model, skills_notice: message })
      } else {
        (@cmd.none, model)
      }
    SkillsChanged =>
      if channel == model.focused {
        (fetch_installed_skills(dispatch, channel), model)
      } else {
        // `installed_skills` is the focused host's mirror. A background
        // device is refreshed when focus moves to it.
        (@cmd.none, model)
      }
    BridgeReady => {
      let connection_generation = dev.connection_generation + 1
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      let workspaces_request_generation = dev.workspaces_request_generation + 1
      // Capture the exact per-session lifecycle frontier before issuing the
      // unversioned runs snapshot. A live Started or Finished received before
      // its reply then wins over both stale positive rows and stale absence.
      let run_frontier = model.run_snapshot_frontier(channel)
      let commands = [
        fetch_sessions(
          dispatch, channel, connection_generation, sessions_request_generation,
        ),
        // In-flight runs, so a page that joined (or reconnected) mid-run
        // learns each live run's identity — the resync half of the
        // protocol's reconnect story (docs/remote-protocol.md).
        fetch_runs(dispatch, channel, run_frontier, connection_generation),
        fetch_archived(
          dispatch, channel, connection_generation, archived_request_generation,
        ),
        fetch_workspaces(
          dispatch, channel, connection_generation, workspaces_request_generation,
        ),
      ]
      // The focused-scoped half: the host-settings mirror and installed
      // skills (they feed the composer's `$` completion, so
      // they load on connect rather than when the Skills page opens) follow
      // the device the UI acts on — always this one while the app runs a
      // single channel.
      if channel == model.focused {
        commands.push(
          fetch_host_settings(dispatch, channel, connection_generation),
        )
        // Legacy client-stored engine settings: the desktop migrates them
        // up to the host, a browser purges them (see `LegacySettingsRead`).
        commands.push(read_legacy_engine_settings(dispatch))
        commands.push(fetch_installed_skills(dispatch, channel))
        // Self-update and the relay sign-in are the desktop window's alone
        // (see `is_desktop`); a browser never checks, so neither UI
        // materializes there. The startup update check rides here: settings
        // (the update channel) load synchronously at Init, so they are in by
        // bridge time.
        if model.is_desktop {
          commands.push(model.fetch_app_info(dispatch))
          commands.push(
            check_for_updates(
              dispatch,
              model.api_provider.update_channel(),
              explicit=false,
            ),
          )
          commands.push(fetch_remote_status(dispatch))
        }
      }
      // Delta streams are not replayable across a connection boundary; keep
      // none of the pre-gap fragment, or the first post-gap delta would splice
      // onto stale text. Compaction has no wire resync in this protocol: an
      // local queued/requested/in-flight marker is released here so a missed
      // terminal event cannot disable Send forever. Any receipt still pending
      // at this boundary becomes truthful `delivery unconfirmed` state; an
      // exact late id can still retract it. If the host still compacts, its
      // next prompt rejection is a transient, visible local failure.
      let reconnect_snapshot_generation = model.transcript_request_generation +
        1
      let conversations = model.conversations.map(conv => {
        if conv.device == channel {
          {
            ..conv
            .clear_streams()
            .mark_awaiting_inputs_unconfirmed(
              snapshot_generation=reconnect_snapshot_generation,
            ),
            compaction: NotCompacting,
          }
        } else {
          conv
        }
      })
      let model = model.replace_device({
        ..dev,
        bridge: Connected,
        reconnect_failures: 0,
        connection_generation,
        sessions_request_generation,
        archived_request_generation,
        workspaces_request_generation,
        archive_overrides: [],
        // Worktree notifications are not replayed across a connection gap.
        // Keep every workspace blocked until this connection returns a fresh
        // list (or a newer `worktree.changed` broadcast) instead of trusting
        // placement cached before the disconnect.
        worktrees: [],
      })
      // Replies from writes issued on the dead bridge carry their captured
      // generation and are ignored below. The new host may have restarted
      // its in-memory settings revision, so its first authoritative status
      // starts a fresh monotonic round. Focused-scoped, like the fetches
      // that repopulate the mirror.
      let model = if channel == model.focused {
        { ..model.clear_host_settings(), conversations, }
      } else {
        { ..model, conversations, }
      }
      // The resync's other half: whatever landed while this client was away
      // (another client's prompts, items a still-running turn completed, a
      // finished run's verdict) exists only in the store. Reads happen
      // exactly where this client was absent: the conversation on screen
      // re-reads now, every other one re-reads when opened (`OpenSession`
      // always reloads). An in-flight user load keeps right of way.
      let model = if channel == model.focused {
        match model.find_conversation(channel, model.active_session) {
          Some(conv) if (
              model.can_reload_transcript(conv) || conv.sync is Reloading(..)
            ) &&
            model.loading_conversation is None => {
            // A real engine pump can restart while the transport remains
            // open. If an older read is already in flight, it may carry a
            // pre-ready cut, so require one follow-up generation rather than
            // treating the old single-flight request as sufficient.
            let (model, generation) = model.ensure_transcript_reload_after_current(
              conv,
            )
            if generation is Some(generation) {
              commands.push(
                session_snapshot_command(
                  dispatch,
                  channel,
                  model,
                  conv.session_id,
                  generation,
                  false,
                ),
              )
            }
            model
          }
          _ => model
        }
      } else {
        model
      }
      guard channel == model.focused else {
        return (@cmd.batch(commands), model)
      }
      (
        @cmd.batch(commands),
        {
          ..model
          // The host this bridge just (re)connected to may be a fresh
          // process with no filesystem watcher; forgetting what was watched
          // makes the post-dispatch panel sync re-issue `fs.watch` instead
          // of reading the stale record as "already placed".
          ,
          file_panel: { ..model.file_panel, watching: None },
          // An unusable endpoint routes straight to Settings — the composer
          // could do nothing anyway.
          screen: if model.api_ready() {
            model.screen
          } else {
            Settings
          },
        },
      )
    }
    BridgeUnavailable(message) => {
      let (terminal_cmd, terminal_panel) = @terminal.disconnect(
        model.terminal_panel,
        channel,
      )
      (
        terminal_cmd,
        {
          ..model.replace_device({ ..dev, bridge: BridgeLost(message) }),
          terminal_panel,
        },
      )
    }
    ChannelDown(websocket_epoch~) => {
      // A close callback may already be queued when sign-out retires a
      // device. If the same relay id is later re-added, it owns a new epoch
      // and must not inherit the retired connection's failure or timer.
      guard websocket_epoch == dev.websocket_epoch else {
        return (@cmd.none, model)
      }
      // Count the loss and schedule the next attempt. Because the attempt
      // comes back through this function, a removed or re-added device fails
      // the state/epoch guards and its old loop simply ends.
      let failures = dev.reconnect_failures + 1
      let bridge = if failures == WsLostAfter {
        BridgeLost(
          "Can't reach OpenSeek. Make sure OpenSeek is running, then reopen this page.",
        )
      } else {
        dev.bridge
      }
      // The whole HostConnection owns the PTY task group. Its first socket
      // loss therefore invalidates every terminal id immediately, even
      // though the rest of the UI tolerates two short reconnect failures
      // before presenting BridgeLost.
      let (terminal_cmd, terminal_panel) = @terminal.disconnect(
        model.terminal_panel,
        channel,
      )
      (
        @cmd.batch([
          @cmd.delay(
            dispatch(FromDevice(channel, ReconnectDue(websocket_epoch~))),
            reconnect_delay(failures),
          ),
          terminal_cmd,
        ]),
        {
          ..model.replace_device({ ..dev, bridge, reconnect_failures: failures }),
          terminal_panel,
        },
      )
    }
    ReconnectDue(websocket_epoch~) => {
      guard websocket_epoch == dev.websocket_epoch else {
        return (@cmd.none, model)
      }
      guard channel is Remote(device) else { return (@cmd.none, model) }
      (connect_ws(dispatch, device, websocket_epoch), model)
    }
    FilePanel(msg) => {
      // The file panel serves the focused conversation; a background
      // device's fs/diagnostics noise must not re-stat or redraw it.
      guard channel == model.focused else { return (@cmd.none, model) }
      update_msg(dispatch, FileEditor(msg), model)
    }
    HostSettingsLoaded(settings, connection_generation~) => {
      guard connection_generation is None ||
        connection_generation == Some(dev.connection_generation) else {
        return (@cmd.none, model)
      }
      // The settings mirror is the focused host's. A generation-carrying
      // reply is only ever requested for the focused channel, but the
      // `settings.changed` broadcast (generation None) arrives from every
      // connected device — a background device's edit must not clobber the
      // form. A focus switch refetches, so nothing is lost.
      guard channel == model.focused else { return (@cmd.none, model) }
      if settings.revision < model.host_settings_revision {
        (@cmd.none, model)
      } else if model.settings_saves > 0 {
        (@cmd.none, model.defer_host_settings(settings))
      } else {
        (@cmd.none, model.apply_host_settings(settings))
      }
    }
    HostSettingsApplied(settings, connection_generation~, cleans_legacy~) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      // A save issued on the old focus may settle after the user switches
      // devices. Its revision and localStorage cleanup belong to that old
      // host and must not alter the newly focused host's mirror.
      guard channel == model.focused else { return (@cmd.none, model) }
      let next = {
        ..model,
        settings_saves: if model.settings_saves > 0 {
          model.settings_saves - 1
        } else {
          0
        },
      }.defer_host_settings(settings)
      // The migration's secrets leave localStorage only once the host
      // confirmed it holds them.
      let cleanup = if cleans_legacy && next.legacy_cleanup_pending {
        clear_legacy_engine_settings()
      } else {
        @cmd.none
      }
      let next = if cleans_legacy {
        { ..next, legacy_cleanup_pending: false }
      } else {
        next
      }
      (
        cleanup,
        if next.settings_saves > 0 {
          next
        } else {
          next.flush_host_settings()
        },
      )
    }
    HostSettingsSaveFailed(message, connection_generation~, cleans_legacy~) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      guard channel == model.focused else { return (@cmd.none, model) }
      let next = {
        ..model,
        settings_saves: if model.settings_saves > 0 {
          model.settings_saves - 1
        } else {
          0
        },
        // The push never landed; the legacy values stay in localStorage for
        // the next launch's retry.
        legacy_cleanup_pending: if cleans_legacy {
          false
        } else {
          model.legacy_cleanup_pending
        },
      }
      let next = if next.settings_saves == 0 {
        next.flush_host_settings()
      } else {
        next
      }
      let (notice, notified) = next.notify_error(
        dispatch,
        "Saving settings failed: \{message}",
      )
      let commands = [notice]
      if next.settings_saves == 0 {
        // No successful reply may follow to correct the optimistic form.
        // An authoritative get (same-revision statuses are accepted) restores
        // host truth after a definite or ambiguous write failure.
        commands.push(
          fetch_host_settings(dispatch, channel, dev.connection_generation),
        )
      }
      (@cmd.batch(commands), notified)
    }
    SteerUndelivered(session~, submission_id~, text~, run_id~) =>
      // The response path failed, but the host may have accepted the steer;
      // keep its exact-id ledger entry and let only a late id-bearing receipt
      // retract the truthful unconfirmed notice.
      if model.find_conversation(channel, session) is Some(conv) {
        let changed = conv.input_ledger
          .iter()
          .any(input => {
            input.submission_id == submission_id &&
            input.kind is SteerInput &&
            input.run_id is Some(owner) &&
            owner == run_id &&
            input.state is Awaiting
          })
        let (next, _) = if changed {
          conv.mark_submission_unconfirmed(
            submission_id,
            steer_unconfirmed_notice(text),
            false,
          )
        } else {
          (conv, false)
        }
        if !changed {
          (@cmd.none, model)
        } else {
          (
            scroll_if_active(model, channel, session),
            model.replace_conversation(next),
          )
        }
      } else {
        (@cmd.none, model)
      }
    SteerRejected(session~, submission_id~, text~, run_id~) =>
      // A concrete `steered:false` cannot later commit. Retire the ledger entry
      // and restore its exact draft; a later same-text submission is unrelated.
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, removed) = conv.reject_submission(
          submission_id,
          SteerInput,
          Some(run_id),
          steer_dropped_notice(text),
        )
        if removed {
          (
            scroll_if_active(model, channel, session),
            model.replace_conversation(next),
          )
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
      }
    SessionsLoaded(items, connection_generation~, request_generation~) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.sessions_request_generation else {
        return (@cmd.none, model)
      }
      // Whole-list replies have no store revision. An identity notification
      // delivered after this request was issued wins for its session: remove
      // newly archived rows and retain newly unarchived rows from the current
      // model when the stale reply omitted them.
      let items = items.filter(item => {
        !(dev.archive_override(item.id) is Some(true))
      })
      for fact in dev.archive_overrides {
        if !fact.archived && !items.iter().any(item => item.id == fact.session) {
          for current in dev.sessions {
            if current.id == fact.session {
              items.push(current)
            }
          }
        }
      }
      // A commit or Started broadcast can materialize a conversation before
      // session.list tells this page which durable store owns it. Reconcile
      // that provisional placement from the list before any later send: an
      // empty workspace hint here would otherwise fork the same session into
      // the default store.
      let conversations = model.conversations.map(conv => {
        if conv.device == channel {
          let mut workspace = conv.workspace
          for item in items {
            if item.id == conv.session_id {
              workspace = item.workspace
            }
          }
          { ..conv, workspace, }
        } else {
          conv
        }
      })
      let mut active_workspace = dev.active_workspace
      if channel == model.focused {
        for item in items {
          if item.id == model.active_session {
            active_workspace = item.workspace
          }
        }
      }
      let mut next = {
        ..model.replace_device({ ..dev, sessions: items, active_workspace }),
        conversations,
      }
      let commands : Array[@cmd.Cmd] = []
      // A start may have been accepted just before the connection vanished,
      // while the first BridgeReady load raced persistence and returned empty.
      // The session list is later durable proof that a record now exists: use
      // that edge to retry exactly unresolved start recoveries.
      for conv in next.conversations {
        if conv.device == channel &&
          conv.has_recovering_initial() &&
          !(conv.sync is Reloading(..)) &&
          items.iter().any(item => item.id == conv.session_id) {
          let (updated, generation) = next.begin_transcript_reload(conv)
          next = updated
          if generation is Some(generation) {
            commands.push(
              session_snapshot_command(
                dispatch,
                channel,
                next,
                conv.session_id,
                generation,
                false,
              ),
            )
          }
        }
      }
      (@cmd.batch(commands), next)
    }
    WorkspacesLoaded(paths, connection_generation~, request_generation~) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.workspaces_request_generation else {
        return (@cmd.none, model)
      }
      // The registry snapshot is also the authority for what this page may
      // keep open. `adopt_workspaces` drops conversations from detached
      // stores; their durable records remain on disk and return through the
      // next session list after the workspace is attached again.
      adopt_workspaces(dispatch, channel, model, paths)
    }
    WorkspacesChanged(paths) => {
      // The post-commit broadcast is newer than every list request issued so
      // far. Advance the token before applying it, so an older list reply can
      // never roll any client back after this canonical mutation order.
      let next = model.replace_device({
        ..dev,
        workspaces_request_generation: dev.workspaces_request_generation + 1,
      })
      adopt_workspaces(dispatch, channel, next, paths)
    }
    WorkspaceFailed(message) =>
      model.notify_error(dispatch, "Workspace error: \{message}")
    WorktreesLoaded(
      rows,
      workspace~,
      connection_generation~,
      request_generation~
    ) => {
      // The staleness fence is per workspace: this reply is stale only when
      // THIS workspace's rows were already applied under a newer token — a
      // broadcast for a sibling workspace must not discard it.
      guard connection_generation == dev.connection_generation &&
        request_generation > dev.worktree_generation(workspace) else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_device(
          dev.with_worktrees(workspace, rows, generation=request_generation),
        ),
      )
    }
    WorktreesFailed(
      workspace~,
      connection_generation~,
      request_generation~,
      message~
    ) => {
      // A later snapshot or broadcast for this workspace makes an older
      // failure irrelevant, just as a dead connection's rejection must not
      // pop over the newly connected UI.
      guard connection_generation == dev.connection_generation &&
        request_generation > dev.worktree_generation(workspace) else {
        return (@cmd.none, model)
      }
      model.notify_error(
        dispatch,
        "Worktree list unavailable for \{workspace.path}: \{message}",
      )
    }
    WorktreesChanged(rows, workspace~) => {
      // The post-commit broadcast is newer than every list request issued so
      // far; advance the mint and stamp this workspace's rows with the new
      // token so an older reply for it can never roll the broadcast back.
      let worktrees_request_generation = dev.worktrees_request_generation + 1
      let next = model.replace_device({
        ..dev.with_worktrees(
          workspace,
          rows,
          generation=worktrees_request_generation,
        ),
        worktrees_request_generation,
      })
      // Every conversation this broadcast unbinds is unbound at the same
      // instant, so one spent request number fences all of their probes.
      let (fence, next) = next.mint_git_request()
      // Only an actual registry-row removal unbinds its conversations. Archive
      // keeps the row with `present: false`, so it passes through unchanged and
      // later Unarchive still surfaces Repair. Stand down any staged confirm
      // only when the placement itself disappeared.
      let conversations = next.conversations.map(conv => {
        if conv.device == channel &&
          conv.worktree is Some(name) &&
          conv.workspace == Some(workspace) &&
          !rows.iter().any(row => row.name == name) {
          // The checkout is gone, so every placement derived from it goes
          // too: a kept cwd would aim OpenFile/LaunchApp at a deleted
          // directory and the composer would keep showing the dead branch,
          // its uncommitted lines, and its pull request. All re-derive from
          // the host on the next run or open — and `forget_git` retires the
          // probes already in flight, which would otherwise answer for the
          // deleted directory and put every one of those fields back.
          { ..conv.forget_git(fence~), worktree: None, cwd: None }
        } else {
          conv
        }
      })
      // An open discard dialog whose mapping just disappeared (a protocol
      // client explicitly removed the worktree) must close too:
      // confirming it later would fire a stale forced archive.
      let archive_confirm = match next.archive_confirm {
        Some(confirm) if confirm.channel == channel &&
          next.find_conversation(channel, confirm.session) is Some(conv) &&
          conv.workspace == Some(workspace) &&
          !rows.iter().any(row => row.session == Some(confirm.session)) => None
        other => other
      }
      (@cmd.none, { ..next, conversations, archive_confirm })
    }
    WorktreeCreated(workspace~, name~, session~) => {
      // The chain's checkout exists: bind the composing conversation, so
      // the chip shows and a retried submit reuses the same environment.
      guard model.find_conversation(channel, session) is Some(conv) &&
        conv.workspace == Some(workspace) else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_conversation({
          ..conv,
          worktree: Some(name),
          worktree_mode: false,
        }),
      )
    }
    ArchiveNeedsForce(session~, refusal~) =>
      // The host refused to archive over the worktree's uncommitted
      // changes; stage the discard-confirmation dialog, whose confirm
      // retries with force.
      (
        @cmd.none,
        { ..model, archive_confirm: Some({ channel, session, refusal }) },
      )
    ArchivedLoaded(
      items,
      connection_generation~,
      request_generation~,
      fresh_session~
    ) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.archived_request_generation else {
        return (@cmd.none, model)
      }
      // A newer unarchive notification wins over an older whole-list reply;
      // a newer archive notification is supplemented from the current list
      // when that reply predates the move.
      let items = items.filter(item => {
        !(dev.archive_override(item.id) is Some(false))
      })
      for fact in dev.archive_overrides {
        if fact.archived && !items.iter().any(item => item.id == fact.session) {
          for current in dev.archived {
            if current.id == fact.session {
              items.push(current)
            }
          }
        }
      }
      // An archive mutation response can beat its session.changed callback.
      // Treat a newly observed archived row as a local tombstone immediately,
      // so a stale live-list reply cannot reopen it in that delivery gap.
      let mut next = model
      for item in items {
        if next.archive_override(channel, item.id) is None {
          next = next.with_archive_override(channel, item.id, true)
        }
      }
      let archived_now = (id : String) => {
        items.iter().any(item => item.id == id)
      }
      // The active conversation lives on the focused channel; another
      // device's archived list must not displace it even when a session id
      // collides across devices.
      if channel == next.focused && archived_now(next.active_session) {
        let mut workspace = next.session_workspace(channel, next.active_session)
        for item in items {
          if item.id == next.active_session {
            workspace = item.workspace
          }
        }
        next = replace_archived_active(
          next,
          channel,
          next.active_session,
          fresh_session,
          workspace,
        )
      }
      let conversations = next.conversations.filter(conv => {
        conv.device != channel || !archived_now(conv.session_id)
      })
      guard next.device_state(channel) is Some(ndev) else {
        return (@cmd.none, { ..next, conversations, })
      }
      let sessions = ndev.sessions.filter(item => !archived_now(item.id))
      (
        @cmd.none,
        {
          ..next.replace_device({ ..ndev, archived: items, sessions }),
          conversations,
        },
      )
    }
    ArchiveFailed(message) => {
      // A definitive refusal usually means this page no longer matches the
      // host's stores — the record moved, or its workspace detached while
      // this sidebar still showed it. Re-adopt the registry snapshot (which
      // prunes detached conversations and refreshes the live list) and the
      // archived list, so the state that made the click possible heals
      // instead of failing identically forever.
      let workspaces_request_generation = dev.workspaces_request_generation + 1
      let refresh = fetch_workspaces(
        dispatch,
        channel,
        dev.connection_generation,
        workspaces_request_generation,
      )
      let model = model.replace_device({ ..dev, workspaces_request_generation, })
      let (archived, model) = request_archived_refresh(dispatch, channel, model)
      let (toast, model) = model.notify_error(
        dispatch,
        "Archive failed: \{message}",
      )
      (@cmd.batch([refresh, archived, toast]), model)
    }
    WorktreeFailed(message) =>
      model.notify_error(dispatch, "Worktree error: \{message}")
    SessionsFailed(message) =>
      model.notify_error(dispatch, "Session list unavailable: \{message}")
    // Another client archived or unarchived a conversation. Both sidebar
    // lists are stale, but this identity-bearing fact takes effect for its
    // session immediately and remains authoritative over in-flight replies.
    SessionsChanged(change~, session~, fresh_session~) => {
      let (sessions, model) = request_sessions_refresh(dispatch, channel, model)
      let (archived, model) = request_archived_refresh(dispatch, channel, model)
      let commands = @cmd.batch([sessions, archived])
      guard model.device_state(channel) is Some(dev) else {
        return (commands, model)
      }
      if change == "unarchived" {
        let mut restored : @transcript.SessionListItem? = None
        for item in dev.archived {
          if item.id == session {
            restored = Some(item)
          }
        }
        let archived = dev.archived.filter(item => item.id != session)
        let sessions = dev.sessions.copy()
        if restored is Some(item) &&
          !sessions.iter().any(current => current.id == session) {
          sessions.push(item)
        }
        return (
          commands,
          model
          .replace_device({ ..dev, sessions, archived })
          .with_archive_override(channel, session, false),
        )
      }
      if change != "archived" {
        return (commands, model)
      }
      // Invalidate the live target before either async list reply. Keeping a
      // placeholder archived entry also blocks a late session.event from
      // rematerializing it during this window.
      let workspace = model.session_workspace(channel, session)
      let sessions = dev.sessions.filter(item => item.id != session)
      let conversations = model.conversations.filter(conv => {
        conv.device != channel || conv.session_id != session
      })
      let archived = dev.archived.copy()
      if !archived.iter().any(item => item.id == session) {
        let mut item : @transcript.SessionListItem = {
          id: session,
          title: None,
          workspace,
          workspace_name: "",
        }
        for live in dev.sessions {
          if live.id == session {
            item = live
          }
        }
        archived.push(item)
      }
      let overridden = model.with_archive_override(channel, session, true)
      let overridden = match overridden.device_state(channel) {
        Some(ndev) => overridden.replace_device({ ..ndev, sessions, archived })
        None => overridden
      }
      let next = {
        ..overridden,
        conversations: if channel == model.focused &&
          model.active_session == session {
          model.conversations
        } else {
          conversations
        },
      }
      if channel == model.focused &&
        model.active_session == session &&
        fresh_session is Some(fresh) {
        (
          commands,
          replace_archived_active(next, channel, session, fresh, workspace),
        )
      } else {
        (commands, { ..next, conversations, })
      }
    }
    SessionLoaded(session~, items~, watermark~, event_boundaries~, generation~) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, event_boundaries, generation,
        true,
      )
    SessionRefreshed(
      session~,
      items~,
      watermark~,
      event_boundaries~,
      generation~
    ) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, event_boundaries, generation,
        false,
      )
    SessionLoadFailed(session~, message~, generation~) =>
      retry_session_snapshot(
        dispatch, channel, model, session, generation, true, message,
      )
    SessionRefreshFailed(session~, generation~) =>
      retry_session_snapshot(
        dispatch,
        channel,
        model,
        session,
        generation,
        false,
        "failed to refresh session \{session}",
      )
    SessionCommitted(session~, sequence~, ts~, item~) => {
      // Archiving removes live client state after the hub's ordered final
      // commit. A stale/replayed commit seen after that local fact must not
      // resurrect the archived record as a live hidden conversation.
      let archived = match dev.archive_override(session) {
        Some(value) => value
        None => dev.archived.iter().any(item => item.id == session)
      }
      if archived {
        return (@cmd.none, model)
      }
      let first_commit_unseen = match
        model.find_conversation(channel, session) {
        Some(conv) => !conv.has_seen_durable_sequence(sequence)
        None => true
      }
      let refresh_sessions = sequence == 1 &&
        !dev.sessions.iter().any(item => item.id == session) &&
        first_commit_unseen
      // A short foreign run can commit and finish before either the session
      // list or run resync reaches this page. Materialize hidden client state
      // from the commit itself: sequence 1 projects immediately; a later
      // sequence exposes a gap and follows the normal snapshot recovery path.
      let model = if model.find_conversation(channel, session) is None {
        model.replace_conversation(
          empty_conversation(
            channel,
            session,
            workspace?=model.session_workspace(channel, session),
            model=model
              .remembered_model(channel, session)
              .unwrap_or(model.default_model),
          ),
        )
      } else {
        model
      }
      let (commit_cmd, next) = if model.find_conversation(channel, session)
        is Some(conv) {
        let commit : BufferedCommit = { sequence, ts, item }
        match conv.sync {
          // A read is in flight: buffer — its snapshot's watermark decides
          // whether this commit is already contained once it lands.
          Reloading(..) =>
            (@cmd.none, model.replace_conversation(conv.buffer_commit(commit)))
          // A new commit is also a retry signal after a bounded round stopped.
          ReloadFailed(..) => {
            let (model, generation) = model.begin_transcript_reload(
              conv.buffer_commit(commit),
            )
            if generation is Some(generation) {
              (
                session_snapshot_command(
                  dispatch, channel, model, session, generation, false,
                ),
                model,
              )
            } else {
              (@cmd.none, model)
            }
          }
          Synced =>
            if sequence <= conv.watermark {
              // Old news: the snapshot (or an earlier commit) already
              // carried it. Re-broadcasts are safe by construction.
              (@cmd.none, model)
            } else if sequence == conv.watermark + 1 {
              let (changed, next) = conv.apply_commit(sequence, item, ts?)
              (
                if changed {
                  scroll_if_active(model, channel, session)
                } else {
                  @cmd.none
                },
                model.replace_conversation({ ..next, watermark: sequence }),
              )
            } else {
              // A gap: this client missed a broadcast (kicked as a slow
              // subscriber, a host restart, an external writer). The record
              // is the source of truth — re-read it, buffering from here.
              let (model, generation) = model.begin_transcript_reload(conv)
              guard model.find_conversation(channel, session) is Some(reloading) else {
                return (@cmd.none, model)
              }
              let model = model.replace_conversation(
                reloading.buffer_commit(commit),
              )
              if generation is Some(generation) {
                (
                  session_snapshot_command(
                    dispatch, channel, model, session, generation, false,
                  ),
                  model,
                )
              } else {
                (@cmd.none, model)
              }
            }
        }
      } else {
        (@cmd.none, model)
      }
      // A live Started can overtake the store write and the BridgeReady list
      // request can therefore miss a newly-created session. Sequence one is
      // the first durable proof that the record exists; refresh the list so
      // older hosts without Started.session_root, and clients that learned
      // the commit first, still converge on the store's workspace grouping.
      if refresh_sessions {
        let (sessions, next) = request_sessions_refresh(dispatch, channel, next)
        (@cmd.batch([commit_cmd, sessions]), next)
      } else {
        (commit_cmd, next)
      }
    }
    BranchLoaded(session~, branch~, diffstat~, generation~, base_hint~) => {
      guard model.find_conversation(channel, session) is Some(conv) else {
        return (@cmd.none, model)
      }
      // A probe that is still counting untracked files while a later one has
      // already answered would otherwise put its older branch and totals back
      // on screen, where nothing would correct them until the next refresh.
      guard generation == conv.branch_generation else {
        return (@cmd.none, model)
      }
      let conv = { ..conv, branch, diffstat, diffstat_hint: base_hint }
      // The pull-request lookup rides on the branch answer rather than on the
      // four places that ask for it: whatever refreshes the branch — a run
      // starting, a session opening, a run finishing — is exactly when the
      // branch's pull request can have changed too.
      guard branch is Some(branch) && !branch.is_empty() else {
        // Not a repository any more: an answer about the branch it used to
        // have would only mislead, including one still on its way.
        let (fence, model) = model.mint_git_request()
        return (
          @cmd.none,
          model.replace_conversation(conv.forget_pull_request(fence~)),
        )
      }
      // A lookup already in flight for this same branch is not stacked on —
      // but it is marked stale, because its answer was gathered before this
      // refresh asked for one. Dropping the refresh outright would leave the
      // chip describing the repository as it was when a run started, with
      // nothing scheduled to correct it.
      if conv.pull_request is Some(probe) &&
        probe.probing &&
        probe.branch == branch {
        let pull_request = Some({ ..probe, stale: true })
        return (
          @cmd.none,
          model.replace_conversation({ ..conv, pull_request, }),
        )
      }
      probe_pull_request(dispatch, model, channel, conv, branch)
    }
    PullRequestLoaded(
      session~,
      branch~,
      generation~,
      queried~,
      pull_request~,
      compare_url~
    ) => {
      guard model.find_conversation(channel, session) is Some(conv) else {
        return (@cmd.none, model)
      }
      // Matched by which request this answers, not by branch: a checkout that
      // moves X → Y → X leaves two lookups for X in flight, and if the newer
      // settles first, matching by name would let the older overwrite it.
      guard generation == conv.pull_request_generation else {
        return (@cmd.none, model)
      }
      // Read before the answer overwrites it: whether a refresh landed while
      // this lookup was in flight.
      let stale = conv.pull_request is Some(probe) && probe.stale
      // Labelled with the branch the host actually read from `HEAD`. When the
      // checkout moved mid-flight the two differ, and the answer is filed
      // under what it describes — where `settled_probe` hides it until the
      // branch chip catches up, instead of showing it against this one.
      let settled : PullRequestProbe = {
        branch: queried.unwrap_or(branch),
        probing: false,
        stale: false,
        pull_request,
        compare_url,
      }
      let conv = { ..conv, pull_request: Some(settled) }
      // A refresh arrived while this lookup was in flight: its answer predates
      // that refresh, so run one more against the branch now checked out.
      if stale && conv.branch is Some(current) && !current.is_empty() {
        return probe_pull_request(dispatch, model, channel, conv, current)
      }
      let model = model.replace_conversation(conv)
      // This answer may have named a base nobody knew when the diffstat beside
      // it was measured — the first pull request a session sees, or one that
      // has been retargeted since. Until it is measured again the popover
      // reports a span from the wrong place, which on a stacked pull request
      // is not a rounding error but the whole branch below this one. Measuring
      // again settles the hint, so this asks at most once per base.
      guard conv.settled_probe() is Some(probe) &&
        probe.pull_request is Some(answer) &&
        conv.diffstat_hint != Some(answer.base) else {
        return (@cmd.none, model)
      }
      probe_branch(dispatch, model, channel, session, conv.cwd)
    }
    Started(
      run_id~,
      session~,
      model=selected_model,
      max_steps~,
      cwd~,
      session_root~,
      task~,
      submission_id~
    ) => {
      // A run another client started may reach us with no local conversation
      // for its session (an `agent.runs` resync on a fresh page, or a live
      // start for a session this client never opened): materialize one, so
      // the run is trackable — streamable, cancellable, steerable — from
      // every client, not just the one that sent the prompt. A run this
      // client sent is already `Starting` when its `started` arrives (the
      // send handler flips the phase before the request leaves). Repeating
      // the same open id is idempotent; a distinct id replacing a stale open
      // run is foreign and first settles that old run's transient state.
      let existing = match model.find_conversation(channel, session) {
        Some(conv) => conv
        None =>
          empty_conversation(
            channel,
            session,
            workspace?=model.session_workspace(channel, session),
            // A conversation this page is meeting for the first time takes
            // the tier its run is on — better evidence than the default,
            // and no choice exists yet to contradict it. A remembered choice
            // still outranks it: that is what the user meant to send next,
            // while the run may have been started elsewhere. A conversation
            // the page already holds keeps its own tier — see below.
            model=model
              .remembered_model(channel, session)
              .unwrap_or(selected_model),
          )
      }
      let existing = match dev.workspace_for_session_root(session_root) {
        Some(workspace) => { ..existing, workspace: Some(workspace) }
        None => existing
      }
      let owned = submission_id is Some(id) &&
        existing.has_initial_submission(id)
      let current_start = submission_id is Some(id) &&
        existing.run is Starting(submission_id=current) &&
        current == id
      let same_open = existing.run is Open(run_id=current, ..) &&
        current == run_id
      // A competing Started while an older start request is still in flight
      // does not retire that request's exact receipt path: its late rejection
      // must still be able to restore the draft. An already-open predecessor,
      // by contrast, is conclusively replaced by this lifecycle boundary.
      let can_retire_previous_initial = current_start ||
        !(existing.run is Starting(..))
      // Started establishes exact run ownership, but neither it nor the start
      // response proves the engine persisted its User item. Keep the draft in
      // the ledger until a terminal-backed normal finish proves that append.
      let conv = if owned && submission_id is Some(id) {
        existing.bind_initial_submission_to_run(id, run_id)
      } else {
        existing
      }
      let successor_snapshot_generation = model.transcript_request_generation +
        1
      let (conv, foreign, stale_terminal) = match conv.run {
        Starting(..) if owned && current_start => (conv, false, false)
        Starting(..) =>
          (
            conv.mark_awaiting_inputs_unconfirmed(
              snapshot_generation=successor_snapshot_generation,
            ),
            true,
            false,
          )
        Open(run_id=current, ..) if current == run_id => (conv, false, false)
        Open(run_id=previous_run, ..) =>
          (
            conv
            .clear_streams()
            .mark_awaiting_steers_unconfirmed(
              owner_run_id=previous_run,
              terminal_expected=false,
              terminal_snapshot_generation=successor_snapshot_generation,
            )
            .mark_initial_for_run_unconfirmed(
              previous_run,
              terminal_snapshot_generation=successor_snapshot_generation,
            ),
            true,
            false,
          )
        NoRun(..) if existing.last_run_id is Some(last) && last == run_id =>
          (conv, false, true)
        NoRun(..) => (conv, true, false)
      }
      let conv = if foreign {
        conv.prepare_tail_notices_for_successor(successor_snapshot_generation)
      } else {
        conv
      }
      // Settle and anchor the predecessor before releasing an older prompt's
      // exact-id ownership. BridgeReady may already have made that prompt
      // Unconfirmed; retiring it first would leave its notice fixed ahead of
      // durable predecessor output that lands with this successor snapshot.
      let conv = if can_retire_previous_initial && submission_id is Some(id) {
        conv.retire_unconfirmed_initials_before(id)
      } else {
        conv
      }
      // The prompt bubble itself is not appended here — not even from the
      // pushed `task`: the durable transcript's only sources are snapshots
      // and `session.event` commits, and the prompt's own commit (or the
      // refresh below) brings it. `task` still rides on the event for
      // clients that render run identity elsewhere.
      ignore(task)
      // A foreign run means the store holds a lifecycle boundary this client
      // cannot infer from item kinds: a delayed User may still belong to the
      // prior run as a steer. Re-read active and background conversations
      // alike; commits buffer until that snapshot establishes the new run's
      // terminal floor. If an older read is already in flight, mark one
      // follow-up generation: its pre-Started cut may drain commits, but may
      // not establish this run's floor.
      // Every newly observed Started boundary gets a post-Started snapshot,
      // including an owned local start. External/CLI turns may have advanced
      // the store while this page was idle without a follower broadcasting
      // them; reusing Send's stale terminal floor would let that older
      // terminal be mistaken for this run's. The host admits this Started
      // only after its predecessor's final drain, so this read is the first
      // safe place to establish the new floor.
      let refresh = foreign || current_start
      let run = if stale_terminal {
        conv.run
      } else {
        match conv.run {
          Open(run_id=current, stage~) if current == run_id =>
            Open(run_id=current, stage~)
          _ => Open(run_id~, stage=Opened)
        }
      }
      let run_durable_floor = if stale_terminal || same_open {
        conv.run_durable_floor
      } else {
        // Lifecycle and durable commits are independent producers. A new run
        // cannot trust this client's apparently-synced terminal frontier: its
        // Started may have overtaken the previous run's terminal commit.
        None
      }
      let run_floor_generation = if refresh {
        Some(successor_snapshot_generation)
      } else {
        conv.run_floor_generation
      }
      let sync = if refresh &&
        conv.sync
        is Reloading(generation~, attempt~, buffered~, reload_after_current=_) {
        Reloading(generation~, attempt~, buffered~, reload_after_current=true)
      } else {
        conv.sync
      }
      let conv = {
        ..conv,
        run,
        run_durable_floor,
        run_floor_generation,
        sync,
        // The tier is deliberately NOT re-established from the run. A start
        // is always older than the composer: the user may have flipped the
        // chip for the next turn while this one was still being spawned, and
        // a turn another client started says nothing about what this user
        // intends to send. The chip means "what your next turn runs on", so
        // only the chip changes it.
        last_run_id: Some(run_id),
        // A started run always reports its directory, but a malformed
        // event decodes as `None`; keeping the previous root beats
        // forgetting one we already knew.
        cwd: if cwd is Some(_) {
          cwd
        } else {
          conv.cwd
        },
      }
      let (updated, generation) = if refresh {
        model.begin_transcript_reload(conv)
      } else {
        (model.replace_conversation(conv), None)
      }
      // The run's workspace directory now exists, so the branch chip can be
      // probed (and refreshed — a rerun may follow a checkout).
      let (branch_cmd, updated) = probe_branch(
        dispatch, updated, channel, session, cwd,
      )
      let commands = [branch_cmd]
      if generation is Some(generation) {
        commands.push(
          session_snapshot_command(
            dispatch, channel, updated, session, generation, false,
          ),
        )
      }
      // A run is what makes a conversation durable, so this is where its tier
      // gets pinned — the chip is not the only way to acquire one. A tier
      // merely inherited from the page default and then used would otherwise
      // stay unremembered, and the conversation would come back on whatever
      // default an unrelated chat has moved to since. Re-pinning the same
      // tier only reorders the list, so consecutive turns write once.
      let pinned = updated.remember_model(channel, session, conv.engine_model)
      if pinned.conversation_models != model.conversation_models {
        commands.push(
          save_conversation_model(
            conversation_model_key(channel, session),
            conv.engine_model,
          ),
        )
      }
      let updated = pinned
      // The model rode in on the conversation above; max steps is still one
      // global setting, so sync it only when this start belongs to the
      // conversation on screen. A slow background start (the user switched
      // chats mid-spawn) must not overwrite a value the user has since
      // changed for the now-active conversation.
      if channel == updated.focused && session == updated.active_session {
        (@cmd.batch(commands), { ..updated, max_steps: max_steps.to_string() })
      } else {
        (@cmd.batch(commands), updated)
      }
    }
    RunsLoaded(runs~, settled~, live~, frontier~, connection_generation~) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      // Accept the snapshot as one state transition. No intermediate replayed
      // Started row is rendered, and a later BridgeReady invalidates both its
      // positive rows and its negative frontier together.
      let commands : Array[@cmd.Cmd] = []
      let mut next = model
      let accepted_settlements : Array[RecoveredSettlement] = []
      let settled_sessions : Array[String] = []
      for settlement in settled {
        if !accepted_settlements
          .iter()
          .any(item => item.run_id == settlement.run_id) &&
          model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(_) {
          accepted_settlements.push(settlement)
          if !settled_sessions.contains(settlement.session) {
            settled_sessions.push(settlement.session)
          }
        }
      }
      // Validate positive rows against the same immutable request-time model,
      // before a predecessor settlement mutates it. One atomic host snapshot
      // may legitimately contain completed r1 and active successor r2 for the
      // same session; both pieces must survive that hand-off.
      let accepted_runs : Array[RecoveredRun] = []
      let admitted_run_sessions : Array[String] = []
      for run in runs {
        let duplicates_settlement = accepted_settlements
          .iter()
          .any(item => item.session == run.session && item.run_id == run.run_id)
        if !duplicates_settlement &&
          !admitted_run_sessions.contains(run.session) &&
          model.matches_run_snapshot_frontier(channel, frontier, run.session) {
          accepted_runs.push(run)
          admitted_run_sessions.push(run.session)
        }
      }
      // A completion selected by this request is stronger than mere absence.
      // Replay it before active rows and negative settlement, but only while
      // the page still has the exact owner captured at request time. A
      // Starting owner first gains the host run id so the ordinary Finished
      // transition can retire or restore its exact initial submission.
      // A session can carry an older run selector and a newer unbound prompt
      // selector at the same cut. Apply run-owned evidence first, then the
      // submission-owned completion that controls the current composer gate.
      let ordered_settlements : Array[RecoveredSettlement] = []
      for settlement in accepted_settlements {
        if model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(SettlementByRun) {
          ordered_settlements.push(settlement)
        }
      }
      for settlement in accepted_settlements {
        if model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(SettlementBySubmission(_)) {
          ordered_settlements.push(settlement)
        }
      }
      for settlement in ordered_settlements {
        guard model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(owner) else {
          continue
        }
        if owner is SettlementBySubmission(submission_id) &&
          next.find_conversation(channel, settlement.session) is Some(conv) {
          let bound = conv.bind_initial_submission_to_run(
            submission_id,
            settlement.run_id,
          )
          next = next.replace_conversation({
            ..bound,
            run: Open(run_id=settlement.run_id, stage=Opened),
            run_durable_floor: None,
            run_floor_generation: None,
            last_run_id: Some(settlement.run_id),
          })
        }
        let (cmd, updated) = update_device_msg(
          dispatch,
          channel,
          Finished(
            run_id=settlement.run_id,
            status=settlement.status,
            answer=None,
            durable_sequence=settlement.durable_sequence,
          ),
          next,
        )
        commands.push(cmd)
        next = updated
      }
      for run in accepted_runs {
        let (cmd, updated) = update_device_msg(
          dispatch,
          channel,
          Started(
            run_id=run.run_id,
            session=run.session,
            model=run.model,
            max_steps=run.max_steps,
            cwd=run.cwd,
            session_root=run.session_root,
            task=run.task,
            submission_id=run.submission_id,
          ),
          next,
        )
        commands.push(cmd)
        next = updated
      }
      // Do not let the older negative-set logic re-anchor a completion that
      // just supplied an exact durable frontier (notably sequence zero).
      let unsettled_frontier = frontier.filter(captured => {
        !settled_sessions.contains(captured.session)
      })
      let (settled_cmd, settled) = update_device_msg(
        dispatch,
        channel,
        RunsSettled(live~, frontier=unsettled_frontier),
        next,
      )
      commands.push(settled_cmd)
      (@cmd.batch(commands), settled)
    }
    RunsSettled(live~, frontier~) => {
      // A conversation still showing an open run the host no longer has: the
      // run ended while this client was away, and its terminal event will
      // never be replayed, so the phase settles here. How it ended is
      // unknowable (`ended=None`); the verdict text lives in the store and
      // arrives through the usual reads — the active conversation reloads at
      // `BridgeReady`, the rest when opened. Only a lifecycle state that still
      // exactly matches this request's per-session frontier may settle; live
      // Started/Finished transitions received meanwhile are newer truth.
      let boundary_reloads : Array[String] = []
      let snapshot_generation = model.transcript_request_generation + 1
      let settled = model.conversations.map(conv => {
        if conv.device != channel {
          return conv
        }
        for captured in frontier {
          if captured.session == conv.session_id {
            return match captured.state {
              SnapshotOpen(run_id~) if conv.run is Open(run_id=current, ..) &&
                current == run_id &&
                !live.contains(run_id) => {
                // The runs reply may be slower than a steer the user sent
                // after this request began. Close the captured lifecycle, but
                // only adjudicate submissions that existed at the request's
                // own frontier; later exact receipts keep their ownership.
                let unconfirmed = conv
                  .clear_streams()
                  .mark_awaiting_steers_unconfirmed(
                    submission_ids=captured.steer_ids,
                    owner_run_id=run_id,
                    terminal_expected=false,
                    terminal_snapshot_generation=snapshot_generation,
                  )
                  .arm_unconfirmed_steers_at_snapshot_cut(
                    captured.steer_ids,
                    run_id,
                    snapshot_generation,
                  )
                  .mark_initial_for_run_unconfirmed(
                    run_id,
                    terminal_snapshot_generation=snapshot_generation,
                  )
                let needs_boundary_reload = unconfirmed.has_submission_at_snapshot_cut_for_run(
                  run_id,
                )
                if needs_boundary_reload {
                  boundary_reloads.push(conv.session_id)
                }
                {
                  ..unconfirmed,
                  run: NoRun(ended=None),
                  last_run_id: Some(run_id),
                }
              }
              SnapshotIdle(last_run_id=Some(run_id)) if conv.run is NoRun(..) &&
                conv.last_run_id is Some(current) &&
                current == run_id => {
                // A prior abnormal finish may have crossed a disconnect after
                // its lifecycle notification but before its exact EOF
                // boundary. Negative idle resync cannot replay that boundary,
                // so arm only the exact steer ids captured with this request
                // for a post-reply snapshot observation cut.
                let armed = conv.arm_unconfirmed_steers_at_snapshot_cut(
                  captured.steer_ids,
                  run_id,
                  snapshot_generation,
                )
                let armed = armed.mark_initial_for_run_unconfirmed(
                  run_id,
                  terminal_snapshot_generation=snapshot_generation,
                )
                let needs_boundary_reload = armed.has_submission_at_snapshot_cut_for_run(
                  run_id,
                )
                if needs_boundary_reload {
                  boundary_reloads.push(conv.session_id)
                }
                armed
              }
              SnapshotStarting(submission_id~) if conv.run
                is Starting(submission_id=current) &&
                current == submission_id => {
                let mut prompt = ""
                for input in conv.input_ledger {
                  if input.kind is InitialPrompt &&
                    input.submission_id == submission_id {
                    prompt = input.draft
                  }
                }
                let (unconfirmed, _) = conv.mark_submission_unconfirmed(
                  submission_id,
                  "Prompt delivery could not be confirmed after run resync — " +
                  "check the transcript before resubmitting: " +
                  prompt,
                  true,
                  terminal_expected=false,
                  terminal_snapshot_generation=snapshot_generation,
                )
                let unconfirmed = unconfirmed.anchor_submission_notice_at_snapshot_cut(
                  submission_id, snapshot_generation,
                )
                if unconfirmed.overlay
                  .iter()
                  .any(notice => {
                    notice.anchor is SnapshotCut(..) &&
                    notice.reconciliation is Submission(id) &&
                    id == submission_id
                  }) {
                  boundary_reloads.push(conv.session_id)
                }
                { ..unconfirmed.clear_streams(), run: NoRun(ended=None) }
              }
              _ => conv
            }
          }
        }
        conv
      })
      let commands : Array[@cmd.Cmd] = []
      let mut next = { ..model, conversations: settled }
      for session in boundary_reloads {
        if next.find_conversation(channel, session) is Some(conv) {
          let (updated, generation) = next.ensure_transcript_reload_after_current(
            conv,
          )
          next = updated
          if generation is Some(generation) {
            commands.push(
              session_snapshot_command(
                dispatch, channel, next, session, generation, false,
              ),
            )
          }
        }
      }
      (@cmd.batch(commands), next)
    }
    Engine(run_id, event, session~) => {
      // Compaction and background notices happen between turns, so their
      // events arrive after the run that owned `run_id` cleared
      // `active_run_id` — or with no run id at all (an engine spawned just
      // to compact). The host stamps them with their session, which covers
      // that case too; the conversation that last held the id remains the
      // fallback for unstamped events.
      let conv = if run_id is Some(id) &&
        model.conversation_by_run(channel, id) is Some(conv) {
        Some(conv)
      } else if is_steer_receipt(event) && run_id is Some(id) {
        // Host settling receipts may intentionally trail the terminal event;
        // an even newer Started can already have replaced last_run_id. Prefer
        // the exact local ownership ledger before the legacy run fallback.
        let exact = match event {
          SteerApplied(submission_id=Some(submission_id), ..) =>
            model.conversation_by_pending_steer(channel, submission_id, id)
          SteerDropped(submission_id=Some(submission_id), ..) =>
            model.conversation_by_pending_steer(channel, submission_id, id)
          _ => None
        }
        if exact is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(channel, id)
        }
      } else if is_idle_event(event) {
        if session is Some(session) &&
          model.find_conversation(channel, session) is Some(conv) {
          Some(conv)
        } else if run_id is Some(id) {
          model.conversation_by_last_run(channel, id)
        } else {
          None
        }
      } else {
        None
      }
      if conv is Some(conv) {
        let (transcript_grew, next) = apply_engine_event(conv, event, run_id)
        (
          if transcript_grew {
            scroll_if_active(model, channel, conv.session_id)
          } else {
            @cmd.none
          },
          model.replace_conversation(next),
        )
      } else {
        (@cmd.none, model)
      }
    }
    // Everything else the panel owns (tree, viewer, diagnostics) is the
    // fileeditor package's business; route it there and adopt its state.
    StartResponded(session~, submission_id~, run_id~, status~, exit_code~) => {
      guard model.find_conversation(channel, session) is Some(conv) &&
        conv.has_initial_submission(submission_id) else {
        return (@cmd.none, model)
      }
      // The id-bearing reply always settles its exact ledger entry, even when
      // Finished A and Started B overtook A's RPC response. Only lifecycle
      // mutation remains conditional on A still owning the conversation.
      let owns_lifecycle = match conv.run {
        Starting(submission_id=current) => current == submission_id
        Open(run_id=current, ..) => current == run_id
        NoRun(..) => conv.last_run_id is Some(last) && last == run_id
      }
      let conv = conv.bind_initial_submission_to_run(submission_id, run_id)
      if status == "accepted" {
        let missed_started = owns_lifecycle &&
          conv.run is Starting(submission_id=current) &&
          current == submission_id
        let late_abnormal = conv.run is NoRun(..) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id &&
          !(conv.run is NoRun(ended=Some(RunFinished(outcome))) &&
          outcome is (Completed | ContextYield | MaxStepsExhausted))
        let snapshot_generation = model.transcript_request_generation + 1
        // `accepted` proves only that the JSONL command reached the child
        // writer. Keep the recoverable prompt until a terminal-backed finish
        // proves its User append; a pre-append engine failure must not erase
        // the user's text. A response that trails such a normal finish can
        // retire it now because the exact run binding is finally known.
        let settled = if conv.run is NoRun(ended=Some(RunFinished(outcome))) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id &&
          outcome is (Completed | ContextYield | MaxStepsExhausted) {
          conv.acknowledge_initial_for_run(run_id)
        } else if conv.run is NoRun(..) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id {
          conv.mark_initial_for_run_unconfirmed(
            run_id,
            terminal_snapshot_generation=snapshot_generation,
          )
        } else {
          conv
        }
        // The reply still opens the lifecycle when its Started notification
        // was delayed. A very short run may already be finished; never
        // resurrect that settled phase.
        let next = if owns_lifecycle {
          match settled.run {
            NoRun(..) => settled
            Open(run_id=current, stage~) if current == run_id =>
              {
                ..settled,
                run: Open(run_id=current, stage~),
                last_run_id: Some(run_id),
              }
            _ =>
              {
                ..settled,
                run: Open(run_id~, stage=Opened),
                last_run_id: Some(run_id),
              }
          }
        } else {
          settled
        }
        let next = if missed_started {
          {
            ..next,
            run_durable_floor: None,
            run_floor_generation: Some(snapshot_generation),
          }
        } else {
          next
        }
        let (updated, generation) = if missed_started || late_abnormal {
          model.ensure_transcript_reload_after_current(next)
        } else {
          (model.replace_conversation(next), None)
        }
        let (branch_cmd, updated) = probe_branch(
          dispatch,
          updated,
          channel,
          session,
          settled.cwd,
        )
        let commands = [branch_cmd]
        if generation is Some(generation) {
          commands.push(
            session_snapshot_command(
              dispatch, channel, updated, session, generation, false,
            ),
          )
        }
        (@cmd.batch(commands), updated)
      } else {
        // The process result closes a still-live run, but does not prove that
        // its User or Terminal append reached the store. Preserve the exact
        // prompt as unconfirmed until durable recovery or a definitive reject.
        let snapshot_generation = model.transcript_request_generation + 1
        let mut prompt = ""
        for input in conv.input_ledger {
          if input.kind is InitialPrompt && input.submission_id == submission_id {
            prompt = input.draft
          }
        }
        let (unconfirmed, _) = conv.mark_submission_unconfirmed(
          submission_id,
          "Prompt delivery could not be confirmed (host returned " +
          status +
          ", exit code " +
          exit_code.to_string() +
          ") — check the transcript before resubmitting: " +
          prompt,
          true,
          terminal_expected=false,
          terminal_snapshot_generation=snapshot_generation,
        )
        let unconfirmed = unconfirmed.anchor_submission_notice_at_snapshot_cut(
          submission_id, snapshot_generation,
        )
        let unconfirmed = if owns_lifecycle {
          unconfirmed.mark_awaiting_steers_unconfirmed(
            owner_run_id=run_id,
            terminal_expected=false,
            terminal_snapshot_generation=snapshot_generation,
          )
        } else {
          unconfirmed
        }
        let next = if owns_lifecycle {
          match unconfirmed.run {
            Starting(..) | Open(..) =>
              {
                ..unconfirmed.clear_streams(),
                run: NoRun(ended=Some(RunFailed)),
                last_run_id: Some(run_id),
              }
            NoRun(..) => unconfirmed
          }
        } else {
          unconfirmed
        }
        let (model, generation) = model.ensure_transcript_reload_after_current(
          next,
        )
        let (sessions, model) = request_sessions_refresh(
          dispatch, channel, model,
        )
        let commands = [
          sessions,
          fetch_runs(
            dispatch,
            channel,
            model.run_snapshot_frontier(channel),
            dev.connection_generation,
          ),
        ]
        if generation is Some(generation) {
          commands.push(
            session_snapshot_command(
              dispatch, channel, model, session, generation, false,
            ),
          )
        }
        (@cmd.batch(commands), model)
      }
    }
    StartUndelivered(session~, submission_id~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        let owns_submission = conv.has_initial_submission(submission_id)
        let mut prompt = ""
        for input in conv.input_ledger {
          if input.kind is InitialPrompt && input.submission_id == submission_id {
            prompt = input.draft
          }
        }
        let (unconfirmed, changed) = conv.mark_submission_unconfirmed(
          submission_id,
          "Prompt delivery could not be confirmed (" +
          message +
          ") — check the transcript before resubmitting: " +
          prompt,
          false,
        )
        if !owns_submission {
          (@cmd.none, model)
        } else {
          let next = if conv.run is Starting(submission_id=current) &&
            current == submission_id {
            { ..unconfirmed.clear_streams(), run: NoRun(ended=Some(RunFailed)) }
          } else {
            // A Started push/response for another run won the race. An
            // uncorrelated transport failure must never close that open run.
            unconfirmed
          }
          let updated = model.replace_conversation(next)
          let (sessions, updated) = request_sessions_refresh(
            dispatch, channel, updated,
          )
          let commands = [
            sessions,
            fetch_runs(
              dispatch,
              channel,
              updated.run_snapshot_frontier(channel),
              dev.connection_generation,
            ),
          ]
          if changed {
            commands.push(scroll_if_active(model, channel, session))
          }
          (@cmd.batch(commands), updated)
        }
      } else {
        (@cmd.none, model)
      }
    StartRejected(session~, submission_id~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        let (rejected, removed) = conv.reject_submission(
          submission_id,
          InitialPrompt,
          None,
          message,
        )
        if !removed {
          (@cmd.none, model)
        } else {
          let next = if conv.run is Starting(submission_id=current) &&
            current == submission_id {
            { ..rejected.clear_streams(), run: NoRun(ended=Some(RunFailed)) }
          } else {
            rejected
          }
          let updated = model.replace_conversation(next)
          if conv.workspace is Some(workspace) &&
            updated.device_state(channel) is Some(dev) {
            // A checkout deleted outside the app cannot publish a registry
            // notification. Any rejected workspace start is a cheap, reliable
            // point to refresh placement; a newly `present: false` row then
            // replaces the generic refusal with Repair/Archive immediately.
            let request_generation = dev.worktrees_request_generation + 1
            (
              @cmd.batch([
                scroll_if_active(model, channel, session),
                fetch_worktrees(
                  dispatch,
                  channel,
                  workspace,
                  dev.connection_generation,
                  request_generation,
                ),
              ]),
              updated.replace_device({
                ..dev,
                worktrees_request_generation: request_generation,
              }),
            )
          } else {
            (scroll_if_active(model, channel, session), updated)
          }
        }
      } else {
        (@cmd.none, model)
      }
    Error(run_id~, message~, diagnostics~, exit_code~) => {
      // Agent-side semantic errors are lifecycle-only here; their durable
      // status is classified by the subsequent Finished event. Process
      // diagnostics carry `exit_code` and have no durable twin, so they remain
      // a local notice.
      let conv = if run_id is Some(run_id) {
        if model.conversation_by_run(channel, run_id) is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(channel, run_id)
        }
      } else if channel == model.focused {
        Some(model.active())
      } else {
        None
      }
      if conv is Some(conv) {
        if run_id is Some(_) && exit_code is None {
          return (@cmd.none, model)
        }
        let content = if diagnostics is Some(diagnostics) &&
          !diagnostics.trim().is_empty() {
          "\{message}\n\n\{diagnostics}"
        } else {
          message
        }
        let next = if run_id is Some(owner) && exit_code is Some(_) {
          conv.append_run_diagnostic(owner, content)
        } else {
          conv.append_local_notice(Assistant(is_danger=true), content)
        }
        (
          scroll_if_active(model, channel, conv.session_id),
          model.replace_conversation(
            if next.run is NoRun(..) {
              { ..next, run: NoRun(ended=Some(RunErrored)) }
            } else {
              next
            },
          ),
        )
      } else {
        (@cmd.none, model)
      }
    }
    CompactRejected(session~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        (
          scroll_if_active(model, channel, conv.session_id),
          model.replace_conversation({
            ..conv.append_local_notice(Assistant(is_danger=true), message),
            compaction: NotCompacting,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    Finished(run_id~, status~, answer~, durable_sequence~) =>
      if (if model.conversation_by_run(channel, run_id) is Some(conv) {
          Some(conv)
        } else {
          // RunsSettled may have closed the phase first; Finished is still the
          // authoritative outcome for the conversation that last owned it.
          model.conversation_by_last_run(channel, run_id)
        })
        is Some(conv) {
        let first_finish = !(conv.run is NoRun(ended=Some(RunFinished(_))) &&
          conv.last_run_id is Some(last) &&
          last == run_id)
        // Missing receipts are not guessed dropped. Keep exact-id ownership
        // briefly and show a truthful unconfirmed notice behind the durable
        // terminal boundary; a trailing receipt may still settle it.
        // On abnormal EOF the host includes a sequence only after its final
        // follower scan succeeded. That is the exact durable EOF boundary;
        // unlike a normal finish, it need not be followed by a Terminal.
        let durable_frontier = durable_sequence
        // Only events logged strictly after a successful Terminal append are
        // terminal-backed. Failed/aborted/cancelled paths attempt the append
        // in a catch block that may itself fail; the host closes that engine
        // and later supplies an exact EOF boundary instead.
        let terminal_expected = match status {
          "finished" | "context_yield" | "max_steps_exhausted" => true
          _ => false
        }
        // Normal finishes use this generation to locate their promised
        // Terminal. Abnormal finishes use the same post-transition read only
        // as an observation cut; they never claim an anonymous Terminal.
        let terminal_snapshot_generation = Some(
          model.transcript_request_generation + 1,
        )
        let conv = if terminal_expected {
          // A successful terminal path can only occur after this run's User
          // append. This is the durable proof that finally retires the prompt
          // kept past the earlier stdin-write response.
          conv.acknowledge_initial_for_run(run_id)
        } else {
          conv.mark_initial_for_run_unconfirmed(
            run_id,
            durable_frontier?,
            terminal_snapshot_generation?,
          )
        }
        let conv = if durable_frontier is Some(frontier) {
          conv
          .anchor_unconfirmed_steers_at_durable_frontier(run_id, frontier)
          .anchor_run_diagnostics_at_durable_frontier(run_id, frontier)
        } else {
          conv
          .anchor_unconfirmed_steers_at_run_finish(
            run_id,
            terminal_expected,
            terminal_snapshot_generation?,
          )
          .anchor_run_diagnostics_at_finish(
            run_id,
            terminal_expected,
            terminal_snapshot_generation?,
          )
        }
        let settled_inputs = conv
          .clear_streams()
          .mark_awaiting_steers_unconfirmed(
            durable_frontier?,
            owner_run_id=run_id,
            terminal_expected~,
            terminal_snapshot_generation?,
          )
        let base = {
          ..settled_inputs,
          run: NoRun(ended=Some(RunFinished(RunOutcome::parse(status)))),
          last_run_id: Some(run_id),
          // A finish the user watched happen needs no reminder; one landing
          // in a background conversation leaves a dot until they visit.
          unseen_finish: conv.device != model.focused ||
          conv.session_id != model.active_session,
        }
        // An exact zero EOF cut proves that a fresh failed run created no
        // durable record. Cancel its now-obsolete speculative snapshot read:
        // otherwise `session.load` can only fail (the file does not exist)
        // and eventually leave Send permanently gated behind ReloadFailed.
        // Be deliberately narrow: any applied or buffered durable content
        // still takes the normal reconciliation path.
        let exact_empty_eof = !terminal_expected &&
          durable_frontier is Some(frontier) &&
          base.is_empty_at_durable_frontier(frontier)
        let base = if exact_empty_eof {
          { ..base.restore_unpersisted_initial_for_run(run_id), sync: Synced }
        } else {
          base
        }
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed —
        // and the turn may have created the repository or switched branches.
        let mut next = model.replace_conversation(base)
        let (sessions, requested) = request_sessions_refresh(
          dispatch, channel, next,
        )
        next = requested
        let (branch_cmd, probed) = probe_branch(
          dispatch,
          next,
          channel,
          conv.session_id,
          conv.cwd,
        )
        next = probed
        let commands = [sessions, branch_cmd]
        // Only the embedded desktop page owns system notifications. Remote
        // browser pages never have the notification extension, and replaying
        // the same Finished boundary must not post a second notification.
        if first_finish && channel is Local {
          commands.push(
            FinishedSystemNotification::{ run_id, status, answer }.command(),
          )
        }
        // The turn's edits routinely land in files the editor panel never
        // shows — paths its pruned watcher does not cover — so the settled
        // boundary re-checks the active MoonBit file's module. The panel's
        // owner fence drops a finish from a conversation it is not showing.
        if first_finish {
          let (panel_cmd, panel_next) = update_msg(
            dispatch,
            FileEditor(RunSettled(owner={ channel, session: conv.session_id })),
            next,
          )
          commands.push(panel_cmd)
          next = panel_next
        }
        if first_finish && !exact_empty_eof && !base.session_id.is_empty() {
          match base.sync {
            Reloading(generation~, attempt~, buffered~, reload_after_current~) =>
              // The current snapshot may have been captured before this
              // Finished boundary. Do not start a concurrent read; remember
              // to run exactly one fresh generation after it settles.
              if !reload_after_current {
                next = next.replace_conversation({
                  ..base,
                  sync: Reloading(
                    generation~,
                    attempt~,
                    buffered~,
                    reload_after_current=true,
                  ),
                })
              }
            Synced | ReloadFailed(..) => {
              let (reloading, generation) = next.begin_transcript_reload(base)
              next = reloading
              if generation is Some(generation) {
                commands.push(
                  session_snapshot_command(
                    dispatch,
                    channel,
                    next,
                    base.session_id,
                    generation,
                    false,
                  ),
                )
              }
            }
          }
        }
        if base.overlay.length() > conv.overlay.length() {
          commands.push(scroll_if_active(model, channel, conv.session_id))
        }
        (@cmd.batch(commands), next)
      } else {
        // Even when this page missed both Started and every commit, the list
        // can reveal the finished durable session for a later open.
        request_sessions_refresh(dispatch, channel, model)
      }
    DurableBoundary(run_id~, session~, sequence~) =>
      if model.find_conversation(channel, session) is Some(conv) &&
        conv.last_run_id is Some(owner) &&
        owner == run_id {
        let anchored = conv
          .mark_initial_for_run_unconfirmed(run_id, durable_frontier=sequence)
          .anchor_unconfirmed_steers_at_durable_frontier(run_id, sequence)
          .anchor_run_diagnostics_at_durable_frontier(run_id, sequence)
        let exact_empty_eof = anchored.is_empty_at_durable_frontier(sequence)
        let anchored = if exact_empty_eof {
          {
            ..anchored.restore_unpersisted_initial_for_run(run_id),
            sync: Synced,
          }
        } else {
          anchored
        }
        let unresolved = anchored.overlay
          .iter()
          .any(notice => {
            notice.anchor is DurableTail(frontier) && frontier == sequence
          })
        if unresolved {
          // The earlier synthetic Finished may already have completed its
          // compatibility reload before this process finally exited. Re-read
          // once so the snapshot's per-event boundaries can place an exact
          // frontier that is older than the current display watermark.
          let (next, generation) = model.begin_transcript_reload(anchored)
          if generation is Some(generation) {
            (
              session_snapshot_command(
                dispatch, channel, next, session, generation, false,
              ),
              next,
            )
          } else {
            (@cmd.none, next)
          }
        } else {
          (@cmd.none, model.replace_conversation(anchored))
        }
        // Finished removes the run from the host's active set before a
        // failed final follower scan can publish this boundary. An earlier
        // runs snapshot may therefore have closed `Starting` without ever
        // learning the run id. The host records the boundary before this
        // notification reaches us; ask once more with the still-exact
        // submission selector so its now-replayable settlement can bind the
        // run and apply the frontier (including exact zero).
      } else if model.find_conversation(channel, session) is Some(conv) &&
        conv.has_recovering_initial() {
        (
          fetch_runs(
            dispatch,
            channel,
            model.run_snapshot_frontier(channel),
            dev.connection_generation,
          ),
          model,
        )
      } else {
        (@cmd.none, model)
      }
  }
}

// Purity and state-transition tests for the update handlers that back the
// streaming, session, and multi-conversation integration. Commands are
// opaque, so the tests assert on the returned model only.
