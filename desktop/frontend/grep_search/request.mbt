///|
priv suberror SearchRequestSub {
  SearchRequest(@interop.ConversationKey, SearchRequest, Int, @cmd.Emit[Msg])
}

///|
/// One armed search request, routed by mode. Text carries the ripgrep payload;
/// Semantic carries the moongrep payload. Both share the session/generation
/// fence so one panel owns both engines without replaying a stale reply of the
/// other mode.
priv enum SearchRequest {
  Text(@protocol.SearchTextPayload)
  Semantic(@protocol.SearchSemanticPayload)
  PatternRepair(@protocol.PatternRepairPayload)
}

///|
struct SearchRequestIdentity {
  root : String
  generation : Int
  kind : String
} derive(Eq)

///|
fn SearchRequest::identity(self : SearchRequest) -> SearchRequestIdentity {
  match self {
    Text(payload) =>
      { root: payload.root, generation: payload.generation, kind: "text", }
    Semantic(payload) =>
      { root: payload.root, generation: payload.generation, kind: "semantic", }
    PatternRepair(payload) =>
      {
        root: payload.root,
        generation: payload.generation,
        kind: "pattern-repair",
      }
  }
}

///|
fn SearchRequest::generation(self : SearchRequest) -> Int {
  self.identity().generation
}

///|
priv enum LoadedReply {
  TextLoaded(@protocol.SearchTextReply)
  SemanticLoaded(@protocol.SearchSemanticReply)
  PatternRepairLoaded(@protocol.PatternRepairReply)
  RequestFailed(String)
}

///|
fn SearchRequest::cancel(
  self : SearchRequest,
  owner : @interop.ConversationKey,
) -> Unit {
  @js.async_run(() => {
    match self {
      Text(payload) =>
        ignore(
          @interop.bridge_request(
            owner.channel,
            @commands.fs_cancel_search_text,
            {
              session_key: payload.session_key,
              generation: payload.generation,
            },
          ),
        ) catch {
          _ => ()
        }
      Semantic(payload) =>
        ignore(
          @interop.bridge_request(
            owner.channel,
            @commands.fs_cancel_search_semantic,
            {
              session_key: payload.session_key,
              generation: payload.generation,
            },
          ),
        ) catch {
          _ => ()
        }
      PatternRepair(_) => ()
    }
  })
}

///|
fn search_request_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload
    is SearchRequestSub::SearchRequest(owner, request, delay_ms, emit) else {
    return None
  }
  let mut emit = emit
  let mut active = true
  let mut settled = false
  let identity = request.identity()
  let request_root = identity.root
  let request_generation = request.generation()
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      scheduler.add(
        emit(
          RequestStarted(
            owner~,
            root=request_root,
            generation=request_generation,
          ),
        ),
      )
      @js.async_run(() => {
        let loaded : LoadedReply = match request {
          Text(payload) =>
            TextLoaded(
              @interop.bridge_request(
                owner.channel,
                @commands.fs_search_text,
                payload,
              ),
            ) catch {
              error => RequestFailed(@interop.bridge_error_text(error))
            }
          Semantic(payload) =>
            SemanticLoaded(
              @interop.bridge_request(
                owner.channel,
                @commands.fs_search_semantic,
                payload,
              ),
            ) catch {
              error => RequestFailed(@interop.bridge_error_text(error))
            }
          PatternRepair(payload) =>
            LoadedReply::PatternRepairLoaded(
              @interop.bridge_request(
                owner.channel,
                @commands.pattern_repair,
                payload,
              ),
            ) catch {
              error =>
                LoadedReply::RequestFailed(@interop.bridge_error_text(error))
            }
        }
        settled = true
        if active {
          match loaded {
            RequestFailed(message) =>
              scheduler.add(
                emit(
                  RequestFailed(
                    owner~,
                    root=request_root,
                    generation=request_generation,
                    code="request_failed",
                    message~,
                  ),
                ),
              )
            TextLoaded(reply) =>
              scheduler.add(
                emit(
                  Loaded(
                    owner~,
                    root=request_root,
                    generation=request_generation,
                    reply~,
                  ),
                ),
              )
            SemanticLoaded(reply) =>
              scheduler.add(
                emit(
                  SemanticLoaded(
                    owner~,
                    root=request_root,
                    generation=request_generation,
                    reply~,
                  ),
                ),
              )
            LoadedReply::PatternRepairLoaded(reply) =>
              scheduler.add(
                emit(
                  if reply.success {
                    PatternRepairSucceeded(
                      root=request_root,
                      generation=request_generation,
                      pattern=reply.pattern,
                      message=reply.message,
                    )
                  } else {
                    PatternRepairFailed(
                      root=request_root,
                      generation=request_generation,
                      message=reply.message,
                    )
                  },
                ),
              )
          }
        }
      })
    },
    delay_ms,
  )
  Some({
    unload: _ => {
      active = false
      @dom.window().clear_timeout(timer)
      if !settled {
        request.cancel(owner)
      }
    },
    update_tagger: payload => {
      guard payload is SearchRequestSub::SearchRequest(_, _, _, next_emit) else {
        return
      }
      emit = next_emit
    },
  })
}

///|
/// Declare the request owned by the file editor's current Search inventory.
/// Presentation changes do not unload it: switching Explorer modes, hiding the
/// tree, or opening a Browser tab may leave an issued search running. Query,
/// mode, and checkout generations still replace the subscription and cancel
/// its child.
pub fn State::subscription(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  let page = self.page
  guard (
      page.phase is Debouncing ||
      page.phase is Loading ||
      page.pattern_repair_phase is PatternRepairRequested
    ) &&
    input.root is Some(root) &&
    @resource.belongs_to(root, input.owner.channel) else {
    return @sub.none
  }
  let request = match page.mode {
    Text =>
      page
      .text_request_payload(input)
      .map(payload => SearchRequest::Text(payload))
    Semantic =>
      if page.pattern_repair_phase is PatternRepairRequested {
        page
        .pattern_repair_request_payload(input)
        .map(payload => SearchRequest::PatternRepair(payload))
      } else {
        page
        .semantic_request_payload(input)
        .map(payload => SearchRequest::Semantic(payload))
      }
  }
  guard request is Some(request) else { return @sub.none }
  let identity = request.identity()
  let request_root = identity.root
  @sub.custom_sub(
    "grep-search:\{input.owner.channel.uri_authority()}:\{input.owner.session}:\{request_root}:\{identity.generation}:\{identity.kind}",
    Local,
    SearchRequestSub::SearchRequest(input.owner, request, page.delay_ms, emit),
    @sub.SubLoader(search_request_loader),
  )
}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend SearchRequestIdentity with Eq::{equal, not_equal}

///|
fn Page::pattern_repair_request_payload(
  self : Page,
  input : Input,
) -> @protocol.PatternRepairPayload? {
  guard self.mode is Semantic &&
    self.pattern_repair_phase is PatternRepairRequested &&
    input.root is Some(root) else {
    return None
  }
  guard self.semantic.patterns.length() > 0 else { return None }
  Some({
    root: root.path,
    pattern: self.semantic.patterns[0],
    generation: self.generation,
  })
}
