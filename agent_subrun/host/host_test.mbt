///|
/// An injection over a local counter, so ordinals are deterministic whatever
/// earlier tests in this process reserved. `issued` stands in for the
/// engine's counter; starting it above zero stands in for a resumed session
/// whose floor an earlier process already pushed up.
fn injection(issued : Ref[Int], model? : String) -> @host.SubrunInjection {
  @host.SubrunInjection(
    exe="/opt/openseek",
    session_root="/store",
    parent="run7",
    workspace_root="/ws",
    model?,
    reserve_ordinals=count => {
      let base = issued.val + 1
      issued.val += count
      base
    },
  )
}

///|
test "blocks are disjoint and come from the allocator" {
  let injection = injection(Ref(8))
  let first = injection.reserve()
  let second = injection.reserve()
  // The floor is honoured: a resumed session never reissues an ordinal an
  // earlier process already persisted.
  assert_eq(first.base(), 9)
  // And the next snippet starts past the whole of the first block, not past
  // the ordinals it happened to use — a snippet that launched two children
  // still holds its block, because the parent cannot see inside it.
  assert_eq(second.base(), 9 + @host.block_size)
  assert_eq(first.limit(), @host.block_size)
  // Every run gets a directory of its own, named by its base, and its files
  // live inside it — the directory is the unit of both write permission and
  // discovery.
  assert_eq(first.dir(), "/store/run7-wf-9")
  assert_eq(first.journal_path(), "/store/run7-wf-9/journal.jsonl")
  assert_eq(first.events_path(), "/store/run7-wf-9/events.jsonl")
}

///|
test "what this host writes is what the library reads" {
  // The round trip that matters: the document put in the guest environment
  // must be one `moonbitlang/workflow/hosted` accepts, with the engine's own
  // argv shape intact. A drift here would be silent — the snippet would see
  // no handoff and quietly delegate to nothing.
  let reservation = injection(Ref(0), model="deepseek-chat").reserve()
  guard reservation.env().get("WORKFLOW_HOST") is Some(raw) else {
    fail("the handoff variable must be set")
  }
  assert_eq(reservation.env().length(), 1)
  let document = @json.parse(raw)
  guard @hosted.parse(document) is Some(ctx) else {
    fail("the library must accept what this host wrote")
  }
  assert_eq(ctx.child_capacity(), @host.block_size)
  assert_eq(ctx.journal_path(), Some("/store/run7-wf-1/journal.jsonl"))
  assert_eq(ctx.events_path(), Some("/store/run7-wf-1/events.jsonl"))
  // The engine's own CLI shape, as data the library substitutes per call: the
  // session flags are what make a child durable, and they name the library's
  // placeholder rather than an ordinal this host would have had to guess. A
  // child RUNS in the workspace, not the session store.
  guard document
    is {
      "child_args": Array(args),
      "child_id": String("run7-sr-{n}"),
      "ids": [Number(1, ..), Number(32, ..)],
      "cwd": String("/ws"),
      ..
    } else {
    fail("handoff shape drifted: \{document.stringify()}")
  }
  let args = args.map(a => {
    match a {
      String(s) => s
      _ => "?"
    }
  })
  assert_eq(args, [
    "subrun", "{kind}", "--model", "deepseek-chat", "--session", "{child}", "--session-root",
    "/store",
  ])
  // No `--max-steps`: per-call ceilings ride the request envelope.
  assert_false(args.contains("--max-steps"))
}
