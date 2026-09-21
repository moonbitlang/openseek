///|
fn change_path_matches(
  path : @pathx.Relative,
  original : @pathx.Relative?,
  query : String,
) -> Bool {
  let query = query.to_lower()
  path.0.to_lower().contains(query) ||
  (original is Some(original) && original.0.to_lower().contains(query))
}

///|
priv struct ReviewFileFilter {
  query : String
  extensions : Array[String?]?
}

///|
fn State::review_file_filter(self : State) -> ReviewFileFilter {
  { query: self.change_path_filter, extensions: self.change_extensions, }
}

///|
fn ReviewFileFilter::matches(
  self : ReviewFileFilter,
  path : @pathx.Relative,
  original : @pathx.Relative?,
) -> Bool {
  change_path_matches(path, original, self.query) &&
  (
    self.extensions is None ||
    (
      self.extensions is Some(selected) &&
      selected.contains(change_extension(path))
    )
  )
}

///|
fn filtered_changes(state : State) -> Array[ChangedFile] {
  match state.changes {
    ChangeListReady(files~, ..) => {
      // An expanded commit owns the filter; working changes remain unfiltered.
      if state.git_graph_selected is Some(_) {
        return files
      }
      let filter = state.review_file_filter()
      files.filter(change => filter.matches(change.path, change.original_path))
    }
    _ => []
  }
}

///|
fn filtered_history_changes(
  state : State,
  files : Array[@protocol.GitHistoricalChange],
) -> Array[@protocol.GitHistoricalChange] {
  let filter = state.review_file_filter()
  files.filter(file => {
    filter.matches(
      Relative(file.path),
      file.original_path.map(path => Relative(path)),
    )
  })
}

///|
priv struct ReviewFilterFile {
  path : @pathx.Relative
  original : @pathx.Relative?
}

///|
/// Only a settled inventory for the selected source can supply filter choices.
/// Loading and failed source states retain their own messages in the lists.
fn review_filter_inventory(state : State) -> Array[ReviewFilterFile]? {
  match state.git_graph_selected {
    Some(selected) =>
      match state.git_commit_files {
        GitCommitFilesReady(commit~, files~, ..) if commit == selected =>
          Some(
            files.map(file => {
              path: Relative(file.path),
              original: file.original_path.map(path => Relative(path)),
            }),
          )
        _ => None
      }
    None =>
      match state.changes {
        ChangeListReady(files~, ..) =>
          Some(
            files.map(file => { path: file.path, original: file.original_path, }),
          )
        _ => None
      }
  }
}

///|
test "path filters match literal paths and rename sources without case sensitivity" {
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, "SRC/"))
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, ".mbt"))
  assert_true(
    change_path_matches(
      Relative("src/Main.mbt"),
      Some(Relative("old/entry.mbt")),
      "old/",
    ),
  )
  assert_true(change_path_matches(Relative("src/Main.mbt"), None, ""))
  assert_false(change_path_matches(Relative("src/Main.mbt"), None, "docs/"))
  assert_false(change_path_matches(Relative("src/Main.mbt"), None, "*.mbt"))
  assert_true(change_path_matches(Relative("docs/my file.md"), None, "my file"))
}

///|
/// A leading dot alone does not give a dotfile an extension.
fn change_extension(path : @pathx.Relative) -> String? {
  let name = basename(path)
  let parts = name.split(".").to_array()
  if parts.length() < 2 || (parts.length() == 2 && parts[0].is_empty()) {
    return None
  }
  let suffix = parts[parts.length() - 1]
  if suffix.is_empty() {
    None
  } else {
    Some("." + suffix.to_owned().to_lower())
  }
}

///|
fn extension_label(
  locale? : @i18n.Locale = English,
  extension : String?,
) -> String {
  match extension {
    Some(value) => value
    None =>
      match locale {
        SimplifiedChinese => "无扩展名"
        TraditionalChinese => "無副檔名"
        Japanese => "拡張子なし"
        English => "No extension"
        Spanish => "Sin extensión"
      }
  }
}

///|
fn change_extension_options(state : State) -> Array[(String?, Int)] {
  let counts : Map[String?, Int] = Map([])
  if review_filter_inventory(state) is Some(files) {
    for change in files {
      let extension = change_extension(change.path)
      counts[extension] = counts.get(extension).unwrap_or(0) + 1
    }
  }
  // Keep a selected type visible if a refresh removes its last file.
  if state.change_extensions is Some(selected) {
    for extension in selected {
      if !counts.contains(extension) {
        counts[extension] = 0
      }
    }
  }
  let options = counts.iter().to_array()
  options.sort_by((a, b) => {
    extension_label(a.0).lexical_compare(extension_label(b.0))
  })
  options
}

///|
test "file extensions use the final suffix and distinguish extensionless files" {
  assert_eq(change_extension(Relative("dir.name/README")), None)
  assert_eq(change_extension(Relative(".gitignore")), None)
  assert_eq(change_extension(Relative(".config.JSON")), Some(".json"))
  assert_eq(change_extension(Relative("src/Main.MBT")), Some(".mbt"))
  assert_eq(change_extension(Relative("archive.tar.gz")), Some(".gz"))
  assert_eq(change_extension(Relative("file.")), None)
}
