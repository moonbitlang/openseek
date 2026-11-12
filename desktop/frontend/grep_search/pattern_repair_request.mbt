///|
/// The current subrun protocol still requires an instruction. Keep it an
/// implementation detail: Pattern Repair is a syntax-repair affordance, not a
/// second user prompt.
const DefaultPatternRepairInstruction : String = "Repair this MoonBit pattern with the smallest syntax-only change."

///|
/// The pattern one repair is asked to fix, and the search it belongs to.
priv struct PatternRepairTarget {
  root : String
  pattern : String
  generation : Int32
}

///|
/// Where one repair runs. The host runs it on the conversation's model and
/// reasoning; Cloud runs it on the session's own settings, so its request
/// carries only the pattern.
priv enum PatternRepairRoute {
  HostRepair(
    @interop.ConversationKey,
    model~ : @wire.Model,
    thinking~ : @wire.ThinkingMode?
  )
  CloudRepair(@interop.ConversationIdentity, @cloud_client.Access)
}

///|
/// The host's request for `target`, run on `model` and `thinking`.
fn PatternRepairTarget::host_payload(
  self : PatternRepairTarget,
  model~ : @wire.Model,
  thinking~ : @wire.ThinkingMode?,
) -> @protocol.PatternRepairPayload {
  {
    model,
    thinking,
    root: self.root,
    pattern: self.pattern,
    instruction: DefaultPatternRepairInstruction,
    generation: self.generation,
  }
}

///|
priv suberror PatternRepairRequestSub {
  PatternRepairRequest(
    PatternRepairRoute,
    PatternRepairTarget,
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
      route,
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
      @js.Promise::from_async(() => {
        let reply = Some(
          match route {
            HostRepair(owner, model~, thinking~) =>
              @interop.bridge_request(
                owner.channel,
                @commands.pattern_repair,
                request.host_payload(model~, thinking~),
              )
            CloudRepair(owner, access) => {
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
        is PatternRepairRequestSub::PatternRepairRequest(_, _, _, next_emit) else {
        return
      }
      emit = next_emit
    },
  })
}

///|
fn Page::pattern_repair_target(
  self : Page,
  input : Input,
) -> PatternRepairTarget? {
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

///|
/// Where `input`'s repair runs: its host, on the conversation's model, or
/// Cloud with the session's access.
fn Input::pattern_repair_route(self : Input) -> PatternRepairRoute? {
  match (self.owner, self.model, self.cloud_access) {
    (Host(owner), Some(model), _) =>
      Some(HostRepair(owner, model~, thinking=self.thinking))
    (Cloud(..) as owner, _, Some(access)) => Some(CloudRepair(owner, access))
    _ => None
  }
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
    input.pattern_repair_route() is Some(route) else {
    return @sub.none
  }
  guard page.pattern_repair_target(input) is Some(request) else {
    return @sub.none
  }
  @sub.custom_sub(
    "grep-pattern-repair:\{input.owner.key()}:\{input.cloud_access.map(access => access.epoch).unwrap_or(0)}:\{request.root}:\{request.generation}",
    Local,
    PatternRepairRequestSub::PatternRepairRequest(route, request, 0, emit),
    @sub.SubLoader(pattern_repair_request_loader),
  )
}
