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
        for name in files => {
          @fs.read_file("share/artifact/rabbita/" + name).text()
        }
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
      let answer = "```openseek-file\nartifact://speedup-v1.html\n```"
      let bodies : Array[String] = []
      guard goal_check_test_server(
          group,
          bodies,
          [
            wait_call_payload("mbtx", {
              "description": "Prepare the answer",
              "source": invalid,
              "args": [scratch + "/invalid-executed"],
              "ptc": false,
            }),
            wait_call_payload("mbtx", {
              "description": "Repair the script and write the component",
              "source": create,
              "args": [project, ..sources.map(source => Json(source))],
              "ptc": false,
            }),
            wait_call_payload("mbtx", build),
            wait_call_payload("mbtx", {
              "description": "Fix the component diagnostics",
              "source": fix,
              "args": [project, sources[2]],
              "ptc": false,
            }),
            wait_call_payload("mbtx", build),
            wait_call_payload("finish", { "answer": answer }),
            wait_call_payload("finish", { "answer": "Selected state explained" }),
          ],
          on_request=() => {
            assert_false(@fs.exists(scratch + "/invalid-executed"))
            if bodies.length() == 4 {
              assert_false(@fs.exists(scratch + "/artifact/speedup-v1.html"))
              assert_false(
                @fs.exists(scratch + "/artifact/speedup-v1.html.source"),
              )
            }
          },
        )
        is Some(url) else {
        fail("offline model fixture unavailable")
      }
      let runtime = @agent_runtime.AgentRuntime(workspace_root=workspace)
      let scope = @agent_runtime.AgentTaskScope(group)
      let tools = @agent.build_tools(
        runtime,
        scope,
        session_scratch_dir=scratch,
      )
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
            system_prompt=@fs.read_file("prompt/default_prompt.mbt.md").text(),
          ),
          content=Content([
            Text("Explain parallel speedup with an interactive answer"),
          ]),
          max_steps=8,
          append_item=(session, item) => session.append(item),
        )
      })
      assert_eq(bodies.length(), 6)
      assert_true(bodies[1].contains("missing_mbtx_function"))
      assert_true(bodies[3].contains("missing_component_function"))
      assert_true(bodies[5].contains("artifact://speedup-v1.html"))
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
        #|{"reference":"artifact://speedup-v1.html","title":"50% sequential, 8 workers","state":{"serial_percent":50,"workers":8}}
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
