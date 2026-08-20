///|
priv suberror SearchRequestSub {
  SearchRequest(
    @interop.ConversationKey,
    @protocol.SearchTextPayload,
    Int,
    @cmd.Emit[Msg]
  )
}

///|
fn cancel_text_search(
  owner : @interop.ConversationKey,
  payload : @protocol.SearchTextPayload,
) -> Unit {
  @js.async_run(() => {
    ignore(
      @interop.bridge_request(owner.channel, @commands.fs_cancel_search_text, {
        session_key: payload.session_key,
        generation: payload.generation,
      }),
    ) catch {
      _ => ()
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
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      scheduler.add(
        emit(
          RequestStarted(
            owner~,
            root=request.root,
            generation=request.generation,
          ),
        ),
      )
      @js.async_run(() => {
        let reply = @interop.bridge_request(
          owner.channel,
          @commands.fs_search_text,
          request,
        ) catch {
          error => {
            settled = true
            if active {
              let message = @interop.bridge_error_text(error)
              scheduler.add(
                emit(
                  RequestFailed(
                    owner~,
                    root=request.root,
                    generation=request.generation,
                    code="request_failed",
                    message~,
                  ),
                ),
              )
            }
            return
          }
        }
        settled = true
        if active {
          scheduler.add(
            emit(
              Loaded(
                owner~,
                root=request.root,
                generation=request.generation,
                reply~,
              ),
            ),
          )
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
        cancel_text_search(owner, request)
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
/// tree, or opening a Browser tab may leave an issued search running. Query and
/// checkout generations still replace the subscription and cancel its child.
pub fn State::subscription(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  let page = self.page
  guard (page.phase is Debouncing || page.phase is Loading) &&
    page.request_payload(input) is Some(payload) &&
    input.root is Some(root) &&
    @resource.belongs_to(root, input.owner.channel) else {
    return @sub.none
  }
  @sub.custom_sub(
    "grep-search:\{input.owner.channel.uri_authority()}:\{input.owner.session}:\{payload.root}:\{payload.generation}",
    Local,
    SearchRequestSub::SearchRequest(input.owner, payload, page.delay_ms, emit),
    @sub.SubLoader(search_request_loader),
  )
}
