///|
fn inventory(count : Int32) -> @protocol.SessionsReply {
  {
    groups: [
      {
        workspace: "/workspace",
        name: "Example",
        session_root: "/workspace/.openseek",
        error: "",
        sessions: [
          for i in 0..<count => {
            {
              id: "session-\{i}",
              title: Some(
                if i == count - 1 {
                  "测试 B"
                } else {
                  "Conversation \{i}"
                },
              ),
              updated_at_ms: None,
            }
          }
        ],
      },
    ],
  }
}

///|
test "large inventories remain valid bounded pages with every chat reachable" {
  let source = inventory(2000)
  assert_true(source.to_json().stringify().length() > 50000)
  let mut offset = 0
  let seen : Array[String] = []
  while true {
    let page : @session_catalog.ListPage = @json.from_json({ "offset": offset })
    let result = page.page(source)
    assert_true(result.stringify().length() < 40000)
    guard result is { "sessions": Array(items), "next_offset": next, .. } else {
      fail("missing pagination contract")
    }
    assert_true(items.length() <= 20)
    for item in items {
      guard item is { "id": String(id), .. } else {
        fail("missing session identity")
      }
      seen.push(id)
    }
    match next {
      Null => break
      _ => offset = @json.from_json(next)
    }
  }
  assert_eq(seen, [ for i in 0..<2000 => "session-\{i}" ])
}

///|
test "empty inventories and offsets past the end are complete empty pages" {
  let first : @session_catalog.ListPage = @json.from_json({})
  assert_true(
    first.page(inventory(0)) is { "sessions": [], "next_offset": Null, .. },
  )
  let beyond : @session_catalog.ListPage = @json.from_json({ "offset": 5 })
  assert_true(
    beyond.page(inventory(1)) is { "sessions": [], "next_offset": Null, .. },
  )
}

///|
test "store failures use the error channel rather than claim an empty list" {
  let source : @protocol.SessionsReply = {
    groups: [
      {
        workspace: "/offline",
        name: "Offline",
        session_root: "/offline/.openseek",
        sessions: [],
        error: "store unavailable",
      },
    ],
  }
  let page : @session_catalog.ListPage = @json.from_json({})
  try page.page(source) catch {
    _ => ()
  } noraise {
    _ => fail("store failure hidden")
  }
}

///|
test "invalid pagination is rejected instead of silently ignoring it" {
  let invalid : Array[Json] = [
    { "offset": -1 },
    { "limit": 0 },
    { "limit": 51 },
    { "offset": 0.5 },
  ]
  for args in invalid {
    try {
      let _ : @session_catalog.ListPage = @json.from_json(args)
    } catch {
      _ => ()
    } noraise {
      _ => fail("invalid pagination accepted")
    }
  }
}

///|
test "escaped long titles stop a page before the bridge truncation limit" {
  let builder = StringBuilder()
  for _ in 0..<8000 {
    builder.write_string("\"")
  }
  let title = builder.to_string()
  let source : @protocol.SessionsReply = {
    groups: [
      {
        workspace: "/workspace",
        name: "Example",
        session_root: "/workspace/.openseek",
        error: "",
        sessions: [
          for i in 0..<3 => {
            { id: "s-\{i}", title: Some(title), updated_at_ms: None, }
          }
        ],
      },
    ],
  }
  let page : @session_catalog.ListPage = @json.from_json({})
  let first = page.page(source)
  assert_true(first.stringify().length() < 32000)
  assert_true(
    first
    is {
      "sessions": [{ "id": "s-0", "title": String(actual), .. }],
      "next_offset": 1,
      ..
    } &&
    actual == title,
  )
}
