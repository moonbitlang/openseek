///|
async test "large request allowance is specific to base64 write and all published traces omit its payload" {
  @async.with_task_group(group => {
    let executed = Ref(0)
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="write",
        description="test write boundary",
        schema=JsonSchema({}),
        program_callable=true,
        execute=Sync(_ => {
          executed.val += 1
          @agent_tool.respond("ok")
        }),
      ),
    ])
    let service = @ptc.Service::start(group, tools)
    let publications : Array[Json] = []
    let program = service.register(on_trace=trace => publications.push(trace))
    guard @json.parse(program.env()["OPENSEEK_PTC"])
      is { "url": String(url), "token": String(token), .. } else {
      fail("missing capability")
    }
    for
      (name, encoding, accepted) in [
        ("write", "text", false),
        ("write", "hex", false),
        ("other", "base64", false),
        ("write", "base64", true),
      ] {
      let (_, body) = @http.post(
        url,
        (
          {
            "version": 1,
            "name": name,
            "arguments": {
              "path": "large.bin",
              "content": "AP+A".repeat(20000),
              "encoding": encoding,
            },
          } : Json),
        headers={ "Authorization": "Bearer \{token}" },
      )
      let result = body.json()
      if accepted {
        assert_true(result is { "is_error": false, .. })
      } else {
        assert_true(result is { "is_error": true, .. })
      }
    }
    assert_eq(executed.val, 1)
    program.close()
    assert_true(publications.length() >= 2)
    for trace in publications {
      assert_false(trace.stringify().contains("AP+A"))
      assert_true(trace.stringify().length() < 2000)
    }
    assert_true(
      program.trace()
      is {
        "ptc_calls": [
          {
            "arguments": {
              "content_omitted": true,
              "content_base64_chars": 80000,
              ..
            },
            "status": "done",
            ..
          },
        ],
        ..
      },
    )
  })
}
