///|
priv enum ModelMessage {
  Connecting
  Unavailable
  SignIn
  LoadingModels
  CommandLabel
  FileChanges
  WebSearch
  ViewedImagePrefix
  Compacted
  ChangedFiles
  SearchedWeb
  ViewedImage
  GenerateImage
  WaitLabel
  EnteredReview
  ExitedReview
  CreateSubagent
  WaitSubagents
  SendSubagent
  ResumeSubagent
  AssignSubagent
  StopSubagent
  CloseSubagent
  ListSubagents
}

///|
fn model_text(locale : @i18n.Locale, message : ModelMessage) -> String {
  match (locale, message) {
    (English, Connecting) => "Codex — connecting…"
    (SimplifiedChinese, Connecting) => "Codex — 正在连接…"
    (English, Unavailable) => "Codex unavailable"
    (SimplifiedChinese, Unavailable) => "Codex 不可用"
    (English, SignIn) => "Sign in to Codex…"
    (SimplifiedChinese, SignIn) => "登录 Codex…"
    (English, LoadingModels) => "Codex — loading models…"
    (SimplifiedChinese, LoadingModels) => "Codex — 正在加载模型…"
    (English, CommandLabel) => "Command"
    (SimplifiedChinese, CommandLabel) => "命令"
    (English, FileChanges) => "File changes"
    (SimplifiedChinese, FileChanges) => "文件更改"
    (English, WebSearch) => "Web search: "
    (SimplifiedChinese, WebSearch) => "网页搜索："
    (English, ViewedImagePrefix) => "Viewed image: "
    (SimplifiedChinese, ViewedImagePrefix) => "已查看图片："
    (English, Compacted) => "Compacted conversation context"
    (SimplifiedChinese, Compacted) => "已压缩对话上下文"
    (English, ChangedFiles) => "Changed files"
    (SimplifiedChinese, ChangedFiles) => "已更改文件"
    (English, SearchedWeb) => "Searched the web"
    (SimplifiedChinese, SearchedWeb) => "已搜索网页"
    (English, ViewedImage) => "Viewed image"
    (SimplifiedChinese, ViewedImage) => "已查看图片"
    (English, GenerateImage) => "Generate image"
    (SimplifiedChinese, GenerateImage) => "生成图片"
    (English, WaitLabel) => "Wait"
    (SimplifiedChinese, WaitLabel) => "等待"
    (English, EnteredReview) => "Entered review mode"
    (SimplifiedChinese, EnteredReview) => "已进入审阅模式"
    (English, ExitedReview) => "Exited review mode"
    (SimplifiedChinese, ExitedReview) => "已退出审阅模式"
    (English, CreateSubagent) => "Create subagent"
    (SimplifiedChinese, CreateSubagent) => "创建子智能体"
    (English, WaitSubagents) => "Wait for subagents"
    (SimplifiedChinese, WaitSubagents) => "等待子智能体"
    (English, SendSubagent) => "Send message to subagent"
    (SimplifiedChinese, SendSubagent) => "向子智能体发送消息"
    (English, ResumeSubagent) => "Resume subagent"
    (SimplifiedChinese, ResumeSubagent) => "恢复子智能体"
    (English, AssignSubagent) => "Assign subagent task"
    (SimplifiedChinese, AssignSubagent) => "分配子智能体任务"
    (English, StopSubagent) => "Stop subagent"
    (SimplifiedChinese, StopSubagent) => "停止子智能体"
    (English, CloseSubagent) => "Close subagent"
    (SimplifiedChinese, CloseSubagent) => "关闭子智能体"
    (English, ListSubagents) => "List subagents"
    (SimplifiedChinese, ListSubagents) => "列出子智能体"
  }
}
