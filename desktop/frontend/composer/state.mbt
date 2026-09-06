///|
/// Which provider owns the visible completion token.
priv enum CompletionKind {
  SlashCommands
  SkillMentions
  Symbols
  Files
} derive(Eq)

///|
/// One completion row and the payload applied when it is accepted.
priv struct CompletionItem {
  label : String
  detail : String
  command : String
  insert : String
  path : String?
  range : @common.Range?
} derive(Eq)

///|
/// The open completion menu for one local composer entry.
priv struct Completion {
  kind : CompletionKind
  menu : Menu[CompletionItem]
} derive(Eq)

///|
/// Results from the last workspace-symbol request. Owner, root, and query are
/// all part of the cache identity so navigation cannot reuse stale rows.
priv struct SymbolCache {
  owner : @interop.ConversationKey?
  root : @common.Uri?
  query : String
  items : Array[CompletionItem]
} derive(Eq)

///|
fn SymbolCache::SymbolCache() -> SymbolCache {
  { owner: None, root: None, query: "", items: [], }
}

///|
fn CompletionItem::slash_commands(
  commands : Array[SlashCommand],
) -> Array[CompletionItem] {
  commands.map(command => {
    label: command.label,
    detail: command.detail,
    command: command.command,
    insert: "",
    path: None,
    range: None,
  })
}

///|
fn CompletionKind::of_trigger(trigger : Trigger) -> CompletionKind? {
  match trigger.marker() {
    "/" => Some(SlashCommands)
    "$" => Some(SkillMentions)
    "#" => Some(Symbols)
    "@" => Some(Files)
    _ => None
  }
}

///|
fn CompletionItem::from_symbol(symbol : @symbols.Symbol) -> CompletionItem {
  let location = if symbol.path.is_empty() {
    ""
  } else {
    "\{symbol.path}:\{symbol.range.start_line_number}"
  }
  let detail = if symbol.container is Some(container) && !container.is_empty() {
    if location.is_empty() {
      container
    } else {
      "\{container} · \{location}"
    }
  } else {
    location
  }
  {
    label: symbol.name,
    detail,
    command: "",
    insert: if location.is_empty() {
      "`\{symbol.name}` "
    } else {
      "`\{symbol.name}` — \{location} "
    },
    path: if symbol.path.is_empty() {
      None
    } else {
      Some(symbol.path)
    },
    range: if symbol.path.is_empty() {
      None
    } else {
      Some(symbol.range)
    },
  }
}

///|
/// Append a chip copy-on-write unless an equal durable reference is already
/// present.
pub fn Draft::with_mention(self : Draft, mention : Mention) -> Draft {
  for existing in self.mentions {
    if existing.ref_ == mention.ref_ {
      return self
    }
  }
  let mentions = self.mentions.copy()
  mentions.push(mention)
  { ..self, mentions, }
}

///|
/// Encode the typed text and chips into the durable prompt sent to the engine.
pub fn Draft::prompt(self : Draft) -> String {
  @mention_context.encode(self.mentions.map(mention => mention.ref_), self.task)
}

///|
fn Draft::without_mention(self : Draft, index : Int) -> Draft {
  guard self.mentions.get(index) is Some(_) else { return self }
  let mentions = self.mentions.copy()
  ignore(mentions.remove(index))
  { ..self, mentions, }
}

///|
/// Three-way merge a root-authored recovery snapshot with newer local typing.
fn Draft::reconciled(self : Draft, source~ : Draft, incoming~ : Draft) -> Draft {
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
    let mut merged = { ..self, task, }
    for mention in incoming.mentions {
      let externally_added = source.mentions
        .iter()
        .all(existing => existing.ref_ != mention.ref_)
      if externally_added {
        merged = merged.with_mention(mention)
      }
    }
    merged.mentions
  }
  { task, mentions, }
}

///|
fn FileIndex::epoch(self : FileIndex) -> Int {
  match self {
    FileIndexEmpty(epoch~)
    | FileIndexLoading(epoch~)
    | FileIndexReady(epoch~, ..)
    | FileIndexFailed(epoch~) => epoch
  }
}

///|
fn FileIndex::needs_start(self : FileIndex) -> Bool {
  self is (FileIndexEmpty(..) | FileIndexFailed(..))
}

///|
fn FileIndex::loading(self : FileIndex, can_index : Bool) -> Bool {
  match self {
    FileIndexEmpty(..) | FileIndexLoading(..) => can_index
    FileIndexReady(truncated=true, ..) => true
    FileIndexFailed(..) | FileIndexReady(truncated=false, ..) => false
  }
}

///|
/// Rank the root-owned file candidates for the local draft without copying
/// that draft into the root Model.
fn Input::completion_files(
  self : Input,
  text : String,
) -> (Array[@files.Match], Bool) {
  guard Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" else {
    return ([], false)
  }
  (
    @files.Search(self.file_candidates, [], None).rank(trigger.query()),
    self.file_index.loading(self.root is Some(_)),
  )
}

///|
/// Build the completion menu from the local draft and root-supplied providers.
fn Input::completion(
  self : Input,
  text : String,
  symbols : SymbolCache,
  owner : @interop.ConversationKey,
  files? : Array[@files.Match] = [],
  files_loading? : Bool = false,
) -> Completion? {
  guard Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    CompletionKind::of_trigger(trigger) is Some(kind) else {
    return None
  }
  match kind {
    SlashCommands | SkillMentions => {
      let items = if kind is SlashCommands {
        CompletionItem::slash_commands(self.slash_commands).filter(item => {
          trigger.matches([item.label])
        })
      } else {
        self.installed_skills
        .filter(skill => trigger.matches([skill.name, skill.description]))
        .map(skill => CompletionItem::{
          label: "$\{skill.name}",
          detail: skill.description,
          command: "",
          insert: "\{skill.name} ",
          path: None,
          range: None,
        })
      }
      if items.is_empty() {
        None
      } else {
        Some({
          kind,
          menu: Menu(
            items,
            loading=false,
            draft_without_token=trigger.draft_without_token(),
          ),
        })
      }
    }
    Symbols => {
      let items = symbols.items.filter(item => {
        trigger.matches([item.label, item.detail])
      })
      Some({
        kind: Symbols,
        menu: Menu(
          items,
          loading=symbols.owner != Some(owner) ||
            symbols.root != self.root ||
            symbols.query != trigger.query(),
          draft_without_token=trigger.draft_without_token(),
        ),
      })
    }
    Files => {
      let items = files.map(file => CompletionItem::{
        label: file.name,
        detail: file.path.0,
        command: "",
        insert: file.path.0,
        path: Some(file.path.0),
        range: None,
      })
      Some({
        kind: Files,
        menu: Menu(
          items,
          loading=files_loading,
          draft_without_token=trigger.draft_without_token(),
        ),
      })
    }
  }
}
