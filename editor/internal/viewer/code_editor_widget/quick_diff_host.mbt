// VS Code quickDiffModel's 200ms coalescing + editor worker computation.
// Only fresh, validated results reach decorations. A failed/timed-out job
// clears the gutter; it is never represented as a successful empty diff.

///|
priv struct QuickDiffCache {
  identity : Int
  version : Int
  original : String
  changes : Array[@diff.DetailedLineRangeMapping]
}

///|
fn QuickDiffContributionState::cancel(
  self : QuickDiffContributionState,
) -> Unit {
  self.generation += 1
  self.scheduler.cancel()
  match self.worker_job {
    Some(job) => job.dispose()
    None => ()
  }
  self.worker_job = None
}

///|
fn CodeEditorWidget::quick_diff_update(
  self : CodeEditorWidget,
  state : QuickDiffContributionState,
) -> Unit {
  state.cancel()
  guard self.is_code_presentation() &&
    self.get_model() is Some(model) &&
    self.services.quick_diff.get_original_content(model.uri) is Some(original) else {
    state.cached = None
    state.collection.set([]) |> ignore
    return
  }
  let identity = model.identity()
  let version = model.get_version_id()
  if state.cached is Some(cached) &&
    cached.identity == identity &&
    cached.version == version &&
    cached.original == original {
    state.collection.set(
      @quick_diff_browser.changes_to_decorations(cached.changes),
    )
    |> ignore
    return
  }
  state.collection.set([]) |> ignore
  let generation = state.generation
  let original_snapshot = @model.TextSnapshot(original)
  let modified_snapshot = model.snapshot
  let complete = (result : @diff.DocumentDiff?) => {
    if self.disposed ||
      generation != state.generation ||
      !(self.get_model() is Some(current) &&
      current.identity() == identity &&
      current.get_version_id() == version) ||
      self.services.quick_diff.get_original_content(model.uri) != Some(original) {
      return
    }
    state.worker_job = None
    let validated = match result {
      Some(result) =>
        @diff.normalize_and_validate_document_diff(
          result, original_snapshot, modified_snapshot,
        )
      None => None
    }
    match validated {
      Some(document) => {
        let changes = document.changes.map(change => change.mapping)
        state.cached = Some({ identity, version, original, changes, })
        state.collection.set(
          @quick_diff_browser.changes_to_decorations(changes),
        )
        |> ignore
      }
      None => {
        state.cached = None
        state.collection.set([]) |> ignore
      }
    }
  }
  let compute = () => {
    if generation != state.generation {
      return
    }
    let job = @code_worker.compute(
      Diff(
        original=original_snapshot.get_value(),
        modified=modified_snapshot.get_value(),
        ignore_trim_whitespace=false,
      ),
      result => {
        match result {
          Ok(Diff(changes)) =>
            complete(Some(@worker_protocol.decode_diff(changes)))
          _ => complete(None)
        }
      },
    )
    match job {
      Some(job) => state.worker_job = Some(job)
      None =>
        complete(
          Some(
            @diff.LineDocumentDiffProvider().compute_diff(
              original_snapshot,
              modified_snapshot,
              { ignore_trim_whitespace: false, },
            ),
          ),
        )
    }
  }
  if @code_worker.available() {
    state.scheduler.schedule(compute)
  } else {
    compute()
  }
}
