///| Concrete stateful grammar backend over shared live model state.
///
/// Source: `vscode/src/vs/editor/common/model/tokens/tokenizerSyntaxTokenBackend.ts`
/// in the checked-in source, lines 26-322. The live
/// `TokenizationModelState`, absent custom/verifier worker arms, and optional
/// epoch scheduler are the reviewed deviations; reset/event/store/refresh
/// ordering and branch constants follow the source.

///|
/// Store delta returned by a syntactic batch write.
priv struct TokenStoreChange {
  changes : Array[ModelTokensChangedRange]
}

///|
/// Per-view handler ownership entry.
priv struct AttachedViewHandlerEntry {
  view : AttachedViewImpl
  handler : AttachedViewHandler
}

///|
/// Concrete TextMate-style syntactic backend.
priv struct TokenizerSyntaxTokenBackend {
  shared : AbstractSyntaxTokenBackend
  model_state : TokenizationModelState
  resolve_support : (String) -> InternalTokenizationSupportAdapter?
  mut tokenizer : TokenizerWithStateStoreAndTextModel?
  mut default_background_tokenizer : DefaultBackgroundTokenizer?
  tokens : @common_tokens.ContiguousTokensStore
  attached_view_states : Array[AttachedViewHandlerEntry]
  mut registry_subscription : @base_common.Disposable?
  mut attached_subscription : @base_common.Disposable?
  mut disposed : Bool
}

///|
/// Constructs the backend from the registry-backed production resolver or a
/// failing/`has_eol`-aware white-box resolver.
fn TokenizerSyntaxTokenBackend::new_with_support_resolver(
  model_state : TokenizationModelState,
  attached_views : AttachedViews,
  resolve_support : (String) -> InternalTokenizationSupportAdapter?,
  subscribe_registry? : Bool = false,
) -> TokenizerSyntaxTokenBackend {
  let backend : TokenizerSyntaxTokenBackend = {
    shared: AbstractSyntaxTokenBackend(),
    model_state,
    resolve_support,
    tokenizer: None,
    default_background_tokenizer: None,
    tokens: ContiguousTokensStore(@services.language_id_codec),
    attached_view_states: [],
    registry_subscription: None,
    attached_subscription: None,
    disposed: false,
  }
  if subscribe_registry {
    backend.registry_subscription = Some(
      @syntax.tokenization_registry.on_did_change(event => {
        let language_id = backend.model_state.language_id
        if event.changed_languages.contains(language_id) {
          backend.reset_tokenization()
        }
      }),
    )
  }
  backend.reset_tokenization()
  backend.attached_subscription = Some(
    attached_views.on_did_change_visible_ranges(change => {
      backend.handle_attached_view_state_change(change)
    }),
  )
  backend
}

///|
/// Handles create/reuse/update and explicit detach disposal in source order.
fn TokenizerSyntaxTokenBackend::handle_attached_view_state_change(
  self : TokenizerSyntaxTokenBackend,
  change : AttachedViewStateChange,
) -> Unit {
  match change.state {
    Some(state) => {
      let mut index = -1
      for i, entry in self.attached_view_states {
        if entry.view.same(change.view) {
          index = i
          break
        }
      }
      let handler = if index >= 0 {
        self.attached_view_states[index].handler
      } else {
        let holder : Ref[AttachedViewHandler?] = Ref(None)
        let handler = AttachedViewHandler(
          () => {
            match holder.val {
              Some(current) => self.refresh_ranges(current.line_ranges())
              None => ()
            }
          },
          () => self.model_state.scheduler.val,
        )
        holder.val = Some(handler)
        self.attached_view_states.push({ view: change.view, handler })
        handler
      }
      handler.handle_state_change(state)
    }
    None => {
      let mut index = -1
      for i, entry in self.attached_view_states {
        if entry.view.same(change.view) {
          index = i
          break
        }
      }
      if index >= 0 {
        self.attached_view_states[index].handler.dispose()
        self.attached_view_states.remove(index) |> ignore
      }
    }
  }
}

///|
/// Resets stores/support/workers and refreshes current visible ranges.
fn TokenizerSyntaxTokenBackend::reset_tokenization(
  self : TokenizerSyntaxTokenBackend,
  fire_token_change_event? : Bool = true,
) -> Unit {
  self.tokens.flush()
  if fire_token_change_event && !self.model_state.disposing.val {
    self.shared.did_change_tokens.fire({
      semantic_tokens_applied: false,
      ranges: [
        {
          from_line_number: 1,
          to_line_number: self.model_state.snapshot.val.line_count(),
        },
      ],
    })
  }
  let mut support : InternalTokenizationSupportAdapter? = None
  if !self.model_state.too_large {
    match (self.resolve_support)(self.model_state.language_id) {
      Some(candidate) =>
        try candidate.initial_state() catch {
          error => (self.model_state.report_unexpected_error)("\{Repr(error)}")
        } noraise {
          _ => support = Some(candidate)
        }
      None => ()
    }
  }
  self.tokenizer = match support {
    Some(candidate) =>
      try
        TokenizerWithStateStoreAndTextModel(
          self.model_state.snapshot.val.line_count(),
          candidate,
          self.model_state,
          @services.language_id_codec,
        )
      catch {
        error => {
          (self.model_state.report_unexpected_error)("\{Repr(error)}")
          None
        }
      } noraise {
        tokenizer => Some(tokenizer)
      }
    None => None
  }
  match self.default_background_tokenizer {
    Some(worker) => worker.dispose()
    None => ()
  }
  self.default_background_tokenizer = None
  match self.tokenizer {
    Some(tokenizer) => {
      let output = BackgroundTokenizationStore(set_tokens=batches => {
        self.set_tokens(batches) |> ignore
      })
      let worker = DefaultBackgroundTokenizer(tokenizer, output)
      self.default_background_tokenizer = Some(worker)
      worker.handle_changes()
    }
    None => ()
  }
  self.refresh_all_visible_line_tokens()
}

///|
/// Re-evaluates default work after an attached-count or scheduler transition.
fn TokenizerSyntaxTokenBackend::handle_did_change_attached(
  self : TokenizerSyntaxTokenBackend,
) -> Unit {
  match self.default_background_tokenizer {
    Some(worker) => worker.handle_changes()
    None => ()
  }
}

///|
/// Flush-only readonly content invalidation.
fn TokenizerSyntaxTokenBackend::handle_did_change_content(
  self : TokenizerSyntaxTokenBackend,
  is_flush~ : Bool,
) -> Unit {
  if is_flush {
    self.reset_tokenization(fire_token_change_event=false)
  }
}

///|
/// Writes batches, emits only nonempty exact changes, and returns the same set.
fn TokenizerSyntaxTokenBackend::set_tokens(
  self : TokenizerSyntaxTokenBackend,
  batches : Array[@common_tokens.ContiguousMultilineTokens],
) -> TokenStoreChange {
  let update = self.tokens.set_multiline_tokens(
    batches,
    self.model_state.language_id,
    line_number => self.model_state.snapshot.val.get_line_length(line_number),
  )
  let changes = update.changes.map(change => ModelTokensChangedRange::{
    from_line_number: change.from_line_number,
    to_line_number: change.to_line_number,
  })
  if !changes.is_empty() && !self.model_state.disposing.val {
    self.shared.did_change_tokens.fire({
      semantic_tokens_applied: false,
      ranges: changes,
    })
  }
  { changes, }
}

///|
/// Joins every per-view latest range and refreshes it.
fn TokenizerSyntaxTokenBackend::refresh_all_visible_line_tokens(
  self : TokenizerSyntaxTokenBackend,
) -> Unit {
  let ranges : Array[@base_common.LineRange] = []
  for entry in self.attached_view_states {
    ranges.append(entry.handler.line_ranges())
  }
  self.refresh_ranges(join_line_ranges(ranges[:]))
}

///|
/// Refreshes normalized ranges in order, converting exclusive end to inclusive.
fn TokenizerSyntaxTokenBackend::refresh_ranges(
  self : TokenizerSyntaxTokenBackend,
  ranges : Array[@base_common.LineRange],
) -> Unit {
  for range in ranges {
    self.refresh_range(
      range.start_line_number,
      range.end_line_number_exclusive - 1,
    )
  }
}

///|
/// Clamps source-asymmetrically, stores heuristic tokens, and requests accuracy.
fn TokenizerSyntaxTokenBackend::refresh_range(
  self : TokenizerSyntaxTokenBackend,
  start_line_number : Int,
  end_line_number : Int,
) -> Unit {
  guard self.tokenizer is Some(tokenizer) else { return }
  let line_count = self.model_state.snapshot.val.line_count()
  let clamped_start = start_line_number.max(1).min(line_count)
  let clamped_end = end_line_number.min(line_count)
  let builder = @common_tokens.ContiguousMultilineTokensBuilder()
  let result = tokenizer.tokenize_heuristically(
    builder, clamped_start, clamped_end,
  )
  let changed = self.set_tokens(builder.finalize())
  if result.heuristic_tokens {
    match self.default_background_tokenizer {
      Some(worker) =>
        for change in changed.changes {
          worker.request_tokens(
            change.from_line_number,
            change.to_line_number + 1,
          )
        }
      None => ()
    }
  }
}

///|
/// Passive stored/default token read; never invokes the lexer.
fn TokenizerSyntaxTokenBackend::get_line_tokens(
  self : TokenizerSyntaxTokenBackend,
  line_number : Int,
) -> @common_tokens.LineTokens {
  self.tokens.get_tokens(
    self.model_state.language_id,
    line_number - 1,
    self.model_state.snapshot.val.line_text(line_number - 1),
  )
}

///|
/// Event subscriptions forwarded by the model part.
fn TokenizerSyntaxTokenBackend::on_did_change_tokens(
  self : TokenizerSyntaxTokenBackend,
  listener : (ModelTokensChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.shared.on_did_change_tokens(listener)
}

///|
/// Releases registry/view subscriptions, handlers, worker, and shared emitters.
fn TokenizerSyntaxTokenBackend::dispose(
  self : TokenizerSyntaxTokenBackend,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.registry_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  match self.attached_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  self.registry_subscription = None
  self.attached_subscription = None
  for entry in self.attached_view_states {
    entry.handler.dispose()
  }
  self.attached_view_states.clear()
  match self.default_background_tokenizer {
    Some(worker) => worker.dispose()
    None => ()
  }
  self.default_background_tokenizer = None
  self.tokenizer = None
  self.shared.dispose()
}
