// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  WhatBuild
  ChooseProject
  NoProjects
  SearchProjects
  ProjectsLabel
  NewProject
  BuildInPrefix
  CodexDescription
  JumpLatest
  RecordedSnapshot
  ToolInProgress
  ToolFailed
  ToolSucceeded
  ToolDetails
  OriginalJson
  ArgumentsLabel
  OutputLabel
  OriginalOutput
  ThinkingLabel
  ThoughtLabel
  SnapshotLabel
  JobId
  CopyJobId
  YouLabel
  AttachedImage
  SentPrefix
  CopyMessage
  CopyUserMessage
  CommittedPrefix
  CopyMarkdown
  CopyAssistantMarkdown
  CompletedPrefix
  ContextCompacted
  SaveRun
  SourceLabel
  FilenameLabel
  ChangeLabel
  ChangesLabel
  ReadFiles
  EditFiles
  WriteFiles
  RemoveFiles
  ExecuteMbtx
  ExecuteCommands
  SearchWeb
  ViewImages
  GenerateImages
  ReviewCode
  CreateSubagents
  WaitSubagents
  SendSubagents
  ResumeSubagents
  AssignSubagents
  StopSubagents
  CloseSubagents
  ListSubagents
  SubmitResults
  SubmitReviews
  UpdatePlan
  UpdateGoal
  OtherTools
  AssistantLabel
  ContextSummary
  WorkCompleted
  ViewActivity
  RequestedChanges
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, WhatBuild) => "What should we build?"
    (SimplifiedChinese, WhatBuild) => "我们来构建什么？"
    (English, ChooseProject) => "Choose a project"
    (SimplifiedChinese, ChooseProject) => "选择项目"
    (English, NoProjects) => "No projects found"
    (SimplifiedChinese, NoProjects) => "未找到项目"
    (English, SearchProjects) => "Search projects"
    (SimplifiedChinese, SearchProjects) => "搜索项目"
    (English, ProjectsLabel) => "Projects"
    (SimplifiedChinese, ProjectsLabel) => "项目"
    (English, NewProject) => "New project"
    (SimplifiedChinese, NewProject) => "新建项目"
    (English, BuildInPrefix) => "What should we build in "
    (SimplifiedChinese, BuildInPrefix) => "想在此项目中构建什么："
    (English, CodexDescription) =>
      "Codex inspects, edits, and runs this workspace with its own account, sandbox, and approvals."
    (SimplifiedChinese, CodexDescription) =>
      "Codex 使用自己的账户、沙盒和审批设置来检查、编辑和运行此工作区。"
    (English, JumpLatest) => "Jump to latest"
    (SimplifiedChinese, JumpLatest) => "跳至最新消息"
    (English, RecordedSnapshot) => "Recorded snapshot"
    (SimplifiedChinese, RecordedSnapshot) => "已记录的快照"
    (English, ToolInProgress) => "Tool in progress"
    (SimplifiedChinese, ToolInProgress) => "工具正在运行"
    (English, ToolFailed) => "Tool failed"
    (SimplifiedChinese, ToolFailed) => "工具运行失败"
    (English, ToolSucceeded) => "Tool succeeded"
    (SimplifiedChinese, ToolSucceeded) => "工具运行成功"
    (English, ToolDetails) => "Tool call details"
    (SimplifiedChinese, ToolDetails) => "工具调用详情"
    (English, OriginalJson) => "Original JSON"
    (SimplifiedChinese, OriginalJson) => "原始 JSON"
    (English, ArgumentsLabel) => "Arguments"
    (SimplifiedChinese, ArgumentsLabel) => "参数"
    (English, OutputLabel) => "Output"
    (SimplifiedChinese, OutputLabel) => "输出"
    (English, OriginalOutput) => "Original output"
    (SimplifiedChinese, OriginalOutput) => "原始输出"
    (English, ThinkingLabel) => "Thinking…"
    (SimplifiedChinese, ThinkingLabel) => "正在思考…"
    (English, ThoughtLabel) => "Thought"
    (SimplifiedChinese, ThoughtLabel) => "思考过程"
    (English, SnapshotLabel) => "Snapshot"
    (SimplifiedChinese, SnapshotLabel) => "快照"
    (English, JobId) => "Job ID"
    (SimplifiedChinese, JobId) => "任务 ID"
    (English, CopyJobId) => "Copy job ID"
    (SimplifiedChinese, CopyJobId) => "复制任务 ID"
    (English, YouLabel) => "You"
    (SimplifiedChinese, YouLabel) => "你"
    (English, AttachedImage) => "Attached image"
    (SimplifiedChinese, AttachedImage) => "附加图片"
    (English, SentPrefix) => "Sent "
    (SimplifiedChinese, SentPrefix) => "发送于 "
    (English, CopyMessage) => "Copy message"
    (SimplifiedChinese, CopyMessage) => "复制消息"
    (English, CopyUserMessage) => "Copy user message"
    (SimplifiedChinese, CopyUserMessage) => "复制用户消息"
    (English, CommittedPrefix) => "Committed "
    (SimplifiedChinese, CommittedPrefix) => "记录于 "
    (English, CopyMarkdown) => "Copy Markdown"
    (SimplifiedChinese, CopyMarkdown) => "复制 Markdown"
    (English, CopyAssistantMarkdown) => "Copy assistant message as Markdown"
    (SimplifiedChinese, CopyAssistantMarkdown) =>
      "以 Markdown 格式复制助手消息"
    (English, CompletedPrefix) => "Completed "
    (SimplifiedChinese, CompletedPrefix) => "完成于 "
    (English, ContextCompacted) => "Context compacted"
    (SimplifiedChinese, ContextCompacted) => "上下文已压缩"
    (English, SaveRun) => "Save & run"
    (SimplifiedChinese, SaveRun) => "保存并运行"
    (English, SourceLabel) => "Source"
    (SimplifiedChinese, SourceLabel) => "源码"
    (English, FilenameLabel) => "Filename"
    (SimplifiedChinese, FilenameLabel) => "文件名"
    (English, ChangeLabel) => "Change"
    (SimplifiedChinese, ChangeLabel) => "更改"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (English, ReadFiles) => "Read files"
    (SimplifiedChinese, ReadFiles) => "读取文件"
    (English, EditFiles) => "Edit files"
    (SimplifiedChinese, EditFiles) => "编辑文件"
    (English, WriteFiles) => "Write files"
    (SimplifiedChinese, WriteFiles) => "写入文件"
    (English, RemoveFiles) => "Remove files"
    (SimplifiedChinese, RemoveFiles) => "移除文件"
    (English, ExecuteMbtx) => "Execute mbtx scripts"
    (SimplifiedChinese, ExecuteMbtx) => "执行 mbtx 脚本"
    (English, ExecuteCommands) => "Execute commands"
    (SimplifiedChinese, ExecuteCommands) => "执行命令"
    (English, SearchWeb) => "Search the web"
    (SimplifiedChinese, SearchWeb) => "搜索网络"
    (English, ViewImages) => "View images"
    (SimplifiedChinese, ViewImages) => "查看图片"
    (English, GenerateImages) => "Generate images"
    (SimplifiedChinese, GenerateImages) => "生成图片"
    (English, ReviewCode) => "Review code"
    (SimplifiedChinese, ReviewCode) => "审阅代码"
    (English, CreateSubagents) => "Create subagents"
    (SimplifiedChinese, CreateSubagents) => "创建子智能体"
    (English, WaitSubagents) => "Wait for subagents"
    (SimplifiedChinese, WaitSubagents) => "等待子智能体"
    (English, SendSubagents) => "Send messages to subagents"
    (SimplifiedChinese, SendSubagents) => "向子智能体发送消息"
    (English, ResumeSubagents) => "Resume subagents"
    (SimplifiedChinese, ResumeSubagents) => "恢复子智能体"
    (English, AssignSubagents) => "Assign subagent tasks"
    (SimplifiedChinese, AssignSubagents) => "分配子智能体任务"
    (English, StopSubagents) => "Stop subagents"
    (SimplifiedChinese, StopSubagents) => "停止子智能体"
    (English, CloseSubagents) => "Close subagents"
    (SimplifiedChinese, CloseSubagents) => "关闭子智能体"
    (English, ListSubagents) => "List subagents"
    (SimplifiedChinese, ListSubagents) => "列出子智能体"
    (English, SubmitResults) => "Submit results"
    (SimplifiedChinese, SubmitResults) => "提交结果"
    (English, SubmitReviews) => "Submit reviews"
    (SimplifiedChinese, SubmitReviews) => "提交审阅"
    (English, UpdatePlan) => "Update plan"
    (SimplifiedChinese, UpdatePlan) => "更新计划"
    (English, UpdateGoal) => "Update goal"
    (SimplifiedChinese, UpdateGoal) => "更新目标"
    (English, OtherTools) => "Other tool calls"
    (SimplifiedChinese, OtherTools) => "其他工具调用"
    (English, AssistantLabel) => "Assistant"
    (SimplifiedChinese, AssistantLabel) => "助手"
    (English, ContextSummary) => "Context summary"
    (SimplifiedChinese, ContextSummary) => "上下文摘要"
    (English, WorkCompleted) => "Work completed"
    (SimplifiedChinese, WorkCompleted) => "工作已完成"
    (English, ViewActivity) => "View activity"
    (SimplifiedChinese, ViewActivity) => "查看活动"
    (English, RequestedChanges) => "Requested changes"
    (SimplifiedChinese, RequestedChanges) => "请求的更改"
  }
}
