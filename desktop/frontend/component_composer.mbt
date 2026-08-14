// The input composer is its own Rabbita state machine. Text edits, completion
// selection, and mention removal stay here. The root sees complete contents
// only at submission, plus a one-bit empty/non-empty transition used to keep
// an unsent conversation reachable in the sidebar.

///|
/// The editable prompt carried by one conversation's composer. The root still
/// accepts this shape atomically at submission time so its delivery ledger can
/// retain the exact text and chips that were sent.
priv struct ComposerDraft {
  task : String
  mentions : Array[Mention]
} derive(Eq)

///|
/// Reconcile a root-authored draft change with newer component-local typing.
/// Root changes are uncommon but important: editor comments add chips, archive
/// recovery moves a draft, and a rejected delivery restores older input. A
/// three-way merge preserves local edits made after the last root snapshot.
fn ComposerDraft::reconciled(
  self : ComposerDraft,
  source~ : ComposerDraft,
  incoming~ : ComposerDraft,
) -> ComposerDraft {
  let task = if incoming.task == source.task {
    self.task
  } else if self.task == source.task || self.task.is_empty() {
    incoming.task
  } else if incoming.task.is_empty() || incoming.task == self.task {
    self.task
  } else {
    incoming.task + "\n\n" + self.task
  }
  let mentions = if incoming.mentions == source.mentions {
    self.mentions
  } else if self.mentions == source.mentions {
    incoming.mentions
  } else {
    let mut merged = self.mentions
    for mention in incoming.mentions {
      let externally_added = source.mentions
        .iter()
        .all(existing => existing.ref_ != mention.ref_)
      if externally_added {
        merged = push_mention(merged, mention)
      }
    }
    merged
  }
  { task, mentions }
}

///|
fn ComposerDraft::without_mention(
  self : ComposerDraft,
  index : Int,
) -> ComposerDraft {
  guard self.mentions.get(index) is Some(_) else { return self }
  let mentions = self.mentions.copy()
  ignore(mentions.remove(index))
  { ..self, mentions, }
}

///|
priv enum PendingComposerSubmission {
  PromptSubmission(sequence_before~ : Int, ComposerDraft)
  GoalSubmission(sequence_before~ : Int, String)
} derive(Eq)

///|
/// File completion follows the component-local draft, so its request identity
/// must live beside that draft too. `RemoteSettled` preserves Host-ranked rows
/// while the shared file panel still exposes only a truncated local snapshot.
priv enum ComposerFileCompletion {
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
fn ComposerFileCompletion::files(
  self : ComposerFileCompletion,
) -> Array[@files.Match] {
  match self {
    Local(files~, ..) => files
    RemotePending(files~, ..) => files
    RemoteSettled(files~, ..) => files
  }
}

///|
fn ComposerFileCompletion::loading(self : ComposerFileCompletion) -> Bool {
  match self {
    Local(loading~, ..) => loading
    RemotePending(..) => true
    RemoteSettled(..) => false
  }
}

///|
/// A remote result belongs to one exact visible token and one file-index run.
/// Any edit, checkout move, or index restart falls back to the current local
/// projection instead of showing rows from the old request.
fn ComposerFileCompletion::matches(
  self : ComposerFileCompletion,
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
/// One conversation's component-local editor state. Entries remain cached for
/// the page lifetime, so switching conversations never needs to write the
/// textarea value into the application Model merely to preserve it.
priv struct ComposerEntry {
  owner : @interop.ConversationKey
  source : ComposerDraft
  draft : ComposerDraft
  source_goal : String?
  goal_draft : String?
  completion : Completion?
  symbol_cache : SymbolCache
  completion_debounce : @composer.Debounce
  file_completion : ComposerFileCompletion
  root : @common.Uri?
  installed_skills : Array[@transcript.InstalledSkillItem]
  context_generation : Int
  pending_submission : PendingComposerSubmission?
} derive(Eq)

///|
fn ComposerEntry::ComposerEntry(input : Model) -> ComposerEntry {
  let conv = input.active()
  let owner : @interop.ConversationKey = {
    channel: input.focused,
    session: conv.session_id,
  }
  let source : ComposerDraft = { task: conv.task, mentions: conv.mentions }
  let source_goal = conv.goal_edit.map(edit => edit.draft)
  let (files, loading) = input.completion_files(source.task)
  {
    owner,
    source,
    draft: source,
    source_goal,
    goal_draft: source_goal,
    completion: None,
    symbol_cache: empty_symbol_cache(),
    completion_debounce: @composer.Debounce(),
    file_completion: Local(
      files~,
      loading~,
      epoch=input.file_panel.request_epoch,
    ),
    root: input.conversation_root(conv),
    installed_skills: input.installed_skills,
    context_generation: input.composer_context_generation,
    pending_submission: None,
  }
}

///|
/// Keep an in-flight or settled Host query only while every part of its
/// identity still matches the local draft. Otherwise derive fresh bounded rows
/// from the root-owned file panel without copying the draft into the root.
fn ComposerEntry::file_completion_for(
  self : ComposerEntry,
  input : Model,
  text : String,
  root : @common.Uri?,
) -> ComposerFileCompletion {
  let query = if @composer.Trigger::parse(text, inline_markers="$#@")
    is Some(trigger) &&
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
      input.file_panel.request_epoch,
    ) {
    self.file_completion
  } else {
    let (files, loading) = input.completion_files(text)
    Local(files~, loading~, epoch=input.file_panel.request_epoch)
  }
}

///|
/// Adopt root-side recovery without treating ordinary root renders as draft
/// writes. A successful prompt submission clears only the prompt; a successful
/// goal submission clears only goal mode, preserving a prompt that was waiting
/// underneath it.
fn ComposerEntry::reconciled(
  self : ComposerEntry,
  input : Model,
) -> ComposerEntry {
  let conv = input.active()
  let incoming : ComposerDraft = { task: conv.task, mentions: conv.mentions }
  let incoming_goal = conv.goal_edit.map(edit => edit.draft)
  let root = input.conversation_root(conv)
  let context_changed = self.context_generation !=
    input.composer_context_generation
  let root_changed = root != self.root
  let skills_changed = self.installed_skills != input.installed_skills
  match self.pending_submission {
    Some(PromptSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before => {
      let symbol_cache = if root_changed {
        empty_symbol_cache()
      } else {
        self.symbol_cache
      }
      let file_completion = self.file_completion_for(input, incoming.task, root)
      return {
        ..self,
        source: incoming,
        draft: incoming,
        source_goal: incoming_goal,
        goal_draft: incoming_goal,
        completion: None,
        symbol_cache,
        file_completion,
        root,
        installed_skills: input.installed_skills,
        context_generation: input.composer_context_generation,
        pending_submission: None,
      }
    }
    Some(GoalSubmission(sequence_before~, _)) if input.submission_sequence >
      sequence_before => {
      let draft = self.draft.reconciled(source=self.source, incoming~)
      let file_completion = self.file_completion_for(input, draft.task, root)
      return {
        ..self,
        source: incoming,
        draft,
        source_goal: incoming_goal,
        goal_draft: incoming_goal,
        completion: None,
        symbol_cache: if root_changed {
          empty_symbol_cache()
        } else {
          self.symbol_cache
        },
        file_completion,
        root,
        installed_skills: input.installed_skills,
        context_generation: input.composer_context_generation,
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
      (None, _, Some(incoming)) => Some(incoming)
      (Some(source), Some(draft_value), Some(incoming)) =>
        if incoming == source {
          Some(draft_value)
        } else if draft_value == source || draft_value.is_empty() {
          Some(incoming)
        } else if incoming.is_empty() || incoming == draft_value {
          Some(draft_value)
        } else {
          Some(incoming + "\n\n" + draft_value)
        }
      (Some(_), None, Some(incoming)) => Some(incoming)
    }
  }
  let symbol_cache = if root_changed {
    empty_symbol_cache()
  } else {
    self.symbol_cache
  }
  let file_completion = self.file_completion_for(input, draft.task, root)
  let visible_files_changed = file_completion != self.file_completion &&
    self.completion is Some(current) &&
    current.kind is Files
  let completion = if incoming_goal is Some(_) || context_changed {
    None
  } else if draft != self.draft ||
    root_changed ||
    skills_changed ||
    visible_files_changed {
    compute_completion(
      draft.task,
      input.installed_skills,
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
    root,
    installed_skills: input.installed_skills,
    context_generation: input.composer_context_generation,
    pending_submission,
  }
}

///|
priv struct ComposerComponentModel {
  entries : Array[ComposerEntry]
} derive(Eq)

///|
fn ComposerComponentModel::ComposerComponentModel(
  input : Model,
) -> ComposerComponentModel {
  { entries: [ComposerEntry(input)] }
}

///|
fn ComposerComponentModel::active(
  self : ComposerComponentModel,
  input : Model,
) -> ComposerEntry {
  let conv = input.active()
  let owner : @interop.ConversationKey = {
    channel: input.focused,
    session: conv.session_id,
  }
  for entry in self.entries {
    if entry.owner == owner {
      return entry.reconciled(input)
    }
  }
  // Archiving replaces the active session id while this component still owns
  // the live textarea. Move that one cached entry to the fresh owner, then use
  // the normal three-way reconciliation to combine it with root-side salvage.
  if input.composer_entry_replacement is Some(replacement) &&
    replacement.fresh == owner {
    for entry in self.entries {
      if entry.owner == replacement.archived {
        return {
          ..entry,
          owner,
          completion: None,
          symbol_cache: empty_symbol_cache(),
          pending_submission: None,
        }.reconciled(input)
      }
    }
  }
  ComposerEntry(input)
}

///|
fn ComposerComponentModel::with_entry(
  self : ComposerComponentModel,
  entry : ComposerEntry,
) -> ComposerComponentModel {
  let entries = self.entries.copy()
  for index, existing in entries {
    if existing.owner == entry.owner {
      entries[index] = entry
      return { entries, }
    }
  }
  entries.push(entry)
  { entries, }
}

///|
priv enum ComposerComponentMsg {
  ComposerTextChanged(String)
  ComposerCompletionDue(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri?,
    query~ : String,
    generation~ : Int
  )
  ComposerCompletionMove(Int)
  ComposerCompletionAccept
  ComposerCompletionPick(Int)
  ComposerCompletionDismiss
  ComposerMentionRemoved(Int)
  ComposerMentionJumped(Int)
  ComposerGoalCancelled
  ComposerSubmitRequested
  ComposerSymbolsLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    items~ : Array[WorkspaceSymbol]
  )
  ComposerSymbolsFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int
  )
  // The shared file panel is root-owned input. A short-lived subscription
  // checks it while an `@` menu is loading, so an index reply can advance this
  // local state without mirroring the textarea value into the root Model.
  ComposerFileCompletionTick
  ComposerFilesLoaded(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    epoch~ : Int,
    files~ : Array[@pathx.Relative]
  )
  ComposerFilesFailed(
    owner~ : @interop.ConversationKey,
    root~ : @common.Uri,
    query~ : String,
    generation~ : Int,
    epoch~ : Int
  )
}

///|
/// The small set of actions whose ownership really is above the component.
/// Unlike keystrokes, each represents one deliberate user operation.
priv enum ComposerRootAction {
  ComposerDraftSubmitted(ComposerDraft)
  ComposerDraftPresenceChanged(
    owner~ : @interop.ConversationKey,
    present~ : Bool
  )
  // Editor and diff comments are root-authored mentions. Removing their chip
  // must clear that root snapshot too, or archive recovery can restore it.
  ComposerRootMentionRemoved(
    owner~ : @interop.ConversationKey,
    mention~ : Mention
  )
  ComposerSlashCommand(String)
  ComposerMentionOpened(Mention)
  ComposerGoalSubmitted(String, prompt_present~ : Bool)
}

///|
/// The root needs only this retention bit, not the draft contents. Goal text
/// counts while goal mode is open; a prompt waiting beneath it counts too.
fn ComposerEntry::holds_draft(self : ComposerEntry) -> Bool {
  !self.draft.task.is_blank() ||
  !self.draft.mentions.is_empty() ||
  (self.goal_draft is Some(goal) && !goal.is_blank())
}

///|
fn ComposerEntry::edited(
  self : ComposerEntry,
  input : Model,
  value : String,
  emit : @cmd.Emit[ComposerComponentMsg],
  root_emit : @cmd.Emit[Msg],
) -> (ComposerEntry, @cmd.Cmd) {
  let conv = input.active()
  if conv.goal_edit is Some(_) {
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
    epoch=input.file_panel.request_epoch,
  )
  let completion = compute_completion(
    value,
    input.installed_skills,
    self.symbol_cache,
    self.owner,
    files~,
    files_loading~,
  )
  let command = match @composer.Trigger::parse(value, inline_markers="$#@") {
    Some(trigger) if trigger.marker() == "#" &&
      (
        self.symbol_cache.owner != Some(self.owner) ||
        self.symbol_cache.root != self.root ||
        self.symbol_cache.query != trigger.query()
      ) =>
      completion_debounce.delayed(generation => {
        emit(
          ComposerCompletionDue(
            owner=self.owner,
            root=self.root,
            query=trigger.query(),
            generation~,
          ),
        )
      })
    Some(trigger) if trigger.marker() == "@" &&
      self.root is Some(_) &&
      (
        input.file_panel.index is @fileeditor.IndexEmpty ||
        input.file_panel.index is @fileeditor.IndexFailed
      ) => root_emit(FileEditor(@fileeditor.EnsureFileIndex))
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
fn ComposerEntry::accept_completion(
  self : ComposerEntry,
  item : CompletionItem,
  root_emit : @cmd.Emit[Msg],
) -> (ComposerEntry, @cmd.Cmd) {
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
        root_emit(ComposerAction(ComposerSlashCommand(item.command))),
      )
    SkillMentions =>
      (
        {
          ..self,
          draft: {
            task: completion.menu.draft_without_token(),
            mentions: push_mention(self.draft.mentions, {
              ref_: Skill(name=item.insert.trim().to_owned()),
              range: None,
            }),
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
            task: completion.menu.draft_without_token(),
            mentions: push_mention(self.draft.mentions, {
              ref_: Symbol(name=item.label, file~, line~),
              range: item.range,
            }),
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
              task: completion.menu.draft_without_token(),
              mentions: push_mention(self.draft.mentions, {
                ref_: File(path~),
                range: None,
              }),
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
/// Settle one exact Host file query. A failed request falls back to the bounded
/// local snapshot, while a successful request ranks the complete cached file
/// list with the same ordering used by Ctrl+P.
fn ComposerEntry::settled_file_completion(
  self : ComposerEntry,
  input : Model,
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  generation : Int,
  epoch : Int,
  remote_files : Array[@pathx.Relative]?,
) -> ComposerEntry? {
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
    @files.Search(
      remote_files,
      quick_open_open_files(input),
      @dock.active_file(input.dock),
    ).rank(query)
  } else {
    input.file_search().rank(query)
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
    completion: compute_completion(
      self.draft.task,
      input.installed_skills,
      self.symbol_cache,
      owner,
      files~,
      files_loading=false,
    ),
  })
}

///|
fn ComposerComponentModel::update(
  self : ComposerComponentModel,
  input : Model,
  msg : ComposerComponentMsg,
  emit : @cmd.Emit[ComposerComponentMsg],
  root_emit : @cmd.Emit[Msg],
) -> (ComposerComponentModel, @cmd.Cmd) {
  let entry = self.active(input)
  match msg {
    ComposerTextChanged(value) => {
      let (next, command) = entry.edited(input, value, emit, root_emit)
      self.commit_entry_change(entry, next, command, root_emit)
    }
    ComposerCompletionMove(delta) => {
      let entry = if entry.completion is Some(completion) {
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
      (self.with_entry(entry), @cmd.none)
    }
    ComposerCompletionDismiss =>
      (self.with_entry({ ..entry, completion: None }), @cmd.none)
    ComposerCompletionAccept => {
      guard entry.completion is Some(completion) &&
        completion.menu.current() is Some(item) else {
        return (self.with_entry({ ..entry, completion: None }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, root_emit)
      self.commit_entry_change(entry, next, command, root_emit)
    }
    ComposerCompletionPick(index) => {
      guard entry.completion is Some(completion) &&
        completion.menu.get(index) is Some(item) else {
        return (self.with_entry({ ..entry, completion: None }), @cmd.none)
      }
      let (next, command) = entry.accept_completion(item, root_emit)
      self.commit_entry_change(entry, next, command, root_emit)
    }
    ComposerMentionRemoved(index) => {
      guard entry.draft.mentions.get(index) is Some(mention) else {
        return (self.with_entry(entry), @cmd.none)
      }
      self.commit_entry_change(
        entry,
        { ..entry, draft: entry.draft.without_mention(index) },
        root_emit(
          ComposerAction(
            ComposerRootMentionRemoved(owner=entry.owner, mention~),
          ),
        ),
        root_emit,
      )
    }
    ComposerMentionJumped(index) => {
      guard entry.draft.mentions.get(index) is Some(mention) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (
        self.with_entry(entry),
        root_emit(ComposerAction(ComposerMentionOpened(mention))),
      )
    }
    ComposerGoalCancelled =>
      self.commit_entry_change(
        entry,
        {
          ..entry,
          goal_draft: None,
          completion: None,
          pending_submission: None,
        },
        root_emit(CloseGoalEditor),
        root_emit,
      )
    ComposerSubmitRequested =>
      if input.active().goal_edit is Some(_) {
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
          root_emit(
            ComposerAction(
              ComposerGoalSubmitted(
                text,
                prompt_present=!entry.draft.task.is_blank() ||
                  !entry.draft.mentions.is_empty(),
              ),
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
          root_emit(ComposerAction(ComposerDraftSubmitted(entry.draft))),
        )
      }
    ComposerCompletionDue(owner~, root~, query~, generation~) => {
      guard owner == entry.owner &&
        root == entry.root &&
        root is Some(root) &&
        entry.completion_debounce.accepts(generation) &&
        @composer.Trigger::parse(entry.draft.task, inline_markers="$#")
        is Some(trigger) &&
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
            emit(
              ComposerSymbolsLoaded(owner~, root~, query~, generation~, items~),
            )
          },
          failed=emit(ComposerSymbolsFailed(owner~, root~, query~, generation~)),
        ),
      )
    }
    ComposerSymbolsLoaded(owner~, root~, query~, generation~, items~) => {
      guard owner == entry.owner &&
        entry.root == Some(root) &&
        entry.completion_debounce.accepts(generation) &&
        @composer.Trigger::parse(entry.draft.task, inline_markers="$#")
        is Some(trigger) &&
        trigger.marker() == "#" &&
        trigger.query() == query &&
        entry.completion is Some(completion) &&
        completion.kind is Symbols &&
        completion.menu.loading() else {
        return (self.with_entry(entry), @cmd.none)
      }
      let rows : Array[CompletionItem] = []
      for item in items {
        rows.push(CompletionItem::from_symbol(item))
      }
      let symbol_cache : SymbolCache = {
        owner: Some(owner),
        root: Some(root),
        query,
        items: rows,
      }
      let completion = compute_completion(
        entry.draft.task,
        input.installed_skills,
        symbol_cache,
        owner,
        files=entry.file_completion.files(),
        files_loading=entry.file_completion.loading(),
      )
      (self.with_entry({ ..entry, symbol_cache, completion }), @cmd.none)
    }
    ComposerSymbolsFailed(owner~, root~, query~, generation~) =>
      self.update(
        input,
        ComposerSymbolsLoaded(owner~, root~, query~, generation~, items=[]),
        emit,
        root_emit,
      )
    ComposerFileCompletionTick => {
      guard @composer.Trigger::parse(entry.draft.task, inline_markers="$#@")
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
          match input.file_panel.index {
            @fileeditor.IndexEmpty | @fileeditor.IndexFailed =>
              (
                self.with_entry(entry),
                root_emit(FileEditor(@fileeditor.EnsureFileIndex)),
              )
            @fileeditor.IndexLoading(_) => (self.with_entry(entry), @cmd.none)
            @fileeditor.IndexReady(truncated=false, ..) =>
              (self.with_entry(entry), @cmd.none)
            @fileeditor.IndexReady(truncated=true, ..) => {
              let owner = entry.owner
              let query = trigger.query()
              let generation = entry.completion_debounce.generation()
              let pending = {
                ..entry,
                file_completion: RemotePending(
                  owner~,
                  root~,
                  query~,
                  generation~,
                  files~,
                  epoch~,
                ),
              }
              (
                self.with_entry(pending),
                @files.Request(owner.channel, owner.session, Some(root)).search_cached(
                  query,
                  generation,
                  (files, _limit_hit) => {
                    emit(
                      ComposerFilesLoaded(
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
                      ComposerFilesFailed(
                        owner~,
                        root~,
                        query~,
                        generation~,
                        epoch~,
                      ),
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
    ComposerFilesLoaded(owner~, root~, query~, generation~, epoch~, files~) => {
      guard entry.settled_file_completion(
          input,
          owner,
          root,
          query,
          generation,
          epoch,
          Some(files),
        )
        is Some(entry) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (self.with_entry(entry), @cmd.none)
    }
    ComposerFilesFailed(owner~, root~, query~, generation~, epoch~) => {
      guard entry.settled_file_completion(
          input,
          owner,
          root,
          query,
          generation,
          epoch,
          None,
        )
        is Some(entry) else {
        return (self.with_entry(entry), @cmd.none)
      }
      (self.with_entry(entry), @cmd.none)
    }
  }
}

///|
/// Store one local transition and notify the root only when its retention
/// answer changed. The command is batched with that one-bit notification so
/// slash commands and goal cancellation remain single user operations.
fn ComposerComponentModel::commit_entry_change(
  self : ComposerComponentModel,
  previous : ComposerEntry,
  entry : ComposerEntry,
  command : @cmd.Cmd,
  root_emit : @cmd.Emit[Msg],
) -> (ComposerComponentModel, @cmd.Cmd) {
  let presence = if previous.holds_draft() != entry.holds_draft() {
    root_emit(
      ComposerAction(
        ComposerDraftPresenceChanged(
          owner=entry.owner,
          present=entry.holds_draft(),
        ),
      ),
    )
  } else {
    @cmd.none
  }
  (self.with_entry(entry), @cmd.batch([command, presence]))
}

///|
/// Watch root-owned file-index input only while a visible `@` menu is waiting.
/// `create_state_with_input` deliberately does not turn input changes into
/// messages, so this bounded subscription gives the local state machine a
/// chance to observe index completion without sending textarea edits upward.
fn ComposerComponentModel::subscriptions(
  self : ComposerComponentModel,
  input : Model,
  emit : @cmd.Emit[ComposerComponentMsg],
) -> @sub.Sub {
  let entry = self.active(input)
  if entry.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() {
    @sub.every(150, emit(ComposerFileCompletionTick))
  } else {
    @sub.none
  }
}

///|
/// Build the composer once and return its independently updated HTML value.
/// Root state remains an input for availability and status; component-local
/// messages never put their text in the root update loop. Only deliberate
/// actions and empty/non-empty retention transitions emit root messages.
fn composer_component(
  input : @rabbita.Val[Model],
  root_emit : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, input) => (ComposerComponentModel(input), @cmd.none),
    update=(state, input, msg, emit) => {
      state.update(input, msg, emit, root_emit)
    },
    subscriptions=(state, input, emit) => state.subscriptions(input, emit),
  )
  state.view2(input, (state, input) => {
    state.active(input).view(emit, root_emit, input)
  })
}

///|
test "composer typing is pure and does not mutate the root draft" {
  let input = test_model()
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let initial = ComposerComponentModel(input)
  let (once, _) = initial.update(
    input,
    ComposerTextChanged("a local draft"),
    component_emit,
    root_emit,
  )
  let (twice, _) = initial.update(
    input,
    ComposerTextChanged("a local draft"),
    component_emit,
    root_emit,
  )
  // Replaying the same component message is deterministic, while the root
  // snapshot supplied to both calls remains untouched.
  assert_eq(once.active(input).draft.task, "a local draft")
  assert_eq(twice.active(input).draft.task, "a local draft")
  assert_eq(input.active().task, "")
  assert_eq(input.submission_sequence, 0)
}

///|
test "isolated composer refreshes and accepts workspace file completion" {
  let initial = test_model()
  let owner : @interop.ConversationKey = {
    channel: initial.focused,
    session: initial.active_session,
  }
  let root = initial.focused.test_resource("/scratch/desktop-test")
  let panel = {
    ..initial.file_panel,
    owner: Some(owner),
    placement_known: true,
    placement_root: Some(root),
    placement_checkout: Some(@interop.WorkspaceRoot),
  }
  let base = { ..initial, file_panel: panel }
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let file_emit = root_emit.map(msg => FileEditor(msg))
  let (_, loading_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(base),
  )
  let loading = { ..base, file_panel: loading_panel }
  let (typed, _) = ComposerComponentModel(loading).update(
    loading,
    ComposerTextChanged("Inspect @main"),
    component_emit,
    root_emit,
  )
  guard typed.active(loading).completion is Some(pending) else {
    fail("the @ menu should open while the workspace index loads")
  }
  assert_true(pending.kind is Files)
  assert_true(pending.menu.loading())
  let (_, ready_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.FilesIndexed(
      owner~,
      epoch=loading_panel.request_epoch,
      files=[@pathx.Relative("src/main.mbt")],
      truncated=false,
    ),
    loading_panel,
    file_ctx(loading),
  )
  let ready = { ..loading, file_panel: ready_panel }
  let (refreshed, _) = typed.update(
    ready,
    ComposerFileCompletionTick,
    component_emit,
    root_emit,
  )
  let reconciled = refreshed.active(ready)
  guard reconciled.completion is Some(completion) &&
    completion.menu.current() is Some(item) else {
    fail("the settled index should refresh the live @ menu")
  }
  assert_false(completion.menu.loading())
  assert_eq(item.path, Some("src/main.mbt"))
  let (accepted, _) = reconciled.accept_completion(item, root_emit)
  assert_eq(accepted.draft.task, "Inspect ")
  assert_true(
    accepted.draft.mentions is [{ ref_: File(path="src/main.mbt"), .. }],
  )
}

///|
test "isolated composer settles a truncated file index from the Host cache" {
  let initial = test_model()
  let owner : @interop.ConversationKey = {
    channel: initial.focused,
    session: initial.active_session,
  }
  let root = initial.focused.test_resource("/scratch/desktop-test")
  let panel = {
    ..initial.file_panel,
    owner: Some(owner),
    placement_known: true,
    placement_root: Some(root),
    placement_checkout: Some(@interop.WorkspaceRoot),
  }
  let base = { ..initial, file_panel: panel }
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let file_emit = root_emit.map(msg => FileEditor(msg))
  let (_, loading_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(base),
  )
  let (_, truncated_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.FilesIndexed(
      owner~,
      epoch=loading_panel.request_epoch,
      files=[@pathx.Relative("src/visible.mbt")],
      truncated=true,
    ),
    loading_panel,
    file_ctx(base),
  )
  let indexed = { ..base, file_panel: truncated_panel }
  let (typed, _) = ComposerComponentModel(indexed).update(
    indexed,
    ComposerTextChanged("Inspect @hidden"),
    component_emit,
    root_emit,
  )
  let (querying, _) = typed.update(
    indexed,
    ComposerFileCompletionTick,
    component_emit,
    root_emit,
  )
  let generation = querying.active(indexed).completion_debounce.generation()
  let epoch = truncated_panel.request_epoch
  assert_true(querying.active(indexed).file_completion is RemotePending(..))
  let (loaded, _) = querying.update(
    indexed,
    ComposerFilesLoaded(owner~, root~, query="hidden", generation~, epoch~, files=[
      @pathx.Relative("other/hidden.mbt"),
    ]),
    component_emit,
    root_emit,
  )
  guard loaded.active(indexed).completion is Some(completion) &&
    completion.menu.current() is Some(item) else {
    fail("the complete Host cache should settle truncated file completion")
  }
  assert_false(completion.menu.loading())
  assert_eq(item.path, Some("other/hidden.mbt"))
}

///|
test "a dismissed local file menu stays closed when its index settles" {
  let initial = test_model()
  let owner : @interop.ConversationKey = {
    channel: initial.focused,
    session: initial.active_session,
  }
  let root = initial.focused.test_resource("/scratch/desktop-test")
  let panel = {
    ..initial.file_panel,
    owner: Some(owner),
    placement_known: true,
    placement_root: Some(root),
    placement_checkout: Some(@interop.WorkspaceRoot),
  }
  let base = { ..initial, file_panel: panel }
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let file_emit = root_emit.map(msg => FileEditor(msg))
  let (_, loading_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(base),
  )
  let loading = { ..base, file_panel: loading_panel }
  let (typed, _) = ComposerComponentModel(loading).update(
    loading,
    ComposerTextChanged("Inspect @main"),
    component_emit,
    root_emit,
  )
  let (dismissed, _) = typed.update(
    loading,
    ComposerCompletionDismiss,
    component_emit,
    root_emit,
  )
  let (_, ready_panel) = @fileeditor.update(
    file_emit,
    @fileeditor.FilesIndexed(
      owner~,
      epoch=loading_panel.request_epoch,
      files=[@pathx.Relative("src/main.mbt")],
      truncated=false,
    ),
    loading_panel,
    file_ctx(loading),
  )
  let ready = { ..loading, file_panel: ready_panel }
  assert_true(dismissed.active(ready).completion is None)
}

///|
#warnings("-alert_unstable")
test "composer send gate reads the local draft rather than the root snapshot" {
  let input = test_model()
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let entry = {
    ..ComposerEntry(input),
    draft: { task: "ready locally", mentions: [] },
  }
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(entry.view(component_emit, test_dispatch(), input))
  })
  guard markup.split_once("id=\"send\"") is Some((_, after_id)) else {
    fail("the send button should render")
  }
  guard after_id.split_once(">") is Some((opening, _)) else {
    fail("the send button opening tag should end")
  }
  assert_false(opening.contains("disabled"))
  assert_eq(input.active().task, "")
}

///|
test "composer caches an independent local draft for each conversation" {
  let conversation_a = empty_conversation(
    @interop.ChannelId::Local,
    "composer-a",
  )
  let conversation_b = empty_conversation(
    @interop.ChannelId::Local,
    "composer-b",
  )
  let input_a = {
    ..test_model(),
    active_session: "composer-a",
    conversations: [conversation_a, conversation_b],
  }
  let input_b = {
    ..input_a,
    active_session: "composer-b",
    composer_context_generation: 1,
  }
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let (drafted_a, _) = ComposerComponentModel(input_a).update(
    input_a,
    ComposerTextChanged("draft A"),
    component_emit,
    root_emit,
  )
  let (drafted_b, _) = drafted_a.update(
    input_b,
    ComposerTextChanged("draft B"),
    component_emit,
    root_emit,
  )
  assert_eq(drafted_b.active(input_a).draft.task, "draft A")
  assert_eq(drafted_b.active(input_b).draft.task, "draft B")
  assert_eq(input_a.active().task, "")
  assert_eq(input_b.active().task, "")
}

///|
test "composer retention uses one root bit instead of mirrored text" {
  let input = test_model()
  let owner : @interop.ConversationKey = {
    channel: input.focused,
    session: input.active_session,
  }
  let (_, retained) = update(
    test_dispatch(),
    ComposerAction(ComposerDraftPresenceChanged(owner~, present=true)),
    input,
  )
  assert_eq(retained.active().task, "")
  assert_true(retained.active().composer_draft_present)
  assert_eq(conversation_title(retained.active()), "New chat")
  let switched = retained.activate(
    @interop.ChannelId::Local,
    "another-conversation",
  )
  assert_true(
    switched.find_conversation(owner.channel, owner.session) is Some(_),
  )
  let (_, released) = update(
    test_dispatch(),
    ComposerAction(ComposerDraftPresenceChanged(owner~, present=false)),
    retained,
  )
  assert_false(released.active().composer_draft_present)
}

///|
test "archive replacement carries the component-local prompt and goal" {
  let input = test_model().with_dev(dev => {
    ..dev,
    sessions: [archived_item("desktop-test")],
  })
  let owner : @interop.ConversationKey = {
    channel: input.focused,
    session: input.active_session,
  }
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let (drafted, _) = ComposerComponentModel(input).update(
    input,
    ComposerTextChanged("local prompt"),
    component_emit,
    root_emit,
  )
  let (_, retained) = update(
    root_emit,
    ComposerAction(ComposerDraftPresenceChanged(owner~, present=true)),
    input,
  )
  let goal_input = retained.replace_conversation({
    ..retained.active(),
    goal_edit: Some({ draft: "root goal" }),
  })
  let (with_goal, _) = drafted.update(
    goal_input,
    ComposerTextChanged("local goal"),
    component_emit,
    root_emit,
  )
  let (_, replaced) = update_dev(
    root_emit,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-fresh"),
    ),
    goal_input,
  )
  let carried = with_goal.active(replaced)
  inspect(carried.owner.session, content="desktop-fresh")
  inspect(carried.draft.task, content="local prompt")
  assert_eq(carried.goal_draft, Some("local goal"))
  assert_true(replaced.active().composer_draft_present)
}

///|
test "removed root mention stays removed across archive replacement" {
  let mention : Mention = { ref_: Skill(name="review"), range: None }
  let input = test_model()
    .replace_conversation({ ..test_conversation(), mentions: [mention] })
    .with_dev(dev => { ..dev, sessions: [archived_item("desktop-test")] })
  let owner : @interop.ConversationKey = {
    channel: input.focused,
    session: input.active_session,
  }
  let dispatch = test_dispatch()
  let (_, replaced) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-fresh"),
    ),
    input,
  )
  inspect(replaced.active().mentions.length(), content="1")
  // A removal queued by the old component owner must land on the fresh root
  // snapshot instead of reviving the chip on the next reconciliation.
  let (_, removed) = update(
    dispatch,
    ComposerAction(ComposerRootMentionRemoved(owner~, mention~)),
    replaced,
  )
  inspect(removed.active().mentions.length(), content="0")
  assert_true(removed.active().draft_empty())
}

///|
test "composer recovery merges a root draft with newer local typing" {
  let input = test_model()
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let (drafted, _) = ComposerComponentModel(input).update(
    input,
    ComposerTextChanged("newer local text"),
    component_emit,
    root_emit,
  )
  let recovered = input.replace_conversation({
    ..input.active(),
    task: "restored delivery text",
  })
  // Both pieces remain visible rather than silently choosing one writer.
  assert_eq(
    drafted.active(recovered).draft.task,
    "restored delivery text\n\nnewer local text",
  )
}

///|
test "composer clears a submitted prompt only after the root accepts it" {
  let input = test_model()
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let (drafted, _) = ComposerComponentModel(input).update(
    input,
    ComposerTextChanged("ship this"),
    component_emit,
    root_emit,
  )
  let (submitted, _) = drafted.update(
    input,
    ComposerSubmitRequested,
    component_emit,
    root_emit,
  )
  // Merely emitting the root action is not success; a rejected submission
  // keeps the exact draft available for retry.
  assert_eq(submitted.active(input).draft.task, "ship this")
  let rejected = input.replace_conversation({
    ..input.active(),
    task: "ship this",
  })
  assert_eq(submitted.active(rejected).draft.task, "ship this")
  // Submission sequence is the root's acceptance acknowledgement. The root
  // draft is empty in this snapshot because Send consumed it atomically.
  let accepted = { ..input, submission_sequence: 1 }
  assert_eq(submitted.active(accepted).draft.task, "")
}

///|
test "submitting a goal preserves the local prompt underneath goal mode" {
  let input = test_model()
  let component_emit : @cmd.Emit[ComposerComponentMsg] = @cmd.Emit(_ => {
    @cmd.none
  })
  let root_emit = test_dispatch()
  let (prompted, _) = ComposerComponentModel(input).update(
    input,
    ComposerTextChanged("prompt waiting below"),
    component_emit,
    root_emit,
  )
  let goal_input = input.replace_conversation({
    ..input.active(),
    goal_edit: Some({ draft: "old goal" }),
  })
  let (edited, _) = prompted.update(
    goal_input,
    ComposerTextChanged("new goal"),
    component_emit,
    root_emit,
  )
  let (submitted, _) = edited.update(
    goal_input,
    ComposerSubmitRequested,
    component_emit,
    root_emit,
  )
  let accepted = { ..input, submission_sequence: 1 }
  let reconciled = submitted.active(accepted)
  assert_eq(reconciled.draft.task, "prompt waiting below")
  assert_true(reconciled.goal_draft is None)
}
