///|
/// Attach one child session's turns to the parent span that spawned it.
///
/// Ownership is already resolved before mounting (via tool-result BFS or
/// legacy `<parent>-sr-N` naming), which tells which session owns the child
/// but not necessarily which *step* did the spawning. Exact `tool_result`
/// mounts name the step directly; otherwise it is recovered from time, and
/// children predating every parent turn fall back to the root run span.
fn mount_child(run : RunBuilder, child : ChildMount) -> Unit {
  // The spawning tool's own result names the child session, so the exact step
  // is known; only a child the log never named falls back to the time window.
  // Whichever decided it is written on the child's first turn, so a reader can
  // tell an exact mount from an inferred one.
  let (mount, how) = match run.child_mounts.get(child.session_id) {
    Some(span_id) => (span_id, "tool_result")
    None =>
      match find_mount_span(run.spans, child) {
        Some(span_id) => (span_id, "time_window")
        None => (run_span_id(run.root_session_id), "run_span")
      }
  }
  for i in 0..<run.spans.length() {
    let span = run.spans[i]
    if span.session_id == child.session_id &&
      span.kind is Turn &&
      span.parent_id is None {
      let metadata = span.metadata.copy()
      metadata["mount"] = Json(how)
      run.spans[i] = { ..span, parent_id: Some(mount), metadata, }
    }
  }
}

///|
/// The id of the run span every root-session turn hangs under.
fn run_span_id(root_session_id : String) -> String {
  "\{root_session_id}:run"
}

///|
/// Whether a parent span can plausibly spawn a child session when `data.session`
/// was not recorded. Delegation and orchestration tools are preferred over
/// ordinary leaf tools so a concurrent `read_file` does not steal the mount.
fn is_delegation_span(span : TrajectorySpan) -> Bool {
  span.kind is WorkflowScript ||
  span.kind is JobWait ||
  span.label == "subagent" ||
  span.label.has_prefix("subagent:")
}

///|
/// Find the parent span a child session was spawned from.
fn find_mount_span(
  spans : Array[TrajectorySpan],
  child : ChildMount,
) -> String? {
  let mut best_delegation : TrajectorySpan? = None
  let mut best_other : TrajectorySpan? = None
  for span in spans {
    if span.session_id != child.parent_session_id {
      continue
    }
    let nests_work = match span.kind {
      ToolExec | WorkflowScript | JobWait => true
      _ => false
    }
    if !nests_work {
      continue
    }
    if span.started_at_ms > child.started_at_ms + MountSlackMs {
      continue
    }
    match span.ended_at_ms {
      Some(end) => if end + MountSlackMs < child.started_at_ms { continue }
      None => ()
    }
    if is_delegation_span(span) {
      let better = match best_delegation {
        None => true
        Some(current) => span.started_at_ms >= current.started_at_ms
      }
      if better {
        best_delegation = Some(span)
      }
    } else {
      let better = match best_other {
        None => true
        Some(current) => span.started_at_ms >= current.started_at_ms
      }
      if better {
        best_other = Some(span)
      }
    }
  }
  let tool = match best_delegation {
    Some(span) => Some(span.id)
    None =>
      match best_other {
        Some(span) => Some(span.id)
        None => None
      }
  }
  if tool is Some(_) {
    return tool
  }
  // No wrapping call: fall back to the parent turn that was open at that
  // moment. When no turn covers the child (for example an earlier-engine
  // worker surfaced through `recovered[]`), let `mount_child` attach it to
  // the run root rather than mis-filing it under the final turn.
  let mut covering : TrajectorySpan? = None
  for span in spans {
    if span.session_id != child.parent_session_id || !(span.kind is Turn) {
      continue
    }
    let ends_after = match span.ended_at_ms {
      Some(end) => end + MountSlackMs >= child.started_at_ms
      None => true
    }
    if span.started_at_ms <= child.started_at_ms + MountSlackMs && ends_after {
      covering = Some(span)
    }
  }
  covering.map(span => span.id)
}

///|
/// Put the spans in rendering order and assign nesting depth.
///
/// The run span leads; below it every span follows its parent and is followed
/// by its own children, siblings oldest first. Depth is read off the tree
/// rather than trusted from the builder, so a re-parented child (mounted under
/// a later-found call) still indents correctly.
fn order_spans(spans : Array[TrajectorySpan]) -> Array[TrajectorySpan] {
  let children : Map[String, Array[Int32]] = Map([])
  let roots : Array[Int32] = []
  for i in 0..<spans.length() {
    let parent = spans[i].parent_id
    match parent {
      Some(id) => {
        let bucket = match children.get(id) {
          Some(bucket) => bucket
          None => {
            let fresh : Array[Int32] = []
            children[id] = fresh
            fresh
          }
        }
        bucket.push(i)
      }
      None => roots.push(i)
    }
  }
  let out : Array[TrajectorySpan] = []
  let visited : Array[Bool] = []
  for _ in 0..<spans.length() {
    visited.push(false)
  }
  fn walk(
    spans : Array[TrajectorySpan],
    children : Map[String, Array[Int32]],
    index : Int32,
    depth : Int32,
    out : Array[TrajectorySpan],
    visited : Array[Bool],
  ) -> Unit {
    if visited[index] {
      return
    }
    visited[index] = true
    let span = spans[index]
    out.push({ ..span, depth, })
    match children.get(span.id) {
      Some(bucket) =>
        for child in bucket {
          walk(spans, children, child, depth + 1, out, visited)
        }
      None => ()
    }
  }
  for root in roots {
    walk(spans, children, root, 0, out, visited)
  }
  // A parent id naming a span that is not in this array (a mount that found
  // nothing) leaves spans unreachable; they still belong on the timeline.
  for i in 0..<spans.length() {
    if !visited[i] {
      walk(spans, children, i, 1, out, visited)
    }
  }
  out
}

///|
/// The longest single step of the run, and the chain it hangs from.
///
/// At each level the child covering the most time wins, which is the branch a
/// reader should look at first when asking "what did this run actually spend
/// its time on". The number is the widest step met on that chain: a session or
/// a turn span is its children's subtotal, not a step. Containment makes the
/// widest step on the heaviest branch the widest step of the run, and summing
/// the nested envelopes instead would count one wall-clock stretch twice.
///
/// A dependency-weighted path would need a causal graph the log does not carry.
fn critical_path_of(
  spans : Array[TrajectorySpan],
  now_ms : Int64,
) -> (Array[String], Int64) {
  let by_parent : Map[String, Array[TrajectorySpan]] = Map([])
  let mut root : TrajectorySpan? = None
  for span in spans {
    match span.parent_id {
      Some(parent) => {
        let bucket = match by_parent.get(parent) {
          Some(bucket) => bucket
          None => {
            let fresh : Array[TrajectorySpan] = []
            by_parent[parent] = fresh
            fresh
          }
        }
        bucket.push(span)
      }
      None => if span.kind is Run { root = Some(span) }
    }
  }
  let path : Array[String] = []
  let (total, widest_at) = match root {
    Some(span) => walk_critical(by_parent, span, path, now_ms)
    None => (0L, 0)
  }
  // The chain stops at the step it reports: whatever sits below that step was
  // inside it, and naming it too would suggest a second answer.
  let chain : Array[String] = []
  for index, id in path {
    if index <= widest_at {
      chain.push(id)
    }
  }
  (chain, total)
}

///|
/// Whether a child's duration is directly observed (closed, or an actively
/// running non-background step up to `now_ms`). An unwaited background job
/// stays open after the run stops, so it is excluded from live weighting.
fn has_observed_duration(span : TrajectorySpan) -> Bool {
  if span.kind is Milestone {
    return false
  }
  span.ended_at_ms is Some(_) || !(span.kind is BackgroundJob)
}

///|
/// Follow the heaviest child of `span` to the bottom, recording the chain, and
/// say where on it the widest step sits.
fn walk_critical(
  by_parent : Map[String, Array[TrajectorySpan]],
  span : TrajectorySpan,
  path : Array[String],
  now_ms : Int64,
) -> (Int64, Int32) {
  let index = path.length()
  path.push(span.id)
  // A session or a turn wraps everything below it, so its width is that
  // branch's subtotal rather than a step anyone can go and look at.
  let mut widest = if span.kind is Run ||
    span.kind is Turn ||
    !has_observed_duration(span) {
    0L
  } else {
    span.duration_ms(now_ms)
  }
  let mut widest_at = index
  if pick_heaviest(by_parent.get(span.id), now_ms) is Some(child) {
    let (below, below_at) = walk_critical(by_parent, child, path, now_ms)
    if below > widest {
      widest = below
      widest_at = below_at
    }
  }
  (widest, widest_at)
}

///|
/// The child of one span that covers the most time, ignoring zero-duration
/// markers unless they are all there is.
fn pick_heaviest(
  children : Array[TrajectorySpan]?,
  now_ms : Int64,
) -> TrajectorySpan? {
  let mut best : TrajectorySpan? = None
  let mut best_duration = -1L
  let mut best_measured : TrajectorySpan? = None
  let mut best_measured_duration = -1L
  match children {
    Some(items) =>
      for child in items {
        let measured = has_observed_duration(child)
        let duration = if measured { child.duration_ms(now_ms) } else { 0L }
        if duration > best_duration {
          best = Some(child)
          best_duration = duration
        }
        if measured && duration > best_measured_duration {
          best_measured = Some(child)
          best_measured_duration = duration
        }
      }
    None => ()
  }
  match best_measured {
    Some(child) => Some(child)
    None => best
  }
}
