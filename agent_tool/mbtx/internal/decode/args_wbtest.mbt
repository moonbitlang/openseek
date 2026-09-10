///|
test "script args default to empty and preserve string values" {
  assert_eq(decode({ "source": "fn main {}" }).args, [])
  assert_eq(decode({ "filename": "check.mbtx", "args": [] }).args, [])
  for
    program in [
      Json({ "source": "fn main {}" }),
      Json({ "filename": "check.mbtx" }),
      Json({ "source": "fn main {}", "filename": "check.mbtx" }),
    ] {
    guard program is Object(fields) else { fail("expected object") }
    fields["args"] = ["--flag", "two words", "", "你好", "$(echo nope)"]
    assert_eq(decode(program).args, [
      "--flag", "two words", "", "你好", "$(echo nope)",
    ])
  }
}

///|
test "script args reject null and non-string values" {
  let invalid : Array[Json] = [null, "x", 1, {}, ["ok", 3]]
  for value in invalid {
    try decode({ "source": "fn main {}", "args": value }) catch {
      error => assert_true(error.to_string().contains("arguments.args"))
    } noraise {
      _ => fail("expected invalid args to fail")
    }
  }
}
