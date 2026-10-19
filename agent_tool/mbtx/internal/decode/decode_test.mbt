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
/// moonrun's policy applies to wasm alone, so every other backend is refused.
test "decode refuses every non-wasm target" {
  for target in ["wasm-gc", "js", "llvm", "native", "banana"] {
    try @decode.decode({ "source": "fn main {  }", "target": target }) catch {
      error =>
        assert_true("\{error}".contains("mbtx only supports the wasm target"))
    } noraise {
      _ => fail("accepted target \{target}")
    }
  }
}

///|
test "decode accepts explicit wasm and defaults a null target to wasm" {
  let input = @decode.decode({ "source": "fn main {  }", "target": "wasm" })
  assert_eq(input.target, "wasm")
  assert_eq(@decode.decode({ "source": "x", "target": null }).target, "wasm")
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
    { "source": "x", "target": 3 },
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
test "decode rejects saving to a namespace with retry guidance" {
  try
    @decode.decode({ "source": "fn main {}", "filename": "@builtin/check.mbtx" })
  catch {
    error => {
      let message = error.to_string()
      assert_true(message.contains("Namespaced scripts are read-only"))
      assert_true(message.contains("without source"))
      assert_true(message.contains("@builtin/check.mbtx"))
    }
  } noraise {
    _ => fail("expected namespace write to be rejected")
  }
}

///|
test "decode accepts filename with unchanged execution options" {
  assert_true(
    @decode.decode({ "source": "fn main {}", "filename": "check.mbtx" }).program
    is Save("fn main {}", "check.mbtx"),
  )
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
