///|
test "decode reads source with the default wasm target" {
  let input = @decode.decode({ "source": "fn main { println(1) }" })
  assert_true(input.program is Source("fn main { println(1) }"))
  assert_eq(input.target, "wasm")
}

///|
test "decode rejects the removed background flag with migration guidance" {
  let message = try {
    @decode.decode({ "source": "x", "run_in_background": true }) |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_true(message.contains("was removed"))
  assert_true(message.contains("automatic"))
}

///|
/// `native` is the one backend a snippet may not ask for: moonrun's policy —
/// the confinement that holds on every platform — applies to wasm alone, and
/// `--wasm-policy` is silently ignored elsewhere, so naming `native` would be
/// a one-argument way out of the sandbox.
test "decode refuses the unsandboxed native target" {
  let refused = try {
    @decode.decode({ "source": "fn main {  }", "target": "native" }) |> ignore
    "accepted"
  } catch {
    error => "\{error}"
  }
  assert_false(refused == "accepted")
  assert_true(refused.contains("wasm"))
}

///|
test "decode accepts an explicit target" {
  let input = @decode.decode({ "source": "fn main {  }", "target": "wasm-gc" })
  assert_eq(input.target, "wasm-gc")
}

///|
test "decode defaults cwd to None and reads an explicit cwd" {
  assert_true(@decode.decode({ "source": "x" }).cwd is None)
  assert_eq(
    @decode.decode({ "source": "x", "cwd": "sub/dir" }).cwd,
    Some("sub/dir"),
  )
}

///|
test "decode defaults warning to off and reads on/off" {
  assert_false(@decode.decode({ "source": "x" }).warning)
  assert_false(@decode.decode({ "source": "x", "warning": "off" }).warning)
  assert_true(@decode.decode({ "source": "x", "warning": "on" }).warning)
}

///|
/// Argument shapes `decode` must refuse. Only the refusal itself is pinned
/// here; the two tests above stay separate because they also pin the wording
/// the model is supposed to read.
test "decode rejects malformed arguments" {
  let malformed : Array[Json] = [
    {},
    { "filename": "" },
    { "filename": "  " },
    { "filename": 3 },
    { "filename": null },
    { "source": null },
    { "source": "x", "filename": "@builtin/check.mbtx" },
    { "source": "x", "filename": null },
    { "source": null, "filename": "run.mbtx" },
    // An unknown warning value, a non-string cwd, an unknown target, a
    // missing source, and arguments that are not an object at all.
    { "source": "x", "warning": "loud" },
    { "source": "x", "cwd": 3 },
    { "source": "x", "description": 3 },
    { "source": "x", "target": "banana" },
    { "code": "x" },
    Json("x"),
  ]
  for arguments in malformed {
    let failed = try {
      @decode.decode(arguments) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg="accepted \{arguments.stringify()}")
  }
}

///|
test "decode rejects both program fields with retry guidance" {
  for filename in ["check.mbtx", "@builtin/check.mbtx"] {
    try @decode.decode({ "source": "fn main {}", "filename": filename }) catch {
      error => {
        assert_true(error.to_string().contains("mutually exclusive"))
        assert_true(error.to_string().contains("write or edit"))
      }
    } noraise {
      _ => fail("both program fields must be rejected")
    }
  }
}

///|
test "decode accepts filename with unchanged execution options" {
  let input = @decode.decode({
    "filename": "scripts/check.mbtx",
    "cwd": "sub",
    "warning": "on",
  })
  assert_true(input.program is File("scripts/check.mbtx"))
  assert_eq(input.cwd, Some("sub"))
  assert_eq(input.target, "wasm")
  assert_true(input.warning)
}

///|
test "missing or invalid program fields give an actionable retry" {
  for
    arguments in [
      ({} : Json),
      Json({ "source": null }),
      Json({ "source": 42 }),
      Json({ "filename": null }),
      Json({ "filename": 42 }),
      Json({ "filename": " " }),
    ] {
    try @decode.decode(arguments) catch {
      error => {
        let message = error.to_string()
        assert_true(message.contains("{\"filename\":\"./check.mbtx\"}"))
        assert_true(message.contains("omit") || message.contains("Omit"))
      }
    } noraise {
      _ => fail("malformed input must fail before execution")
    }
  }
}

///|
test "description is optional presentation metadata" {
  assert_eq(@decode.decode({ "source": "x" }).description, None)
  assert_eq(
    @decode.decode({ "source": "x", "description": null }).description,
    None,
  )
  assert_eq(
    @decode.decode({ "source": "x", "description": "Run tests" }).description,
    Some("Run tests"),
  )
  assert_eq(
    @decode.decode({ "source": "x", "description": "" }).description,
    Some(""),
  )
}
