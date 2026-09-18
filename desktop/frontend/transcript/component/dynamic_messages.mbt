///|
priv enum DynamicMessage {
  DOpenSubagent(String)
  DProgramCalls(String)
  DToolOutput(String)
  DToolError(String)
  DJumpLine(String, String)
  DJumpFile(String)
  DProgramCallsArray(String)
  DWhatBuild(String)
  DChooseProject(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DOpenSubagent(p0)) =>
      "Open this subagent's own transcript (\{p0})"
    (SimplifiedChinese, DOpenSubagent(p0)) =>
      "打开此子智能体的对话记录（\{p0}）"
    (English, DProgramCalls(p0)) => "Program tool calls (\{p0})"
    (SimplifiedChinese, DProgramCalls(p0)) => "程序工具调用（\{p0}）"
    (English, DToolOutput(p0)) => "Tool output · \{p0}"
    (SimplifiedChinese, DToolOutput(p0)) => "工具输出 · \{p0}"
    (English, DToolError(p0)) => "Tool error · \{p0}"
    (SimplifiedChinese, DToolError(p0)) => "工具错误 · \{p0}"
    (English, DJumpLine(p0, p1)) => "Jump to \{p0}:\{p1}"
    (SimplifiedChinese, DJumpLine(p0, p1)) => "跳转至 \{p0}:\{p1}"
    (English, DJumpFile(p0)) => "Jump to \{p0}"
    (SimplifiedChinese, DJumpFile(p0)) => "跳转至 \{p0}"
    (English, DProgramCallsArray(p0)) => "Program tool calls (\{p0})"
    (SimplifiedChinese, DProgramCallsArray(p0)) =>
      "程序工具调用（\{p0}）"
    (English, DWhatBuild(p0)) => "What should we build in \{p0}?"
    (SimplifiedChinese, DWhatBuild(p0)) => "想在 \{p0} 中构建什么？"
    (English, DChooseProject(p0)) => "Choose project, current project \{p0}"
    (SimplifiedChinese, DChooseProject(p0)) =>
      "选择项目，当前项目为 \{p0}"
  }
}
