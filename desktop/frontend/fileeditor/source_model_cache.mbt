///|
/// Product resource identity; even equal paths on two conversation/worktree
/// owners are separate. Notice URI schemes remain distinct from live files.
priv struct SourceModelScope {
  owner : @interop.ConversationKey
  root : @common.Uri?
} derive(Eq)

///|
priv struct CachedSourceModel {
  document : @common.Uri
  model : @model.TextModel
  mut leases : Int
  mut retained : Bool
  mut used : Int
}

///|
priv struct SourceModelLease {
  model : @model.TextModel
  lifetime : @common.Disposable
}

///|
fn SourceModelLease::dispose(self : SourceModelLease) -> Unit {
  self.lifetime.dispose()
}

///|
/// Owns models independently of a source surface. Active leases cannot be
/// evicted; detached entries are LRU with both count and estimated byte bounds.
priv struct SourceModelCache {
  mut scope : SourceModelScope?
  entries : Array[CachedSourceModel]
  mut clock : Int
  max_entries : Int
  max_bytes : Int
}

///|
fn SourceModelCache::SourceModelCache(
  max_entries? : Int = 12,
  max_bytes? : Int = 8 * 1024 * 1024,
) -> SourceModelCache {
  {
    scope: None,
    entries: [],
    clock: 0,
    max_entries: max_entries.max(1),
    max_bytes: max_bytes.max(1),
  }
}

///|
fn cached_source_model_cost(model : @model.TextModel) -> Int {
  // UTF16 text, line offsets/projections and encoded tokens. This intentionally
  // charges derived data too, instead of merely limiting file/tab count.
  model.get_value().length() * 2 +
  model.get_line_count() * 40 +
  model.tokenization.token_count() * 12
}

///|
fn SourceModelCache::retire_entry(self : SourceModelCache, index : Int) -> Unit {
  let entry = self.entries[index]
  self.entries.remove(index) |> ignore
  entry.retained = false
  if entry.leases == 0 {
    entry.model.dispose()
  }
}

///|
fn SourceModelCache::clear(self : SourceModelCache) -> Unit {
  while !self.entries.is_empty() {
    self.retire_entry(self.entries.length() - 1)
  }
  self.scope = None
}

///|
fn SourceModelCache::retire_document(
  self : SourceModelCache,
  document : @common.Uri,
) -> Unit {
  let mut i = self.entries.length() - 1
  while i >= 0 {
    if self.entries[i].document == document {
      self.retire_entry(i)
    }
    i -= 1
  }
}

///|
fn SourceModelCache::trim(self : SourceModelCache) -> Unit {
  while true {
    let mut bytes = 0
    let mut candidate : Int? = None
    for i, entry in self.entries {
      bytes += cached_source_model_cost(entry.model)
      if entry.leases == 0 {
        match candidate {
          Some(previous) =>
            if entry.used < self.entries[previous].used {
              candidate = Some(i)
            }
          None => candidate = Some(i)
        }
      }
    }
    if self.entries.length() <= self.max_entries && bytes <= self.max_bytes {
      return
    }
    match candidate {
      Some(index) => self.retire_entry(index)
      None => return // leased resources may temporarily exceed the idle budget
    }
  }
}

///|
fn SourceModelCache::acquire(
  self : SourceModelCache,
  scope : SourceModelScope,
  document : @common.Uri,
  uri : @common.Uri,
  content : String,
  create : () -> @model.TextModel,
) -> SourceModelLease {
  if self.scope != Some(scope) {
    self.clear()
    self.scope = Some(scope)
  }
  let existing = for entry in self.entries {
    if entry.model.uri == uri {
      break Some(entry)
    }
  } nobreak {
    None
  }
  let entry = match existing {
    Some(entry) => {
      if !entry.model.has_same_content(content) {
        entry.model.set_value(content)
      }
      entry
    }
    None => {
      let entry : CachedSourceModel = {
        document,
        model: create(),
        leases: 0,
        retained: true,
        used: 0,
      }
      self.entries.push(entry)
      entry
    }
  }
  self.clock += 1
  entry.used = self.clock
  entry.leases += 1
  self.trim()
  {
    model: entry.model,
    lifetime: @common.Disposable::from(() => {
      entry.leases -= 1
      if !entry.retained && entry.leases == 0 {
        entry.model.dispose()
      }
      self.trim()
    }),
  }
}
