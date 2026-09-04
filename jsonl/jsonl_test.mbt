///|
test "parse decodes one value per line in order" {
  let values = @jsonl.parse(
    (
      #|{"event": "agent_step", "step": 1}
      #|{"event": "usage", "prompt_tokens": 4540}
      #|{"event": "agent_finished", "answer": "DONE"}
    ),
  )
  assert_eq(values.length(), 3)
  assert_true(values[0] == { "event": "agent_step", "step": 1 })
  assert_true(values[1] == { "event": "usage", "prompt_tokens": 4540 })
  assert_true(values[2] == { "event": "agent_finished", "answer": "DONE" })
}

///|
test "parse skips blank and whitespace-only lines" {
  let values = @jsonl.parse(
    (
      #|{"a": 1}
      #|
      #|
      #|{"b": 2}
      #|
    ),
  )
  assert_eq(values.length(), 2)
  assert_true(values[0] == { "a": 1 })
  assert_true(values[1] == { "b": 2 })
}

///|
test "parse tolerates a trailing line without a newline" {
  let values = @jsonl.parse("{\"only\": true}")
  assert_eq(values.length(), 1)
  assert_true(values[0] == { "only": true })
}

///|
test "parse decodes nested values and arrays" {
  let values = @jsonl.parse(
    (
      #|{"tool": {"name": "shell", "args": ["ls", "-l"]}}
      #|[1, 2, 3]
    ),
  )
  assert_eq(values.length(), 2)
  assert_true(
    values[0] == { "tool": { "name": "shell", "args": ["ls", "-l"] } },
  )
  assert_true(values[1] == ([1, 2, 3] : Json))
}

///|
test "parse raises on a malformed line" {
  let failed = try {
    let _ = @jsonl.parse(
      (
        #|{"ok": 1}
        #|{not json}
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "parse returns no values for empty input" {
  assert_eq(@jsonl.parse("").length(), 0)
  assert_eq(@jsonl.parse("\n\n").length(), 0)
}

///|
async test "read_all streams every value from a reader" {
  @async.with_task_group(group => {
    let (rd, wr) = @io.pipe()
    group.spawn_bg(() => {
      wr.write("{\"n\": 1}\n{\"n\": 2}\n{\"n\": 3}\n")
      wr.close()
    })
    let values = @jsonl.read_all(rd)
    assert_eq(values.length(), 3)
    assert_true(values[0] == { "n": 1 })
    assert_true(values[2] == { "n": 3 })
  })
}

///|
async test "each visits values in order and skips blank lines" {
  @async.with_task_group(group => {
    let (rd, wr) = @io.pipe()
    group.spawn_bg(() => {
      wr.write("{\"i\": 0}\n\n{\"i\": 1}\n")
      wr.close()
    })
    let seen = []
    @jsonl.each(rd, value => seen.push(value))
    assert_true(seen == [{ "i": 0 }, { "i": 1 }])
  })
}
