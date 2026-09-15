///|
async test "public calls discover the host and forward JSON arguments unchanged" {
  // This blackbox test exercises only the SDK's public API. Restore the
  // process environment on success, assertion failure, or cancellation.
  let previous = @env.get_env_var("OPENSEEK_PTC")
  defer (match previous {
    Some(value) => @env.set_env_var("OPENSEEK_PTC", value)
    None => @env.unset_env_var("OPENSEEK_PTC")
  })
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let received : Array[Json] = []
      let worker = group.spawn(no_wait=true, () => {
        server.run_forever((req, body, conn) => {
          defer conn.close()
          assert_true(req.meth is Post)
          assert_eq(req.path, "/call")
          assert_eq(
            req.headers.get("Authorization"),
            Some("Bearer public-api-test"),
          )
          let input = @json.parse(body.read_all().text())
          received.push(input)
          conn.send_response(200, "OK")
          conn.write(
            (
              {
                "version": 1,
                "content": "mock reply",
                "is_error": false,
                "data": input,
              } : Json),
          )
          conn.end_response()
        })
      })
      defer {
        worker.cancel()
        @async.protect_from_cancel(() => worker.wait() catch { _ => () })
      }
      @env.set_env_var(
        "OPENSEEK_PTC",
        (
          {
            "version": 1,
            "url": "http://127.0.0.1:\{server.addr.port()}/call",
            "token": "public-api-test",
          } : Json).stringify(),
      )
      let requests : Array[(String, Json)] = [
        (
          "edit",
          {
            "path": "note.txt",
            "start_line": 1,
            "old_string": "before",
            "new_string": "after",
            "revert_on_parse_errors": false,
          },
        ),
        (
          "multi_edit",
          {
            "edits": [
              {
                "file": "note.txt",
                "start_line": 1,
                "old_string": "after",
                "new_string": "done",
              },
            ],
          },
        ),
        ("multi_edit", { "edits_file": "edits.json" }),
        ("web_search", { "query": "MoonBit async" }),
        ("extension", { "nested": { "values": [1, true, "value"] } }),
      ]
      let results = []
      for (name, arguments) in requests {
        results.push(@openseek_tools.call(name, arguments))
      }
      assert_eq(received.length(), requests.length())
      for i, (name, arguments) in requests {
        let expected : Json = {
          "version": 1,
          "name": name,
          "arguments": arguments,
        }
        // Exact equality catches rewritten arguments or SDK-injected defaults.
        assert_eq(received[i], expected)
        assert_eq(results[i].content, "mock reply")
        assert_false(results[i].is_error)
        assert_eq(results[i].data, Some(expected))
      }
    })
  })
}
