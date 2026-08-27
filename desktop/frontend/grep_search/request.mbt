///|
priv suberror SearchRequestSub {
  SearchRequest(@interop.ConversationKey, SearchRequest, Int, @cmd.Emit[Msg])
}

///|
/// One armed search request, routed by mode. Text carries the ripgrep payload;
/// Semantic carries the moongrep payload. Both share one request UUID so the
/// panel cannot replay a stale reply from the other mode.
priv enum SearchRequest {
  Text(@protocol.SearchTextPayload)
  Semantic(@protocol.SearchSemanticPayload)
}

///|
fn SearchRequest::request_id(self : SearchRequest) -> String {
  match self {
    Text(payload) => payload.request_id
    Semantic(payload) => payload.request_id
  }
}

///|
priv enum LoadedReply {
  TextLoaded(@protocol.SearchTextReply)
  SemanticLoaded(@protocol.SearchSemanticReply)
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
            { request_id: payload.request_id },
          ),
        ) catch {
          _ => ()
        }
      Semantic(payload) =>
        ignore(
          @interop.bridge_request(
            owner.channel,
            @commands.fs_cancel_search_semantic,
            { request_id: payload.request_id },
          ),
        ) catch {
          _ => ()
        }
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
  let request_id = request.request_id()
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      scheduler.add(emit(RequestStarted(request_id~)))
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
        }
        settled = true
        if active {
          match loaded {
            RequestFailed(message) =>
              scheduler.add(
                emit(
                  RequestFailed(request_id~, code="request_failed", message~),
                ),
              )
            LoadedReply::TextLoaded(reply) =>
              scheduler.add(emit(Loaded(request_id~, reply~)))
            LoadedReply::SemanticLoaded(reply) =>
              scheduler.add(emit(SemanticLoaded(request_id~, reply~)))
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
/// mode, and checkout request UUIDs still replace the subscription and cancel
/// its child.
pub fn State::subscription(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  let page = self.page
  guard (page.phase is Debouncing || page.phase is Loading) &&
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
      page.semantic_request_payload(input).map(payload => Semantic(payload))
  }
  guard request is Some(request) else { return @sub.none }
  @sub.custom_sub(
    "grep-search:\{request.request_id()}",
    Local,
    SearchRequestSub::SearchRequest(input.owner, request, page.delay_ms, emit),
    @sub.SubLoader(search_request_loader),
  )
}
