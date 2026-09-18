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
    (TraditionalChinese, DOpenSubagent(p0)) =>
      "開啟此子代理程式的對話記錄（\{p0}）"
    (Japanese, DOpenSubagent(p0)) =>
      "このサブエージェントのチャット履歴を開く（\{p0}）"
    (English, DProgramCalls(p0)) => "Program tool calls (\{p0})"
    (SimplifiedChinese, DProgramCalls(p0)) => "程序工具调用（\{p0}）"
    (TraditionalChinese, DProgramCalls(p0)) => "程式工具呼叫（\{p0}）"
    (Japanese, DProgramCalls(p0)) =>
      "プログラムツール呼び出し（\{p0}）"
    (English, DToolOutput(p0)) => "Tool output · \{p0}"
    (SimplifiedChinese, DToolOutput(p0)) => "工具输出 · \{p0}"
    (TraditionalChinese, DToolOutput(p0)) => "工具輸出 · \{p0}"
    (Japanese, DToolOutput(p0)) => "ツール出力 · \{p0}"
    (English, DToolError(p0)) => "Tool error · \{p0}"
    (SimplifiedChinese, DToolError(p0)) => "工具错误 · \{p0}"
    (TraditionalChinese, DToolError(p0)) => "工具錯誤 · \{p0}"
    (Japanese, DToolError(p0)) => "ツールエラー · \{p0}"
    (English, DJumpLine(p0, p1)) => "Jump to \{p0}:\{p1}"
    (SimplifiedChinese, DJumpLine(p0, p1)) => "跳转至 \{p0}:\{p1}"
    (TraditionalChinese, DJumpLine(p0, p1)) => "跳轉至 \{p0}:\{p1}"
    (Japanese, DJumpLine(p0, p1)) => "\{p0}:\{p1} へ移動"
    (English, DJumpFile(p0)) => "Jump to \{p0}"
    (SimplifiedChinese, DJumpFile(p0)) => "跳转至 \{p0}"
    (TraditionalChinese, DJumpFile(p0)) => "跳轉至 \{p0}"
    (Japanese, DJumpFile(p0)) => "\{p0} へ移動"
    (English, DProgramCallsArray(p0)) => "Program tool calls (\{p0})"
    (SimplifiedChinese, DProgramCallsArray(p0)) =>
      "程序工具调用（\{p0}）"
    (TraditionalChinese, DProgramCallsArray(p0)) =>
      "程式工具呼叫（\{p0}）"
    (Japanese, DProgramCallsArray(p0)) =>
      "プログラムツール呼び出し（\{p0}）"
    (English, DWhatBuild(p0)) => "What should we build in \{p0}?"
    (SimplifiedChinese, DWhatBuild(p0)) => "想在 \{p0} 中构建什么？"
    (TraditionalChinese, DWhatBuild(p0)) => "想在 \{p0} 中構建什麼？"
    (Japanese, DWhatBuild(p0)) => "\{p0} で何を作りましょうか？"
    (English, DChooseProject(p0)) => "Choose project, current project \{p0}"
    (SimplifiedChinese, DChooseProject(p0)) =>
      "选择项目，当前项目为 \{p0}"
    (TraditionalChinese, DChooseProject(p0)) =>
      "選擇專案，當前專案為 \{p0}"
    (Japanese, DChooseProject(p0)) =>
      "プロジェクトを選択、現在のプロジェクト：\{p0}"
  }
}
