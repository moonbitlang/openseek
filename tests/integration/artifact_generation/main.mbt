///|
/// Live-model acceptance configured through the client's engine settings.
async fn main {
  let args = @env.args()[1:]
  guard args is [settings_file, .. rest] && rest.length() <= 1 else {
    fail(
      "Usage: artifact_generation ENGINE_SETTINGS_FILE [RESUME_ACCEPTANCE_DIRECTORY]",
    )
  }
  let settings = @json.parse(@fs.read_file(settings_file).text())
  guard settings
    is {
      "provider": String("deepseek"),
      "deepseek_api_key": String(api_key),
      ..
    } &&
    !api_key.trim().is_empty() else {
    fail("live acceptance requires the configured DeepSeek provider")
  }
  let resuming = rest is [_]
  let root = match rest {
    [directory] => @fs.realpath(directory)
    _ => @fs.realpath(@fs.tmpdir(prefix="openseek-live-artifact-"))
  }
  let workspace = root + "/workspace"
  let scratch = root + "/scratch"
  if !resuming {
    @fs.mkdir(workspace)
    @fs.mkdir(scratch)
  }
  println("Live acceptance output: \{root}")
  let resources = @fs.realpath("share")
  let model : @deepseek.Model = Deepseek(V4Flash)
  let system = @prompt.system_prompt_for_model(model).replace_all(
      old="<bundled-resources>",
      new=resources,
    ) +
    "\n\nEnvironment\nWorkspace: \{workspace}\nSession scratch directory: \{scratch}\nBundled resources: \{resources}\n"
  let initial : @agent_session.Session = if resuming {
    @json.from_json(@json.parse(@fs.read_file(root + "/session.json").text()))
  } else {
    Session(SessionId("live-artifact"), system_prompt=system)
  }
  let latest = Ref(initial)
  let selected = if resuming && @fs.exists(root + "/selection.json") {
    Some(@fs.read_file(root + "/selection.json").text())
  } else {
    None
  }
  let original_page = if selected is Some(_) {
    Some(@fs.read_file(scratch + "/artifact/linear-v1.html").binary())
  } else {
    None
  }
  let outcome = Ok(
    @async.with_timeout(480000, () => {
      @async.with_task_group(group => {
        let runtime = @agent_runtime.AgentRuntime(workspace_root=workspace)
        let scope = @agent_runtime.AgentTaskScope(group)
        let tools = @agent.build_tools(
          runtime,
          scope,
          session_scratch_dir=scratch,
        )
        let task = if selected is Some(snapshot) {
          "请根据我选择的当前状态解释 x=2 时的结果，并核对你上一条回答中的所有数值示例，明确每个例子的完整 a、b 参数。只解释，不修改或重新生成组件文件。\n\n<user_mentions>\n<interactive_answer>\n\{snapshot}\n</interactive_answer>\n</user_mentions>"
        } else if resuming {
          "继续完成现有线性函数组件。项目已准备在 scratch/component-work/linear；用 artifact/write.mbtx 批量修复相关源码，不再创建中转源码项目。运行整个项目的 JS 检查和测试，再调用 build.mbtx 发布 linear-v1.html，成功后 finish 引用页面。"
        } else {
          "用一个中文交互组件解释线性函数 y = ax + b。两个有标签的整数滑块分别调节 a、b（范围 -5 到 5、步长 1，id 分别为 a 和 b），初始 a=1、b=0；在 id=y2 的 output 中显示 x=2 时 y 的数值，并提供重置。不需要图像或 SVG，只围绕参数和结果解释这个问题。使用普通 MoonBit/Rabbita 源码和本地事件，调用内置打包脚本，输出文件名必须为 linear-v1.html。沿用起始项目的状态桥，提供数值字段 a、b、y_at_2，让用户能携带当前参数继续提问。只读取内置参考资料、依赖、这个空工作区和 scratch，不修改其他目录。先读产物指南和起始项目，用 init.mbtx 准备项目，源码写到新的 scratch 文件，再通过 write.mbtx 传入来源文件路径批量应用。检查并运行相关纯模型测试，打包成功后在最终回答引用页面。不要运行应用、开发服务器或浏览器。"
        }
        let content : @protocol.Content = Content([Text(task)])
        @agent.run_turn_in_scope(
          runtime~,
          scope~,
          tools~,
          api_key~,
          model~,
          thinking=High,
          session=latest.val,
          content~,
          max_steps=32,
          retry_attempts=1,
          append_item=(session, item) => {
            let next = session.append(item)
            latest.val = next
            match item {
              Tool(result) =>
                println(
                  "tool: \{result.tool_name()} error=\{result.is_error()}",
                )
              _ => ()
            }
            next
          },
        )
      })
    }),
  ) catch {
    error => Err(error)
  }
  @fs.write_file(
    root + "/session.json",
    ToJson::to_json(latest.val).stringify(indent=2),
    create_mode=CreateOrTruncate,
  )
  let session = match outcome {
    Ok(session) => session
    Err(error) => fail("live acceptance did not finish: \{error}")
  }
  guard session.last_terminal() is Some(Finished(answer)) else {
    fail("live model did not finish; inspect the saved acceptance session")
  }
  if selected is Some(_) {
    @fs.write_file(root + "/followup.md", answer, create_mode=CreateOrTruncate)
    assert_true(
      original_page is Some(bytes) &&
      @fs.read_file(scratch + "/artifact/linear-v1.html").binary() == bytes,
    )
    println("Live follow-up ready: \{root}/followup.md")
  } else {
    @fs.write_file(root + "/answer.md", answer, create_mode=CreateOrTruncate)
    guard answer.contains("artifact://linear-v1.html") else {
      fail("live answer omitted the page reference")
    }
  }
  guard @fs.exists(scratch + "/artifact/linear-v1.html") &&
    @fs.exists(scratch + "/artifact/linear-v1.html.source/main.mbt") else {
    fail("live model did not produce the requested editable component")
  }
  println("Live component ready: \{scratch}/artifact/linear-v1.html")
}
