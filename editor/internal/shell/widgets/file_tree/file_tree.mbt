///|
/// Explorer-style workspace tree widget. It owns a tree of lazily
/// resolved `WorkspaceStat` nodes plus per-node expansion state (the
/// `ExplorerItem`/`AsyncDataTree` role): directories render collapsed
/// until expanded, expansion resolves exactly one level through the
/// provider and caches it on the node, and `set_active` is `autoReveal`.
/// Opening files is an intent reported through `on_open`; the widget
/// never opens documents itself.
struct FileTree {
  emit : @rabbita.Emit[FileTreeMsg]
  view_value : @rabbita.Val[@html.Html]
}

///|
priv enum FileTreeMsg {
  Refresh
  DirectoryResolved(@base_common.Uri, @workspace.WorkspaceResolveResult)
  ToggleDirectory(@base_common.Uri)
  OpenFile(@base_common.Uri)
  SetActive(@base_common.Uri)
}

///|
/// Creates a file tree over a workspace provider and reports file-open
/// intents to the host.
pub fn FileTree::FileTree(
  provider : &@workspace.WorkspaceTreeProvider,
  on_open~ : (@base_common.Uri) -> Unit,
) -> FileTree {
  let model : FileTreeModel = {
    root: None,
    selected: None,
    pending_reveal: None,
  }
  let (state, emit) = @rabbita.create_state(model, update=(model, msg, emit) => {
    let (cmd, model) = model.update(provider, on_open, emit, msg)
    (model, cmd)
  })
  let view_value = state.view(model => model.view(emit))
  { emit, view_value, }
}

///|
/// Returns the tree's incremental view for composition by the host component.
pub fn FileTree::view(self : FileTree) -> @rabbita.Val[@html.Html] {
  self.view_value
}

///|
/// Re-resolves the tree from the provider's root, replacing every cached
/// node; the host calls this on (re)connect. The active file, if any, is
/// auto-revealed again in the fresh tree.
pub fn FileTree::refresh(self : FileTree) -> @rabbita.Cmd {
  (self.emit)(Refresh)
}

///|
/// `autoReveal`: resolves and expands the ancestor chain of `uri` (derived
/// from its root-relative path segments) and marks the node selected.
pub fn FileTree::set_active(
  self : FileTree,
  uri : @base_common.Uri,
) -> @rabbita.Cmd {
  (self.emit)(SetActive(uri))
}

///|
fn FileTreeModel::update(
  self : FileTreeModel,
  provider : &@workspace.WorkspaceTreeProvider,
  on_open : (@base_common.Uri) -> Unit,
  emit : @rabbita.Emit[FileTreeMsg],
  msg : FileTreeMsg,
) -> (@rabbita.Cmd, FileTreeModel) {
  match msg {
    Refresh =>
      (FileTree::resolve_directory(provider, emit, provider.root()), self)
    DirectoryResolved(uri, result) =>
      self.with_directory_resolved(provider, emit, uri, result)
    ToggleDirectory(uri) =>
      if self.root is Some(root) && root.toggle(uri) is Some((toggled, effect)) {
        let model = { ..self, root: Some(toggled), }
        match effect {
          ToggleResolve(uri) =>
            (FileTree::resolve_directory(provider, emit, uri), model)
          ToggleNone => (@rabbita.none, model)
        }
      } else {
        (@rabbita.none, self)
      }
    OpenFile(uri) =>
      (@cmd.custom_cmd(_ => on_open(uri)), { ..self, selected: Some(uri), })
    SetActive(uri) =>
      { ..self, selected: Some(uri), pending_reveal: Some(uri), }.continue_reveal(
        provider, emit,
      )
  }
}

///|
fn FileTreeModel::with_directory_resolved(
  self : FileTreeModel,
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
  uri : @base_common.Uri,
  result : @workspace.WorkspaceResolveResult,
) -> (@rabbita.Cmd, FileTreeModel) {
  match result {
    WorkspaceResolved(stat) => {
      let model = if uri == provider.root() {
        {
          ..self,
          root: Some(TreeNode::from_stat(stat, expanded=true)),
          pending_reveal: if self.pending_reveal is Some(_) {
            self.pending_reveal
          } else {
            self.selected
          },
        }
      } else if self.root is Some(root) &&
        root.with_resolved(uri, stat) is Some(resolved) {
        { ..self, root: Some(resolved), }
      } else {
        self
      }
      model.continue_reveal(provider, emit)
    }
    WorkspaceResolveError(_) => {
      // The folder keeps rendering as an empty-with-error level; children
      // stay unresolved so the next expand retries the resolve.
      let model = if self.root is Some(root) &&
        root.with_resolve_failed(uri) is Some(failed) {
        { ..self, root: Some(failed), pending_reveal: None, }
      } else {
        { ..self, pending_reveal: None, }
      }
      (@rabbita.none, model)
    }
  }
}

///|
fn FileTreeModel::continue_reveal(
  self : FileTreeModel,
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
) -> (@rabbita.Cmd, FileTreeModel) {
  match (self.root, self.pending_reveal) {
    (Some(root), Some(target)) => {
      let (root, step) = root.reveal_step(target)
      let model = { ..self, root: Some(root), }
      match step {
        RevealResolve(uri) =>
          (FileTree::resolve_directory(provider, emit, uri), model)
        RevealDone | RevealUnreachable =>
          (@rabbita.none, { ..model, pending_reveal: None, })
      }
    }
    _ => (@rabbita.none, self)
  }
}

///|
fn FileTree::resolve_directory(
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
  uri : @base_common.Uri,
) -> @rabbita.Cmd {
  @cmd.perform(result => emit(DirectoryResolved(uri, result)), async fn() noraise {
    provider.resolve(uri) catch {
      _ =>
        WorkspaceResolveError(
          FileSystemProviderError(
            Unavailable,
            "Directory resolve failed.",
            uri~,
          ),
        )
    }
  })
}

///|
fn FileTreeModel::view(
  self : FileTreeModel,
  emit : @rabbita.Emit[FileTreeMsg],
) -> @html.Html {
  let children : Array[@html.Html] = []
  if self.root is Some(root) {
    for row in root.visible_rows() {
      if row.node.kind == Directory {
        children.push(row.folder_view(emit))
      } else {
        children.push(row.file_view(emit, self))
      }
    }
  }
  @html.div(class="file-tree", children)
}

///|
fn TreeRow::folder_view(
  self : TreeRow,
  emit : @rabbita.Emit[FileTreeMsg],
) -> @html.Html {
  let node = self.node
  let class_name = if node.resolve_failed {
    "workspace-item workspace-folder resolve-failed"
  } else {
    "workspace-item workspace-folder"
  }
  @html.button(
    type_="button",
    class=class_name,
    on_click=emit(ToggleDirectory(node.uri)),
    attrs=@html.Attrs::build()
      .data_set("workspace-id", node.uri.to_string())
      .data_set("workspace-kind", "folder")
      .aria_expanded(node.expanded.to_string())
      .style("--depth", self.depth.to_string()),
    [
      FileTree::indent_guides(self.depth),
      @html.span(class="workspace-twistie", icon_chevron_right()),
      @html.span(class="workspace-label", node.name),
    ],
  )
}

///|
fn TreeRow::file_view(
  self : TreeRow,
  emit : @rabbita.Emit[FileTreeMsg],
  model : FileTreeModel,
) -> @html.Html {
  let node = self.node
  let selected = model.selected is Some(uri) && uri == node.uri
  let class_name = if selected {
    "workspace-item workspace-file is-selected"
  } else {
    "workspace-item workspace-file"
  }
  @html.button(
    type_="button",
    class=class_name,
    on_click=emit(OpenFile(node.uri)),
    attrs=@html.Attrs::build()
      .data_set("workspace-id", node.uri.to_string())
      .data_set("workspace-kind", "file")
      .data_set("selected", selected.to_string())
      .aria_selected(selected.to_string())
      .style("--depth", self.depth.to_string()),
    [
      FileTree::indent_guides(self.depth),
      @html.span(class="workspace-twistie workspace-twistie-spacer", ""),
      @html.span(class="workspace-file-icon", icon_file()),
      @html.span(class="workspace-label", node.name),
    ],
  )
}

///|
fn FileTree::indent_guides(depth : Int) -> @html.Html {
  let guides : Array[@html.Html] = [
    for _ in 0..<depth => @html.span(class="indent-guide", "")
  ]
  @html.span(class="workspace-guides", guides)
}
