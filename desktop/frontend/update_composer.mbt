// Composer, completion, mention, and editor-jump transitions.

///|
/// Apply an accepted completion row: a slash command runs its action, while a
/// skill mention or symbol reference becomes a chip in the composer's mention
/// tray (its expansion is spliced into the prompt on send). Either way the menu
/// closes and only the typed trigger token is removed from the textarea.
fn accept_completion(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  menu : Completion,
  item : CompletionItem,
) -> (@cmd.Cmd, Model) {
  match menu.kind {
    SlashCommands => run_slash_command(dispatch, model, item.command)
    // The chip carries its envelope form directly: the skill's bare name (its
    // `insert` has a trailing space), or the symbol's name plus resolved
    // location.
    SkillMentions =>
      accept_mention(
        model,
        Skill(name=item.insert.trim().to_owned()),
        range=None,
        task=menu.task_without_token,
      )
    Symbols => {
      let (file, line) = if item.path is Some(path) && item.range is Some(range) {
        (path, range.start_line_number)
      } else {
        ("", 0)
      }
      accept_mention(
        model,
        Symbol(name=item.label, file~, line~),
        range=item.range,
        task=menu.task_without_token,
      )
    }
  }
}

///|
/// Attach a mention chip to the active conversation's draft (deduplicated),
/// remove the typed trigger token while preserving preceding prompt text, and
/// close the menu.
fn accept_mention(
  model : Model,
  ref_ : @mention_context.MentionRef,
  range~ : @common.Range?,
  task~ : String,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let mentions = push_mention(conv.mentions, { ref_, range })
  (
    @cmd.none,
    {
      ..model.replace_conversation({ ..conv, task, mentions }),
      completion: None,
    },
  )
}

///|
/// A chip's raw jump path as the workspace-relative form the panel and the
/// host's workspace-rooted ops speak. The steady state is the identity: chips
/// minted since the panel started recording relative names are already
/// relative. A legacy envelope can still carry an absolute path (minted
/// before `cwd` was known); those are brought back inside against the
/// conversation's roots, and `None` — an absolute path outside anything this
/// conversation knows — means there is nothing the panel could open.
fn conversation_relative(
  conv : Conversation,
  path : String,
) -> @pathx.Relative? {
  guard @resource.of_path(conv.device, path) is Some(absolute) else {
    // A string that is not a complete absolute path keeps its existing
    // workspace-relative interpretation.
    return Some(Relative(path))
  }
  for root in [conv.cwd, conv.workspace] {
    if root is Some(root) &&
      @resource.relative_to(absolute, root) is Some(rest) &&
      !rest.is_root() {
      return Some(rest)
    }
  }
  None
}

///|
/// Open (or refocus) the editor side-panel on `path`, revealing `range` when
/// given — the shared tail of a composer chip's and a transcript chip's jump.
/// The raw path comes from a chip or envelope; a legacy absolute one that
/// cannot be brought inside the workspace surfaces as a panel error instead
/// of a bogus host read.
fn open_editor_at(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
  range : @common.Range?,
  annotation? : String,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let placement = model.checkout_placement(conv)
  // Chip/transcript jumps call the file-editor package directly rather than
  // passing through its guarded message dispatcher. Keep them parked too: the
  // dock must not grow a loading tab, nor may a host read start, while checkout
  // placement is unresolved or missing.
  guard !(placement is None || placement is Some(@interop.MissingWorktree(_))) else {
    return (@cmd.none, model)
  }
  let owner : @interop.ConversationKey = {
    channel: model.focused,
    session: conv.session_id,
  }
  let femit = dispatch.map(msg => FileEditor(msg))
  // Park/restore the strip for a conversation switch up front, and re-root
  // the file subsystem when its cached tree belongs to another conversation;
  // otherwise `sync_file_panel`'s post-dispatch pass would see a session
  // mismatch and wipe the freshly opened tab below. A re-rooted document
  // table is seeded from the restored strip (identities only), exactly like
  // `@fileeditor.sync`'s own re-root.
  let dock = @dock.sync(model.dock, owner)
  let previous_panel = model.file_panel
  let panel = if previous_panel.owner == Some(owner) {
    previous_panel
  } else {
    let docs : Map[@pathx.Relative, @fileeditor.Doc] = Map([])
    for open_path in @dock.file_paths(dock) {
      docs[open_path] = {
        name: @fileeditor.basename(open_path),
        state: TabLoading,
        review: None,
        stale: false,
      }
    }
    {
      ..@fileeditor.State::empty(),
      owner: Some(owner),
      // Mirror fileeditor.sync's re-root invariants. In particular, the
      // generation must outlive an A→B→A jump so an older A reply cannot
      // collide with the next request after this eager re-root.
      tree_open: previous_panel.tree_open,
      explorer_mode: previous_panel.explorer_mode,
      review_view_mode: previous_panel.review_view_mode,
      changes_generation: previous_panel.changes_generation,
      request_epoch: previous_panel.request_epoch + 1,
      review_generation: previous_panel.review_generation,
      // Preserve the old host configuration until the post-dispatch sync can
      // explicitly retire or replace it.
      watching: previous_panel.watching,
      docs,
    }
  }
  guard conversation_relative(conv, path) is Some(relative) else {
    return (
      @fileeditor.mount_cmds(femit),
      {
        ..model,
        dock: { ..dock, open: true },
        file_panel: {
          ..panel,
          error: Some("\{path} is outside the conversation workspace"),
        },
      },
    )
  }
  let had_active = @dock.active_file(dock) is Some(_)
  // An explicit open while the picker is the active tab fulfills it, the
  // same as a pick from its tree.
  let dock = if dock.active is Some(FilePicker) {
    { ..@dock.resolve_pick(dock, relative), open: true }
  } else {
    { ..@dock.open_file(dock, relative), open: true }
  }
  let model = { ..model, dock, file_panel: panel }
  let (cmd, panel) = @fileeditor.open_file(
    femit,
    panel,
    file_ctx(model),
    relative,
    range~,
    annotation?,
    had_active~,
  )
  (cmd, { ..model, file_panel: panel })
}

///|
/// The command, if any, to fetch workspace symbols for a changed draft. Fires
/// only when the draft ends in a live `#` query whose results are not already
/// cached for this conversation — so a fresh keystroke refetches but a repeat
/// of the same query does not.
fn symbol_fetch_cmd(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  value : String,
  owner : @interop.ConversationKey,
) -> @cmd.Cmd {
  guard CompletionTrigger::parse(value) is Some(trigger) &&
    trigger.kind is Symbols else {
    return @cmd.none
  }
  let query = trigger.query
  if model.symbol_cache.owner == Some(owner) &&
    model.symbol_cache.query == query {
    return @cmd.none
  }
  read_workspace_symbols(
    dispatch,
    owner,
    query,
    workspace=model.session_workspace(owner.channel, owner.session),
  )
}

///|
/// Fold a workspace-symbol reply into the model: cache it and rebuild the menu,
/// but only while it still answers the composer's live `#` query for the active
/// conversation — a reply overtaken by a conversation switch or a later
/// keystroke is dropped, the same staleness guard the file panel uses.
fn apply_symbol_reply(
  model : Model,
  owner : @interop.ConversationKey,
  query : String,
  symbols : Array[WorkspaceSymbol],
) -> (@cmd.Cmd, Model) {
  let draft = model.active().task
  guard owner.channel == model.focused &&
    owner.session == model.active().session_id &&
    CompletionTrigger::parse(draft) is Some(trigger) &&
    trigger.kind is Symbols &&
    trigger.query == query else {
    return (@cmd.none, model)
  }
  let items : Array[CompletionItem] = []
  for symbol in symbols {
    items.push(symbol.completion_item())
  }
  let cache : SymbolCache = { owner: Some(owner), query, items }
  (
    @cmd.none,
    {
      ..model,
      symbol_cache: cache,
      completion: compute_completion(
        draft,
        model.installed_skills,
        cache,
        owner,
      ),
    },
  )
}

///|
/// Run an accepted slash command against the active conversation and close the
/// completion menu. The command text is cleared from the composer; an unknown
/// id just dismisses the menu.
fn run_slash_command(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  command : String,
) -> (@cmd.Cmd, Model) {
  match command {
    "compact" => {
      let conv = model.active()
      // One compaction at a time: a repeat while one is queued or in flight
      // would stack another behind it in the engine's pending queue (the
      // host rejects it anyway) — swallow it like any settled command.
      if !(conv.compaction is NotCompacting) {
        (
          @cmd.none,
          {
            ..model.replace_conversation({ ..conv, task: "" }),
            completion: None,
          },
        )
      } else {
        (
          compact_openseek(
            dispatch,
            model.focused,
            session=conv.session_id,
            model=conv.engine_model,
            max_steps=model.max_steps,
            workspace?=conv.workspace,
          ),
          {
            ..model.replace_conversation({
              ..conv,
              task: "",
              // Hold the send gate before the host answers: mid-turn the
              // command queues behind the open run, and an idle request may
              // sit in the spawn/write window for seconds (a resumed
              // conversation gets its engine spawned on demand) — a prompt
              // sent into either gap would be consumed and rejected instead
              // of held. compaction_started confirms; CompactRejected clears.
              compaction: if conv.is_running() {
                Queued
              } else {
                Requested
              },
            }),
            completion: None,
          },
        )
      }
    }
    _ => (@cmd.none, { ..model, completion: None })
  }
}

///|
test "a symbol reply with the same session id but another channel is stale" {
  let dispatch = test_dispatch()
  let local_owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let remote_owner : @interop.ConversationKey = {
    channel: Remote("d-remote"),
    session: "desktop-test",
  }
  let (_, querying) = update(dispatch, TaskChanged("#parse"), test_model())
  let items : Array[WorkspaceSymbol] = [
    {
      name: "parse_file",
      kind: Some(12),
      container: None,
      path: "src/main.mbt",
      range: @common.Range::Range(1, 1, 1, 1),
    },
  ]
  let (_, stale) = update(
    dispatch,
    SymbolsLoaded(owner=remote_owner, query="parse", items~),
    querying,
  )
  guard stale.completion is Some(stale_menu) else {
    fail("symbol menu disappeared")
  }
  assert_true(stale_menu.loading)
  let (_, settled) = update(
    dispatch,
    SymbolsLoaded(owner=local_owner, query="parse", items~),
    stale,
  )
  guard settled.completion is Some(menu) else {
    fail("symbol menu disappeared")
  }
  assert_false(menu.loading)
  inspect(menu.items[0].label, content="parse_file")
}

///|
test "concurrent conversations keep their streams apart" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    run: Open(run_id="r8", stage=Opened),
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r8"), AssistantDelta("for B"), session=None),
    model,
  )
  // Run 8 belongs to the background conversation; the active one is untouched.
  inspect(next.active().streaming_response, content="")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.streaming_response, content="for B")
}

///|
test "a background run finishes without disturbing the conversation on screen" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    run: Open(run_id="r8", stage=Opened),
    messages: [{ kind: User, content: "background ask", ts: None }],
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r8",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.is_running(), content="false")
  assert_true(bg.run is NoRun(ended=Some(RunFinished(_))))
  inspect(bg.overlay.length(), content="0")
  // The conversation on screen is still running its own turn.
  inspect(next.active().is_running(), content="true")
  assert_true(next.display_status() is Running)
}

///|
test "send while running queues a steer instead of a prompt" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    task: "focus on the tests",
  })
  let (_, once) = update(dispatch, Send, model)
  let (_, twice) = update(dispatch, Send, model)
  inspect(once.active().task, content="")
  inspect(once.active().pending_steers().length(), content="1")
  inspect(once.active().pending_steers()[0], content="focus on the tests")
  // The steer is pending, not part of the transcript yet.
  inspect(once.active().messages.length(), content="0")
  inspect(once.active().is_running(), content="true")
  inspect(twice.active().pending_steers().length(), content="1")
  inspect(twice.active().pending_steers()[0], content="focus on the tests")
}

///|
test "a cancelling turn cannot be steered; the text stays in the composer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id="r7", stage=Cancelling),
    task: "too late",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="too late")
  inspect(next.active().pending_steers().length(), content="0")
}

///|
test "the composer draft stays with its conversation across a switch" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    messages: [{ kind: User, content: "earlier", ts: None }],
  })
  let (_, drafted) = update(dispatch, TaskChanged("half a thought"), model)
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-second"),
    drafted,
  )
  // The other conversation starts with its own (empty) draft …
  inspect(switched.active().task, content="")
  let (_, back) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    switched,
  )
  // … and the original draft is still waiting where it was typed.
  inspect(back.active().task, content="half a thought")
}

///|
test "update is pure: accepting an inline skill preserves prompt text" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    installed_skills: [installed_skill("review-pr", "Review a pull request")],
  }
  let (_, drafted) = update(dispatch, TaskChanged("Please use $rev"), model)
  guard drafted.completion is Some(menu) else {
    fail("the inline skill token should open completion")
  }
  assert_eq(menu.task_without_token, "Please use ")
  let (_, once) = update(dispatch, CompletionAccept, drafted)
  let (_, twice) = update(dispatch, CompletionAccept, drafted)
  // The same message and model always produce the same plain-data state.
  assert_eq(once.active().task, "Please use ")
  assert_eq(twice.active().task, "Please use ")
  assert_eq(once.active().mentions.length(), 1)
  assert_eq(twice.active().mentions.length(), 1)
  assert_true(
    once.active().mentions[0].ref_ is Skill(name="review-pr") &&
    twice.active().mentions[0].ref_ is Skill(name="review-pr"),
  )
  assert_true(once.completion is None && twice.completion is None)
}

///|
test "an inline symbol reply rebuilds the live completion menu" {
  let dispatch = test_dispatch()
  let (_, searching) = update(
    dispatch,
    TaskChanged("Inspect #parse"),
    test_model(),
  )
  guard searching.completion is Some(pending) else {
    fail("the inline symbol token should open completion")
  }
  assert_true(pending.kind is Symbols)
  assert_true(pending.loading)
  assert_eq(pending.task_without_token, "Inspect ")
  let item : WorkspaceSymbol = {
    name: "parse_hover",
    kind: Some(12),
    container: None,
    path: "src/main.mbt",
    range: @common.Range::Range(4, 2, 4, 13),
  }
  let (_, loaded) = update(
    dispatch,
    SymbolsLoaded(
      owner={ channel: Local, session: "desktop-test" },
      query="parse",
      items=[item],
    ),
    searching,
  )
  guard loaded.completion is Some(menu) else {
    fail("the matching inline symbol reply should rebuild completion")
  }
  assert_false(menu.loading)
  assert_eq(menu.items.length(), 1)
  assert_eq(menu.items[0].label, "parse_hover")
  assert_eq(menu.task_without_token, "Inspect ")
}

///|
test "file editor context reports the file body actual visibility" {
  let model = test_model()
  let path = @pathx.Relative("src/main.mbt")
  let file_model = {
    ..model,
    dock: {
      ..model.dock,
      open: true,
      tabs: [File(path~)],
      active: Some(File(path~)),
    },
  }
  assert_true(file_ctx(file_model).panel_open)
  assert_false(
    file_ctx({ ..file_model, dock: { ..file_model.dock, open: false } }).panel_open,
  )
  let picker_model = {
    ..file_model,
    dock: { ..file_model.dock, tabs: [FilePicker], active: Some(FilePicker) },
  }
  assert_true(file_ctx(picker_model).panel_open)
  let browser_model = {
    ..file_model,
    dock: {
      ..file_model.dock,
      tabs: [Browser(id=1)],
      active: Some(Browser(id=1)),
    },
  }
  assert_false(file_ctx(browser_model).panel_open)
  let launcher_model = {
    ..file_model,
    dock: { ..file_model.dock, tabs: [], active: None },
  }
  assert_false(file_ctx(launcher_model).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Skills }).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Settings }).panel_open)
}

///|
test "JumpToMention opens the editor panel and selects the mention's file" {
  let dispatch = test_dispatch()
  let mention : Mention = {
    ref_: Symbol(name="parse_hover", file="src/main.mbt", line=5),
    range: Some(@common.Range::Range(5, 1, 5, 12)),
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_true(next.dock.open)
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  // The document table follows the strip: the jumped-to file has an entry.
  assert_true(next.file_panel.docs.contains(Relative("src/main.mbt")))
}

///|
test "JumpToMention is a no-op for a chip without a resolved location" {
  let dispatch = test_dispatch()
  let mention : Mention = { ref_: Skill(name="review-pr"), range: None }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.dock.open)
  assert_true(next.dock.active is None)
}

///|
test "EditorCommentAdded attaches a deduplicated annotation chip" {
  let dispatch = test_dispatch()
  let model = test_model()
  let absolute = @interop.ChannelId::Local.test_resource(
    "/work/project/src/main.mbt",
  )
  // The chip path arrives workspace-relative from the panel (recorded when
  // the file was shown); the resource URI only routes the bubble removal.
  let msg : Msg = FileEditor(
    EditorCommentAdded(
      resource=@fileeditor.ModelUri::of(absolute),
      file=Relative("src/main.mbt"),
      range=@common.Range::Range(5, 1, 6, 3),
      quote="fn parse_hover() {",
      comment="rename this",
      feedback_id="viewer-feedback-0",
    ),
  )
  let (_, next) = update(dispatch, msg, model)
  let mentions = next.active().mentions
  assert_eq(mentions.length(), 1)
  assert_true(
    mentions[0].ref_
    is Annotation(file="src/main.mbt", start_line=5, end_line=6, ..),
  )
  // Submitting the identical comment again is a no-op, not a second chip.
  let (_, again) = update(dispatch, msg, next)
  assert_eq(again.active().mentions.length(), 1)
}

///|
test "UnifiedDiffCommentAdded preserves modified and original-only line identity" {
  let dispatch = test_dispatch()
  let file = @pathx.Relative("src/main.mbt")
  let added : Msg = FileEditor(
    UnifiedDiffCommentAdded(
      file~,
      original_line_number=None,
      modified_line_number=Some(7),
      quote="let answer = 42",
      comment="name this constant",
    ),
  )
  let (_, with_added) = update(dispatch, added, test_model())
  let added_mentions = with_added.active().mentions
  assert_eq(added_mentions.length(), 1)
  assert_true(
    added_mentions[0].ref_
    is Annotation(
      file="src/main.mbt",
      start_line=7,
      end_line=7,
      quote="let answer = 42",
      comment="name this constant",
      side=@mention_context.WorkingRevision
    ),
  )
  assert_eq(added_mentions[0].range, Some(@common.Range::Range(7, 1, 7, 16)))
  let deleted : Msg = FileEditor(
    UnifiedDiffCommentAdded(
      file~,
      original_line_number=Some(3),
      modified_line_number=None,
      quote="obsolete()",
      comment="good removal",
    ),
  )
  let (_, with_deleted) = update(dispatch, deleted, with_added)
  let deleted_mentions = with_deleted.active().mentions
  assert_eq(deleted_mentions.length(), 2)
  assert_true(
    deleted_mentions[1].ref_
    is Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="good removal",
      side=@mention_context.OriginalRevision
    ),
  )
  assert_eq(deleted_mentions[1].range, None)
}

///|
test "original-revision diff comment chip does not navigate into the working file" {
  let dispatch = test_dispatch()
  let original_comment : Mention = {
    ref_: Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="good removal",
      side=@mention_context.OriginalRevision,
    ),
    range: None,
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [original_comment],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.dock.open)
  assert_true(next.dock.active is None)
}

///|
test "chip jumps relativize legacy absolute paths against the roots" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/project")
  // Preferred root: the run-reported cwd.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    cwd: Some(workspace),
  })
  let model = {
    ..model,
    file_panel: {
      ..model.file_panel,
      owner: Some({
        channel: @interop.ChannelId::Remote("previous"),
        session: "previous-session",
      }),
      tree_open: false,
      explorer_mode: @fileeditor.ExplorerChanges,
      review_view_mode: @fileeditor.ReviewUnifiedDiff,
      changes_generation: 7,
    },
  }
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  assert_false(next.file_panel.tree_open)
  assert_true(next.file_panel.explorer_mode is @fileeditor.ExplorerChanges)
  assert_true(next.file_panel.review_view_mode is @fileeditor.ReviewUnifiedDiff)
  // The eager re-root retains 7. The jump keeps the explorer hidden while the
  // file is active, so Changes waits until the pane is shown before refreshing.
  assert_true(next.file_panel.changes_generation == 7)
  // Before the first run reports cwd, the attached workspace serves as root.
  let model = test_model()
    .replace_conversation({ ..test_conversation(), workspace: Some(workspace) })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ workspace, rows: [], generation: 1 }],
    })
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  // An absolute path outside every root cannot be opened; the panel says so
  // instead of sending the host a bogus read.
  let (_, outside) = update(
    dispatch,
    JumpToLocation(
      path="/elsewhere/note.md",
      range=Some(@common.Range::Range(1, 1, 1, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(outside.dock.active is None)
  assert_true(outside.file_panel.error is Some(_))
}

///|
test "RevealDirectory(\"\") opens the tree pane without a highlight" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let dock = {
    ..@dock.open_file(model.dock, Relative("README.md")),
    open: true,
    owner: Some(owner),
  }
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    tree_open: false,
    highlighted: Some(Relative("src")),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(@pathx.Relative::root())),
    { ..model, dock, file_panel: panel },
  )
  // The active tab stays put — revealing the tree must not close the file.
  assert_true(@dock.active_file(next.dock) is Some(Relative("README.md")))
  assert_true(next.file_panel.tree_open)
  assert_true(next.file_panel.highlighted is None)
}

///|
test "RevealDirectory expands an uncached ancestor and highlights the target" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test" }),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
  )
  assert_true(next.file_panel.expanded.contains(Relative("src")))
  assert_true(next.file_panel.loading.contains(Relative("src")))
  assert_true(next.file_panel.highlighted is Some(Relative("src/foo")))
}

///|
test "RevealDirectory on an already-cached ancestor needs no reload" {
  let dispatch = test_dispatch()
  let model = test_model()
  let children : Map[@pathx.Relative, Array[@fileeditor.FileEntry]] = Map([
    (Relative("src"), []),
  ])
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test" }),
    children,
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
  )
  assert_true(next.file_panel.expanded.contains(Relative("src")))
  assert_false(next.file_panel.loading.contains(Relative("src")))
}

///|
test "HighlightCleared only clears a highlight that still matches" {
  let dispatch = test_dispatch()
  let model = test_model()
  // Rooted in the active session, or the post-dispatch `sync` re-roots the
  // panel and clears the highlight itself.
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test" }),
    highlighted: Some(Relative("src")),
  }
  let (_, stale) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("old"))),
    { ..model, file_panel: panel },
  )
  assert_true(stale.file_panel.highlighted is Some(Relative("src")))
  let (_, cleared) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("src"))),
    { ..model, file_panel: panel },
  )
  assert_true(cleared.file_panel.highlighted is None)
}
