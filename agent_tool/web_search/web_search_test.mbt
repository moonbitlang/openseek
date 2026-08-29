///|
/// A canned Anthropic-style Messages response body: two searched sources, one
/// carrying a citation excerpt in a separate text block.
fn sample_response_body() -> String {
  (
    {
      "content": [
        {
          "type": "server_tool_use",
          "id": "srvtoolu_1",
          "name": "web_search",
          "input": { "query": "moonbit language" },
        },
        {
          "type": "web_search_tool_result",
          "tool_use_id": "srvtoolu_1",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/a",
              "title": "Example A",
              "page_age": "January 5, 2026",
            },
            { "type": "web_search_result", "url": "https://example.org/b" },
          ],
        },
        {
          "type": "text",
          "text": "According to Example A, MoonBit is fast.",
          "citations": [
            {
              "type": "citations_web_search_result_location",
              "url": "https://example.com/a",
              "cited_text": "MoonBit is a fast language.",
            },
          ],
        },
      ],
    } : Json).stringify()
}

///|
/// Bind a localhost mock server for one test, or report the skip and return
/// `None` where the sandbox forbids TCP binds.
async fn bind_test_server(skip_message : String) -> @http.Server? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println(skip_message)
      return None
    }
    error => raise error
  }
  Some(server)
}

///|
async test "web_search executes end-to-end against a mock messages endpoint" {
  @async.with_task_group(group => {
    guard bind_test_server(
        "local TCP bind unavailable; skipping web_search test",
      )
      is Some(server) else {
      return
    }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, conn) => {
          let _ = body.read_all()
          assert_eq(request.path, "/anthropic/v1/messages")
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(sample_response_body())
        },
        max_connections=4,
      )
    }
    let tool = @web_search.definition(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/anthropic/v1",
    )
    assert_eq(tool.name, "web_search")
    guard tool.execute is Async(execute) else {
      fail("expected async executor")
    }
    let action = execute({ "query": "moonbit language" })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("[Example A](https://example.com/a)"))
    assert_true(
      output.content.contains("- [example.org](https://example.org/b)"),
    )
    assert_true(output.content.contains("Cite the relevant URLs"))
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_true(brief.contains("web_search"))
  })
}

///|
async test "web_search surfaces a provider error as a recoverable tool error" {
  @async.with_task_group(group => {
    guard bind_test_server(
        "local TCP bind unavailable; skipping web_search test",
      )
      is Some(server) else {
      return
    }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          conn.send_response(401, "Unauthorized", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            "{\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}",
          )
        },
        max_connections=4,
      )
    }
    let tool = @web_search.definition(
      api_key="bad-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/anthropic/v1",
    )
    guard tool.execute is Async(execute) else {
      fail("expected async executor")
    }
    let action = execute({ "query": "moonbit language" })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("401"))
    assert_true(output.content.contains("invalid x-api-key"))
  })
}

///|
async test "web_search rejects blank and oversized queries locally" {
  guard @web_search.definition(api_key="k").execute is Async(execute) else {
    fail("expected async executor")
  }
  guard execute({ "query": "   " }) is Respond(blank) else {
    fail("expected Respond")
  }
  assert_true(blank.is_error)
  assert_true(blank.content.contains("non-empty string `query`"))
  // One past the tool's documented 2000-char query cap.
  guard execute({ "query": "q".repeat(2001).to_json() }) is Respond(oversized) else {
    fail("expected Respond")
  }
  assert_true(oversized.is_error)
  assert_true(oversized.content.contains("exceeds"))
}

///|
/// Live check against the real DeepSeek Anthropic-compatible endpoint. Opt-in
/// like `deepseek/client/client_realworld_test.mbt`: runs only when the
/// `DEEPSEEK` key is exported, prints a skip notice otherwise. The real
/// endpoint is exercised end to end — the tool must come back with at least
/// one citeable source rendered as a markdown link, plus a success brief.
///
/// A typical live result looks like (this exact output came from a real run of
/// this very test):
///
///     Sources:
///     - [docs.moonbitlang.com](https://docs.moonbitlang.com/zh-cn/stable/_downloads/78d8998d78e60fd7b1b2f4c9bb2819fb/summary.md)
///     - [docs.moonbitlang.com](https://docs.moonbitlang.com/en/stable/_downloads/78d8998d78e60fd7b1b2f4c9bb2819fb/summary.md)
///     - [MoonBit - 计算机编程语言](https://baike.baidu.com/item/MoonBit/64190586?fr=ge_ala#1)
///     - [MoonBit Language](https://docs.moonbitlang.com/en/stable/language/index.html)
///     - [MoonBit: Explore the Design of an AI-Friendly Programming Language](https://llm4code.github.io/assets/pdf/papers/7.pdf#1#1)
///     - [About us | MoonBit](https://www.moonbitlang.com/about-us)
///     - [MoonBit](https://baike.baidu.com/item/MoonBit)
///     - [docs.moonbitlang.cn](https://docs.moonbitlang.cn/_sources/tutorial/for-go-programmers/index.md)
///
///     (Showing the first 8 sources. Refine the query for more.)
///
///     Cite the relevant URLs above as markdown links in your answer.
///
/// Only the SHAPE is stable, not the contents: which URLs surface, whether
/// titles are present (a title-less source falls back to its hostname label,
/// as the first two lines above show), whether citation snippets and dates
/// are joined in, and whether the result cap actually truncates — all drift
/// between runs.
async test "realworld web_search performs a native search against DeepSeek" {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK environment variable is not set or is empty; skipping realworld web_search test",
    )
    return
  }
  let tool = @web_search.definition(api_key~)
  guard tool.execute is Async(execute) else { fail("expected async executor") }
  let action = execute({ "query": "MoonBit programming language" })
  guard action is Respond(output) else { fail("expected Respond") }
  // debug_inspect(output.content, content="typical live web_search output")
  // Uncomment while iterating to see the exact current output; it stays
  // commented because real results drift between runs (see the doc comment
  // above) and must not become a stable fixture.
  assert_false(output.is_error)
  assert_true(output.content.contains("Sources:"))
  // A real search must return at least one citeable source with a markdown
  // link; the URL itself is provider-chosen, only the shape is stable.
  assert_true(output.content.contains("](https://"))
  guard output.brief is Some(brief) else { fail("expected a brief") }
  assert_true(brief.contains("web_search"))
  assert_true(brief.contains("source(s)"))
}

///|
/// Live auth-failure check: a bad key against the real endpoint must surface
/// as a recoverable tool error carrying the provider's message — never a
/// crash. Guarded on `DEEPSEEK` like the success test, so the offline suite
/// stays network-free.
async test "realworld web_search surfaces an auth failure from the live endpoint" {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK environment variable is not set or is empty; skipping realworld web_search auth test",
    )
    return
  }
  let tool = @web_search.definition(api_key="sk-invalid-key-for-realworld-test")
  guard tool.execute is Async(execute) else { fail("expected async executor") }
  let action = execute({ "query": "MoonBit" })
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("error: web_search failed"))
  guard output.brief is Some(brief) else { fail("expected a brief") }
  assert_true(brief.contains("(failed)"))
}
