///|
fn tool_call_payload(name : String, args : Json) -> String {
  let payload : Json = {
    "choices": [
      {
        "delta": {
          "tool_calls": [
            {
              "index": 0,
              "id": "artifact-call",
              "type": "function",
              "function": { "name": name, "arguments": args.stringify() },
            },
          ],
        },
      },
    ],
  }
  payload.stringify()
}

///|
async test "interactive answer generation repairs script and component diagnostics before publishing" {
  @vfs.with_tmpdir(root => {
    @async.with_task_group(group => {
      let workspace = root + "/workspace"
      let scratch = root + "/scratch"
      let project = scratch + "/answer"
      @fs.mkdir(workspace)
      let files = [
        "moon.mod", "moon.pkg", "main.mbt", "model.mbt", "model_wbtest.mbt", "bridge.mbt",
        "index.html",
      ]
      let sources = [
        for name in files => @fs.read_text("share/artifact/rabbita/" + name)
      ]
      let create =
        #|---
        #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
        #|---
        #|async fn main {
        #|  let args = @env.args()
        #|  @fs.mkdir(args[1], recursive=true)
        #|  for index, name in ["moon.mod", "moon.pkg", "main.mbt", "model.mbt", "model_wbtest.mbt", "bridge.mbt", "index.html"] {
        #|    @fs.write_text(args[1] + "/" + name, args[index + 2])
        #|  }
        #|  @fs.write_text(args[1] + "/main.mbt", "fn main { missing_component_function() }", create_mode=CreateOrTruncate)
        #|}
      let invalid =
        #|---
        #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
        #|---
        #|async fn main {
        #|  @fs.write_text(@env.args()[1], "must not execute")
        #|  missing_mbtx_function()
        #|}
      let fix =
        #|---
        #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
        #|---
        #|async fn main {
        #|  let args = @env.args()
        #|  @fs.write_text(args[1] + "/main.mbt", args[2], create_mode=CreateOrTruncate)
        #|}
      let recipe = @fs.realpath("share/artifact/build.mbtx")
      let build : Json = {
        "description": "Check and package the answer",
        "filename": recipe,
        "args": [project, scratch + "/artifact", "speedup-v1.html"],
        "ptc": false,
      }
      let answer = "```openseek-file artifact\nscratch/artifact/speedup-v1.html\n```"
      let bodies : Array[String] = []
      let responses = [
        tool_call_payload("mbtx", {
          "description": "Prepare the answer",
          "source": invalid,
          "args": [scratch + "/invalid-executed"],
          "ptc": false,
        }),
        tool_call_payload("mbtx", {
          "description": "Repair the script and write the component",
          "source": create,
          "args": [project, ..sources.map(source => Json(source))],
          "ptc": false,
        }),
        tool_call_payload("mbtx", build),
        tool_call_payload("mbtx", {
          "description": "Fix the component diagnostics",
          "source": fix,
          "args": [project, sources[2]],
          "ptc": false,
        }),
        tool_call_payload("mbtx", build),
        tool_call_payload("finish", { "answer": answer }),
        tool_call_payload("finish", { "answer": "Selected state explained" }),
      ]
      let runtime = @agent_runtime.AgentRuntime(workspace_root=workspace)
      let scope = @agent_runtime.AgentTaskScope(group)
      let tools = @agent.build_tools(
        runtime,
        scope,
        session_scratch_dir=scratch,
      )
      let jobs = tools.background_job_runtime().unwrap()
      let read_jobs : Array[String] = []
      let mut awaiting_output : String? = None
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever(
          (_request, conn) => {
            let body = conn.text.read_all()
            // A cold or contended build can exceed mbtx's inline allowance.
            // Read its real job result before advancing the scripted model.
            let payload = if awaiting_output is Some(id) {
              awaiting_output = None
              read_jobs.push(id)
              tool_call_payload("job_output", { "job_id": id })
            } else if jobs
              .list()
              .iter()
              .find_first(job => !read_jobs.contains(job.id))
              is Some(job) {
              awaiting_output = Some(job.id)
              tool_call_payload("job_wait", { "job_ids": [job.id] })
            } else {
              bodies.push(body)
              responses[bodies.length() - 1]
            }
            assert_false(@fs.exists(scratch + "/invalid-executed"))
            if bodies.length() == 4 {
              assert_false(@fs.exists(scratch + "/artifact/speedup-v1.html"))
              assert_false(
                @fs.exists(scratch + "/artifact/speedup-v1.html.source"),
              )
            }
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            conn.write_string("data: \{payload}\n\n")
            conn.write_string("data: [DONE]\n\n")
          },
          max_connections=responses.length() * 3,
        )
      }
      let url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
      let session = @async.with_timeout(120000, () => {
        @agent.run_turn_in_scope(
          runtime~,
          scope~,
          tools~,
          api_key="offline",
          model=Deepseek(V4Flash),
          api_url=url,
          session=Session(
            SessionId("interactive-answer"),
            system_prompt=@fs.read_text("prompt/default_prompt.mbt.md"),
          ),
          content=Content([
            Text("Explain parallel speedup with an interactive answer"),
          ]),
          max_steps=responses.length() * 3,
          append_item=(session, item) => session.append(item),
        )
      })
      assert_eq(bodies.length(), 6)
      assert_true(bodies[1].contains("missing_mbtx_function"))
      assert_true(bodies[3].contains("missing_component_function"))
      assert_true(
        bodies[5].contains("scratch/artifact/speedup-v1.html"),
        msg=bodies[5],
      )
      assert_true(@fs.exists(scratch + "/artifact/speedup-v1.html"))
      assert_true(
        @fs.exists(scratch + "/artifact/speedup-v1.html.source/bridge.mbt"),
      )
      let mut finished = false
      for event in session.events() {
        if event.item() is Terminal(Finished(text)) && text == answer {
          finished = true
        }
      }
      assert_true(finished)
      let selected =
        #|Explain the selected state.
        #|
        #|<user_mentions>
        #|<interactive_answer>
        #|{"reference":"scratch/artifact/speedup-v1.html","title":"50% sequential, 8 workers","state":{"serial_percent":50,"workers":8}}
        #|</interactive_answer>
        #|</user_mentions>
      let followed = @agent.run_turn_in_scope(
        runtime~,
        scope~,
        tools~,
        api_key="offline",
        model=Deepseek(V4Flash),
        api_url=url,
        session~,
        content=Content([Text(selected)]),
        max_steps=2,
        append_item=(session, item) => session.append(item),
      )
      assert_true(
        followed.last_terminal() is Some(Finished("Selected state explained")),
      )
      assert_eq(bodies.length(), 7)
      guard @json.parse(bodies[6]) is { "messages": Array(messages), .. } else {
        fail("missing model request messages")
      }
      let mut saw_selected_state = false
      for message in messages {
        match message {
          { "role": String("user"), "content": String(text), .. } if text ==
            selected => saw_selected_state = true
          { "role": String("user"), "content": Array(parts), .. } =>
            for part in parts {
              if part is { "type": String("text"), "text": String(text), .. } &&
                text == selected {
                saw_selected_state = true
              }
            }
          _ => ()
        }
      }
      assert_true(saw_selected_state)
    })
  })
}
