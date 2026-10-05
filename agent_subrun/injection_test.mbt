///|
/// A session over a ledger in a fresh directory, closed when `body` returns.
async fn with_session(
  parent : String,
  body : async (@agent_subrun.ChildSession, String) -> Unit,
  first_free? : Int = 1,
) -> Unit {
  let dir = @fs.tmpdir(prefix="openseek-subrun-")
  defer @fs.rmdir(dir, recursive=true)
  let session = @agent_subrun.ChildSession(
    root="/store",
    parent~,
    ledger="\{dir}/subagents.jsonl",
    first_free=() => first_free,
  )
  defer session.close()
  body(session, dir)
}

///|
async test "a session's injection draws blocks from the session's ledger" {
  with_session("run7", first_free=5, (session, dir) => {
    let injection = session.injection(exe="/opt/openseek", workspace_root="/ws")
    let first = injection.reserve(result_root="/run/tmp")
    let second = injection.reserve(result_root="/run/tmp")
    // Consecutive, disjoint, and never below the session's floor.
    assert_eq(first.base(), 5)
    assert_eq(second.base(), 5 + @host.block_size)
    assert_eq(first.dir(), "/store/run7-wf-5")
    // Both blocks are on record before either was handed out, so they stay
    // taken for whoever opens this ledger next.
    let recorded = @fs.read_file("\{dir}/subagents.jsonl").text()
    assert_eq(recorded.split("\n").filter(line => !line.is_empty()).count(), 2)
    assert_true(recorded.contains("\"owner\":\"workflow\""))
  })
}

///|
/// The session forwards the host's launch prefix unchanged into the handoff.
async test "a wasm engine's handoff names its runtime, module and fence" {
  with_session("run7", (session, _) => {
    let injection = session.injection(
      exe="moonrun",
      launch_prefix=["/build/wasm/openseek.wasm", "--"],
      workspace_root="/ws",
    )
    assert_eq(injection.exe(), "moonrun")
    assert_eq(injection.launch_prefix(), ["/build/wasm/openseek.wasm", "--"])
    guard injection.reserve(result_root="/run/tmp").env().get("WORKFLOW_HOST")
      is Some(raw) else {
      fail("the handoff variable must be set")
    }
    let document = @json.parse(raw)
    guard document is { "exe": String(exe), "child_args": Array(args), .. } else {
      fail("handoff shape drifted: \{document.stringify()}")
    }
    assert_eq(exe, "moonrun")
    let args = args.map(item => {
      match item {
        String(value) => value
        _ => "?"
      }
    })
    assert_eq(args, [
      "/build/wasm/openseek.wasm", "--", "run", "--input-format", "json", "--cancel-on-stdin-eof",
      "--dir", "/ws", "--session-root", "/store", "--result-root", "/run/tmp", "--api-url",
      "", "--kind", "{kind}", "--result-file", "{result_file}", "--session", "{child}",
    ])
  })
}

///|
/// One engine process runs a session's subagents at a time. It becomes the
/// owner at its first allocation; a second is then refused with the reason,
/// instead of handing out ordinals the first may also hand out.
async test "a session whose subagents another owner holds reserves nothing" {
  with_session("run7", (session, dir) => {
    let second = @agent_subrun.ChildSession(
      root="/store",
      parent="run7",
      ledger="\{dir}/subagents.jsonl",
    )
    defer second.close()
    // Building the value takes nothing: no ledger, no lock, no directory.
    assert_true(@fs.readdir(dir).is_empty())
    let ours = session.injection(exe="/opt/openseek", workspace_root="/ws")
    let theirs = second.injection(exe="/opt/openseek", workspace_root="/ws")
    assert_eq(ours.reserve(result_root="/run/tmp").base(), 1)
    try theirs.reserve(result_root="/run/tmp") catch {
      error => assert_true("\{error}".contains("another openseek process"))
    } noraise {
      _ => fail("a reservation must fail when the session's ledger is not ours")
    }
    // The owner is unaffected, and once it lets go the other may take over
    // from where the record stands.
    assert_eq(ours.reserve(result_root="/run/tmp").base(), 1 + @host.block_size)
    session.close()
    assert_eq(
      theirs.reserve(result_root="/run/tmp").base(),
      1 + 2 * @host.block_size,
    )
  })
}

///|
/// Opening is lazy, so the first allocations can race each other to it. One
/// opens; the rest wait for it and allocate after — no two get one ordinal,
/// and none is refused as if another owner held the ledger.
async test "simultaneous first allocations open the ledger once" {
  with_session("run7", (session, _) => {
    let injection = session.injection(exe="/opt/openseek", workspace_root="/ws")
    let bases : Array[Int] = []
    @async.with_task_group(group => {
      for _ in 0..<6 {
        group.spawn_bg(() => {
          bases.push(injection.reserve(result_root="/run/tmp").base())
        })
      }
    })
    bases.sort()
    assert_eq(bases, [
      1,
      1 + @host.block_size,
      1 + 2 * @host.block_size,
      1 + 3 * @host.block_size,
      1 + 4 * @host.block_size,
      1 + 5 * @host.block_size,
    ])
  })
}

///|
/// Closing waits for an allocation in flight — it must not release the
/// ledger under an ordinal that is chosen and not yet written — and ends
/// admission: a later allocation is refused, not served by quietly taking
/// the ledger back.
async test "close drains allocations and refuses the ones that come after" {
  with_session("run7", (session, dir) => {
    let injection = session.injection(exe="/opt/openseek", workspace_root="/ws")
    let bases : Array[Int] = []
    @async.with_task_group(group => {
      // Started together, before the ledger is even open: the reservation
      // goes first and the close queues behind it.
      group.spawn_bg(() => {
        bases.push(injection.reserve(result_root="/run/tmp").base())
      })
      group.spawn_bg(() => session.close())
    })
    assert_eq(bases, [1])
    try injection.reserve(result_root="/run/tmp") catch {
      error => assert_true("\{error}".contains("subagents are closed"))
    } noraise {
      _ => fail("a closed session must not allocate")
    }
    // The ledger really was given back: another owner continues from the
    // one block that was handed out.
    let next = @agent_subrun.ChildSession(
      root="/store",
      parent="run7",
      ledger="\{dir}/subagents.jsonl",
    )
    defer next.close()
    assert_eq(
      next
      .injection(exe="/opt/openseek", workspace_root="/ws")
      .reserve(result_root="/run/tmp")
      .base(),
      1 + @host.block_size,
    )
  })
}

///|
/// An opening that fails leaves nothing behind — no lock, no half-open
/// ledger — and the next allocation opens afresh.
async test "an opening that fails is retried by the next allocation" {
  with_session("run7", (session, dir) => {
    let injection = session.injection(exe="/opt/openseek", workspace_root="/ws")
    // The ledger's path is a directory: reading it fails.
    @fs.mkdir("\{dir}/subagents.jsonl", recursive=true)
    try injection.reserve(result_root="/run/tmp") catch {
      _ => ()
    } noraise {
      _ => fail("a ledger that cannot be read must not allocate")
    }
    // The failed opening released its lock: another opener is not refused.
    let other = @agent_subrun.ChildSession(
      root="/store",
      parent="run7",
      ledger="\{dir}/other.jsonl",
    )
    defer other.close()
    @fs.rmdir("\{dir}/subagents.jsonl", recursive=true)
    assert_eq(injection.reserve(result_root="/run/tmp").base(), 1)
    try
      other
      .injection(exe="/opt/openseek", workspace_root="/ws")
      .reserve(result_root="/run/tmp")
    catch {
      error => assert_true("\{error}".contains("another openseek process"))
    } noraise {
      _ => fail("the lock belongs to the session that opened the ledger")
    }
  })
}

///|
/// The lowest unused ordinal is asked for when the ledger is opened, not
/// when the session value is built: a child that is not in the ledger — one
/// from before there was a ledger — can appear in between.
async test "a child that appears before the first allocation is not reused" {
  let dir = @fs.tmpdir(prefix="openseek-subrun-")
  defer @fs.rmdir(dir, recursive=true)
  let highest_child = Ref(7)
  let session = @agent_subrun.ChildSession(
    root="/store",
    parent="run7",
    ledger="\{dir}/subagents.jsonl",
    first_free=() => highest_child.val + 1,
  )
  defer session.close()
  // The engine sits idle; a surviving pre-ledger workflow creates sr-8.
  highest_child.val = 8
  assert_eq(
    session
    .injection(exe="/opt/openseek", workspace_root="/ws")
    .reserve(result_root="/run/tmp")
    .base(),
    9,
  )
}
