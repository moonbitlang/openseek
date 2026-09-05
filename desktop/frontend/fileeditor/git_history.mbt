// Git Graph and immutable historical comparisons. Repository plumbing stays
// in the native host; this package owns request fencing, graph presentation
// state, and the inert DiffEditor models selected from the Review sidebar.

///|
const GitHistoryPageSize = 50

///|
fn history_diff_key(diff : @dock.GitHistoryDiff) -> String {
  diff.commit + "\u{0}" + diff.path.0
}

///|
fn short_commit(commit : String) -> String {
  if commit.length() <= 8 {
    commit
  } else {
    commit.view(end_offset=8).to_owned()
  }
}

///|
fn request_git_history(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  generation : Int,
  append : Bool,
  snapshot : @protocol.GitHistorySnapshot?,
  skip : Int,
  workspace~ : @common.Uri?,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, owner.channel) =>
      return dispatch(
        GitHistoryFailed(
          owner~,
          generation~,
          append~,
          message="workspace moved to another host before Git history refresh",
        ),
      )
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.git_history,
        {
          session: owner.session,
          workspace: workspace.map(value => value.path),
          snapshot,
          skip,
          limit: GitHistoryPageSize,
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              GitHistoryFailed(
                owner~,
                generation~,
                append~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(GitHistoryLoaded(owner~, generation~, append~, reply~)),
      )
    })
  })
}

///|
fn request_git_commit_changes(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  generation : Int,
  commit : String,
  workspace~ : @common.Uri?,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, owner.channel) =>
      return dispatch(
        GitCommitChangesFailed(
          owner~,
          generation~,
          commit~,
          message="workspace moved to another host before commit inspection",
        ),
      )
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.git_commit_changes,
        {
          session: owner.session,
          workspace: workspace.map(value => value.path),
          commit,
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              GitCommitChangesFailed(
                owner~,
                generation~,
                commit~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(GitCommitChangesLoaded(owner~, generation~, reply~)),
      )
    })
  })
}

///|
fn request_history_blob(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  key : String,
  generation : Int,
  side : HistoryDiffSide,
  path : @pathx.Relative,
  revision : String,
  workspace~ : @common.Uri?,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, owner.channel) =>
      return dispatch(
        HistoryBlobFailed(
          owner~,
          key~,
          generation~,
          side~,
          message="workspace moved to another host before historical diff",
        ),
      )
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let blob = @interop.bridge_request(
        owner.channel,
        @commands.git_original_file,
        {
          session: owner.session,
          workspace: workspace.map(value => value.path),
          path: path.0,
          revision: Some(revision),
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              HistoryBlobFailed(
                owner~,
                key~,
                generation~,
                side~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(HistoryBlobLoaded(owner~, key~, generation~, side~, blob~)),
      )
    })
  })
}

///|
fn refresh_git_graph(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard state.owner == Some(ctx.owner) &&
    ctx.checkout_ready() &&
    !ctx.owner.session.is_empty() else {
    return (@cmd.none, state)
  }
  let generation = state.git_graph_generation + 1
  (
    request_git_history(
      dispatch,
      ctx.owner,
      generation,
      false,
      None,
      0,
      workspace=ctx.workspace(),
    ),
    {
      ..state,
      git_graph: GitGraphLoading,
      git_graph_generation: generation,
      git_graph_selected: None,
      git_commit_files: GitCommitFilesIdle,
    },
  )
}

///|
fn load_more_git_history(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard state.owner == Some(ctx.owner) &&
    ctx.checkout_ready() &&
    state.git_graph
    is GitGraphReady(
      repository=true,
      snapshot~,
      commits~,
      has_more=true,
      loading_more=false,
      ..
    ) else {
    return (@cmd.none, state)
  }
  let generation = state.git_graph_generation + 1
  (
    request_git_history(
      dispatch,
      ctx.owner,
      generation,
      true,
      Some(snapshot),
      commits.length(),
      workspace=ctx.workspace(),
    ),
    {
      ..state,
      git_graph_generation: generation,
      git_graph: GitGraphReady(
        repository=true,
        snapshot~,
        commits~,
        has_more=true,
        loading_more=true,
        load_error=None,
      ),
    },
  )
}

///|
fn select_git_commit(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  commit : String,
) -> (@cmd.Cmd, State) {
  if state.git_graph_selected == Some(commit) {
    return (
      @cmd.none,
      {
        ..state,
        git_graph_selected: None,
        git_commit_files: GitCommitFilesIdle,
      },
    )
  }
  guard state.git_graph is GitGraphReady(repository=true, commits~, ..) &&
    commits.any(item => item.id == commit) else {
    return (@cmd.none, state)
  }
  let generation = state.git_commit_files_generation + 1
  (
    request_git_commit_changes(
      dispatch,
      ctx.owner,
      generation,
      commit,
      workspace=ctx.workspace(),
    ),
    {
      ..state,
      git_graph_selected: Some(commit),
      git_commit_files_generation: generation,
      git_commit_files: GitCommitFilesLoading(commit~),
    },
  )
}

///|
fn retry_git_commit_changes(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  commit : String,
) -> (@cmd.Cmd, State) {
  guard state.git_graph_selected == Some(commit) &&
    state.git_graph is GitGraphReady(repository=true, commits~, ..) &&
    commits.any(item => item.id == commit) else {
    return (@cmd.none, state)
  }
  let generation = state.git_commit_files_generation + 1
  (
    request_git_commit_changes(
      dispatch,
      ctx.owner,
      generation,
      commit,
      workspace=ctx.workspace(),
    ),
    {
      ..state,
      git_commit_files_generation: generation,
      git_commit_files: GitCommitFilesLoading(commit~),
    },
  )
}

///|
fn HistoryBlob::text(self : HistoryBlob) -> String? {
  match self {
    HistoryBlobContent(content) => Some(content)
    HistoryBlobMissing => Some("")
    HistoryBlobLoading
    | HistoryBlobBinary
    | HistoryBlobOversized
    | HistoryBlobError(_) => None
  }
}

///|
fn show_history_doc(
  owner : @interop.ConversationKey,
  doc : HistoryDiffDoc,
) -> @cmd.Cmd {
  guard doc.original.text() is Some(original) &&
    doc.modified.text() is Some(modified) else {
    return @cmd.none
  }
  show_history_diff_in_viewer(owner, doc.diff, original, modified)
}

///|
pub fn open_history_diff(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  diff : @dock.GitHistoryDiff,
) -> (@cmd.Cmd, State) {
  guard ctx.placement_ready() && diff.kind == "file" else {
    return (@cmd.none, state)
  }
  let key = history_diff_key(diff)
  if state.history_docs.get(key) is Some(doc) {
    return (
      @cmd.batch([show_history_doc(ctx.owner, doc), request_viewer_remeasure()]),
      state,
    )
  }
  let generation = state.history_generation + 1
  let original = if diff.parent is None {
    HistoryBlobMissing
  } else {
    HistoryBlobLoading
  }
  let doc : HistoryDiffDoc = {
    diff,
    generation,
    original,
    modified: HistoryBlobLoading,
  }
  let history_docs = state.history_docs.copy()
  history_docs[key] = doc
  let cmds = [request_viewer_remeasure()]
  if diff.parent is Some(parent) {
    cmds.push(
      request_history_blob(
        dispatch,
        ctx.owner,
        key,
        generation,
        HistoryOriginal,
        diff.original_path.unwrap_or(diff.path),
        parent,
        workspace=ctx.workspace(),
      ),
    )
  }
  cmds.push(
    request_history_blob(
      dispatch,
      ctx.owner,
      key,
      generation,
      HistoryModified,
      diff.path,
      diff.commit,
      workspace=ctx.workspace(),
    ),
  )
  (@cmd.batch(cmds), { ..state, history_docs, history_generation: generation, })
}

///|
pub fn activate_history_diff(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  diff : @dock.GitHistoryDiff,
) -> (@cmd.Cmd, State) {
  match state.history_docs.get(history_diff_key(diff)) {
    Some(doc) =>
      (
        @cmd.batch([
          show_history_doc(ctx.owner, doc),
          request_viewer_remeasure(),
        ]),
        state,
      )
    None => open_history_diff(dispatch, state, ctx, diff)
  }
}

///|
pub fn close_history_diff(state : State, diff : @dock.GitHistoryDiff) -> State {
  let history_docs = state.history_docs.copy()
  history_docs.remove(history_diff_key(diff))
  { ..state, history_docs, }
}

///|
struct GraphLane {
  id : String
  color : Int
} derive(Eq)

///|
struct GraphRow {
  input_swimlanes : Array[GraphLane]
  output_swimlanes : Array[GraphLane]
} derive(Eq)

///|
/// VS Code cycles five graph colors for ordinary lanes, while refs with a
/// product meaning keep a stable semantic color across their lane.
const GraphGenericColorCount = 5

///|
const GraphCurrentColor = 5

///|
const GraphUpstreamColor = 6

///|
const GraphBaseColor = 7

///|
fn git_history_ref_rank(kind : String) -> Int {
  match kind {
    "current" => 0
    "head" => 1
    "upstream" => 2
    "base" => 3
    _ => 4
  }
}

///|
fn graph_ref_color(
  snapshot : @protocol.GitHistorySnapshot,
  revision : String,
) -> Int? {
  let mut best_rank = 5
  let mut result : Int? = None
  for ref_ in snapshot.refs {
    guard ref_.revision == revision else { continue }
    let rank = git_history_ref_rank(ref_.kind)
    guard rank < best_rank else { continue }
    let color = match ref_.kind {
      "current" | "head" => Some(GraphCurrentColor)
      "upstream" => Some(GraphUpstreamColor)
      "base" => Some(GraphBaseColor)
      _ => None
    }
    if color is Some(_) {
      best_rank = rank
      result = color
    }
  }
  result
}

///|
fn find_graph_lane(lanes : Array[GraphLane], id : String) -> Int? {
  lanes.search_by(lane => lane.id == id)
}

///|
/// Port of VS Code's `toISCMHistoryItemViewModelArray` swimlane transition.
/// Duplicate parent identities are intentionally retained: they represent
/// distinct graph paths and only converge when that commit row is rendered.
fn graph_rows(
  commits : Array[@protocol.GitHistoryCommit],
  snapshot : @protocol.GitHistorySnapshot,
) -> Array[GraphRow] {
  let rows : Array[GraphRow] = []
  let mut output_from_previous : Array[GraphLane] = []
  let mut next_color = 0
  for commit in commits {
    let input_swimlanes = output_from_previous.copy()
    let output_swimlanes : Array[GraphLane] = []
    let mut first_parent_added = false

    if !commit.parent_ids.is_empty() {
      for node in input_swimlanes {
        if node.id == commit.id {
          if !first_parent_added {
            output_swimlanes.push({
              id: commit.parent_ids[0],
              color: graph_ref_color(snapshot, commit.id).unwrap_or(node.color),
            })
            first_parent_added = true
          }
          continue
        }
        output_swimlanes.push(node)
      }
    }

    let first_unprocessed_parent = if first_parent_added { 1 } else { 0 }
    for parent_index in first_unprocessed_parent..<commit.parent_ids.length() {
      let parent = commit.parent_ids[parent_index]
      let semantic_color = if parent_index == 0 {
        graph_ref_color(snapshot, commit.id)
      } else if commits.any(item => item.id == parent) {
        graph_ref_color(snapshot, parent)
      } else {
        None
      }
      let color = match semantic_color {
        Some(color) => color
        None => {
          let color = next_color
          next_color = (next_color + 1) % GraphGenericColorCount
          color
        }
      }
      output_swimlanes.push({ id: parent, color, })
    }

    rows.push({ input_swimlanes, output_swimlanes, })
    output_from_previous = output_swimlanes
  }
  rows
}

///|
fn graph_test_commit(
  id : String,
  parent_ids : Array[String],
) -> @protocol.GitHistoryCommit {
  {
    id,
    parent_ids,
    subject: id,
    author: "A",
    authored_at: "2026-01-01T00:00:00Z",
  }
}

///|
fn graph_lane_signature(lanes : Array[GraphLane]) -> String {
  lanes.map(lane => "\{lane.id}:\{lane.color}").join(",")
}

///|
test "Git graph matches VS Code linear swimlane transitions" {
  let rows = graph_rows(
    [
      graph_test_commit("a", ["b"]),
      graph_test_commit("b", ["c"]),
      graph_test_commit("c", ["d"]),
      graph_test_commit("d", ["e"]),
      graph_test_commit("e", []),
    ],
    { head: None, branch: None, refs: [], tips: [], },
  )
  assert_eq(rows.length(), 5)
  assert_eq(graph_lane_signature(rows[0].input_swimlanes), "")
  assert_eq(graph_lane_signature(rows[0].output_swimlanes), "b:0")
  assert_eq(graph_lane_signature(rows[1].input_swimlanes), "b:0")
  assert_eq(graph_lane_signature(rows[1].output_swimlanes), "c:0")
  assert_eq(graph_lane_signature(rows[2].output_swimlanes), "d:0")
  assert_eq(graph_lane_signature(rows[3].output_swimlanes), "e:0")
  assert_eq(graph_lane_signature(rows[4].input_swimlanes), "e:0")
  assert_eq(graph_lane_signature(rows[4].output_swimlanes), "")
}

///|
test "Git graph matches VS Code single-commit topic branch transitions" {
  let rows = graph_rows(
    [
      graph_test_commit("a", ["b"]),
      graph_test_commit("b", ["c", "d"]),
      graph_test_commit("d", ["c"]),
      graph_test_commit("c", ["e"]),
      graph_test_commit("e", ["f"]),
    ],
    { head: None, branch: None, refs: [], tips: [], },
  )
  assert_eq(graph_lane_signature(rows[0].output_swimlanes), "b:0")
  assert_eq(graph_lane_signature(rows[1].input_swimlanes), "b:0")
  assert_eq(graph_lane_signature(rows[1].output_swimlanes), "c:0,d:1")
  assert_eq(graph_lane_signature(rows[2].input_swimlanes), "c:0,d:1")
  assert_eq(graph_lane_signature(rows[2].output_swimlanes), "c:0,c:1")
  assert_eq(graph_lane_signature(rows[3].input_swimlanes), "c:0,c:1")
  assert_eq(graph_lane_signature(rows[3].output_swimlanes), "e:0")
  assert_eq(graph_lane_signature(rows[4].output_swimlanes), "f:0")
}

///|
test "Git graph matches VS Code multi-commit topic branch transitions" {
  let rows = graph_rows(
    [
      graph_test_commit("a", ["b", "c"]),
      graph_test_commit("c", ["d"]),
      graph_test_commit("b", ["e"]),
      graph_test_commit("e", ["f"]),
      graph_test_commit("f", ["d"]),
      graph_test_commit("d", ["g"]),
    ],
    { head: None, branch: None, refs: [], tips: [], },
  )
  assert_eq(graph_lane_signature(rows[0].output_swimlanes), "b:0,c:1")
  assert_eq(graph_lane_signature(rows[1].output_swimlanes), "b:0,d:1")
  assert_eq(graph_lane_signature(rows[2].output_swimlanes), "e:0,d:1")
  assert_eq(graph_lane_signature(rows[3].output_swimlanes), "f:0,d:1")
  assert_eq(graph_lane_signature(rows[4].output_swimlanes), "d:0,d:1")
  assert_eq(graph_lane_signature(rows[5].input_swimlanes), "d:0,d:1")
  assert_eq(graph_lane_signature(rows[5].output_swimlanes), "g:0")
}

///|
test "Git graph lanes retain linear history and connect merge parents" {
  let rows = graph_rows(
    [
      {
        id: "merge",
        parent_ids: ["left", "right"],
        subject: "merge",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
      {
        id: "right",
        parent_ids: ["base"],
        subject: "right",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
      {
        id: "left",
        parent_ids: ["base"],
        subject: "left",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
    ],
    { head: Some("merge"), branch: None, refs: [], tips: ["merge"], },
  )
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].input_swimlanes.length(), 0)
  assert_eq(rows[0].output_swimlanes.map(lane => lane.id), ["left", "right"])
  assert_eq(rows[1].input_swimlanes.map(lane => lane.id), ["left", "right"])
  assert_eq(rows[1].output_swimlanes.map(lane => lane.id), ["left", "base"])
  assert_eq(rows[2].input_swimlanes.map(lane => lane.id), ["left", "base"])
  assert_eq(rows[2].output_swimlanes.map(lane => lane.id), ["base", "base"])
}

///|
test "Git graph semantic colors follow refs through the pagination boundary" {
  let snapshot : @protocol.GitHistorySnapshot = {
    head: Some("head"),
    branch: Some("feature/graph"),
    refs: [
      { name: "feature/graph", revision: "head", kind: "current", },
      { name: "origin/feature/graph", revision: "remote", kind: "upstream", },
      { name: "origin/main", revision: "base", kind: "base", },
    ],
    tips: ["head", "remote", "base"],
  }
  let rows = graph_rows(
    [
      {
        id: "head",
        parent_ids: ["middle"],
        subject: "head",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
      {
        id: "middle",
        parent_ids: ["base"],
        subject: "middle",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
      {
        id: "base",
        parent_ids: ["root"],
        subject: "base",
        author: "A",
        authored_at: "2026-01-01T00:00:00Z",
      },
    ],
    snapshot,
  )
  assert_eq(rows[0].input_swimlanes.length(), 0)
  assert_eq(rows[0].output_swimlanes.map(lane => lane.color), [
    GraphCurrentColor,
  ])
  assert_eq(rows[1].output_swimlanes.map(lane => lane.color), [
    GraphCurrentColor,
  ])
  assert_eq(rows[2].output_swimlanes.map(lane => lane.color), [GraphBaseColor])
  assert_eq(graph_ref_color(snapshot, "remote"), Some(GraphUpstreamColor))
}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend GraphLane with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend GraphRow with Eq::{equal, not_equal}
