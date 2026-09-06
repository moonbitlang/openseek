// The input composer is one self-contained Rabbita state machine. Its Model
// stores local drafts and completion state; the application root supplies
// canonical external facts through `Input` and receives deliberate `Action`s.

///|
priv enum PendingSubmission {
  PromptSubmission(sequence_before~ : Int, Draft)
  GoalSubmission(sequence_before~ : Int, String)
} derive(Eq)

///|
/// File completion follows the component-local draft. A settled Host result
/// stays valid only while owner, root, query, and index epoch all still
/// match. There is no pending variant: while a remote lookup is wanted, the
/// declared `Request::searching` subscription IS the in-flight state.
priv enum FileCompletion {
  Local(files~ : Array[@files.Match], loading~ : Bool, epoch~ : Int)
  RemoteSettled(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    files~ : Array[@files.Match],
    epoch~ : Int
  )
} derive(Eq)

///|
fn FileCompletion::files(self : FileCompletion) -> Array[@files.Match] {
  match self {
    Local(files~, ..) | RemoteSettled(files~, ..) => files
  }
}

///|
fn FileCompletion::loading(self : FileCompletion) -> Bool {
  match self {
    Local(loading~, ..) => loading
    RemoteSettled(..) => false
  }
}

///|
fn FileCompletion::matches(
  self : FileCompletion,
  owner : @interop.ConversationKey,
  root : @common.Uri?,
  query : String?,
  epoch : Int,
) -> Bool {
  match self {
    RemoteSettled(
      owner=remote_owner,
      root=remote_root,
      query=remote_query,
      epoch=remote_epoch,
      ..
    ) =>
      remote_owner == owner &&
      root == Some(remote_root) &&
      query == Some(remote_query) &&
      remote_epoch == epoch
    Local(..) => false
  }
}

///|
/// One conversation's local editor state. Entries remain cached for the page
/// lifetime, so navigation never mirrors keystrokes into the root Model.
priv struct Entry {
  owner : @interop.ConversationKey
  action_generation : Int
  source : Draft
  draft : Draft
  source_goal : String?
  goal_draft : String?
  completion : Completion?
  symbol_cache : SymbolCache
  file_completion : FileCompletion
  root : @common.Uri?
  installed_skills : Array[@skills.InstalledItem]
  context_generation : Int
  pending_submission : PendingSubmission?
} derive(Eq)

///|
fn Entry::Entry(input : Input) -> Entry {
  let (files, loading) = input.completion_files(input.draft.task)
  {
    owner: input.identity.owner,
    action_generation: input.identity.archive_generation,
    source: input.draft,
    draft: input.draft,
    source_goal: input.goal.draft,
    goal_draft: input.goal.draft,
    completion: None,
    symbol_cache: SymbolCache(),
    file_completion: Local(files~, loading~, epoch=input.file_index.epoch()),
    root: input.root,
    installed_skills: input.installed_skills,
    context_generation: input.context_generation,
    pending_submission: None,
  }
}

///|
fn Entry::identity(self : Entry) -> Identity {
  { owner: self.owner, archive_generation: self.action_generation, }
}

///|
fn Entry::file_completion_for(
  self : Entry,
  input : Input,
  text : String,
  root : @common.Uri?,
) -> FileCompletion {
  let query = if Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" {
    Some(trigger.query())
  } else {
    None
  }
  if self.file_completion.matches(
      self.owner,
      root,
      query,
      input.file_index.epoch(),
    ) {
    self.file_completion
  } else {
    let (files, loading) = input.completion_files(text)
    Local(files~, loading~, epoch=input.file_index.epoch())
  }
}

///|
/// Reconcile root-authored recovery with local edits. Submission acknowledgement
/// clears only the submitted editor: prompt and goal drafts are independent.
fn Entry::reconciled(self : Entry, input : Input) -> Entry {
  let incoming = input.draft
  let incoming_goal = input.goal.draft
  let root_changed = input.root != self.root
  let context_changed = self.context_generation != input.context_generation
  let skills_changed = self.installed_skills != input.installed_skills
  let acknowledged : Draft? = match self.pending_submission {
    Some(PromptSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before => Some(incoming)
    Some(GoalSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before =>
      Some(self.draft.reconciled(source=self.source, incoming~))
    _ => None
  }
  if acknowledged is Some(draft) {
    return {
      ..self,
      source: incoming,
      draft,
      source_goal: incoming_goal,
      goal_draft: incoming_goal,
      completion: None,
      symbol_cache: if root_changed {
        SymbolCache()
      } else {
        self.symbol_cache
      },
      file_completion: self.file_completion_for(input, draft.task, input.root),
      root: input.root,
      installed_skills: input.installed_skills,
      context_generation: input.context_generation,
      pending_submission: None,
    }
  }
  let draft = self.draft.reconciled(source=self.source, incoming~)
  let goal_draft = if incoming_goal == self.source_goal {
    self.goal_draft
  } else {
    match (self.source_goal, self.goal_draft, incoming_goal) {
      (_, _, None) => None
      (None, _, Some(value)) => Some(value)
      (Some(source), Some(local_draft), Some(value)) =>
        if value == source {
          Some(local_draft)
        } else if local_draft == source || local_draft.is_empty() {
          Some(value)
        } else if value.is_empty() || value == local_draft {
          Some(local_draft)
        } else {
          Some(value + "\n\n" + local_draft)
        }
      (Some(_), None, Some(value)) => Some(value)
    }
  }
  let symbol_cache = if root_changed {
    SymbolCache()
  } else {
    self.symbol_cache
  }
  let file_completion = self.file_completion_for(input, draft.task, input.root)
  let visible_files_changed = file_completion != self.file_completion &&
    self.completion is Some(current) &&
    current.kind is Files
  let completion = if incoming_goal is Some(_) || context_changed {
    None
  } else if draft != self.draft ||
    root_changed ||
    skills_changed ||
    visible_files_changed {
    input.completion(
      draft.task,
      symbol_cache,
      self.owner,
      files=file_completion.files(),
      files_loading=file_completion.loading(),
    )
  } else {
    self.completion
  }
  let pending_submission = match self.pending_submission {
    Some(PromptSubmission(sequence_before=_, submitted)) if incoming ==
      submitted => None
    Some(GoalSubmission(sequence_before=_, submitted)) if incoming_goal ==
      Some(submitted) => None
    pending => pending
  }
  {
    ..self,
    source: incoming,
    draft,
    source_goal: incoming_goal,
    goal_draft,
    completion,
    symbol_cache,
    file_completion,
    root: input.root,
    installed_skills: input.installed_skills,
    context_generation: input.context_generation,
    pending_submission,
  }
}

///|
priv struct Model {
  entries : Array[Entry]
  applied_retirements : Int
  // The clock the running row's elapsed span is measured against, advanced by
  // `ClockTicked` and only while a turn is open. Component state rather than
  // the application's: a value that changes every second belongs to the one
  // subtree that displays it, or every other component's input is reprojected
  // once a second to redraw a single line.
  clock_ms : Double
} derive(Eq)

///|
fn Model::Model(input : Input) -> Model {
  {
    entries: [Entry(input)],
    applied_retirements: input.retirements.length(),
    clock_ms: @interop.now_ms(),
  }
}

///|
fn Model::owner_has_pending_retirement(
  self : Model,
  input : Input,
  owner : @interop.ConversationKey,
) -> Bool {
  for index in self.applied_retirements..<input.retirements.length() {
    if input.retirements[index] == owner {
      return true
    }
  }
  false
}

///|
fn Model::with_retirements_applied(self : Model, input : Input) -> Model {
  let mut entries = self.entries
  for index in self.applied_retirements..<input.retirements.length() {
    let retired = input.retirements[index]
    entries = entries.filter(entry => entry.owner != retired)
  }
  { ..self, entries, applied_retirements: input.retirements.length(), }
}

///|
fn Model::active(self : Model, input : Input) -> Entry {
  for entry in self.entries {
    if entry.owner == input.identity.owner &&
      !self.owner_has_pending_retirement(input, entry.owner) {
      return entry.reconciled(input)
    }
  }
  Entry(input)
}

///|
fn Model::with_entry(self : Model, entry : Entry) -> Model {
  let entries = self.entries.copy()
  match entries.search_by(existing => existing.owner == entry.owner) {
    Some(index) => entries[index] = entry
    None => entries.push(entry)
  }
  { ..self, entries, }
}

///|
priv enum Msg {
  TextChanged(String)
  CompletionMove(Int)
  CompletionAccept
  CompletionPick(Int)
  CompletionDismiss
  EntriesRetired
  CompletionPump
  // A second passed while a turn was open. Carries nothing: the handler reads
  // the clock, and the message exists only to advance the span on screen.
  ClockTicked
  MentionRemoved(Int)
  MentionJumped(Int)
  GoalCancelled
  SubmitRequested
  SymbolsLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    items~ : Array[@symbols.Symbol]
  )
  SymbolsFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String
  )
  FilesLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    epoch~ : Int,
    files~ : Array[@pathx.Relative]
  )
  FilesFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    epoch~ : Int
  )
}

///|
fn Entry::holds_draft(self : Entry) -> Bool {
  !self.draft.task.is_blank() ||
  !self.draft.mentions.is_empty() ||
  (self.goal_draft is Some(goal) && !goal.is_blank())
}

///|
fn Entry::edited(
  self : Entry,
  input : Input,
  value : String,
  action_emit : @cmd.Emit[Action],
) -> (Entry, @cmd.Cmd) {
  if input.goal.draft is Some(_) {
    return (
      {
        ..self,
        goal_draft: Some(value),
        completion: None,
        pending_submission: None,
      },
      @cmd.none,
    )
  }
  let draft = { ..self.draft, task: value, }
  let (files, files_loading) = input.completion_files(value)
  let file_completion = Local(
    files~,
    loading=files_loading,
    epoch=input.file_index.epoch(),
  )
  let completion = input.completion(
    value,
    self.symbol_cache,
    self.owner,
    files~,
    files_loading~,
  )
  // Remote lookups need no command here: the subscription diff after this
  // update derives them from the loading menu this edit just opened.
  let command = match Trigger::parse(value, inline_markers="$#@") {
    Some(trigger) if trigger.marker() == "@" &&
      self.root is Some(_) &&
      input.file_index.needs_start() =>
      action_emit(FileIndexEnsured(identity=self.identity()))
    _ => @cmd.none
  }
  (
    { ..self, draft, completion, file_completion, pending_submission: None, },
    command,
  )
}

///|
fn Entry::accept_completion(
  self : Entry,
  item : CompletionItem,
  action_emit : @cmd.Emit[Action],
) -> (Entry, @cmd.Cmd) {
  guard self.completion is Some(completion) else {
    return ({ ..self, completion: None, }, @cmd.none)
  }
  let mention : Mention? = match completion.kind {
    SlashCommands =>
      return (
        {
          ..self,
          draft: { ..self.draft, task: completion.menu.draft_without_token(), },
          completion: None,
        },
        action_emit(
          SlashCommand(identity=self.identity(), command=item.command),
        ),
      )
    SkillMentions =>
      Some({
        ref_: @mention_context.Skill(name=item.insert.trim().to_owned()),
        range: None,
      })
    Symbols => {
      let (file, line) = if item.path is Some(path) && item.range is Some(range) {
        (path, range.start_line_number)
      } else {
        ("", 0)
      }
      Some({
        ref_: @mention_context.Symbol(name=item.label, file~, line~),
        range: item.range,
      })
    }
    Files =>
      item.path.map(path => Mention::{
        ref_: @mention_context.File(path~),
        range: None,
      })
  }
  guard mention is Some(mention) else {
    return ({ ..self, completion: None, }, @cmd.none)
  }
  (
    {
      ..self,
      draft: {
        ..self.draft.with_mention(mention),
        task: completion.menu.draft_without_token(),
      },
      completion: None,
    },
    @cmd.none,
  )
}

///|
/// Adopt one remote file-search reply. The declared subscription already
/// muted replies whose (owner, root, query, epoch) key is no longer wanted;
/// this guard restates that declaration against the reconciled entry, so a
/// menu closed by a context switch in the same pass also rejects the reply.
fn Entry::settled_file_completion(
  self : Entry,
  input : Input,
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  epoch : Int,
  remote_files : Array[@pathx.Relative]?,
) -> Entry? {
  guard owner == self.owner &&
    self.root == Some(root) &&
    epoch == input.file_index.epoch() &&
    Trigger::parse(self.draft.task, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" &&
    trigger.query() == query &&
    self.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() else {
    return None
  }
  let files = if remote_files is Some(remote_files) {
    @files.Search(remote_files, input.open_files, input.active_file).rank(query)
  } else {
    @files.Search(input.file_candidates, [], None).rank(query)
  }
  let file_completion = RemoteSettled(owner~, root~, query~, files~, epoch~)
  Some({
    ..self,
    file_completion,
    completion: input.completion(
      self.draft.task,
      self.symbol_cache,
      owner,
      files~,
      files_loading=false,
    ),
  })
}

///|
fn Model::commit_entry_change(
  self : Model,
  previous : Entry,
  entry : Entry,
  command : @cmd.Cmd,
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  let presence = if previous.holds_draft() != entry.holds_draft() {
    action_emit(
      DraftPresenceChanged(
        identity=entry.identity(),
        present=entry.holds_draft(),
        cleared_source=if entry.holds_draft() {
          None
        } else {
          Some(entry.source)
        },
      ),
    )
  } else {
    @cmd.none
  }
  (self.with_entry(entry), @cmd.batch([command, presence]))
}

///|
fn Model::update(
  self : Model,
  input : Input,
  msg : Msg,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  let self = self.with_retirements_applied(input)
  let entry = self.active(input)
  let self = self.with_entry(entry)
  match msg {
    TextChanged(value) => {
      let (next, command) = entry.edited(input, value, action_emit)
      self.commit_entry_change(entry, next, command, action_emit)
    }
    CompletionMove(delta) => {
      let next = if entry.completion is Some(completion) {
        {
          ..entry,
          completion: Some({
            ..completion,
            menu: completion.menu.shifted(delta),
          }),
        }
      } else {
        entry
      }
      (self.with_entry(next), @cmd.none)
    }
    CompletionDismiss =>
      (self.with_entry({ ..entry, completion: None, }), @cmd.none)
    CompletionAccept => {
      guard entry.completion is Some(completion) &&
        completion.menu.current() is Some(item) else {
        return (self.with_entry({ ..entry, completion: None, }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, action_emit)
      self.commit_entry_change(entry, next, command, action_emit)
    }
    CompletionPick(index) => {
      guard entry.completion is Some(completion) &&
        completion.menu.get(index) is Some(item) else {
        return (self.with_entry({ ..entry, completion: None, }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, action_emit)
      self.commit_entry_change(entry, next, command, action_emit)
    }
    EntriesRetired => (self, @cmd.none)
    MentionRemoved(index) => {
      guard entry.draft.mentions.get(index) is Some(mention) else {
        return (self.with_entry(entry), @cmd.none)
      }
      self.commit_entry_change(
        entry,
        { ..entry, draft: entry.draft.without_mention(index), },
        action_emit(RootMentionRemoved(identity=entry.identity(), mention~)),
        action_emit,
      )
    }
    MentionJumped(index) => {
      guard entry.draft.mentions.get(index) is Some(mention) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (
        self.with_entry(entry),
        action_emit(MentionOpened(identity=entry.identity(), mention~)),
      )
    }
    GoalCancelled =>
      self.commit_entry_change(
        entry,
        {
          ..entry,
          goal_draft: None,
          completion: None,
          pending_submission: None,
        },
        action_emit(GoalCancelled(identity=entry.identity())),
        action_emit,
      )
    SubmitRequested =>
      if input.goal.draft is Some(_) {
        let text = entry.goal_draft.unwrap_or("").trim().to_owned()
        guard !text.is_empty() else {
          return (self.with_entry(entry), @cmd.none)
        }
        (
          self.with_entry({
            ..entry,
            completion: None,
            pending_submission: Some(
              GoalSubmission(sequence_before=input.submission_sequence, text),
            ),
          }),
          action_emit(
            GoalSubmitted(
              identity=entry.identity(),
              draft=text,
              prompt_present=!entry.draft.task.is_blank() ||
                !entry.draft.mentions.is_empty(),
            ),
          ),
        )
      } else {
        guard !entry.draft.task.is_blank() || !entry.draft.mentions.is_empty() else {
          return (self.with_entry(entry), @cmd.none)
        }
        (
          self.with_entry({
            ..entry,
            completion: None,
            pending_submission: Some(
              PromptSubmission(
                sequence_before=input.submission_sequence,
                entry.draft,
              ),
            ),
          }),
          action_emit(
            DraftSubmitted(identity=entry.identity(), draft=entry.draft),
          ),
        )
      }
    SymbolsLoaded(owner~, root~, query~, items~) => {
      // The declared subscription already muted replies whose (channel, root,
      // query) key is no longer wanted; this guard restates that declaration
      // against the reconciled entry, so a menu closed by a context switch in
      // the same pass also rejects the reply instead of reopening.
      guard owner == entry.owner &&
        entry.root == Some(root) &&
        Trigger::parse(entry.draft.task, inline_markers="$#") is Some(trigger) &&
        trigger.marker() == "#" &&
        trigger.query() == query &&
        entry.completion is Some(completion) &&
        completion.kind is Symbols &&
        completion.menu.loading() else {
        return (self.with_entry(entry), @cmd.none)
      }
      let rows = items.map(CompletionItem::from_symbol)
      let symbol_cache : SymbolCache = {
        owner: Some(owner),
        root: Some(root),
        query,
        items: rows,
      }
      (
        self.with_entry({
          ..entry,
          symbol_cache,
          completion: input.completion(
            entry.draft.task,
            symbol_cache,
            owner,
            files=entry.file_completion.files(),
            files_loading=entry.file_completion.loading(),
          ),
        }),
        @cmd.none,
      )
    }
    SymbolsFailed(owner~, root~, query~) =>
      self.update(
        input,
        SymbolsLoaded(owner~, root~, query~, items=[]),
        emit,
        action_emit,
      )
    // The tick runs whether or not a turn is open (see `subscriptions`), so
    // this is where an idle one is discarded: the clock only moves while
    // there is a span to measure, leaving the model equal to itself and
    // nothing to re-render.
    ClockTicked => {
      let clock_ms = if input.run is Some(_) {
        @interop.now_ms()
      } else {
        self.clock_ms
      }
      ({ ..self.with_entry(entry), clock_ms, }, @cmd.none)
    }
    CompletionPump => {
      // Committing the reconciled entry above is this tick's real work: the
      // subscription diff after every update re-derives the declared lookups
      // from that entry, so input-only changes (root, file-index state,
      // context) re-key or cancel them within one pump period. The only
      // remaining imperative duty is nudging the root to (re)build a missing
      // file index.
      guard entry.completion is Some(completion) &&
        completion.kind is Files &&
        completion.menu.loading() &&
        entry.file_completion is Local(loading=true, ..) &&
        input.file_index.needs_start() else {
        return (self.with_entry(entry), @cmd.none)
      }
      (
        self.with_entry(entry),
        action_emit(FileIndexEnsured(identity=entry.identity())),
      )
    }
    FilesLoaded(owner~, root~, query~, epoch~, files~) => {
      let next = entry
        .settled_file_completion(input, owner, root, query, epoch, Some(files))
        .unwrap_or(entry)
      (self.with_entry(next), @cmd.none)
    }
    FilesFailed(owner~, root~, query~, epoch~) => {
      let next = entry
        .settled_file_completion(input, owner, root, query, epoch, None)
        .unwrap_or(entry)
      (self.with_entry(next), @cmd.none)
    }
  }
}

///|
/// Declare what should be in flight for the current state. Remote completion
/// lookups are subscriptions, not commands: while a loading menu wants a
/// (channel, root, query) lookup, that lookup is declared here, and any state
/// or input change that stops wanting it unloads the subscription — which
/// cancels the pending debounce timer or mutes the reply inside the effect
/// package. Every staleness axis lives in the subscription key, in one place,
/// instead of being re-checked at issue, delay-fire, and ingest time.
fn Model::subscriptions(
  self : Model,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  // The heartbeat tick is permanent, deliberately: a component's
  // subscriptions are re-derived only when that component processes a
  // message, never when its input alone changes (`handle_subs` runs at
  // construction and inside `on_update`). A tick declared only while
  // `input.run` is set would therefore never be installed for the case this
  // row exists for — submit, then wait without touching the composer, where
  // no further message ever arrives. Worse, the submit cannot install it
  // either: `on_update` refreshes subscriptions *before* running the command
  // that tells the root to open the run, so it still reads `run: None`.
  //
  // `ClockTicked` is what stays conditional instead: an idle tick leaves the
  // model equal to itself, so it costs a comparison and no render.
  @sub.batch([
    @sub.every(1000, emit(ClockTicked)),
    self.editing_subscriptions(input, emit),
  ])
}

///|
fn Model::editing_subscriptions(
  self : Model,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  if self.applied_retirements < input.retirements.length() {
    return @sub.every(150, emit(EntriesRetired))
  }
  let entry = self.active(input)
  guard entry.completion is Some(completion) && completion.menu.loading() else {
    return @sub.none
  }
  // Subscriptions are only re-derived when a message is processed, so every
  // remote-backed loading menu keeps one pump tick alive. Each tick commits
  // the reconciled entry, which turns input-only changes (root, file-index
  // state, context) into a re-keyed or cancelled lookup below.
  let subs = [@sub.every(150, emit(CompletionPump))]
  match completion.kind {
    Symbols =>
      if entry.root is Some(root) &&
        Trigger::parse(entry.draft.task, inline_markers="$#") is Some(trigger) &&
        trigger.marker() == "#" {
        let owner = entry.owner
        let query = trigger.query()
        subs.push(
          @symbols.searching(
            owner,
            query,
            root~,
            loaded=items => emit(SymbolsLoaded(owner~, root~, query~, items~)),
            failed=emit(SymbolsFailed(owner~, root~, query~)),
          ),
        )
      }
    Files =>
      if entry.root is Some(root) &&
        Trigger::parse(entry.draft.task, inline_markers="$#@") is Some(trigger) &&
        trigger.marker() == "@" &&
        input.file_index is FileIndexReady(truncated=true, ..) {
        let owner = entry.owner
        let query = trigger.query()
        let epoch = input.file_index.epoch()
        subs.push(
          @files.Request(owner.channel, owner.session, Some(root)).searching(
            query,
            epoch~,
            loaded=(files, _limit_hit) => {
              emit(FilesLoaded(owner~, root~, query~, epoch~, files~))
            },
            failed=() => emit(FilesFailed(owner~, root~, query~, epoch~)),
          ),
        )
      }
    SlashCommands | SkillMentions => ()
  }
  @sub.batch(subs)
}

///|
/// Create the package-owned composer component. The root provides only
/// `Input` values and receives only deliberate `Action`s.
pub fn component(
  input : @rabbita.Val[Input],
  action_emit : @cmd.Emit[Action],
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, input) => (Model(input), @cmd.none),
    update=(state, input, msg, emit) => {
      state.update(input, msg, emit, action_emit)
    },
    subscriptions=(state, input, emit) => state.subscriptions(input, emit),
  )
  state.view2(input, (state, input) => {
    state.active(input).view(emit, action_emit, input, clock_ms=state.clock_ms)
  })
}
