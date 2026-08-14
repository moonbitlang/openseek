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
/// stays valid only while owner, root, query, generation, and index epoch all
/// still match.
priv enum FileCompletion {
  Local(files~ : Array[@files.Match], loading~ : Bool, epoch~ : Int)
  RemotePending(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    files~ : Array[@files.Match],
    epoch~ : Int
  )
  RemoteSettled(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    files~ : Array[@files.Match],
    epoch~ : Int
  )
} derive(Eq)

///|
fn FileCompletion::files(self : FileCompletion) -> Array[@files.Match] {
  match self {
    Local(files~, ..) | RemotePending(files~, ..) | RemoteSettled(files~, ..) =>
      files
  }
}

///|
fn FileCompletion::loading(self : FileCompletion) -> Bool {
  match self {
    Local(loading~, ..) => loading
    RemotePending(..) => true
    RemoteSettled(..) => false
  }
}

///|
fn FileCompletion::matches(
  self : FileCompletion,
  owner : @interop.ConversationKey,
  root : @common.Uri?,
  query : String?,
  generation : Int,
  epoch : Int,
) -> Bool {
  match self {
    RemotePending(
      owner=remote_owner,
      root=remote_root,
      query=remote_query,
      generation=remote_generation,
      epoch=remote_epoch,
      ..
    )
    | RemoteSettled(
      owner=remote_owner,
      root=remote_root,
      query=remote_query,
      generation=remote_generation,
      epoch=remote_epoch,
      ..
    ) =>
      remote_owner == owner &&
      root == Some(remote_root) &&
      query == Some(remote_query) &&
      remote_generation == generation &&
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
  completion_debounce : Debounce
  file_completion : FileCompletion
  root : @common.Uri?
  installed_skills : Array[@transcript.InstalledSkillItem]
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
    completion_debounce: Debounce(),
    file_completion: Local(files~, loading~, epoch=input.file_index.epoch()),
    root: input.root,
    installed_skills: input.installed_skills,
    context_generation: input.context_generation,
    pending_submission: None,
  }
}

///|
fn Entry::identity(self : Entry) -> Identity {
  { owner: self.owner, archive_generation: self.action_generation }
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
      self.completion_debounce.generation(),
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
  match self.pending_submission {
    Some(PromptSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before =>
      return {
        ..self,
        source: incoming,
        draft: incoming,
        source_goal: incoming_goal,
        goal_draft: incoming_goal,
        completion: None,
        symbol_cache: if root_changed {
          SymbolCache()
        } else {
          self.symbol_cache
        },
        file_completion: self.file_completion_for(
          input,
          incoming.task,
          input.root,
        ),
        root: input.root,
        installed_skills: input.installed_skills,
        context_generation: input.context_generation,
        pending_submission: None,
      }
    Some(GoalSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before => {
      let draft = self.draft.reconciled(source=self.source, incoming~)
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
    _ => ()
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
  applied_replacements : Int
} derive(Eq)

///|
fn Model::Model(input : Input) -> Model {
  {
    entries: [Entry(input)],
    applied_retirements: input.retirements.length(),
    applied_replacements: input.replacements.length(),
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
  { ..self, entries, applied_retirements: input.retirements.length() }
}

///|
fn Model::with_replacements_applied(self : Model, input : Input) -> Model {
  let mut entries = self.entries
  for index in self.applied_replacements..<input.replacements.length() {
    let replacement = input.replacements[index]
    let snapshot = entries
    for archived_entry in snapshot {
      if archived_entry.owner == replacement.archived {
        entries = entries.filter(existing => {
          existing.owner != replacement.archived &&
          existing.owner != replacement.fresh
        })
        entries.push({
          ..archived_entry,
          owner: replacement.fresh,
          completion: None,
          symbol_cache: SymbolCache(),
          pending_submission: None,
        })
        break
      }
    }
  }
  { ..self, entries, applied_replacements: input.replacements.length() }
}

///|
fn Model::active(self : Model, input : Input) -> Entry {
  let self = self.with_replacements_applied(input)
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
  for index, existing in entries {
    if existing.owner == entry.owner {
      entries[index] = entry
      return { ..self, entries, }
    }
  }
  entries.push(entry)
  { ..self, entries, }
}

///|
priv enum Msg {
  TextChanged(String)
  CompletionDue(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri?,
    query~ : String,
    generation~ : Int
  )
  CompletionMove(Int)
  CompletionAccept
  CompletionPick(Int)
  CompletionDismiss
  EntriesTransferred
  EntriesRetired
  SymbolRootChanged
  MentionRemoved(Int)
  MentionJumped(Int)
  GoalCancelled
  SubmitRequested
  SymbolsLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    items~ : Array[@symbols.Symbol]
  )
  SymbolsFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int
  )
  FileCompletionTick
  FilesLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    epoch~ : Int,
    files~ : Array[@pathx.Relative]
  )
  FilesFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
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
  emit : @cmd.Emit[Msg],
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
  let completion_debounce = self.completion_debounce.advanced()
  let draft = { ..self.draft, task: value }
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
  let command = match Trigger::parse(value, inline_markers="$#@") {
    Some(trigger) if trigger.marker() == "#" &&
      (
        self.symbol_cache.owner != Some(self.owner) ||
        self.symbol_cache.root != self.root ||
        self.symbol_cache.query != trigger.query()
      ) =>
      completion_debounce.delayed(generation => {
        emit(
          CompletionDue(
            owner=self.owner,
            root=self.root,
            query=trigger.query(),
            generation~,
          ),
        )
      })
    Some(trigger) if trigger.marker() == "@" &&
      self.root is Some(_) &&
      input.file_index.needs_start() =>
      action_emit(FileIndexEnsured(identity=self.identity()))
    _ => @cmd.none
  }
  (
    {
      ..self,
      draft,
      completion,
      completion_debounce,
      file_completion,
      pending_submission: None,
    },
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
    return ({ ..self, completion: None }, @cmd.none)
  }
  match completion.kind {
    SlashCommands =>
      (
        {
          ..self,
          draft: { ..self.draft, task: completion.menu.draft_without_token() },
          completion: None,
        },
        action_emit(
          SlashCommand(identity=self.identity(), command=item.command),
        ),
      )
    SkillMentions =>
      (
        {
          ..self,
          draft: {
            ..self.draft.with_mention({
              ref_: @mention_context.Skill(name=item.insert.trim().to_owned()),
              range: None,
            }),
            task: completion.menu.draft_without_token(),
          },
          completion: None,
        },
        @cmd.none,
      )
    Symbols => {
      let (file, line) = if item.path is Some(path) && item.range is Some(range) {
        (path, range.start_line_number)
      } else {
        ("", 0)
      }
      (
        {
          ..self,
          draft: {
            ..self.draft.with_mention({
              ref_: @mention_context.Symbol(name=item.label, file~, line~),
              range: item.range,
            }),
            task: completion.menu.draft_without_token(),
          },
          completion: None,
        },
        @cmd.none,
      )
    }
    Files =>
      if item.path is Some(path) {
        (
          {
            ..self,
            draft: {
              ..self.draft.with_mention({
                ref_: @mention_context.File(path~),
                range: None,
              }),
              task: completion.menu.draft_without_token(),
            },
            completion: None,
          },
          @cmd.none,
        )
      } else {
        ({ ..self, completion: None }, @cmd.none)
      }
  }
}

///|
fn Entry::settled_file_completion(
  self : Entry,
  input : Input,
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  generation : Int,
  epoch : Int,
  remote_files : Array[@pathx.Relative]?,
) -> Entry? {
  guard self.file_completion
    is RemotePending(
      owner=pending_owner,
      root=pending_root,
      query=pending_query,
      generation=pending_generation,
      epoch=pending_epoch,
      ..
    ) &&
    pending_owner == owner &&
    pending_root == root &&
    pending_query == query &&
    pending_generation == generation &&
    pending_epoch == epoch &&
    self.completion_debounce.accepts(generation) &&
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
  let file_completion = RemoteSettled(
    owner~,
    root~,
    query~,
    generation~,
    files~,
    epoch~,
  )
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
  let self = self
    .with_replacements_applied(input)
    .with_retirements_applied(input)
  let entry = self.active(input)
  let self = self.with_entry(entry)
  match msg {
    TextChanged(value) => {
      let (next, command) = entry.edited(input, value, emit, action_emit)
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
      (self.with_entry({ ..entry, completion: None }), @cmd.none)
    CompletionAccept => {
      guard entry.completion is Some(completion) &&
        completion.menu.current() is Some(item) else {
        return (self.with_entry({ ..entry, completion: None }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, action_emit)
      self.commit_entry_change(entry, next, command, action_emit)
    }
    CompletionPick(index) => {
      guard entry.completion is Some(completion) &&
        completion.menu.get(index) is Some(item) else {
        return (self.with_entry({ ..entry, completion: None }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, action_emit)
      self.commit_entry_change(entry, next, command, action_emit)
    }
    EntriesTransferred | EntriesRetired => (self, @cmd.none)
    SymbolRootChanged => {
      guard Trigger::parse(entry.draft.task, inline_markers="$#")
        is Some(trigger) &&
        trigger.marker() == "#" &&
        entry.root is Some(root) &&
        entry.completion is Some(completion) &&
        completion.kind is Symbols &&
        completion.menu.loading() else {
        return (self.with_entry(entry), @cmd.none)
      }
      let debounce = entry.completion_debounce.advanced()
      (
        self.with_entry({ ..entry, completion_debounce: debounce }),
        emit(
          CompletionDue(
            owner=entry.owner,
            root=Some(root),
            query=trigger.query(),
            generation=debounce.generation(),
          ),
        ),
      )
    }
    MentionRemoved(index) => {
      guard entry.draft.mentions.get(index) is Some(mention) else {
        return (self.with_entry(entry), @cmd.none)
      }
      self.commit_entry_change(
        entry,
        { ..entry, draft: entry.draft.without_mention(index) },
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
        guard !entry.draft.task.is_blank() else {
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
    CompletionDue(owner~, root~, query~, generation~) => {
      guard owner == entry.owner &&
        root == entry.root &&
        root is Some(root) &&
        entry.completion_debounce.accepts(generation) &&
        Trigger::parse(entry.draft.task, inline_markers="$#") is Some(trigger) &&
        trigger.marker() == "#" &&
        trigger.query() == query &&
        entry.completion is Some(completion) &&
        completion.kind is Symbols &&
        completion.menu.loading() else {
        return (self.with_entry(entry), @cmd.none)
      }
      if entry.symbol_cache.owner == Some(owner) &&
        entry.symbol_cache.root == Some(root) &&
        entry.symbol_cache.query == query {
        return (self.with_entry(entry), @cmd.none)
      }
      (
        self.with_entry(entry),
        @symbols.search(
          owner.channel,
          query,
          root~,
          loaded=items => {
            emit(SymbolsLoaded(owner~, root~, query~, generation~, items~))
          },
          failed=emit(SymbolsFailed(owner~, root~, query~, generation~)),
        ),
      )
    }
    SymbolsLoaded(owner~, root~, query~, generation~, items~) => {
      guard owner == entry.owner &&
        entry.root == Some(root) &&
        entry.completion_debounce.accepts(generation) &&
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
    SymbolsFailed(owner~, root~, query~, generation~) =>
      self.update(
        input,
        SymbolsLoaded(owner~, root~, query~, generation~, items=[]),
        emit,
        action_emit,
      )
    FileCompletionTick => {
      guard Trigger::parse(entry.draft.task, inline_markers="$#@")
        is Some(trigger) &&
        trigger.marker() == "@" &&
        entry.root is Some(root) &&
        entry.completion is Some(completion) &&
        completion.kind is Files &&
        completion.menu.loading() else {
        return (self.with_entry(entry), @cmd.none)
      }
      match entry.file_completion {
        Local(files~, loading=true, epoch~) =>
          match input.file_index {
            FileIndexEmpty(..) | FileIndexFailed(..) =>
              (
                self.with_entry(entry),
                action_emit(FileIndexEnsured(identity=entry.identity())),
              )
            FileIndexLoading(..) => (self.with_entry(entry), @cmd.none)
            FileIndexReady(truncated=false, ..) =>
              (self.with_entry(entry), @cmd.none)
            FileIndexReady(truncated=true, ..) => {
              let owner = entry.owner
              let query = trigger.query()
              let generation = entry.completion_debounce.generation()
              (
                self.with_entry({
                  ..entry,
                  file_completion: RemotePending(
                    owner~,
                    root~,
                    query~,
                    generation~,
                    files~,
                    epoch~,
                  ),
                }),
                @files.Request(owner.channel, owner.session, Some(root)).search_cached(
                  query,
                  generation,
                  (files, _limit_hit) => {
                    emit(
                      FilesLoaded(
                        owner~,
                        root~,
                        query~,
                        generation~,
                        epoch~,
                        files~,
                      ),
                    )
                  },
                  () => {
                    emit(
                      FilesFailed(owner~, root~, query~, generation~, epoch~),
                    )
                  },
                ),
              )
            }
          }
        Local(loading=false, ..) | RemotePending(..) | RemoteSettled(..) =>
          (self.with_entry(entry), @cmd.none)
      }
    }
    FilesLoaded(owner~, root~, query~, generation~, epoch~, files~) => {
      guard entry.settled_file_completion(
          input,
          owner,
          root,
          query,
          generation,
          epoch,
          Some(files),
        )
        is Some(next) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (self.with_entry(next), @cmd.none)
    }
    FilesFailed(owner~, root~, query~, generation~, epoch~) => {
      guard entry.settled_file_completion(
          input,
          owner,
          root,
          query,
          generation,
          epoch,
          None,
        )
        is Some(next) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (self.with_entry(next), @cmd.none)
    }
  }
}

///|
fn Model::subscriptions(
  self : Model,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  if self.applied_retirements < input.retirements.length() {
    return @sub.every(150, emit(EntriesRetired))
  }
  if self.applied_replacements < input.replacements.length() {
    return @sub.every(150, emit(EntriesTransferred))
  }
  for stored in self.entries {
    if stored.owner == input.identity.owner &&
      stored.root != input.root &&
      stored.completion is Some(completion) &&
      completion.kind is Symbols &&
      Trigger::parse(stored.draft.task, inline_markers="$#") is Some(trigger) &&
      trigger.marker() == "#" {
      return @sub.every(150, emit(SymbolRootChanged))
    }
  }
  let entry = self.active(input)
  if entry.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() {
    @sub.every(150, emit(FileCompletionTick))
  } else {
    @sub.none
  }
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
    state.active(input).view(emit, action_emit, input)
  })
}
