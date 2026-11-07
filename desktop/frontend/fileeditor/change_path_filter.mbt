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
  guard name.rev_split_once(".") is Some((stem, suffix)) &&
    !stem.is_empty() &&
    !suffix.is_empty() else {
    return None
  }
  Some(".\{suffix}".to_lower())
}

///|
fn extension_label(
  locale~ : @i18n.Locale = English,
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
fn change_extension_options(state : State) -> Array[(String?, Int32)] {
  let counts : Map[String?, Int32] = Map([])
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

///|
test "filter actions intersect file types and paths without replacing the open review" {
  let (initial, ctx, source) = review_progress_state()
  let second = test_modified_change(Relative("src/lib.mbt"))
  let doc = test_modified_change(Relative("docs/guide.md"))
  let plain = test_modified_change(Relative("LICENSE"))
  let files = [source, second, doc, plain]
  let state = {
    ..initial,
    changes: ChangeListReady(
      repository=true,
      files~,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let (_, paths) = update(
    test_emit(),
    ChangePathFilterChanged("SRC/"),
    state,
    ctx,
  )
  assert_true(filtered_changes(paths) == [source, second])
  assert_true(review_neighbor(paths, source, 1) == Some(second))
  assert_true(paths.docs == state.docs)
  assert_eq(change_extension_options(paths), [
    (Some(".mbt"), 2),
    (Some(".md"), 1),
    (None, 1),
  ])
  let (_, no_markdown) = update(
    test_emit(),
    ChangeExtensionToggled(Some(".md")),
    paths,
    ctx,
  )
  let (_, source_only) = update(
    test_emit(),
    ChangeExtensionToggled(None),
    no_markdown,
    ctx,
  )
  assert_eq(source_only.change_extensions, Some([Some(".mbt")]))
  let (_, excluded) = update(
    test_emit(),
    ChangePathFilterChanged("docs/"),
    source_only,
    ctx,
  )
  assert_true(filtered_changes(excluded).is_empty())
  let (_, included) = update(
    test_emit(),
    ChangeExtensionToggled(Some(".md")),
    excluded,
    ctx,
  )
  assert_true(filtered_changes(included) == [doc])
  assert_true(included.docs == state.docs)
  assert_true(active_review_change(included, ctx) == Some(source))
  let (_, no_match) = update(
    test_emit(),
    ChangePathFilterChanged("does-not-exist"),
    included,
    ctx,
  )
  assert_true(filtered_changes(no_match).is_empty())
  let (_, cleared) = update(test_emit(), ChangeFiltersCleared, no_match, ctx)
  assert_eq(cleared.change_path_filter, "")
  assert_true(cleared.change_extensions is None)
  assert_true(filtered_changes(cleared) == files)
  assert_true(cleared.docs == state.docs)
  let (_, no_source) = update(
    test_emit(),
    ChangeExtensionToggled(Some(".mbt")),
    cleared,
    ctx,
  )
  let (_, only_plain) = update(
    test_emit(),
    ChangeExtensionToggled(Some(".md")),
    no_source,
    ctx,
  )
  let (_, empty) = update(
    test_emit(),
    ChangeExtensionToggled(None),
    only_plain,
    ctx,
  )
  assert_eq(empty.change_extensions, Some([]))
  assert_true(filtered_changes(empty).is_empty())
  let (_, restored) = update(test_emit(), ChangeFiltersCleared, empty, ctx)
  assert_true(filtered_changes(restored) == files)
  assert_true(state.change_extensions is None)
  assert_eq(state.change_path_filter, "")
}
