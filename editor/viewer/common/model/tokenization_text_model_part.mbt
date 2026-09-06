///| Readonly-applicable `TokenizationTextModelPart` over a live stateful backend.
///
/// Source: `vscode/src/vs/editor/common/model/tokens/tokenizationTextModelPart.ts`
/// and `vscode/src/vs/editor/common/tokenizationTextModelPart.ts` at
/// checked-in source. Semantic, dynamic-language,
/// embedded-language, bracket, and editable prediction arms remain the
/// explicitly deferred/N-A ledger rows; the syntactic lifecycle below keeps
/// source event order and per-line validation/demand.

///|
/// Exact syntactic/semantic token-change event payload.
pub(all) struct ModelTokensChangedEvent {
  semantic_tokens_applied : Bool
  ranges : Array[ModelTokensChangedRange]
}

///|
/// One inclusive changed line range.
pub(all) struct ModelTokensChangedRange {
  from_line_number : Int
  to_line_number : Int
}

///|
/// Public model tokenization part. Reads are passive; attached visible ranges
/// and the background worker drive lexing.
struct TokenizationTextModelPart {
  model_state : TokenizationModelState
  backend : TokenizerSyntaxTokenBackend
  did_change_tokens : @base_common.Emitter[ModelTokensChangedEvent]
  mut backend_token_subscription : @base_common.Disposable?
  mut disposed : Bool
}

///|
/// Constructs the registry-backed live backend and event forwarding in source order.
fn TokenizationTextModelPart::TokenizationTextModelPart(
  model_state : TokenizationModelState,
  attached_views : AttachedViews,
) -> TokenizationTextModelPart {
  TokenizationTextModelPart::new_with_support_resolver(
    model_state,
    attached_views,
    language_id => {
      @syntax.tokenization_registry
      .get(language_id)
      .map(tokenizer => {
        public_tokenizer_adapter(
          tokenizer, @services.language_id_codec, language_id,
        )
      })
    },
    subscribe_registry=true,
  )
}

///|
/// Internal-support test seam preserving failing and `has_eol`-aware adapters.
fn TokenizationTextModelPart::new_with_support_resolver(
  model_state : TokenizationModelState,
  attached_views : AttachedViews,
  resolve_support : (String) -> InternalTokenizationSupportAdapter?,
  subscribe_registry? : Bool = false,
) -> TokenizationTextModelPart {
  let backend = TokenizerSyntaxTokenBackend::new_with_support_resolver(
    model_state,
    attached_views,
    resolve_support,
    subscribe_registry~,
  )
  let part : TokenizationTextModelPart = {
    model_state,
    backend,
    did_change_tokens: Emitter(),
    backend_token_subscription: None,
    disposed: false,
  }
  part.backend_token_subscription = Some(
    backend.on_did_change_tokens(event => {
      if !part.model_state.disposing.val {
        part.did_change_tokens.fire(event)
      }
    }),
  )
  part
}

///|
/// Subscribes to exact changed token ranges.
fn TokenizationTextModelPart::on_did_change_tokens(
  self : TokenizationTextModelPart,
  listener : (ModelTokensChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_tokens.event(listener)
}

///|
/// Construction-fixed language id read from the shared model state.
fn TokenizationTextModelPart::get_language_id(
  self : TokenizationTextModelPart,
) -> String {
  self.model_state.language_id
}

///|
/// Inherited `TextModelPart` liveness guard. Guarded work continues while live
/// and enters the exact failure arm after terminal disposal.
fn TokenizationTextModelPart::assert_not_disposed(
  self : TokenizationTextModelPart,
) -> Unit {
  if self.disposed {
    abort("TextModelPart is disposed!")
  }
}

///|
/// Validates the inclusive one-based model-line domain.
fn TokenizationTextModelPart::validate_line_number(
  self : TokenizationTextModelPart,
  line_number : Int,
) -> Unit {
  if line_number < 1 || line_number > self.model_state.snapshot.val.line_count() {
    abort("Illegal value for lineNumber")
  }
}

///|
/// Passive stored/default syntactic tokens; never invokes the lexer.
pub fn TokenizationTextModelPart::get_line_tokens(
  self : TokenizationTextModelPart,
  line_number : Int,
) -> @common_tokens.LineTokens {
  self.validate_line_number(line_number)
  self.backend.get_line_tokens(line_number)
}

///|
/// Flush content handling; live lines were replaced before this call.
fn TokenizationTextModelPart::handle_did_change_content(
  self : TokenizationTextModelPart,
  is_flush~ : Bool,
) -> Unit {
  self.backend.handle_did_change_content(is_flush~)
}

///|
/// Re-evaluates scheduling after aggregate attach/scheduler transitions.
fn TokenizationTextModelPart::handle_did_change_attached(
  self : TokenizationTextModelPart,
) -> Unit {
  self.backend.handle_did_change_attached()
}

///|
/// Passive telemetry count. One stored/default read per model line and zero
/// lexer calls, including initial attach and token-change notification paths.
pub fn TokenizationTextModelPart::token_count(
  self : TokenizationTextModelPart,
) -> Int {
  self.assert_not_disposed()
  let mut count = 0
  for line_number in 1..<=self.model_state.snapshot.val.line_count() {
    count += self.backend.get_line_tokens(line_number).get_count()
  }
  count
}

///|
/// Retained token listeners participate in model listener ownership.
fn TokenizationTextModelPart::has_listeners(
  self : TokenizationTextModelPart,
) -> Bool {
  self.did_change_tokens.has_listeners()
}

///|
/// Releases every registered resource while the inherited disposed flag is
/// still false: forwarding subscription, registered emitter, then backend.
fn TokenizationTextModelPart::dispose_owned_resources(
  self : TokenizationTextModelPart,
) -> Unit {
  match self.backend_token_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  self.backend_token_subscription = None
  self.did_change_tokens.dispose()
  self.backend.dispose()
}

///|
/// Source-order teardown: registered resources first, terminal flag second.
fn TokenizationTextModelPart::dispose(self : TokenizationTextModelPart) -> Unit {
  if self.disposed {
    return
  }
  self.dispose_owned_resources()
  self.disposed = true
}
