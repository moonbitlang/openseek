// The desktop explorer's Git changed-file inventory. Git interpretation and
// repository access stay in the host; this side only decodes its typed reply,
// fences it to the requesting conversation, and presents stable categories.

///|
fn ChangeKind::parse(value : String) -> ChangeKind {
  match value {
    "modified" => ChangeModified
    "added" => ChangeAdded
    "deleted" => ChangeDeleted
    "renamed" => ChangeRenamed
    "copied" => ChangeCopied
    "unmerged" => ChangeUnmerged
    "type-changed" => ChangeTypeChanged
    "untracked" => ChangeUntracked
    "submodule" => ChangeSubmodule
    "symlink" => ChangeSymlink
    _ => ChangeUnknown
  }
}

///|
fn ChangedFile::from_reply(change : @protocol.GitChange) -> ChangedFile? {
  guard !change.path.is_empty() else { return None }
  Some({
    path: @pathx.Relative(change.path),
    original_path: change.original_path.map(path => @pathx.Relative(path)),
    index_status: change.index_status,
    worktree_status: change.worktree_status,
    kind: ChangeKind::parse(change.kind),
  })
}

///|
/// Modern hosts return the chosen comparison boundary: a worktree's task base
/// or an ordinary branch's fork point. Older hosts retain the immutable HEAD
/// identity. Keeping this choice in one place prevents a later commit from
/// silently rebasing an in-progress review.
fn git_review_revision(reply : @protocol.GitChangesReply) -> String? {
  match reply.baseline {
    Some(baseline) => Some(baseline)
    None => reply.head
  }
}

///|
/// Ask the owning host for the checkout's review inventory. Worktree tasks use
/// their immutable creation commit; ordinary branches with committed work use
/// their default-branch fork point; otherwise the host retains HEAD status. As
/// with filesystem calls, a resource hint belonging to another host is
/// rejected before bridge access.
fn list_changes(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  request_id : String,
  workspace~ : @common.Uri?,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, owner.channel) =>
      // `refresh_changes` has already marked this UUID in flight. A
      // silent no-op would wedge the inventory in Loading/refreshing forever;
      // settle it through the ordinary fenced failure path instead.
      return dispatch(
        ChangesFailed(
          owner~,
          request_id~,
          message="workspace moved to another host before Git refresh",
        ),
      )
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.git_changes,
        {
          session: owner.session,
          workspace: workspace.map(value => value.path),
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              ChangesFailed(
                owner~,
                request_id~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      let files = reply.changes.filter_map(ChangedFile::from_reply)
      // New hosts pin Review to the selected comparison commit. Older hosts
      // omit `baseline`, so keep their exact HEAD identity.
      let revision = git_review_revision(reply)
      scheduler.add(dispatch(GitHeadObserved(owner~, head=reply.head)))
      scheduler.add(
        dispatch(
          ChangesLoaded(
            owner~,
            request_id~,
            repository=reply.repository,
            head=revision,
            files~,
          ),
        ),
      )
    })
  })
}

///|
/// Load the comparison side of one selected change. `path` is the current
/// document key; `source` is the rename/copy source when Git reported one.
/// The owner and current path ride the reply so a close, ordinary reopen, or
/// conversation switch can discard it without touching the Viewer.
fn read_git_original(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  source : @pathx.Relative,
  generation : Int,
  background? : Bool = false,
  revision~ : String?,
  workspace~ : @common.Uri?,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, owner.channel) =>
      return dispatch(
        GitOriginalFailed(
          owner~,
          path~,
          generation~,
          background~,
          message="workspace moved to another host before Git review",
        ),
      )
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let original = @interop.bridge_request(
        owner.channel,
        @commands.git_original_file,
        {
          session: owner.session,
          workspace: workspace.map(value => value.path),
          path: source.0,
          revision,
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              GitOriginalFailed(
                owner~,
                path~,
                generation~,
                background~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          GitOriginalLoaded(owner~, path~, generation~, background~, original~),
        ),
      )
    })
  })
}

///|
/// Compact label used by each changed-file row. Raw index/worktree columns
/// remain available in the title for precise staged/unstaged detail.
fn ChangedFile::status_label(self : ChangedFile) -> String {
  if self.kind is ChangeSubmodule && self.has_unmerged_status() {
    return "U"
  }
  match self.kind {
    ChangeModified => "M"
    ChangeAdded => "A"
    ChangeDeleted => "D"
    ChangeRenamed => "R"
    ChangeCopied => "C"
    ChangeUnmerged => "U"
    ChangeTypeChanged => "T"
    ChangeUntracked => "?"
    ChangeSubmodule => "S"
    ChangeSymlink => "L"
    ChangeUnknown => "!"
  }
}

///|
fn ChangedFile::has_unmerged_status(self : ChangedFile) -> Bool {
  ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(
    self.index_status + self.worktree_status,
  )
}

///|
fn ChangedFile::status_title(self : ChangedFile) -> String {
  let detail = "index: \{self.index_status}, worktree: \{self.worktree_status}"
  match self.original_path {
    Some(original) => "\{original.0} → \{self.path.0} (\{detail})"
    None => "\{self.path.0} (\{detail})"
  }
}

///|
/// Whether the change has a regular working-tree file for `fs.read_file`.
/// Deleted rows remain reviewable through their baseline content, but must skip
/// that ordinary read. Besides a plain deletion this covers a renamed/copied
/// path deleted again (`RD` / `CD`) and a both-deleted conflict (`DD`).
fn ChangedFile::has_working_tree_file(self : ChangedFile) -> Bool {
  if self.kind is ChangeUnmerged {
    // Conflict codes are exceptional: the retained side remains readable for
    // `DU` and `UD`; only `DD` has no working-tree file.
    !(self.index_status == "D" && self.worktree_status == "D")
  } else {
    // Rename/copy classification takes precedence over worktree deletion in
    // the host, so the raw second column is still required for `RD` / `CD`.
    !(self.kind is ChangeDeleted) && self.worktree_status != "D"
  }
}

///|
/// Whether the row can open a textual review. Missing working-tree files are
/// allowed because `git.original_file` supplies their deleted-file preview;
/// non-file entries stay inert and explain why.
fn ChangedFile::selectable(self : ChangedFile) -> Bool {
  if self.kind is ChangeSubmodule ||
    self.kind is ChangeSymlink ||
    self.path.0.has_suffix("/") {
    false
  } else {
    true
  }
}

///|
/// Explain why an informative row cannot use the ordinary file reader.
fn ChangedFile::unselectable_title(self : ChangedFile) -> String {
  let reason = if self.kind is ChangeSubmodule {
    "Git submodule; open its nested checkout separately"
  } else if self.kind is ChangeSymlink {
    "Git symlink; opening its target is disabled"
  } else if self.path.0.has_suffix("/") {
    "untracked directory; open its nested checkout separately"
  } else {
    "change cannot be previewed"
  }
  self.status_title() + " — " + reason
}

///|
test "changed-file replies decode presentation categories and rename sources" {
  assert_true(ChangeKind::parse("submodule") is ChangeSubmodule)
  assert_true(ChangeKind::parse("symlink") is ChangeSymlink)
  let change : @protocol.GitChange = {
    path: "new.mbt",
    original_path: Some("old.mbt"),
    index_status: "R",
    worktree_status: " ",
    kind: "renamed",
  }
  assert_true(
    ChangedFile::from_reply(change)
    is Some(
      {
        path: @pathx.Relative("new.mbt"),
        original_path: Some(@pathx.Relative("old.mbt")),
        index_status: "R",
        worktree_status: " ",
        kind: ChangeRenamed,
      }
    ),
  )
}

///|
test "empty changed-file paths are ignored defensively" {
  assert_true(
    ChangedFile::from_reply({
      path: "",
      original_path: None,
      index_status: "?",
      worktree_status: "?",
      kind: "untracked",
    })
    is None,
  )
}

///|
test "task baselines win over moving HEAD with a legacy fallback" {
  let task : @protocol.GitChangesReply = {
    repository: true,
    head: Some("new-head"),
    baseline: Some("task-base"),
    changes: [],
  }
  assert_eq(git_review_revision(task), Some("task-base"))
  assert_eq(git_review_revision({ ..task, baseline: None, }), Some("new-head"))
}

///|
test "deleted rows use baseline previews while non-file rows stay inert" {
  let deleted : ChangedFile = {
    path: @pathx.Relative("removed.mbt"),
    original_path: None,
    index_status: " ",
    worktree_status: "D",
    kind: ChangeDeleted,
  }
  assert_true(deleted.selectable())
  assert_false(deleted.has_working_tree_file())
  let renamed_deleted = {
    ..deleted,
    index_status: "R",
    worktree_status: "D",
    kind: ChangeRenamed,
  }
  assert_true(renamed_deleted.selectable())
  assert_false(renamed_deleted.has_working_tree_file())
  let both_deleted = {
    ..deleted,
    index_status: "D",
    worktree_status: "D",
    kind: ChangeUnmerged,
  }
  assert_true(both_deleted.selectable())
  assert_false(both_deleted.has_working_tree_file())
  assert_false(
    { ..deleted, worktree_status: "M", kind: ChangeSubmodule, }.selectable(),
  )
  assert_false(
    { ..deleted, worktree_status: "M", kind: ChangeSymlink, }.selectable(),
  )
  assert_false(
    {
      ..deleted,
      path: @pathx.Relative("nested/"),
      index_status: "?",
      worktree_status: "?",
      kind: ChangeUntracked,
    }.selectable(),
  )
  assert_true(
    {
      ..deleted,
      index_status: "D",
      worktree_status: "U",
      kind: ChangeUnmerged,
    }.selectable(),
  )
  assert_true(
    {
      ..deleted,
      index_status: "D",
      worktree_status: "U",
      kind: ChangeUnmerged,
    }.has_working_tree_file(),
  )
  assert_true(
    {
      ..deleted,
      index_status: "U",
      worktree_status: "D",
      kind: ChangeUnmerged,
    }.selectable(),
  )
  assert_true(
    { ..deleted, worktree_status: "M", kind: ChangeModified, }.selectable(),
  )
  assert_eq(
    {
      ..deleted,
      index_status: "U",
      worktree_status: "U",
      kind: ChangeSubmodule,
    }.status_label(),
    "U",
  )
}
