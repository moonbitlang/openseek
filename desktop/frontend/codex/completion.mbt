// Codex composer completion. Slash commands call dedicated app-server
// methods; `#` uses the same workspace-symbol search as OpenSeek, `@` uses
// the same host file index and fuzzy ranking as Ctrl+P, and `$` uses Codex
// app-server's cwd-scoped skill catalog.

///|
priv enum CodexCompletionKind {
  CodexCommands
  CodexSkills
  CodexSymbols
  CodexFiles
} derive(Eq)

///|
priv struct CodexCompletionItem {
  label : String
  detail : String
  command : String
  name : String
  path : String
  range : @common.Range?
} derive(Eq)

///|
priv enum CodexMention {
  CodexFileMention(name~ : String, path~ : String)
  CodexSkillMention(name~ : String, path~ : String)
  CodexSymbolMention(name~ : String, path~ : String, range~ : @common.Range)
  CodexEditorAnnotation(
    file~ : String,
    range~ : @common.Range,
    quote~ : String,
    comment~ : String
  )
} derive(Eq)

///|
fn CodexCompletionKind::of_trigger(
  trigger : @composer.Trigger,
) -> CodexCompletionKind? {
  match trigger.marker() {
    "/" => Some(CodexCommands)
    "$" => Some(CodexSkills)
    "#" => Some(CodexSymbols)
    "@" => Some(CodexFiles)
    _ => None
  }
}

///|
priv struct CodexSearchOwner {
  thread_id : String
  cwd : String
  query : String
} derive(Eq)

///|
priv struct CodexFileOwner {
  thread_id : String
  cwd : String
} derive(Eq)

///|
priv enum CodexFileIndex {
  CodexFilesEmpty
  CodexFilesLoading(CodexFileOwner)
  CodexFilesReady(CodexFileOwner, Array[@pathx.Relative], Bool)
  CodexFilesFailed(CodexFileOwner)
} derive(Eq)

///|
priv struct CodexSkill {
  name : String
  description : String
  path : String
} derive(Eq)

///|
priv enum CodexSkillCatalog {
  CodexSkillsEmpty
  CodexSkillsLoading(String)
  CodexSkillsReady(String, Array[CodexSkill])
  CodexSkillsFailed(String)
} derive(Eq)

///|
fn CodexSkill::decode_list(value : Json, cwd : String) -> Array[CodexSkill]? {
  guard value is Object(fields) && fields.get("data") is Some(Array(entries)) else {
    return None
  }
  for index, entry in entries {
    guard entry is Object(entry_fields) &&
      @jsonx.json_text(entry_fields, "cwd") is Some(entry_cwd) &&
      (entry_cwd == cwd || (entries.length() == 1 && index == 0)) &&
      entry_fields.get("skills") is Some(Array(skills)) else {
      continue
    }
    let decoded : Array[CodexSkill] = []
    for skill in skills {
      guard skill is Object(skill_fields) &&
        @jsonx.json_bool(skill_fields, "enabled").unwrap_or(false) &&
        @jsonx.json_text(skill_fields, "name") is Some(name) &&
        @jsonx.json_text(skill_fields, "description") is Some(description) &&
        @jsonx.json_text(skill_fields, "path") is Some(path) else {
        continue
      }
      decoded.push({ name, description, path })
    }
    return Some(decoded)
  }
  None
}

///|
priv struct CodexSymbolSearchCache {
  owner : CodexSearchOwner?
  items : Array[CodexCompletionItem]
} derive(Eq)

///|
fn CodexSymbolSearchCache::empty() -> CodexSymbolSearchCache {
  { owner: None, items: [] }
}

///|
fn CodexCompletionItem::commands() -> Array[CodexCompletionItem] {
  [
    {
      label: "/compact",
      detail: "Summarize and shrink this conversation's context",
      command: "compact",
      name: "",
      path: "",
      range: None,
    },
    {
      label: "/review",
      detail: "Review staged, unstaged, and untracked changes",
      command: "review",
      name: "",
      path: "",
      range: None,
    },
  ]
}

///|
fn CodexCompletionItem::from_file(file : @files.Match) -> CodexCompletionItem {
  {
    label: file.name,
    detail: file.path.0,
    command: "",
    name: file.name,
    path: file.path.0,
    range: None,
  }
}

///|
fn CodexCompletionItem::from_skill(skill : CodexSkill) -> CodexCompletionItem {
  {
    label: "$\{skill.name}",
    detail: skill.description,
    command: "",
    name: skill.name,
    path: skill.path,
    range: None,
  }
}

///|
fn CodexCompletionItem::from_symbol(
  symbol : @symbols.Symbol,
) -> CodexCompletionItem {
  {
    label: symbol.name,
    detail: symbol.detail(),
    command: "",
    name: symbol.name,
    path: symbol.path,
    range: Some(symbol.range),
  }
}

///|
fn State::search_owner(self : State, query : String) -> CodexSearchOwner? {
  self
  .file_owner()
  .map(owner => { thread_id: owner.thread_id, cwd: owner.cwd, query })
}

///|
fn State::file_owner(self : State) -> CodexFileOwner? {
  match self.selection {
    CodexDraftTask(draft) =>
      draft.project_root.map(cwd => { thread_id: draft.id, cwd })
    CodexStoredTask(active) => {
      guard !self.has_missing_worktree() &&
        active.cwd is Some(cwd) &&
        !cwd.trim().is_empty() else {
        return None
      }
      Some({ thread_id: active.id, cwd })
    }
    CodexNoTask => None
  }
}

///|
fn CodexFileIndex::search(
  self : CodexFileIndex,
  owner : CodexFileOwner,
  query : String,
) -> (Array[CodexCompletionItem], Bool) {
  match self {
    CodexFilesReady(current, paths, _) if current == owner =>
      (
        @files.Search(paths, [], None)
        .rank(query)
        .map(CodexCompletionItem::from_file),
        false,
      )
    CodexFilesFailed(current) if current == owner => ([], false)
    _ => ([], true)
  }
}

///|
fn CodexSkillCatalog::search(
  self : CodexSkillCatalog,
  cwd : String,
  trigger : @composer.Trigger,
) -> (Array[CodexCompletionItem], Bool) {
  match self {
    CodexSkillsReady(current, skills) if current == cwd =>
      (
        skills
        .filter(skill => trigger.matches([skill.name, skill.description]))
        .map(CodexCompletionItem::from_skill),
        false,
      )
    CodexSkillsFailed(current) if current == cwd => ([], false)
    _ => ([], true)
  }
}

///|
fn State::completion_for_draft(
  self : State,
  text : String,
) -> @composer.ControllerCompletion[CodexCompletionKind, CodexCompletionItem]? {
  guard @composer.Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    CodexCompletionKind::of_trigger(trigger) is Some(kind) else {
    return None
  }
  match kind {
    CodexCommands => {
      let items = CodexCompletionItem::commands().filter(item => {
        trigger.matches([item.label, item.detail])
      })
      if items.is_empty() {
        None
      } else {
        Some(
          @composer.ControllerCompletion(
            CodexCommands,
            @composer.Menu(
              items,
              loading=false,
              draft_without_token=trigger.draft_without_token(),
            ),
          ),
        )
      }
    }
    CodexSkills => {
      let (items, loading) = match self.file_owner() {
        Some(owner) => self.skills.search(owner.cwd, trigger)
        _ => ([], false)
      }
      Some(
        @composer.ControllerCompletion(
          CodexSkills,
          @composer.Menu(
            items,
            loading~,
            draft_without_token=trigger.draft_without_token(),
          ),
        ),
      )
    }
    CodexSymbols => {
      let owner = self.search_owner(trigger.query())
      let items = if owner is Some(_) && self.symbol_search.owner == owner {
        self.symbol_search.items.filter(item => {
          trigger.matches([item.name, item.detail, item.path])
        })
      } else {
        []
      }
      Some(
        @composer.ControllerCompletion(
          CodexSymbols,
          @composer.Menu(
            items,
            loading=owner is Some(_) && self.symbol_search.owner != owner,
            draft_without_token=trigger.draft_without_token(),
          ),
        ),
      )
    }
    CodexFiles => {
      let (items, loading) = match self.file_owner() {
        Some(owner) => self.file_index.search(owner, trigger.query())
        None => ([], false)
      }
      Some(
        @composer.ControllerCompletion(
          CodexFiles,
          @composer.Menu(
            items,
            loading~,
            draft_without_token=trigger.draft_without_token(),
          ),
        ),
      )
    }
  }
}

///|
fn State::with_context_mention(
  self : State,
  kind : CodexCompletionKind,
  item : CodexCompletionItem,
  draft_without_token : String,
) -> State {
  let mention = match kind {
    CodexFiles => CodexFileMention(name=item.name, path=item.path)
    CodexSkills => CodexSkillMention(name=item.name, path=item.path)
    CodexSymbols => {
      guard item.range is Some(range) else { return self }
      CodexSymbolMention(name=item.name, path=item.path, range~)
    }
    CodexCommands => return self
  }
  let mentions = self.mentions.copy()
  if !mentions.contains(mention) {
    mentions.push(mention)
  }
  { ..self, draft: draft_without_token, mentions }
}

///|
fn State::composer_controller(
  self : State,
) -> @composer.Controller[
  CodexCompletionKind,
  CodexCompletionItem,
  CodexMention,
] {
  @composer.Controller(self.draft, self.mentions, self.completion)
}

///|
/// Project the shared controller result back into Codex state. Account,
/// thread, provider caches, and app-server lifecycle never cross this boundary.
fn State::with_composer_controller(
  self : State,
  controller : @composer.Controller[
    CodexCompletionKind,
    CodexCompletionItem,
    CodexMention,
  ],
) -> State {
  {
    ..self,
    draft: controller.draft(),
    mentions: controller.mentions(),
    completion: controller.completion(),
  }
}

///|
fn State::input_empty(self : State) -> Bool {
  self.draft.trim().is_empty() && self.mentions.is_empty()
}

///|
fn State::with_files(
  self : State,
  owner : CodexFileOwner,
  files : Array[@pathx.Relative],
  truncated : Bool,
) -> State {
  guard self.file_owner() == Some(owner) else { return self }
  let next = { ..self, file_index: CodexFilesReady(owner, files, truncated) }
  {
    ..next,
    completion: next.completion.refreshed(next.completion_for_draft(next.draft)),
  }
}

///|
fn State::with_file_failure(self : State, owner : CodexFileOwner) -> State {
  guard self.file_owner() == Some(owner) else { return self }
  // A refresh failure must not discard a usable index already shown for this
  // owner. Initial failures settle the loading menu as empty and retryable.
  let file_index = match self.file_index {
    CodexFilesReady(current, _, _) if current == owner => self.file_index
    _ => CodexFilesFailed(owner)
  }
  let next = { ..self, file_index, }
  {
    ..next,
    completion: next.completion.refreshed(next.completion_for_draft(next.draft)),
  }
}

///|
fn State::with_skills(
  self : State,
  cwd : String,
  skills : Array[CodexSkill],
) -> State {
  guard self.file_owner() is Some(owner) && owner.cwd == cwd else {
    return self
  }
  let next = { ..self, skills: CodexSkillsReady(cwd, skills) }
  {
    ..next,
    completion: next.completion.refreshed(next.completion_for_draft(next.draft)),
  }
}

///|
fn State::with_skill_failure(self : State, cwd : String) -> State {
  guard self.file_owner() is Some(owner) && owner.cwd == cwd else {
    return self
  }
  // Keep a previously rendered catalog across a transient refresh failure.
  let skills = match self.skills {
    CodexSkillsReady(current, _) if current == cwd => self.skills
    _ => CodexSkillsFailed(cwd)
  }
  let next = { ..self, skills, }
  {
    ..next,
    completion: next.completion.refreshed(next.completion_for_draft(next.draft)),
  }
}

///|
/// Mark both cwd-scoped catalogs as loading when a thread becomes active.
/// Existing data for the same owner stays usable while a notification refresh
/// runs; switching owners never exposes rows from the previous workspace.
fn State::loading_context(self : State, force_skills : Bool) -> State {
  guard self.file_owner() is Some(file_owner) else { return self }
  let skills = match self.skills {
    CodexSkillsReady(cwd, _) if cwd == file_owner.cwd && !force_skills =>
      self.skills
    CodexSkillsLoading(cwd) if cwd == file_owner.cwd => self.skills
    _ => CodexSkillsLoading(file_owner.cwd)
  }
  let file_index = match self.file_index {
    CodexFilesReady(owner, _, _) if owner == file_owner => self.file_index
    CodexFilesLoading(owner) if owner == file_owner => self.file_index
    _ => CodexFilesLoading(file_owner)
  }
  { ..self, skills, file_index }
}

///|
fn State::with_symbols(
  self : State,
  owner : CodexSearchOwner,
  generation : Int,
  symbols : Array[@symbols.Symbol],
) -> State {
  guard self.completion.accepts(generation) &&
    self.file_owner() is Some(current) &&
    current.thread_id == owner.thread_id &&
    current.cwd == owner.cwd &&
    @composer.Trigger::parse(self.draft, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "#" &&
    trigger.query() == owner.query &&
    self.completion.current() is Some(completion) &&
    completion.kind() is CodexSymbols &&
    completion.menu().loading() else {
    return self
  }
  let items = symbols.map(symbol => CodexCompletionItem::from_symbol(symbol))
  let next = { ..self, symbol_search: { owner: Some(owner), items } }
  {
    ..next,
    completion: next.completion.refreshed(next.completion_for_draft(next.draft)),
  }
}

///|
fn State::load_composer_provider(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  value : String,
) -> (@cmd.Cmd, State) {
  let completion = self.completion
  let command = if @composer.Trigger::parse(value, inline_markers="$#@")
    is Some(trigger) &&
    CodexCompletionKind::of_trigger(trigger) is Some(kind) &&
    self.search_owner(trigger.query()) is Some(owner) {
    match kind {
      CodexSymbols if self.symbol_search.owner != Some(owner) =>
        completion.delayed(generation => {
          dispatch(SymbolSearchDue(owner~, generation~))
        })
      _ => @cmd.none
    }
  } else {
    @cmd.none
  }
  let (context_command, next) = match
    @composer.Trigger::parse(value, inline_markers="$#@") {
    Some(trigger) if trigger.marker() == "@" && self.file_owner() is Some(owner) =>
      match self.file_index {
        CodexFilesReady(current, _, _) if current == owner => (@cmd.none, self)
        CodexFilesLoading(current) if current == owner => (@cmd.none, self)
        _ =>
          (
            self.load_files(dispatch, channel),
            { ..self, file_index: CodexFilesLoading(owner) },
          )
      }
    Some(trigger) if trigger.marker() == "$" && self.file_owner() is Some(owner) => {
      let cwd = owner.cwd
      match self.skills {
        CodexSkillsReady(current, _) if current == cwd => (@cmd.none, self)
        CodexSkillsLoading(current) if current == cwd => (@cmd.none, self)
        _ =>
          (
            self.load_skills(dispatch, channel, force_reload=false),
            { ..self, skills: CodexSkillsLoading(cwd) },
          )
      }
    }
    _ => (@cmd.none, self)
  }
  (@cmd.batch([command, context_command]), next)
}

///|
/// Start the delayed lookup only if no later draft edit or provider switch has
/// overtaken it. The same generation then fences the eventual app-server or
/// workspace-symbol reply.
fn State::begin_completion_search(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  kind : CodexCompletionKind,
  owner : CodexSearchOwner,
  generation : Int,
) -> (@cmd.Cmd, State) {
  guard self.completion.accepts(generation) &&
    self.file_owner() is Some(current) &&
    current.thread_id == owner.thread_id &&
    current.cwd == owner.cwd &&
    @composer.Trigger::parse(self.draft, inline_markers="$#@") is Some(trigger) &&
    CodexCompletionKind::of_trigger(trigger) == Some(kind) &&
    trigger.query() == owner.query &&
    self.completion.current() is Some(completion) &&
    completion.kind() == kind &&
    completion.menu().loading() else {
    return (@cmd.none, self)
  }
  let command = match kind {
    CodexSymbols if self.symbol_search.owner != Some(owner) =>
      self.search_symbols(dispatch, channel, owner, generation)
    CodexCommands | CodexSkills | CodexFiles => @cmd.none
    _ => @cmd.none
  }
  (command, self)
}

///|
fn State::accept_completion(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  kind : CodexCompletionKind,
  item : CodexCompletionItem,
  draft_without_token : String,
) -> (@cmd.Cmd, State) {
  match kind {
    CodexSkills | CodexSymbols | CodexFiles =>
      (@cmd.none, self.with_context_mention(kind, item, draft_without_token))
    CodexCommands => {
      let original = self.draft
      let command = match item.command {
        "compact" => self.compact(dispatch, channel, original)
        "review" => self.review(dispatch, channel, original)
        _ => @cmd.none
      }
      (
        command,
        {
          ..self,
          loading: item.command == "compact" || item.command == "review",
          notice: "",
        },
      )
    }
  }
}

///|
/// Codex's adapter around the one shared input controller. Every input first
/// crosses the same transition; typed requests are then interpreted with
/// app-server catalogs, commands, and writer ownership.
fn State::update_composer(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  msg : @composer.ControllerMsg,
) -> (@cmd.Cmd, State) {
  self
  .composer_controller()
  .update_parent(
    self,
    msg,
    text => self.completion_for_draft(text),
    (state, controller) => state.with_composer_controller(controller),
    (next, request) => {
      match request {
        @composer.NoControllerRequest => (@cmd.none, next)
        @composer.DraftUpdated(value) =>
          next.load_composer_provider(dispatch, channel, value)
        @composer.CompletionChosen(kind~, item~, draft_without_token~) =>
          next.accept_completion(
            dispatch, channel, kind, item, draft_without_token,
          )
        @composer.SubmissionRequested => next.submit_composer(dispatch, channel)
      }
    },
  )
}

///|
/// Interpret the controller's submit request through Codex writer ownership
/// and app-server lifecycle. No input mechanics are duplicated here.
fn State::submit_composer(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  if self.input_empty() ||
    !self.has_active() ||
    self.loading ||
    !self.can_prompt() {
    return (@cmd.none, self)
  }
  if self.active_draft() is Some(_) {
    (
      self.start_draft_thread(dispatch, channel),
      { ..self, loading: true, notice: "" },
    )
  } else if self.write_access is CodexWritable {
    (self.send(dispatch, channel), { ..self, loading: true, notice: "" })
  } else {
    (
      self.resume_for_send(dispatch, channel),
      { ..self, loading: true, notice: "" },
    )
  }
}

///|
test "Codex skills/list keeps enabled skills for the requested cwd" {
  guard CodexSkill::decode_list(
      {
        "data": [
          {
            "cwd": "/work/project",
            "errors": [],
            "skills": [
              {
                "name": "review-pr",
                "description": "Review a pull request",
                "enabled": true,
                "path": "/skills/review-pr/SKILL.md",
                "scope": "user",
              },
              {
                "name": "disabled",
                "description": "Disabled",
                "enabled": false,
                "path": "/skills/disabled/SKILL.md",
                "scope": "user",
              },
            ],
          },
        ],
      },
      "/work/project",
    )
    is Some(skills) else {
    fail("skills/list reply should decode")
  }
  assert_eq(skills.length(), 1)
  assert_eq(skills[0].name, "review-pr")
}

///|
test "Codex dollar and at completion use cwd-scoped catalogs" {
  let base = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "cwd": "/work/project", "turns": [] },
  })
  let state = {
    ..base,
    skills: CodexSkillsReady("/work/project", [
      {
        name: "review-pr",
        description: "Review a pull request",
        path: "/skills/review-pr/SKILL.md",
      },
    ]),
    file_index: CodexFilesReady(
      { thread_id: "thread-1", cwd: "/work/project" },
      [@pathx.Relative("src/main.mbt")],
      false,
    ),
  }
  guard state.completion_for_draft("Use $rev") is Some(skills) else {
    fail("Codex skill menu expected")
  }
  assert_true(skills.kind() is CodexSkills)
  guard skills.menu().get(0) is Some(skill) else { fail("skill row expected") }
  assert_eq(skill.label, "$review-pr")
  guard state.completion_for_draft("Open @main") is Some(files) else {
    fail("Codex file menu expected")
  }
  assert_true(files.kind() is CodexFiles)
  guard files.menu().get(0) is Some(file) else { fail("file row expected") }
  assert_eq(file.path, "src/main.mbt")
}

///|
test "Codex catalog replies do not reopen a dismissed completion" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let state = State::from_thread_snapshot({
    "thread": { "id": "thread-1", "cwd": "/work/project", "turns": [] },
  })
  let (_, searching) = state.update_composer(
    dispatch,
    @interop.ChannelId::Local,
    @composer.ControllerDraftChanged("Open @main"),
  )
  assert_true(searching.completion.current() is Some(_))
  let dismissed = { ..searching, completion: searching.completion.dismissed() }
  let loaded = dismissed.with_files(
    { thread_id: "thread-1", cwd: "/work/project" },
    [@pathx.Relative("src/main.mbt")],
    false,
  )
  assert_true(loaded.completion.current() is None)
}

///|
test "Codex skill chips send both marker text and native skill input" {
  let state = {
    ..State(),
    draft: "review this",
    mentions: [
      CodexSkillMention(name="review-pr", path="/skills/review-pr/SKILL.md"),
    ],
  }
  assert_eq(state.prompt_text(), "$review-pr review this")
  guard state.mentions[0].to_input() is Object(fields) else {
    fail("native skill input expected")
  }
  assert_eq(@jsonx.json_text(fields, "type"), Some("skill"))
  assert_eq(@jsonx.json_text(fields, "name"), Some("review-pr"))
  assert_eq(
    @jsonx.json_text(fields, "path"),
    Some("/skills/review-pr/SKILL.md"),
  )
}
