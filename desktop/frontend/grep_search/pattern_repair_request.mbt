///|
priv suberror PatternRepairRequestSub {
  PatternRepairRequest(
    @interop.ConversationKey,
    @protocol.PatternRepairPayload,
    Int,
    @cmd.Emit[Msg]
  )
}

///|
fn pattern_repair_request_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload
    is PatternRepairRequestSub::PatternRepairRequest(
      owner,
      request,
      delay_ms,
      emit
    ) else {
    return None
  }
  let mut emit = emit
  let mut active = true
  let mut settled = false
  let timer = @dom.window().set_timeout(
    () => {
      guard active else { return }
      @js.async_run(() => {
        let reply = @interop.bridge_request(
          owner.channel,
          @commands.pattern_repair,
          request,
        ) catch {
          error => {
            settled = true
            guard active else { return }
            scheduler.add(
              emit(
                PatternRepairFailed(
                  root=request.root,
                  generation=request.generation,
                  message=@interop.bridge_error_text(error),
                ),
              ),
            )
            return
          }
        }
        settled = true
        guard active else { return }
        match reply {
          reply if reply.valid =>
            scheduler.add(
              emit(
                PatternRepairPreview(
                  root=request.root,
                  generation=request.generation,
                  candidate_pattern=reply.candidate_pattern,
                  message=reply.message,
                ),
              ),
            )
          reply =>
            scheduler.add(
              emit(
                PatternRepairFailed(
                  root=request.root,
                  generation=request.generation,
                  message=reply.message,
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
        // The bridge request has no server-side cancellation yet. Unloading
        // still fences its eventual reply through `active`.
      }
    },
    update_tagger: payload => {
      guard payload
        is PatternRepairRequestSub::PatternRepairRequest(_, _, _, next_emit) else {
        return
      }
      emit = next_emit
    },
  })
}

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
    instruction: self.pattern_repair_instruction,
    generation: self.generation,
  })
}

///|
pub fn State::subscription(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  @sub.batch([
    self.search_subscription(input, emit),
    self.pattern_repair_subscription(input, emit),
  ])
}

///|
fn State::pattern_repair_subscription(
  self : State,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @sub.Sub {
  let page = self.page
  guard page.pattern_repair_phase is PatternRepairRequested &&
    input.root is Some(root) &&
    @resource.belongs_to(root, input.owner.channel) else {
    return @sub.none
  }
  guard page.pattern_repair_request_payload(input) is Some(request) else {
    return @sub.none
  }
  @sub.custom_sub(
    "grep-pattern-repair:\{input.owner.channel.uri_authority()}:\{input.owner.session}:\{request.root}:\{request.generation}",
    Local,
    PatternRepairRequestSub::PatternRepairRequest(input.owner, request, 0, emit),
    @sub.SubLoader(pattern_repair_request_loader),
  )
}
