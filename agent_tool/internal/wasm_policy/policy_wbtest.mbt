///|
test "the reservation reaches the guest, and only its own directory is writable" {
  fn test_injection(issued : Ref[Int]) -> @host.SubrunInjection {
    SubrunInjection(
      exe="/opt/openseek",
      session_root="/store",
      parent="run7",
      workspace_root="/ws",
      reserve_ordinals=count => {
        let base = issued.val + 1
        issued.val += count
        base
      },
    )
  }
  let injection = test_injection(Ref(0))
  let reservation = injection.reserve(result_root="/run/tmp")
  // A snippet that tried to redirect its own scratch space cannot: the policy
  // writes TMPDIR last, so the one name here whose value is a policy decision
  // rather than a message always wins.
  let inject = reservation.env()
  inject["TMPDIR"] = "/somewhere/else"
  let policy = wasm_policy_document(
    tmp_dir="/run/tmp",
    extra_roots=[reservation.dir()],
    inject~,
    spawnable=Some((injection.exe(), reservation.spawn_prefix())),
  )
  guard policy
    is {
      "env": { "set": Object(set), .. },
      "fs": { "write": Array(write), .. },
      "process": { "allow": Array(allow), .. },
      ..
    } else {
    fail("policy lost its env, fs or process section")
  }
  assert_eq(set.get("TMPDIR"), Some(Json::string("/run/tmp")))
  assert_true(set.get("WORKFLOW_HOST") is Some(String(_)))
  // The run's directory is writable; the session store as a whole is not. A
  // snippet can append its own ledger and nothing else's transcript.
  assert_true(write.contains("/store/run7-wf-1"))
  assert_false(write.contains("/store"))
  // The engine is admitted by ABSOLUTE path and in one form, with the host's
  // values pinned: moonrun matches the program exactly and the argv by
  // prefix, so a snippet may only append to this, and `run` refuses a second
  // copy of any option pinned here.
  assert_true(
    allow.contains({
      "program": "/opt/openseek",
      "args_prefix": json_strings([
        "run", "--input-format", "json", "--cancel-on-stdin-eof", "--dir", "/ws",
        "--session-root", "/store", "--result-root", "/run/tmp", "--api-url", "",
        "--kind",
      ]),
    }),
  )
}

///|
/// A wasm engine is admitted through its runtime, and the module this host
/// chose is what pins the entry: bare `moonrun` would be a general licence to
/// run modules, and the module alone names no program to run. The entry is
/// generated per reservation rather than living in `spawnable_commands` for
/// exactly that reason — the model's vocabulary does not grow.
test "a wasm engine is admitted as its runtime plus the chosen module" {
  let injection = @host.SubrunInjection(
    exe="moonrun",
    launch_prefix=["/engine/openseek.wasm", "--"],
    session_root="/store",
    parent="run7",
    workspace_root="/ws",
    reserve_ordinals=_ => 1,
  )
  let prefix = injection.reserve(result_root="/run/tmp").spawn_prefix()
  let policy = wasm_policy_document(
    tmp_dir="/run/tmp",
    extra_roots=[],
    inject=Map([]),
    spawnable=Some((injection.exe(), prefix)),
  )
  guard policy is { "process": { "allow": Array(allow), .. }, .. } else {
    fail("policy lost its process section")
  }
  assert_eq(prefix[:3], ["/engine/openseek.wasm", "--", "run"])
  assert_true(
    allow.contains({ "program": "moonrun", "args_prefix": json_strings(prefix) }),
  )
  // The module is part of the rule: a snippet cannot point the runtime at
  // another module, nor run one it wrote itself.
  assert_false(
    allow.contains({
      "program": "moonrun",
      "args_prefix": json_strings(prefix[2:].to_owned()),
    }),
  )
  assert_false(allow.contains({ "program": "moonrun" }))
}

///|
test "no injection clears any inherited handoff and admits no engine" {
  let policy = wasm_policy_document(
    tmp_dir="/run/tmp",
    extra_roots=[],
    inject=Map([]),
    spawnable=None,
  )
  guard policy
    is {
      "env": { "set": Object(set), .. },
      "process": { "allow": Array(allow), .. },
      ..
    } else {
    fail("policy lost its env or process section")
  }
  // A conversation with no durable session gets no coordinates and no engine
  // in its command vocabulary: there is nowhere to put a child transcript, so
  // admitting the spawn would only produce invisible children.
  //
  // `WORKFLOW_HOST` is still SET — to nothing. The guest copies the host's
  // environment, and this process may itself be a child of a hosted snippet,
  // whose handoff it inherited. Left alone, that handoff would reach this
  // snippet, which would mint child ids from a block that belongs to its
  // grandparent. An empty value fails the library's reader closed.
  assert_eq(set.length(), 3)
  assert_true(set.get("TMPDIR") is Some(_))
  assert_eq(set.get("WORKFLOW_HOST"), Some(Json::string("")))
  guard set.get("OPENSEEK_PTC") is Some(String(ptc)) else {
    fail("missing PTC capability override")
  }
  assert_eq(@json.parse(ptc), { "version": 1, "available": false })
  for rule in allow {
    guard rule is { "program": String(program), .. } else { continue }
    assert_false(program.contains("openseek"))
  }
}
