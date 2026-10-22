///|
async test "compaction rejects empty sessions before summary generation" {
  try
    @compact.compact_session(
      Session(SessionId("empty"), system_prompt="system"),
      api_key="",
      model=Deepseek(V4Flash),
    )
  catch {
    error => assert_true("\{error}".contains("at least one event"))
  } noraise {
    _ => fail("accepted empty session")
  }
}

///|
async test "manual compaction persists usage before validating an empty summary" {
  for summary in ["summary", ""] {
    @async.with_task_group() <| group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.add_defer(() => server.close())
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever(
          (_request, body, conn) => {
            ignore(body.read_all())
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            conn.write(
              (
                {
                  "id": "summary-response",
                  "choices": [{ "message": { "content": summary } }],
                  "usage": {
                    "prompt_tokens": 10,
                    "completion_tokens": 0,
                    "total_tokens": 10,
                  },
                } : Json).stringify(),
            )
          },
          max_connections=1,
        )
      }
      let root = @fs.tmpdir(prefix="compaction-usage-")
      defer @fs.rmdir(root, recursive=true)
      let store = @store.SessionStore(root)
      let initial = store.append(
        Session(SessionId("manual"), system_prompt="s"),
        User(UserMessage(Content([Text("go")]))),
      )
      let failed = try {
        ignore(
          @compact.compact_session(
            store~,
            initial,
            api_key="test-key",
            model=Deepseek(V4Flash),
            api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
            retry_attempts=1,
          ),
        )
        false
      } catch {
        _ => true
      }
      assert_eq(failed, summary == "")
      let loaded = store.load(SessionId("manual"))
      assert_eq(loaded.usage_records().length(), 1)
      assert_eq(loaded.usage_records()[0].purpose, "manual_compaction")
      assert_eq(loaded.usage_records()[0].response_id, Some("summary-response"))
      assert_eq(loaded.usage_records()[0].report.total_tokens, Some(10))
      assert_eq(loaded.events().length(), if summary == "" { 1 } else { 2 })
    }
  }
}
