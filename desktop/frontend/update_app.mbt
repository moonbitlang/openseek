// Page-level message dispatch.

///|
fn update_msg(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    Init =>
      // A browser console boots by asking the relay who is signed in; the
      // bridge, the session rotation, and the transcript scroll watcher
      // wait for the first roster (`apply_roster`) — before sign-in there
      // is no channel to install and no transcript DOM to watch. The
      // desktop window boots its one Local channel directly.
      match model.console {
        Some(_) =>
          (
            @cmd.batch([
              fetch_console_me(dispatch),
              load_saved_settings(dispatch),
              // Browser localStorage is relay-origin state, not device
              // state. Purge old client-held engine credentials even while
              // signed out or when no device is online to reach
              // `BridgeReady`.
              clear_legacy_engine_settings(),
              watch_color_scheme(dispatch),
            ]),
            model,
          )
        None =>
          (
            @cmd.batch([
              install_bridge(dispatch, model.focused, 0),
              load_saved_settings(dispatch),
              watch_transcript_scroll(dispatch),
              watch_color_scheme(dispatch),
              rotate_session(dispatch, model.focused),
            ]),
            model,
          )
      }
    Console(msg) => update_console_msg(dispatch, msg, model)
    SettingsLoaded(
      notification_corner~,
      tree_layout~,
      theme~,
      model=stored,
      conversation_models=remembered
    ) => {
      let theme = Theme::parse(theme, model.theme)
      // Startup runs before any conversation exists, so adopting the stored
      // tiers here is enough — every conversation minted afterwards reads
      // them.
      let default_model = EngineModel::parse(stored).unwrap_or(
        model.default_model,
      )
      (
        theme.apply(model.system_dark),
        {
          ..model,
          notification_corner: NotificationCorner::parse(notification_corner),
          tree_layout: @fileeditor.TreeLayout::parse(tree_layout),
          theme,
          default_model,
          conversation_models: parse_conversation_models(remembered),
        },
      )
    }
    // The host's settings, from the bridge-time `settings.get` or a peer's
    // edit broadcast. Revisions order concurrent clients and RPC replies;
    // while this page has optimistic writes, keep only the newest status and
    // apply it once the last write settles.
    LegacySettingsRead(provider~, custom_url~, api_key~, custom_api_key~) =>
      // Only the desktop window migrates: it is the one client whose stored
      // values are unambiguously this host's. A browser page's copy may
      // belong to a different device behind the same origin — pushing it is
      // exactly the leak the host-side store removes — so it is purged.
      if model.is_desktop {
        let patch = legacy_settings_patch(
          provider~,
          custom_url~,
          api_key~,
          custom_api_key~,
        )
        // Mirror the pushed values optimistically so the Settings page and
        // the ready gate reflect the migration immediately.
        let next = {
          ..model,
          api_provider: ApiProvider::parse(provider),
          custom_api_url: custom_url.trim().to_owned(),
          deepseek_key_saved: model.deepseek_key_saved ||
          !api_key.trim().is_empty(),
          custom_key_saved: model.custom_key_saved ||
          !custom_api_key.trim().is_empty(),
          settings_saves: model.settings_saves + 1,
          legacy_cleanup_pending: true,
        }
        (
          push_host_settings(
            dispatch,
            model.focused,
            patch,
            model.focused_connection_generation(),
            cleans_legacy=true,
          ),
          next,
        )
      } else {
        (clear_legacy_engine_settings(), model)
      }
    TaskChanged(value) => {
      let owner : @interop.ConversationKey = {
        channel: model.focused,
        session: model.active().session_id,
      }
      (
        symbol_fetch_cmd(dispatch, model, value, owner),
        {
          ..model.replace_conversation({ ..model.active(), task: value }),
          completion: compute_completion(
            value,
            model.installed_skills,
            model.symbol_cache,
            owner,
          ),
        },
      )
    }
    CompletionMove(delta) =>
      if model.completion is Some(menu) {
        (@cmd.none, { ..model, completion: Some(menu.shifted(delta)) })
      } else {
        (@cmd.none, model)
      }
    CompletionDismiss => (@cmd.none, { ..model, completion: None })
    RemoveMention(index) => {
      let conv = model.active()
      guard conv.mentions.get(index) is Some(_) else {
        return (@cmd.none, model)
      }
      let mentions = conv.mentions.copy()
      let _ = mentions.remove(index)
      (@cmd.none, model.replace_conversation({ ..conv, mentions, }))
    }
    JumpToMention(index) => {
      let conv = model.active()
      guard conv.mentions.get(index) is Some(mention) else {
        return (@cmd.none, model)
      }
      guard mention_target(mention.ref_) is Some(target) else {
        return (@cmd.none, model)
      }
      // A draft chip still holds the full resolved range (columns included);
      // the envelope-shaped target range is the fallback.
      let range = if mention.range is Some(_) {
        mention.range
      } else {
        target.range
      }
      open_editor_at(
        dispatch,
        model,
        target.file,
        range,
        annotation?=target.annotation,
      )
    }
    JumpToLocation(path~, range~, annotation~) =>
      open_editor_at(dispatch, model, path, range, annotation?)
    // Intercepted here rather than delegated to the fileeditor package: the
    // comment becomes an annotation chip on the composer draft, which only
    // this model knows about. `quote`/`range` come from the panel's viewer.
    FileEditor(
      EditorCommentAdded(
        resource~,
        file~,
        range~,
        quote~,
        comment~,
        feedback_id~
      )
    ) => {
      let conv = model.active()
      let mentions = push_mention(conv.mentions, {
        ref_: Annotation(
          file=file.0,
          start_line=range.start_line_number,
          end_line=range.end_line_number,
          quote~,
          comment~,
          side=@mention_context.WorkingRevision,
        ),
        range: Some(range),
      })
      // The chip is the comment's carrier from here on; clearing the editor's
      // own bubble keeps the two from drifting apart (and from double-sending
      // if the user comments again).
      (
        @fileeditor.remove_editor_feedback(resource, feedback_id),
        model.replace_conversation({ ..conv, mentions, }),
      )
    }
    // Full-diff comments carry both line domains because a deletion has no
    // working-document position. Prefer the modified line for additions and
    // context; retain the original line for an original-only deletion. Only a
    // modified-side comment receives a concrete editor range, so reopening a
    // deleted-line chip cannot claim stale source columns.
    FileEditor(
      UnifiedDiffCommentAdded(
        file~,
        original_line_number~,
        modified_line_number~,
        quote~,
        comment~
      )
    ) => {
      let (line_number, range, side) = match modified_line_number {
        Some(line_number) if line_number >= 1 => {
          let end_column = if quote.is_empty() { 1 } else { quote.length() + 1 }
          (
            line_number,
            Some(@common.Range::Range(line_number, 1, line_number, end_column)),
            @mention_context.WorkingRevision,
          )
        }
        _ =>
          match original_line_number {
            Some(line_number) if line_number >= 1 =>
              (line_number, None, @mention_context.OriginalRevision)
            _ => return (@cmd.none, model)
          }
      }
      let conv = model.active()
      let mentions = push_mention(conv.mentions, {
        ref_: Annotation(
          file=file.0,
          start_line=line_number,
          end_line=line_number,
          quote~,
          comment~,
          side~,
        ),
        range,
      })
      (@cmd.none, model.replace_conversation({ ..conv, mentions, }))
    }
    // Intercepted like the comment above: which dock tab a tree click opens
    // is the strip's business. The dock opens (or re-activates) the tab,
    // then the file subsystem loads and shows the document against the
    // fresh projection.
    FileEditor(FileSelected(path~, name~)) => {
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
        return (@cmd.none, model)
      }
      let had_active = @dock.active_file(model.dock) is Some(_)
      // A pick made from the active FilePicker tab fulfills it: the picker
      // is replaced in place (or the already-open tab activates and the
      // picker closes). Any other tree click opens tabs as before.
      let dock = if model.dock.active is Some(FilePicker) {
        @dock.resolve_pick(model.dock, path)
      } else {
        @dock.open_file(model.dock, path)
      }
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_document(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        path,
        name~,
        range=None,
        had_active~,
      )
      (cmd, { ..model, file_panel: panel })
    }
    // A Changes row is the review action: open/activate the same ordinary file
    // tab, then let the file subsystem pair its working-tree document with the
    // row's HEAD path. Deleted rows have no working file but still use the
    // current path as their tab identity.
    FileEditor(ChangedFileSelected(change)) => {
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
        return (@cmd.none, model)
      }
      let had_active = @dock.active_file(model.dock) is Some(_)
      let dock = if model.dock.active is Some(FilePicker) {
        @dock.resolve_pick(model.dock, change.path)
      } else {
        @dock.open_file(model.dock, change.path)
      }
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_changed_document(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        change,
        had_active~,
      )
      (cmd, { ..model, file_panel: panel })
    }
    // Intercepted for the same reason: a navigation jump (go-to-definition,
    // a reference pick) opens a dock tab before the document loads. The
    // owner stamp rejects a reply that outlived a conversation switch.
    FileEditor(OpenNavigationLocation(owner~, path~, range~)) => {
      guard model.file_panel.owner == Some(owner) &&
        file_ctx(model).owner == owner else {
        return (@cmd.none, model)
      }
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
        return (@cmd.none, model)
      }
      let had_active = @dock.active_file(model.dock) is Some(_)
      let dock = @dock.open_file(model.dock, path)
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_file(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        path,
        range=Some(range),
        had_active~,
      )
      (cmd, { ..model, file_panel: panel })
    }
    CompletionAccept =>
      if model.completion is Some(menu) && menu.current() is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    CompletionPick(index) =>
      if model.completion is Some(menu) && menu.items.get(index) is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    SymbolsLoaded(owner~, query~, items~) =>
      apply_symbol_reply(model, owner, query, items)
    // A failed search reads as "no symbols": cache an empty result for the
    // query so the menu settles on "No symbols" rather than spinning.
    SymbolsFailed(owner~, query~) => apply_symbol_reply(model, owner, query, [])
    QuickOpenOpen(mode) => open_quick_open(dispatch, model, mode)
    QuickOpenValueChanged(value) =>
      change_quick_open_value(dispatch, model, value)
    QuickOpenDue(owner~, query~, generation~) =>
      begin_quick_open_symbol_request(dispatch, model, owner, query, generation)
    QuickOpenSymbolsLoaded(owner~, query~, generation~, items~) =>
      apply_quick_open_symbol_result(model, owner, query, generation, items)
    QuickOpenSymbolsRequestFailed(owner~, query~, generation~) =>
      fail_quick_open_symbol_request(model, owner, query, generation)
    QuickOpenMove(delta) => move_quick_open_selection(model, delta)
    QuickOpenSelect(index) => select_quick_open_row(model, index)
    QuickOpenAccept => accept_quick_open(dispatch, model)
    QuickOpenPick(index) => pick_quick_open_row(dispatch, model, index)
    QuickOpenDismiss => (@cmd.none, { ..model, quick_open: None })
    ToggleModel => {
      // The chip switches the conversation on screen. The tier is pinned to
      // that conversation right away — a chat can be given a tier and left
      // unsent for days — and becomes what the next new chat starts from.
      // (Starting a run pins it too; see `Started`.) A turn already in flight
      // keeps the model it was started with; this takes effect on the next.
      let conv = model.active()
      let engine_model = conv.engine_model.toggled()
      let next = model
        .replace_conversation({ ..conv, engine_model, })
        .remember_model(conv.device, conv.session_id, engine_model)
      (
        @cmd.batch([
          save_default_model(engine_model),
          save_conversation_model(
            conversation_model_key(conv.device, conv.session_id),
            engine_model,
          ),
        ]),
        { ..next, default_model: engine_model },
      )
    }
    MaxStepsChanged(value) => (@cmd.none, { ..model, max_steps: value })
    SetupApiKeyChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      (@cmd.none, { ..model, setup_api_key: value })
    }
    ProviderChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let provider = ApiProvider::parse(value)
      // A server switch can move the update channel with it; whatever the
      // old channel's check said no longer applies.
      let update_ux = if provider.update_channel() ==
        model.api_provider.update_channel() {
        model.update_ux
      } else {
        UpdateUnknown
      }
      (
        push_host_settings(
          dispatch,
          model.focused,
          provider_settings_patch(provider),
          model.focused_connection_generation(),
        ),
        {
          ..model,
          api_provider: provider,
          setup_api_key: "",
          settings_saves: model.settings_saves + 1,
          update_ux,
        },
      )
    }
    CustomApiUrlChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      (
        push_host_settings(
          dispatch,
          model.focused,
          custom_url_settings_patch(value),
          model.focused_connection_generation(),
        ),
        {
          ..model,
          custom_api_url: value,
          settings_saves: model.settings_saves + 1,
        },
      )
    }
    NotificationCornerChanged(value) => {
      let corner = NotificationCorner::parse(value)
      (
        save_notification_corner(corner),
        { ..model, notification_corner: corner },
      )
    }
    TreeLayoutChanged(value) => {
      let layout = @fileeditor.TreeLayout::parse(value)
      // The dock flips purely in CSS, but the viewer cannot see its host
      // change size on its own — remeasure it (mount_cmds is idempotent and
      // carries the remeasure).
      (
        @cmd.batch([
          save_tree_layout(layout),
          @fileeditor.mount_cmds(dispatch.map(msg => FileEditor(msg))),
        ]),
        { ..model, tree_layout: layout },
      )
    }
    NotificationExpired(id) | DismissNotification(id) =>
      (
        @cmd.none,
        { ..model, notifications: model.notifications.filter(t => t.id != id) },
      )
    RemoteStatusLoaded(status) =>
      (@cmd.none, { ..model, remote_access: Some(status) })
    RemoteConnectClicked =>
      // The flow blocks on a browser round-trip; a second click while one
      // is pending would start a second loopback flow just to be refused.
      if model.remote_connecting {
        (@cmd.none, model)
      } else {
        (
          connect_remote(dispatch),
          { ..model, remote_connecting: true, remote_error: None },
        )
      }
    RemoteConnectFinished(status) =>
      (
        @cmd.none,
        {
          ..model,
          remote_access: Some(status),
          remote_connecting: false,
          remote_error: None,
        },
      )
    RemoteConnectFailed(message) =>
      (
        @cmd.none,
        { ..model, remote_connecting: false, remote_error: Some(message) },
      )
    RemoteCancelClicked =>
      // Fire-and-forget: the connect that is being cancelled reports back
      // through its own reply, which is what clears the pending state.
      (cancel_remote(dispatch), model)
    RemoteDisconnectClicked =>
      (disconnect_remote(dispatch), { ..model, remote_error: None })
    RemoteDisconnectFailed(message) =>
      (@cmd.none, { ..model, remote_error: Some(message) })
    AppInfoLoaded(version) => (@cmd.none, { ..model, app_version: version })
    CheckForUpdates =>
      // A user-initiated check; never stacks on an in-flight one, and never
      // interrupts a download already underway.
      if model.update_ux
        is (CheckingForUpdate
        | ConfirmingRestart(..)
        | DownloadingUpdate(..)
        | RestartingForUpdate(..)) {
        (@cmd.none, model)
      } else {
        (
          check_for_updates(
            dispatch,
            model.api_provider.update_channel(),
            explicit=true,
          ),
          { ..model, update_ux: CheckingForUpdate },
        )
      }
    UpdateCheckFinished(result~, explicit~) => {
      // A stale reply must not clobber a flow the user has since started
      // (confirming, downloading); only the waiting states accept results.
      guard model.update_ux
        is (UpdateUnknown
        | CheckingForUpdate
        | UpToDate
        | UpdateCheckFailed(..)) else {
        return (@cmd.none, model)
      }
      match result {
        CheckFound(version~, installable~, unavailable_reason~) => {
          let (cmd, next) = if !installable &&
            unavailable_reason is Some(reason) {
            model.notify_error(dispatch, reason)
          } else {
            (@cmd.none, model)
          }
          (cmd, { ..next, update_ux: UpdateAvailable(version~, installable~) })
        }
        CheckUpToDate =>
          (
            @cmd.none,
            {
              ..model
              // Only worth stating when the user asked; a quiet startup
              // check leaves nothing behind.
              ,
              update_ux: if explicit {
                UpToDate
              } else {
                UpdateUnknown
              },
            },
          )
        CheckUnreachable(reason~) =>
          // Offline is routine for the app, an answer for the user.
          if explicit {
            (
              @cmd.none,
              {
                ..model,
                update_ux: UpdateCheckFailed(
                  message="Could not reach the update server: \{reason}",
                ),
              },
            )
          } else {
            (@cmd.none, { ..model, update_ux: UpdateUnknown })
          }
        CheckMalformed(reason~) =>
          // A garbage manifest also happens under captive portals, so the
          // app asking stays quiet (the host logged it); the user asking
          // gets the truth.
          if explicit {
            (
              @cmd.none,
              {
                ..model,
                update_ux: UpdateCheckFailed(
                  message="The update server answered unusably: \{reason}",
                ),
              },
            )
          } else {
            (@cmd.none, { ..model, update_ux: UpdateUnknown })
          }
        CheckBroken(version~, reason~) => {
          // A broken package entry can only be the publisher's fault:
          // loud both ways.
          let message = "OpenSeek \{version} is published but its package is unusable: \{reason}"
          let (cmd, next) = if explicit {
            (@cmd.none, model)
          } else {
            model.notify_error(dispatch, message)
          }
          (cmd, { ..next, update_ux: UpdateCheckFailed(message~) })
        }
      }
    }
    UpdateClicked =>
      // Only meaningful while an installable release is on offer; the
      // button does not render otherwise, but a stale click must not
      // restart a download.
      if model.update_ux is UpdateAvailable(version~, installable=true) {
        if model.any_conversation_busy() {
          (@cmd.none, { ..model, update_ux: ConfirmingRestart(version~) })
        } else {
          (
            download_update(dispatch, model.api_provider.update_channel()),
            {
              ..model,
              update_ux: DownloadingUpdate(version~, progress={
                downloaded_bytes: 0,
                total_bytes: None,
              }),
            },
          )
        }
      } else {
        (@cmd.none, model)
      }
    ConfirmUpdateRestart =>
      if model.update_ux is ConfirmingRestart(version~) {
        (
          download_update(dispatch, model.api_provider.update_channel()),
          {
            ..model,
            update_ux: DownloadingUpdate(version~, progress={
              downloaded_bytes: 0,
              total_bytes: None,
            }),
          },
        )
      } else {
        (@cmd.none, model)
      }
    CancelUpdateRestart =>
      if model.update_ux is ConfirmingRestart(version~) {
        (
          @cmd.none,
          { ..model, update_ux: UpdateAvailable(version~, installable=true) },
        )
      } else {
        (@cmd.none, model)
      }
    UpdateDownloadProgress(downloaded_bytes~, total_bytes~) =>
      if model.update_ux is DownloadingUpdate(version~, ..) {
        (
          @cmd.none,
          {
            ..model,
            update_ux: DownloadingUpdate(version~, progress={
              downloaded_bytes,
              total_bytes,
            }),
          },
        )
      } else {
        // A late event must not revive a completed, failed, or never-started
        // download after the UI has moved to another state.
        (@cmd.none, model)
      }
    UpdateDownloaded =>
      if model.update_ux is DownloadingUpdate(version~, ..) {
        (
          apply_update(dispatch),
          { ..model, update_ux: RestartingForUpdate(version~) },
        )
      } else {
        (@cmd.none, model)
      }
    UpdateFailed(message~) => {
      // A failed download can be retried. A failed swap means the preflight
      // no longer considers this location replaceable, so withdraw the
      // button until a fresh check says otherwise. Both failures say why.
      let (cmd, next) = model.notify_error(dispatch, message)
      let update_ux = match next.update_ux {
        DownloadingUpdate(version~, ..) =>
          UpdateAvailable(version~, installable=true)
        RestartingForUpdate(version~) =>
          UpdateAvailable(version~, installable=false)
        other => other
      }
      (cmd, { ..next, update_ux, })
    }
    UpdateApplied => (close_window(), model)
    OpenSetup => (@cmd.none, { ..model, screen: Settings, setup_api_key: "" })
    ToggleSidebar => (@cmd.none, { ..model, sidebar_open: !model.sidebar_open })
    ViewportResized(width~) => {
      let narrow = width <= NarrowBreakpoint
      // The embedded viewer only learns its host's size through layout(),
      // so any resize while a document is up remeasures it — same-side
      // resizes included (a rotation changes the host without crossing the
      // breakpoint).
      let cmds = if model.dock.open && @dock.active_file(model.dock) is Some(_) {
        [@fileeditor.request_viewer_remeasure()]
      } else {
        []
      }
      // A horizontal resize can move the right-anchored browser pane
      // without resizing it (`--editor-width` is fixed pixels after a
      // drag): its ResizeObserver stays silent and the geometry signature
      // never changes, so the resize itself must trigger the re-measure.
      if desired_browser_view(model) is Some(_) {
        cmds.push(measure_browser_pane(dispatch))
      }
      let cmd = @cmd.batch(cmds)
      if narrow == model.narrow {
        (cmd, model)
      } else {
        // Crossing the breakpoint resets the sidebar to the new layout's
        // default: an open column on wide, a closed drawer on narrow.
        (cmd, { ..model, narrow, sidebar_open: !narrow })
      }
    }
    ToggleChatsSection =>
      (@cmd.none, { ..model, chats_collapsed: !model.chats_collapsed })
    ToggleWorkspacesSection =>
      (
        @cmd.none,
        { ..model, workspaces_collapsed: !model.workspaces_collapsed },
      )
    ToggleSubruns(channel, session_id) => {
      let expanded = if model.subruns_expanded(channel, session_id) {
        model.expanded_subruns.filter(entry => {
          !(entry.0 == channel && entry.1 == session_id)
        })
      } else {
        [..model.expanded_subruns, (channel, session_id)]
      }
      (@cmd.none, { ..model, expanded_subruns: expanded })
    }
    SaveApiKey => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, model)
      } else {
        match model.api_provider {
          // The key goes straight to the host's store; the mirror keeps
          // only its presence. Saving the key that completes the setup
          // returns to the chat — the same auto-dismiss the popup used to
          // have — optimistically; a failed save comes back as a toast.
          Deepseek | Custom as provider => {
            let next = {
              ..model,
              deepseek_key_saved: model.deepseek_key_saved ||
              provider is Deepseek,
              custom_key_saved: model.custom_key_saved || provider is Custom,
              setup_api_key: "",
              settings_saves: model.settings_saves + 1,
            }
            (
              push_host_settings(
                dispatch,
                model.focused,
                api_key_settings_patch(provider, api_key),
                model.focused_connection_generation(),
              ),
              { ..next, screen: if next.api_ready() { Chat } else { Settings } },
            )
          }
          Openseek | OpenseekStaging =>
            (@cmd.none, { ..model, setup_api_key: "" })
        }
      }
    }
    OpenSkills => {
      // The catalog is fetched once per app run (and again after a
      // failure); the installed list is cheap and refreshes on every open.
      let (catalog_cmd, skills_catalog) = match model.skills_catalog {
        CatalogIdle | CatalogFailed(_) =>
          (fetch_skills_catalog(dispatch, model.focused), CatalogLoading)
        current => (@cmd.none, current)
      }
      (
        @cmd.batch([
          catalog_cmd,
          fetch_installed_skills(dispatch, model.focused),
        ]),
        { ..model, screen: Skills, skills_catalog, skills_notice: "" },
      )
    }
    SkillsQueryChanged(value) => (@cmd.none, { ..model, skills_query: value })
    SkillsCatalogLoaded(items) =>
      (@cmd.none, { ..model, skills_catalog: CatalogReady(items) })
    SkillsCatalogFailed(message) =>
      (@cmd.none, { ..model, skills_catalog: CatalogFailed(message) })
    SkillsNotice(message) => (@cmd.none, { ..model, skills_notice: message })
    InstallSkill(item) => {
      let key = @transcript.market_source_label(item)
      if model.skills_busy.contains(key) {
        (@cmd.none, model)
      } else {
        let skills_busy = model.skills_busy.copy()
        skills_busy.push(key)
        (
          install_skill(dispatch, model.focused, item),
          { ..model, skills_busy, skills_notice: "" },
        )
      }
    }
    UninstallSkill(id) =>
      if model.skills_busy.contains(id) {
        (@cmd.none, model)
      } else {
        let skills_busy = model.skills_busy.copy()
        skills_busy.push(id)
        (
          uninstall_skill(dispatch, model.focused, id),
          { ..model, skills_busy, skills_notice: "" },
        )
      }
    SkillActionDone(channel~, key~, error~) => {
      let skills_busy = model.skills_busy.filter(entry => entry != key)
      if error.is_empty() {
        // The library changed; what the panel shows must come from disk,
        // not from a client-side guess. A result that outlived a focus
        // switch belongs to its old host; that host will refetch when it is
        // focused again.
        if channel == model.focused {
          (fetch_installed_skills(dispatch, channel), { ..model, skills_busy, })
        } else {
          (@cmd.none, { ..model, skills_busy, })
        }
      } else {
        (
          @cmd.none,
          {
            ..model,
            skills_busy,
            skills_notice: if channel == model.focused {
              error
            } else {
              model.skills_notice
            },
          },
        )
      }
    }
    Send => {
      let conv = model.active()
      let checkout = model.checkout_placement(conv)
      // The outgoing prompt is the typed text with the chips folded in as the
      // `<user_mentions>` envelope. Typed text is required — chips alone are
      // context without an instruction and stay in the composer.
      let task = compose_prompt(conv.mentions, conv.task).trim().to_owned()
      if !conv.draft_sendable() ||
        !(model.bridge_state() is Connected) ||
        !model.api_ready() ||
        checkout is None ||
        checkout is Some(@interop.MissingWorktree(_)) {
        (@cmd.none, model)
      } else if !(conv.sync is Synced) {
        // A prompt or steer submitted while the durable frontier is unknown
        // could make a delayed prior terminal look like this run's boundary.
        // Keep the draft until the single-flight snapshot settles.
        (@cmd.none, model)
      } else if conv.has_unresolved_run_tail_notice() {
        // The previous run's durable terminal is not proved yet. Starting or
        // steering another run would make its later terminal ambiguous.
        (@cmd.none, model)
      } else if conv.is_running() {
        // Submitting while this conversation's turn runs steers it: the text
        // is folded into the running turn at its next step boundary and
        // echoed back as a `steer_applied` event. A turn being cancelled
        // cannot be steered — the steer could outlive the dying turn in the
        // engine's queue and contaminate a later prompt — so the text stays
        // in the composer.
        if conv.run is Open(run_id~, stage~) &&
          !(stage is Cancelling) &&
          conv.run_durable_floor is Some(_) {
          let (model, submission_id) = model.allocate_submission_id()
          let conv = conv.enqueue_input(
            SteerInput,
            submission_id,
            Some(run_id),
            task,
            conv.task,
            conv.mentions,
          )
          (
            @cmd.batch([
              steer_openseek(
                dispatch,
                model.focused,
                conv.session_id,
                submission_id,
                task,
                run_id,
              ),
              scroll_transcript_after_render(),
            ]),
            {
              ..model.replace_conversation({ ..conv, task: "", mentions: [] }),
              transcript_pinned: true,
              completion: None,
            },
          )
        } else {
          (@cmd.none, model)
        }
      } else if !(conv.compaction is NotCompacting) {
        // A prompt submitted mid-compaction would sit in the serve engine's
        // queue behind it, where Stop (which cancels only the compaction)
        // cannot reach it — the user's cancel would not stop the submitted
        // work. A queued or just-requested compaction is the same gap one
        // step earlier: the command is on its way and compaction_started has
        // not yet arrived. The draft stays in the composer until the
        // compaction settles.
        (@cmd.none, model)
      } else {
        let (model, submission_id) = model.allocate_submission_id()
        // The worktree launch mode acts until a create has bound the
        // conversation; the eligibility must survive a rejected setup
        // attempt (see `wants_fresh_worktree`). Read before the ledger
        // entry below mutates the conversation.
        let fresh_worktree = conv.wants_fresh_worktree()
        let conv = conv.enqueue_input(
          InitialPrompt,
          submission_id,
          None,
          task,
          conv.task,
          conv.mentions,
        )
        let next = {
          ..conv,
          task: "",
          mentions: [],
          run: Starting(submission_id~),
          // The store may have advanced through an external CLI while this
          // page was idle. Only the real Started seam's causal snapshot may
          // establish this run's predecessor terminal floor.
          run_durable_floor: None,
          run_floor_generation: None,
          usage_tokens: 0,
        }
        // The worktree launch mode's first submit creates the environment
        // (the host names it, binds this conversation) and starts inside
        // it, as one command; every other submit is a plain start — a
        // bound session's cwd comes from the host's registry.
        let start_cmd = if fresh_worktree && conv.workspace is Some(workspace) {
          start_in_new_worktree(
            dispatch,
            model.focused,
            task,
            submission_id,
            conv.engine_model,
            model.max_steps,
            conv.session_id,
            workspace,
          )
        } else {
          start_openseek(
            dispatch,
            model.focused,
            task,
            submission_id,
            conv.engine_model,
            model.max_steps,
            conv.session_id,
            workspace=conv.workspace,
          )
        }
        (
          @cmd.batch([start_cmd, scroll_transcript_after_render()]),
          // Submitting is an explicit jump to the conversation's tail, so it
          // re-pins a transcript the user had scrolled away from.
          {
            ..model.replace_conversation(next),
            transcript_pinned: true,
            completion: None,
          },
        )
      }
    }
    Stop => {
      let conv = model.active()
      if conv.run is Open(run_id~, ..) {
        (
          cancel_openseek(dispatch, model.focused, run_id),
          model.replace_conversation({
            ..conv,
            run: Open(run_id~, stage=Cancelling),
          }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    NewChat =>
      // A fresh conversation can start at any time: the current one keeps
      // running in the background and stays one sidebar click away. It lands
      // in the active workspace — the one the on-screen conversation uses.
      (
        rotate_session(dispatch, model.focused),
        { ..model, loading_conversation: None },
      )
    NewChatIn(channel, workspace) => {
      // A workspace section's own "new chat": the fresh conversation lands in
      // that project, and the workspace stays active for the next one. A new
      // loose chat unfolds the Chats section so its row is visible; a new
      // workspace chat unfolds the Workspaces section for the same reason.
      // On the console, another device's ＋ first moves focus there.
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      (
        @cmd.batch([focus_cmd, rotate_session(dispatch, channel)]),
        {
          ..model.with_active_workspace(workspace),
          loading_conversation: None,
          chats_collapsed: model.chats_collapsed && workspace is Some(_),
          workspaces_collapsed: model.workspaces_collapsed && workspace is None,
        },
      )
    }
    ToggleWorktreeMode => {
      // Only a workspace conversation with no durable history (and no
      // bound environment yet) can still choose where its first prompt
      // runs. Durable emptiness, not `has_begun` — the toggle must stay
      // available after a rejected setup attempt's overlay notice, or the
      // user is locked into the failing mode.
      let conv = model.active()
      if conv.workspace is Some(_) &&
        conv.messages.length() == 0 &&
        conv.worktree is None {
        (
          @cmd.none,
          model.replace_conversation({
            ..conv,
            worktree_mode: !conv.worktree_mode,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    RetryWorktreePlacement => {
      let conv = model.active()
      guard model.checkout_placement(conv) is None &&
        conv.workspace is Some(workspace) &&
        model.device_state(conv.device) is Some(dev) else {
        return (@cmd.none, model)
      }
      let request_generation = dev.worktrees_request_generation + 1
      (
        fetch_worktrees(
          dispatch,
          conv.device,
          workspace,
          dev.connection_generation,
          request_generation,
        ),
        model.replace_device({
          ..dev,
          worktrees_request_generation: request_generation,
        }),
      )
    }
    RepairWorktree => {
      let conv = model.active()
      guard model.checkout_placement(conv) is Some(@interop.MissingWorktree(_)) &&
        conv.workspace is Some(workspace) else {
        return (@cmd.none, model)
      }
      (
        repair_worktree_cmd(
          dispatch,
          conv.device,
          workspace.path,
          conv.session_id,
        ),
        model,
      )
    }
    ConfirmArchiveDiscard =>
      match model.archive_confirm {
        Some(confirm) => {
          // The dialog's confirm IS the force: retry the archive discarding
          // the worktree's uncommitted changes. Same generation dance as
          // the plain archive click.
          guard model.device_state(confirm.channel) is Some(dev) else {
            return (@cmd.none, { ..model, archive_confirm: None })
          }
          let sessions_request_generation = dev.sessions_request_generation + 1
          let archived_request_generation = dev.archived_request_generation + 1
          (
            archive_session(
              dispatch,
              confirm.channel,
              confirm.session,
              dev.connection_generation,
              sessions_request_generation,
              archived_request_generation,
              force=true,
            ),
            {
              ..model.replace_device({
                ..dev,
                sessions_request_generation,
                archived_request_generation,
              }),
              archive_confirm: None,
            },
          )
        }
        None => (@cmd.none, model)
      }
    CancelArchiveDiscard => (@cmd.none, { ..model, archive_confirm: None })
    SessionRotated(owner) => {
      // A delayed rotation is owned by the channel that requested it. A focus
      // switch overtakes it; activating the old owner's id here would yank the
      // user back to the host they already left.
      guard owner.channel == model.focused &&
        model.device_state(owner.channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let activated = model.activate(owner.channel, owner.session)
      // A rotation creates the conversation, so stamp it with the workspace
      // it was asked into; an existing conversation keeps its own.
      let conversations = activated.conversations.map(conv => {
        if conv.device == owner.channel &&
          conv.session_id == owner.session &&
          conv.messages.length() == 0 &&
          !conv.is_running() {
          { ..conv, workspace: dev.active_workspace }
        } else {
          conv
        }
      })
      (
        @cmd.none,
        {
          ..activated,
          conversations,
          screen: Chat,
          transcript_pinned: true,
          loading_conversation: None,
          completion: None,
        },
      )
    }
    PickWorkspace(channel) => {
      // Focus moves for the surrounding UI, while the picker itself keeps
      // `channel` as its owner through every later navigation and confirm.
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      let picker = opening_workspace_picker(channel)
      (
        @cmd.batch([
          focus_cmd,
          browse_directory(dispatch, channel, "", generation=picker.generation),
        ]),
        { ..model, workspace_picker: Some(picker) },
      )
    }
    WorkspacePickerNavigate(path) =>
      match model.workspace_picker {
        Some(picker) => {
          let generation = picker.generation + 1
          (
            browse_directory(dispatch, picker.channel, path, generation~),
            {
              ..model,
              workspace_picker: Some({ ..picker, loading: true, generation }),
            },
          )
        }
        None => (@cmd.none, model)
      }
    WorkspacePickerLoaded(channel~, path~, entries~, generation~) =>
      // A listing for a picker the user already closed — or one answering
      // a navigation that has since been superseded — is dropped. The
      // go-to field clears on arrival: the breadcrumb shows the location,
      // and the field is for typing the next jump.
      match model.workspace_picker {
        Some(picker) if picker.channel == channel &&
          picker.generation == generation =>
          (
            @cmd.none,
            {
              ..model,
              workspace_picker: Some({
                channel,
                path: Some(path),
                entries,
                input: "",
                loading: false,
                error: None,
                generation,
              }),
            },
          )
        _ => (@cmd.none, model)
      }
    WorkspacePickerFailed(channel~, message~, generation~) =>
      match model.workspace_picker {
        Some(picker) if picker.channel == channel &&
          picker.generation == generation =>
          (
            @cmd.none,
            {
              ..model,
              workspace_picker: Some({
                ..picker,
                loading: false,
                error: Some(message),
              }),
            },
          )
        _ => (@cmd.none, model)
      }
    WorkspacePickerInput(text) =>
      match model.workspace_picker {
        Some(picker) =>
          (
            @cmd.none,
            { ..model, workspace_picker: Some({ ..picker, input: text }) },
          )
        None => (@cmd.none, model)
      }
    WorkspacePickerConfirm =>
      match model.workspace_picker {
        // Confirm registers the directory the host last listed — always
        // something it confirmed exists — never raw field text; Enter in
        // the field navigates (and validates) first.
        Some(picker) if picker.path is Some(path) =>
          (
            add_workspace(dispatch, picker.channel, path.path),
            { ..model, workspace_picker: None },
          )
        _ => (@cmd.none, model)
      }
    WorkspacePickerClose => (@cmd.none, { ..model, workspace_picker: None })
    RemoveWorkspace(channel, path) =>
      if @resource.belongs_to(path, channel) {
        (remove_workspace(dispatch, channel, path.path), model)
      } else {
        (@cmd.none, model)
      }
    ArchiveSession(channel, session_id) => {
      // Archiving acts on the row's own device and never moves focus.
      guard model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      (
        archive_session(
          dispatch,
          channel,
          session_id,
          dev.connection_generation,
          sessions_request_generation,
          archived_request_generation,
        ),
        model.replace_device({
          ..dev,
          sessions_request_generation,
          archived_request_generation,
        }),
      )
    }
    UnarchiveSession(channel, session_id) => {
      guard model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      (
        unarchive_session(
          dispatch,
          channel,
          session_id,
          dev.connection_generation,
          sessions_request_generation,
          archived_request_generation,
        ),
        model.replace_device({
          ..dev,
          sessions_request_generation,
          archived_request_generation,
        }),
      )
    }
    NotificationClicked(run_id~) => {
      // The run has finished by the time its notification is clicked, so the
      // owner usually matches by last run id; a still-running owner (steered
      // runs re-notify per turn) matches by active run.
      let conv = if model.conversation_by_last_run(model.focused, run_id)
        is Some(conv) {
        Some(conv)
      } else {
        model.conversation_by_run(model.focused, run_id)
      }
      if conv is Some(conv) {
        update_msg(dispatch, OpenSession(conv.device, conv.session_id), model)
      } else {
        (@cmd.none, model)
      }
    }
    OpenSession(channel, session_id) =>
      // Selecting a conversation always returns to the chat — including
      // re-selecting the active one from the Skills page. On the console a
      // click in another device's group is also the focus switch: the
      // focused-scoped mirrors refetch, then the open runs on that channel.
      if session_id.is_empty() {
        (@cmd.none, model)
      } else {
        // A row click that raced its device's removal has nowhere to go.
        guard model.device_state(channel) is Some(_) else {
          return (@cmd.none, model)
        }
        let (focus_cmd, model) = focus_channel(dispatch, model, channel)
        let (cmd, model) = open_session_on(dispatch, channel, model, session_id)
        (@cmd.batch([focus_cmd, cmd]), model)
      }
    TranscriptPinned(pinned) =>
      (@cmd.none, { ..model, transcript_pinned: pinned })
    // Pin eagerly so the button hides on the click's own render; the scroll
    // watcher would only confirm it after the scroll settles.
    JumpToLatest =>
      (scroll_transcript_after_render(), { ..model, transcript_pinned: true })
    ColorSchemeChanged(dark) => {
      let model = { ..model, system_dark: dark }
      match model.theme {
        System => (System.apply(dark), model)
        Light | Dark => (@cmd.none, model)
      }
    }
    ThemeChanged(value) => {
      let theme = Theme::parse(value, model.theme)
      if theme == model.theme {
        (@cmd.none, model)
      } else {
        (
          @cmd.batch([theme.apply(model.system_dark), theme.save()]),
          { ..model, theme, },
        )
      }
    }
    OpenFile(path) => {
      // A relative path is taken against the active conversation's working
      // directory: its `cwd` for a live run, or — when resumed without one —
      // the directory the host derives from the session id. Absolute paths
      // open directly. No workspace containment — the agent surfaced it.
      let conv = model.active()
      (
        open_file(dispatch, model.focused, conv.session_id, cwd=conv.cwd, path),
        model,
      )
    }
    ToggleGitDetails => {
      let opening = !model.git_details_open
      let model = { ..model, git_details_open: opening }
      guard opening else { return (@cmd.none, model) }
      // Opening it is a request for current information, and everything it
      // shows goes stale on its own: CI finishes minutes after the run that
      // started it, and the working tree keeps moving. Nothing else looks
      // again until the next run, so without this the chip's tint can sit on
      // "running" long after the checks settled.
      //
      // The branch probe is the refresh — it re-counts the lines and, through
      // its reply, re-runs the pull-request lookup, which is the same path
      // every run boundary takes, in-flight fencing and all.
      let conv = model.active()
      probe_branch(dispatch, model, conv.device, conv.session_id, conv.cwd)
    }
    CloseGitDetails => (@cmd.none, { ..model, git_details_open: false })
    CloseLauncher =>
      (@cmd.none, { ..model, launcher: { ..model.launcher, open: false } })
    CloseDockMenu =>
      (@cmd.none, { ..model, dock: @dock.close_menu(model.dock) })
    ToggleLauncher => {
      let opening = !model.launcher.open
      // The launcher exists only in the desktop window, whose one native
      // host is Local. Installed apps are host-global, while the workspace
      // is supplied later to app.launch.
      let (cmd, apps) = if opening {
        match model.launcher.apps {
          AppsNotFetched | AppsFailed(_) => (fetch_apps(dispatch), AppsLoading)
          AppsLoading | AppsFetched(_) => (@cmd.none, model.launcher.apps)
        }
      } else {
        (@cmd.none, model.launcher.apps)
      }
      (cmd, { ..model, launcher: { open: opening, apps } })
    }
    LauncherLoaded(apps) => {
      // Only the one outstanding Local probe may settle the catalog. A
      // duplicate or delayed reply after it settled cannot overwrite it.
      guard model.launcher.apps is AppsLoading else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFetched(apps) } },
      )
    }
    LauncherFailed(message) => {
      guard model.launcher.apps is AppsLoading else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFailed(message) } },
      )
    }
    LaunchApp(app) => {
      let conv = model.active()
      (
        launch_app(dispatch, conv.session_id, cwd=conv.cwd, app),
        { ..model, launcher: { ..model.launcher, open: false } },
      )
    }
    FileEditor(msg) => {
      let (cmd, panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        msg,
        model.file_panel,
        file_ctx(model),
      )
      let next = { ..model, file_panel: panel }
      let next = match msg {
        @fileeditor.FilesIndexed(..) => refresh_file_quick_open(next)
        @fileeditor.FileIndexFailed(..) => fail_file_quick_open(next)
        _ => next
      }
      (cmd, next)
    }
    Dock(msg) => {
      // The strip machine is pure; the cross-package effects of the
      // transition — showing or dropping documents, mounting hosts — are
      // commanded here off the before/after difference.
      let before = model.dock
      let dock = @dock.update(msg, before)
      let model = { ..model, dock, }
      let femit = dispatch.map(msg => FileEditor(msg))
      match msg {
        TogglePanel => {
          let (cmd, panel) = @fileeditor.panel_toggle_cmds(
            femit,
            model.file_panel,
            file_ctx(model),
            opening=dock.open,
          )
          (cmd, { ..model, file_panel: panel })
        }
        MenuToggled =>
          // Pure UI state; the browser sync pass hides the native view
          // while the popup would overlap it.
          (@cmd.none, model)
        TabActivated(_) =>
          if dock.active != before.active &&
            @dock.active_file(dock) is Some(path) {
            let cmds : Array[@cmd.Cmd] = []
            if @dock.active_file(before) is None {
              // The file body was CSS-hidden behind the browser pane or
              // the picker overlay; the viewer must re-measure its host on
              // return.
              cmds.push(@fileeditor.request_viewer_remeasure())
            }
            let (cmd, panel) = @fileeditor.activate(
              femit,
              model.file_panel,
              file_ctx(model),
              path,
            )
            cmds.push(cmd)
            (@cmd.batch(cmds), { ..model, file_panel: panel })
          } else {
            (@cmd.none, model)
          }
        TabClosed(tab) =>
          // A stale close (racing another close) leaves the strip — and so
          // the document table — untouched.
          if before.tabs.search_by(entry => entry == tab) is Some(_) {
            // When the closed tab was on screen and a file tab inherits it,
            // its document must be shown; a file close routes through
            // close_document (which also drops the document), the other
            // kinds activate directly.
            let next_file = @dock.active_file(dock)
            let was_active = before.active == Some(tab)
            match tab {
              File(path~) => {
                let (cmd, panel) = @fileeditor.close_document(
                  femit,
                  model.file_panel,
                  file_ctx(model),
                  path,
                  next=next_file,
                  was_active~,
                )
                (cmd, { ..model, file_panel: panel })
              }
              Browser(id~) => {
                let cmds : Array[@cmd.Cmd] = [browser_close_view(dispatch, id)]
                let model = {
                  ..model,
                  preview: @preview.close_page(model.preview, id),
                }
                if was_active && next_file is Some(path) {
                  cmds.push(@fileeditor.request_viewer_remeasure())
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    path,
                  )
                  cmds.push(cmd)
                  (@cmd.batch(cmds), { ..model, file_panel: panel })
                } else {
                  (@cmd.batch(cmds), model)
                }
              }
              FilePicker =>
                if was_active && next_file is Some(path) {
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    path,
                  )
                  (cmd, { ..model, file_panel: panel })
                } else {
                  (@cmd.none, model)
                }
            }
          } else {
            (@cmd.none, model)
          }
      }
    }
    Preview(msg) =>
      (@cmd.none, { ..model, preview: @preview.update(msg, model.preview) })
    BrowserTabRequested => {
      let (preview, id) = @preview.open_page(model.preview)
      let dock = @dock.close_menu(@dock.open_browser(model.dock, id))
      (focus_browser_address(), { ..model, preview, dock })
    }
    FilePickerRequested => {
      let dock = @dock.close_menu(@dock.open_picker(model.dock))
      let next = { ..model, dock, }
      let (cmd, file_panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        @fileeditor.ExplorerModeSelected(ExplorerFiles),
        next.file_panel,
        file_ctx(next),
      )
      (cmd, { ..next, file_panel, })
    }
    ReviewRequested => {
      let dock = @dock.close_menu(@dock.open_picker(model.dock))
      let next = { ..model, dock, }
      let (cmd, file_panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        @fileeditor.ExplorerModeSelected(ExplorerChanges),
        next.file_panel,
        file_ctx(next),
      )
      (cmd, { ..next, file_panel, })
    }
    BrowserAddressEdited(value) =>
      match @dock.active_browser(model.dock) {
        Some(id) =>
          (
            @cmd.none,
            {
              ..model,
              preview: @preview.update(
                @preview.Msg::InputChanged(id~, value~),
                model.preview,
              ),
            },
          )
        None => (@cmd.none, model)
      }
    BrowserNavigateSubmitted => {
      guard @dock.active_browser(model.dock) is Some(id) &&
        @preview.page(model.preview, id) is Some(page) &&
        @preview.normalize_url(page.input) is Some(url) else {
        return (@cmd.none, model)
      }
      // A blank tab's first navigation creates the native view; later ones
      // navigate the existing view.
      let (cmd, pane) = if page.url is Some(_) {
        // `browser.navigate` builds the view back when it is gone — a create
        // the host refused, or one a reload's `close_all` swept — and a
        // rebuilt view arrives hidden at a placeholder size. No view op is
        // acknowledged, so the cached placement may describe a view that
        // never existed; forgetting it has the next sync measure and place
        // whatever the host actually has now.
        (
          browser_navigate(dispatch, id, url),
          { shown: None, rect: None, geo: None },
        )
      } else {
        // The blank tab's own placement is already absent (a page without a
        // URL is never the desired view), so the create needs no reset.
        (browser_open(dispatch, id, url), model.browser_pane)
      }
      (
        cmd,
        {
          ..model,
          preview: @preview.navigate(model.preview, id, url),
          browser_pane: pane,
        },
      )
    }
    BrowserBack =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_back),
        model,
      )
    BrowserForward =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_forward),
        model,
      )
    BrowserReload =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_reload),
        model,
      )
    BrowserOpenExternal => {
      guard @dock.active_browser(model.dock) is Some(id) &&
        @preview.page(model.preview, id) is Some(page) &&
        page.url is Some(url) else {
        return (@cmd.none, model)
      }
      (open_external_link(dispatch, url), model)
    }
    BrowserPaneMeasured(rect~) => {
      // A rectangle for a view that already left the screen (or a zero
      // rectangle from the observer watching a hidden pane) is stale.
      guard desired_browser_view(model) is Some(id) &&
        rect.width > 0 &&
        rect.height > 0 else {
        return (@cmd.none, model)
      }
      let pane = model.browser_pane
      let cmds : Array[@cmd.Cmd] = []
      if pane.rect != Some(rect) || pane.shown != Some(id) {
        cmds.push(browser_set_bounds(dispatch, id, rect))
      }
      if pane.shown != Some(id) {
        // Bounds land before visibility so the view never flashes at its
        // previous place.
        if pane.shown is Some(old) {
          cmds.push(browser_set_visible(dispatch, old, false))
        }
        cmds.push(browser_set_visible(dispatch, id, true))
      }
      (
        @cmd.batch(cmds),
        { ..model, browser_pane: { ..pane, shown: Some(id), rect: Some(rect) } },
      )
    }
    Terminal(msg) => {
      // xterm is an imperative widget rather than document anchor markup, so
      // its web-links addon reports activation as a terminal message. Feed it
      // back through the exact conversation-link route: desktop Chat opens or
      // reuses a dock browser tab, while other hosts/screens open externally.
      if msg is LinkActivated(url~) {
        return update(dispatch, ExternalLinkClicked(url), model)
      }
      // Host-originated replies and notifications can already be queued when
      // a WebSocket closes. Their terminal ids belong to the dead connection,
      // not to a later connection for the same relay device, so ignore them
      // from the first loss onward. User actions carry a tab key instead and
      // continue through the terminal state machine normally.
      let owner_live = match msg {
        Opened(channel~, key=_, id=_)
        | Output(channel~, id=_, sequence=_, data=_)
        | OutputRendered(channel~, id=_, sequence=_)
        | SessionExited(channel~, id=_, code=_) =>
          match model.device_state(channel) {
            Some(dev) => dev.bridge is Connected && dev.reconnect_failures == 0
            None => false
          }
        _ => true
      }
      guard owner_live else { return (@cmd.none, model) }
      let (cmd, panel) = @terminal.update(
        dispatch.map(msg => Terminal(msg)),
        msg,
        model.terminal_panel,
        terminal_ctx(model),
      )
      let model = { ..model, terminal_panel: panel }
      // A rejected input means those keystrokes were lost; keep the session
      // alive, but surface the transport error on the app's toast rail.
      match msg {
        InputFailed(key=_, message~) => {
          let (toast, next) = model.notify_error(dispatch, message)
          (@cmd.batch([cmd, toast]), next)
        }
        _ => (cmd, model)
      }
    }
    HostActionFailed(message) => model.notify_error(dispatch, message)
    ExternalLinkClicked(url) =>
      // Web links open in the dock's Browser tabs by default — the
      // toolbar's open-external button hands the page to the system
      // browser when its chrome or logins are needed. Non-web schemes
      // (mailto:, vscode:, …) and remote consoles (no native views) keep
      // the external path. A same-URL tab already in this strip
      // re-activates instead of duplicating.
      //
      // Only from Chat: the capture listener behind this message is a
      // document-wide one, so it also reports anchors on the other screens,
      // where the dock is not rendered at all — routing there would open a
      // tab nobody can see. Settings' device-page link is the clearest
      // case: it names a URL to open in a browser the user is signed in to,
      // which a native view (with its own cookie jar) is not.
      if model.is_desktop && model.screen is Chat && @preview.is_web_url(url) {
        // The scan is over this strip's tabs, not the global page map: a
        // parked conversation may hold the same URL, and matching its page
        // first would shadow this strip's own tab forever.
        let reuse = for tab in model.dock.tabs {
          if tab is Browser(id~) &&
            @preview.page(model.preview, id) is Some(page) &&
            page.url == Some(url) {
            break Some(id)
          }
        } nobreak {
          None
        }
        match reuse {
          Some(id) => {
            let dock = { ..@dock.open_browser(model.dock, id), open: true }
            (@cmd.none, { ..model, dock, })
          }
          None => {
            let (preview, id) = @preview.open_page(model.preview, url~)
            let dock = { ..@dock.open_browser(model.dock, id), open: true }
            (browser_open(dispatch, id, url), { ..model, preview, dock })
          }
        }
      } else {
        (open_external_link(dispatch, url), model)
      }
    FromDevice(channel, msg) => update_device_msg(dispatch, channel, msg, model)
  }
}
