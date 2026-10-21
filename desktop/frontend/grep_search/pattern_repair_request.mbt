///|
/// The current subrun protocol still requires an instruction. Keep it an
/// implementation detail: Pattern Repair is a syntax-repair affordance, not a
/// second user prompt.
const DefaultPatternRepairInstruction : String = "Repair this MoonBit pattern with the smallest syntax-only change."

///|
priv suberror PatternRepairRequestSub {
  PatternRepairRequest(
    @interop.ConversationIdentity,
    @protocol.PatternRepairPayload,
    @cloud_client.Access?,
    Int32,
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
      access,
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
      @js.Promise::from_async(() => {
        let reply = Some(
          match owner {
            Host(owner) =>
              @interop.bridge_request(
                owner.channel,
                @commands.pattern_repair,
                request,
              )
            Cloud(..) => {
              guard access is Some(access) else {
                raise @cloud_client.RequestError(Unauthorized)
              }
              let json = @cloud_client.request(
                @cloud_client.CloudOrigin,
                "/v1/sessions/\{@uri.encode_component(owner.session())}/files/search/semantic/repair",
                Post,
                token=access.token,
                body={
                  "pattern": request.pattern,
                  "generation": request.generation,
                },
              )
              let fields : Map[String, Json] = @json.from_json(json)
              fields["root"] = Json(request.root)
              @json.from_json(Json(fields))
            }
          },
        ) catch {
          _ => None
        }
        settled = true
        guard active else { return }
        scheduler.add(
          emit(
            PatternRepairFinished(
              root=request.root,
              generation=request.generation,
              reply~,
            ),
          ),
        )
      })
      |> ignore
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
        is PatternRepairRequestSub::PatternRepairRequest(_, _, _, _, next_emit) else {
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
    model: input.model,
    thinking: input.thinking,
    root: root.path,
    pattern: self.semantic.patterns[0],
    instruction: DefaultPatternRepairInstruction,
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
    input.owns_root(root) &&
    (input.owner is Host(_) || input.cloud_access is Some(_)) else {
    return @sub.none
  }
  guard page.pattern_repair_request_payload(input) is Some(request) else {
    return @sub.none
  }
  @sub.custom_sub(
    "grep-pattern-repair:\{input.owner.key()}:\{input.cloud_access.map(access => access.epoch).unwrap_or(0)}:\{request.root}:\{request.generation}",
    Local,
    PatternRepairRequestSub::PatternRepairRequest(
      input.owner,
      request,
      input.cloud_access,
      0,
      emit,
    ),
    @sub.SubLoader(pattern_repair_request_loader),
  )
}
