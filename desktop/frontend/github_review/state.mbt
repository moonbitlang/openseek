///|
using @protocol {type GithubDraftTarget, type GithubDraft}

///|
pub(all) struct State {
  checkout : @github.CheckoutScope?
  path : String?
  refresh_pending : Bool
  enabled : Bool
  epoch : Int
  loading : Bool
  review : @protocol.GithubReview?
  file : Result[@protocol.GithubReviewFile?, String]?
  files : Array[(String, @protocol.GithubReviewFile?)]
  file_epoch : Int
  file_loading : Bool
  error : String?
  drafts : Array[GithubDraft]
  active : GithubDraftTarget?
  expanded : Array[String]
  deleting : String?
  busy : Bool
  mutation_epoch : Int
  mutation_error : Failure?
  storage_error : Failure?
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    checkout: None,
    path: None,
    refresh_pending: false,
    enabled: false,
    epoch: 0,
    loading: false,
    review: None,
    file: None,
    files: [],
    file_epoch: 0,
    file_loading: false,
    error: None,
    drafts: [],
    active: None,
    expanded: [],
    deleting: None,
    busy: false,
    mutation_epoch: 0,
    mutation_error: None,
    storage_error: None,
  }
}

///|
pub(all) enum Msg {
  CheckAvailability
  Toggle
  Refresh
  Loaded(
    Int,
    Result[@protocol.GithubReviewReply, String],
    Result[Array[GithubDraft], Failure]
  )
  FileLoaded(Int, String, Result[@protocol.GithubReviewFileReply, String])
  Compose(GithubDraftTarget)
  Edit(GithubDraftTarget, String)
  Cancel(GithubDraftTarget)
  Send(GithubDraftTarget)
  DeleteRequested(String)
  DeleteCancelled
  DeleteConfirmed(String)
  Resolve(String, Bool)
  Expand(String)
  Mutated(
    Int,
    @protocol.GithubReviewAction,
    GithubDraft?,
    Result[@protocol.GithubReviewMutationReply, String],
    Result[Unit, Failure]
  )
  StorageSaved(String, Result[Unit, Failure])
}

///|
/// Track only the identity of the checkout whose discussions we hold. PR
/// discovery, revalidation and its errors are supplied by the application.
pub fn reconcile(
  emit : @cmd.Emit[Msg],
  state : State,
  current : @github.State,
  path : String?,
) -> (@cmd.Cmd, State) {
  let changed = state.checkout != current.scope ||
    (
      current.has_open_pr() &&
      state.review is Some(review) &&
      current.current_url() != Some(review.url)
    )
  let next = if changed {
    {
      ..State::empty(),
      checkout: current.scope,
      path,
      enabled: state.enabled,
      epoch: state.epoch + 1,
      file_epoch: state.file_epoch + 1,
      mutation_epoch: state.mutation_epoch + 1,
    }
  } else if state.path != path {
    {
      ..state,
      path,
      file_epoch: state.file_epoch + 1,
      file_loading: false,
      file: None,
    }
  } else {
    state
  }
  if current.current_loading || current.current is None {
    return (@cmd.none, next)
  }
  if !current.has_open_pr() {
    return (
      @cmd.none,
      if next.enabled || next.loading || next.file_loading {
        {
          ..next,
          enabled: false,
          refresh_pending: false,
          loading: false,
          epoch: next.epoch + 1,
          file_loading: false,
          file_epoch: next.file_epoch + 1,
        }
      } else {
        next
      },
    )
  }
  if next.enabled &&
    !next.loading &&
    (next.refresh_pending || (next.review is None && next.error is None)) {
    request(emit, next, current)
  } else {
    request_file(emit, next)
  }
}

///|
fn request(
  emit : @cmd.Emit[Msg],
  state : State,
  current : @github.State,
) -> (@cmd.Cmd, State) {
  guard current.has_open_pr() &&
    !current.current_loading &&
    state.checkout is Some(owner) &&
    !state.busy else {
    return (@cmd.none, { ..state, refresh_pending: true, })
  }
  let epoch = state.epoch + 1
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result = Ok(
        @interop.bridge_request(owner.channel, @commands.github_review, {
          cwd: owner.cwd,
        }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      let drafts = match result {
        Ok(@protocol.ReviewLoaded(Some(review))) => load_drafts(review.url)
        _ => Ok([])
      }
      scheduler.add(emit(Loaded(epoch, result, drafts)))
    })
    |> ignore
  })
  (
    command,
    { ..state, epoch, loading: true, refresh_pending: false, error: None, },
  )
}

///|
/// Discussions belong to a PR revision, not to the selected file. Once that
/// revision is known, file switches need only immutable local Git snapshots.
fn request_file(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  guard state.enabled &&
    !state.file_loading &&
    state.file is None &&
    state.checkout is Some(owner) &&
    state.path is Some(path) &&
    state.review is Some(review) else {
    return (@cmd.none, state)
  }
  if state.files.iter().filter(item => item.0 == path).next() is Some((_, file)) {
    return (@cmd.none, { ..state, file: Some(Ok(file)), })
  }
  let epoch = state.file_epoch + 1
  let command = @cmd.attempt(
    result => {
      emit(FileLoaded(epoch, path, result.map_err(@interop.bridge_error_text)))
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.github_review_file, {
        cwd: owner.cwd,
        path,
        base: review.base,
        head: review.head,
      })
    },
  )
  (command, { ..state, file_epoch: epoch, file_loading: true, })
}

///|
pub fn State::draft_body(self : State, target : GithubDraftTarget) -> String {
  self.drafts
  .iter()
  .filter(draft => draft.target == target)
  .next()
  .map(draft => draft.body)
  .unwrap_or("")
}

///|
fn save(emit : @cmd.Emit[Msg], state : State) -> @cmd.Cmd {
  guard state.review is Some(review) else { return @cmd.none }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      scheduler.add(
        emit(StorageSaved(review.url, store_drafts(review.url, state.drafts))),
      )
    })
    |> ignore
  })
}

///|
fn mutation(
  emit : @cmd.Emit[Msg],
  state : State,
  action : @protocol.GithubReviewAction,
  draft : GithubDraft?,
) -> (@cmd.Cmd, State) {
  guard !state.busy &&
    state.checkout is Some(owner) &&
    state.review is Some(review) else {
    return (@cmd.none, state)
  }
  let epoch = state.mutation_epoch + 1
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result = Ok(
        @interop.bridge_request(owner.channel, @commands.github_review_mutate, {
          cwd: owner.cwd,
          url: review.url,
          action,
        }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      // Complete the originating draft even if navigation has retired its UI.
      // A newer local edit is never removed by an older request's completion.
      let storage = if result is Ok(@protocol.ReviewMutationSuccess) &&
        draft is Some(sent) {
        remove_sent_draft(review.url, sent)
      } else {
        Ok(())
      }
      scheduler.add(emit(Mutated(epoch, action, draft, result, storage)))
    })
    |> ignore
  })
  (
    command,
    {
      ..state,
      busy: true,
      mutation_epoch: epoch,
      mutation_error: None,
      deleting: None,
    },
  )
}

///|
pub fn update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  current~ : @github.State,
) -> (@cmd.Cmd, State) {
  match msg {
    // The root handles this refresh intent before dispatching to Review.
    CheckAvailability => (@cmd.none, state)
    Toggle => {
      guard current.has_open_pr() else { return (@cmd.none, state) }
      let next = { ..state, enabled: !state.enabled, }
      if next.enabled {
        request(emit, next, current)
      } else {
        (@cmd.none, next)
      }
    }
    Refresh =>
      if state.enabled {
        request(emit, state, current)
      } else {
        (@cmd.none, state)
      }
    Loaded(epoch, result, drafts) => {
      guard epoch == state.epoch else { return (@cmd.none, state) }
      let result = match result {
        Ok(@protocol.ReviewLoaded(review)) => Ok(review)
        Ok(@protocol.ReviewLoadFailed(error)) | Err(error) => Err(error)
      }
      match result {
        Err(error) =>
          (@cmd.none, { ..state, loading: false, error: Some(error), })
        Ok(review) => {
          let same_pr = state.review.map(pr => pr.url) ==
            review.map(pr => pr.url)
          let same_revision = state.review.map(pr => (pr.url, pr.base, pr.head)) ==
            review.map(pr => (pr.url, pr.base, pr.head))
          let (drafts, storage_error) = if same_pr &&
            state.storage_error is Some(_) {
            // A refresh must not overwrite unsaved edits or restore a comment
            // already sent when removing its local draft failed.
            (state.drafts, state.storage_error)
          } else {
            match drafts {
              Ok(drafts) => (drafts, None)
              Err(error) =>
                (if same_pr { state.drafts } else { [] }, Some(error))
            }
          }
          request_file(emit, {
            ..state,
            review,
            enabled: state.enabled && review is Some(_),
            files: if same_revision {
              state.files
            } else {
              []
            },
            file_epoch: state.file_epoch + 1,
            file_loading: false,
            file: None,
            loading: false,
            error: None,
            drafts,
            storage_error,
            active: if same_pr {
              state.active
            } else {
              None
            },
            expanded: if same_pr {
              state.expanded
            } else {
              []
            },
          })
        }
      }
    }
    FileLoaded(epoch, path, result) => {
      guard epoch == state.file_epoch &&
        state.path == Some(path) &&
        state.review is Some(_) else {
        return (@cmd.none, state)
      }
      let file = match result {
        Ok(@protocol.ReviewFileLoaded(file)) => Ok(file)
        Ok(@protocol.ReviewFileFailed(error)) | Err(error) => Err(error)
      }
      (
        @cmd.none,
        {
          ..state,
          files: match file {
            Ok(file) =>
              state.files.filter(item => item.0 != path) + [(path, file)]
            Err(_) => state.files
          },
          file_loading: false,
          file: Some(file),
        },
      )
    }
    Compose(target) => {
      guard !state.busy else { return (@cmd.none, state) }
      (
        @cmd.custom_cmd(
          _ => {
            if @dom.document()
              .get_element_by_id("github-review-input:" + target.key())
              .to_option()
              is Some(input) {
              // Inline blocks are initially hidden until the editor publishes
              // their ViewZone geometry. The adapter completes this focus then.
              input.set_attribute("data-github-review-focus", "")
              @base_browser.focus_prevent_scroll(input)
              if @base_browser.element_has_focus(input) {
                input.remove_attribute("data-github-review-focus")
              }
            }
          },
          kind=@cmd.after_render,
        ),
        { ..state, active: Some(target), mutation_error: None, },
      )
    }
    Edit(target, body) => {
      guard !state.busy else { return (@cmd.none, state) }
      let drafts = state.drafts.filter(draft => draft.target != target)
      if !body.is_empty() {
        drafts.push({ target, body, })
      }
      let next = { ..state, drafts, active: Some(target), }
      (save(emit, next), next)
    }
    Cancel(target) => {
      guard !state.busy else { return (@cmd.none, state) }
      let next = {
        ..state,
        drafts: state.drafts.filter(draft => draft.target != target),
        active: None,
        mutation_error: None,
      }
      (save(emit, next), next)
    }
    Send(target) => {
      guard !state.busy &&
        state.review is Some(review) &&
        state.drafts.iter().filter(draft => draft.target == target).next()
        is Some(draft) &&
        !draft.body.trim().is_empty() else {
        return (@cmd.none, state)
      }
      let action : @protocol.GithubReviewAction = match target {
        Line(path~, side~, line~, head~) => {
          guard head == review.head else {
            return (
              @cmd.none,
              { ..state, mutation_error: Some(EarlierRevision), },
            )
          }
          guard review.can_comment(path, side == "LEFT", line) else {
            return (
              @cmd.none,
              { ..state, mutation_error: Some(LineOutsideDiff), },
            )
          }
          Post(path~, side~, line~, head~, body=draft.body)
        }
        Thread(comment~, ..) => Reply(comment~, body=draft.body)
      }
      mutation(emit, state, action, Some(draft))
    }
    DeleteRequested(id) => (@cmd.none, { ..state, deleting: Some(id), })
    DeleteCancelled => (@cmd.none, { ..state, deleting: None, })
    DeleteConfirmed(comment) => mutation(emit, state, Delete(comment~), None)
    Resolve(thread, resolved) =>
      mutation(emit, state, Resolve(thread~, resolved~), None)
    Expand(id) =>
      (
        @cmd.none,
        {
          ..state,
          expanded: if state.expanded.contains(id) {
            state.expanded.filter(item => item != id)
          } else {
            state.expanded + [id]
          },
        },
      )
    Mutated(epoch, action, draft, result, storage) => {
      guard epoch == state.mutation_epoch else { return (@cmd.none, state) }
      match result {
        Ok(@protocol.ReviewMutationSuccess) => {
          let review = state.review.map(review => {
            let threads = review.threads
              .map(thread => {
                match action {
                  Resolve(thread=id, resolved~) if id == thread.id =>
                    {
                      ..thread,
                      resolved,
                      can_resolve: !resolved,
                      can_unresolve: resolved,
                    }
                  Delete(comment~) =>
                    {
                      ..thread,
                      comments: thread.comments.filter(item => {
                        item.id != comment
                      }),
                    }
                  _ => thread
                }
              })
              .filter(thread => !thread.comments.is_empty())
            { ..review, threads, }
          })
          let storage_error = match storage {
            Ok(_) => state.storage_error
            Err(error) => Some(error)
          }
          let next = {
            ..state,
            review,
            busy: false,
            storage_error,
            drafts: state.drafts.filter(item => Some(item) != draft),
            active: None,
            mutation_error: None,
          }
          request(emit, next, current)
        }
        Ok(@protocol.ReviewMutationFailure(error)) | Err(error) =>
          (
            @cmd.none,
            { ..state, busy: false, mutation_error: Some(Remote(error)), },
          )
      }
    }
    StorageSaved(url, result) => {
      guard state.review.map(review => review.url) == Some(url) else {
        return (@cmd.none, state)
      }
      (
        @cmd.none,
        {
          ..state,
          storage_error: match result {
            Ok(_) => None
            Err(error) => Some(error)
          },
        },
      )
    }
  }
}

///|
pub extend State with Eq::{equal, not_equal}
