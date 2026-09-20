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
  BuildInSuffix
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
  CopyDiff
  OpenDiffFile
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, CopyDiff) => "Copy diff"
    (SimplifiedChinese, CopyDiff) => "复制差异"
    (TraditionalChinese, CopyDiff) => "複製差異"
    (Japanese, CopyDiff) => "差分をコピー"
    (English, OpenDiffFile) => "Open file"
    (SimplifiedChinese, OpenDiffFile) => "打开文件"
    (TraditionalChinese, OpenDiffFile) => "開啟檔案"
    (Japanese, OpenDiffFile) => "ファイルを開く"
    (English, WhatBuild) => "What should we build?"
    (SimplifiedChinese, WhatBuild) => "我们来构建什么？"
    (TraditionalChinese, WhatBuild) => "我們來構建什麼？"
    (Japanese, WhatBuild) => "何を作りましょうか？"
    (English, ChooseProject) => "Choose a project"
    (SimplifiedChinese, ChooseProject) => "选择项目"
    (TraditionalChinese, ChooseProject) => "選擇專案"
    (Japanese, ChooseProject) => "プロジェクトを選択"
    (English, NoProjects) => "No projects found"
    (SimplifiedChinese, NoProjects) => "未找到项目"
    (TraditionalChinese, NoProjects) => "未找到專案"
    (Japanese, NoProjects) => "プロジェクトが見つかりません"
    (English, SearchProjects) => "Search projects"
    (SimplifiedChinese, SearchProjects) => "搜索项目"
    (TraditionalChinese, SearchProjects) => "搜尋專案"
    (Japanese, SearchProjects) => "プロジェクトを検索"
    (English, ProjectsLabel) => "Projects"
    (SimplifiedChinese, ProjectsLabel) => "项目"
    (TraditionalChinese, ProjectsLabel) => "專案"
    (Japanese, ProjectsLabel) => "プロジェクト"
    (English, NewProject) => "New project"
    (SimplifiedChinese, NewProject) => "新建项目"
    (TraditionalChinese, NewProject) => "新建專案"
    (Japanese, NewProject) => "新しいプロジェクト"
    (English, BuildInPrefix) => "What should we build in "
    (SimplifiedChinese, BuildInPrefix) => "想在此项目中构建什么："
    (TraditionalChinese, BuildInPrefix) => "想在此專案中構建什麼："
    (Japanese, BuildInPrefix) => ""
    (English, BuildInSuffix) => "?"
    (SimplifiedChinese, BuildInSuffix) => "？"
    (TraditionalChinese, BuildInSuffix) => "？"
    (Japanese, BuildInSuffix) => "で何を作りましょうか？"
    (English, CodexDescription) =>
      "Codex inspects, edits, and runs this workspace with its own account, sandbox, and approvals."
    (SimplifiedChinese, CodexDescription) =>
      "Codex 使用自己的账户、沙盒和审批设置来检查、编辑和运行此工作区。"
    (TraditionalChinese, CodexDescription) =>
      "Codex 使用自己的帳戶、沙盒和審批設定來檢查、編輯和執行此工作區。"
    (Japanese, CodexDescription) =>
      "Codex は独自のアカウント、サンドボックス、承認設定を使用して、このワークスペースの調査・編集・実行を行います。"
    (English, JumpLatest) => "Jump to latest"
    (SimplifiedChinese, JumpLatest) => "跳至最新消息"
    (TraditionalChinese, JumpLatest) => "跳至最新訊息"
    (Japanese, JumpLatest) => "最新のメッセージへ移動"
    (English, RecordedSnapshot) => "Recorded snapshot"
    (SimplifiedChinese, RecordedSnapshot) => "已记录的快照"
    (TraditionalChinese, RecordedSnapshot) => "已記錄的快照"
    (Japanese, RecordedSnapshot) => "記録済みスナップショット"
    (English, ToolInProgress) => "Tool in progress"
    (SimplifiedChinese, ToolInProgress) => "工具正在运行"
    (TraditionalChinese, ToolInProgress) => "工具正在執行"
    (Japanese, ToolInProgress) => "ツールを実行中"
    (English, ToolFailed) => "Tool failed"
    (SimplifiedChinese, ToolFailed) => "工具运行失败"
    (TraditionalChinese, ToolFailed) => "工具執行失敗"
    (Japanese, ToolFailed) => "ツールの実行に失敗しました"
    (English, ToolSucceeded) => "Tool succeeded"
    (SimplifiedChinese, ToolSucceeded) => "工具运行成功"
    (TraditionalChinese, ToolSucceeded) => "工具執行成功"
    (Japanese, ToolSucceeded) => "ツールの実行に成功しました"
    (English, ToolDetails) => "Tool call details"
    (SimplifiedChinese, ToolDetails) => "工具调用详情"
    (TraditionalChinese, ToolDetails) => "工具呼叫詳情"
    (Japanese, ToolDetails) => "ツール呼び出しの詳細"
    (English, OriginalJson) => "Original JSON"
    (SimplifiedChinese, OriginalJson) => "原始 JSON"
    (TraditionalChinese, OriginalJson) => "原始 JSON"
    (Japanese, OriginalJson) => "元の JSON"
    (English, ArgumentsLabel) => "Arguments"
    (SimplifiedChinese, ArgumentsLabel) => "参数"
    (TraditionalChinese, ArgumentsLabel) => "引數"
    (Japanese, ArgumentsLabel) => "引数"
    (English, OutputLabel) => "Output"
    (SimplifiedChinese, OutputLabel) => "输出"
    (TraditionalChinese, OutputLabel) => "輸出"
    (Japanese, OutputLabel) => "出力"
    (English, OriginalOutput) => "Original output"
    (SimplifiedChinese, OriginalOutput) => "原始输出"
    (TraditionalChinese, OriginalOutput) => "原始輸出"
    (Japanese, OriginalOutput) => "元の出力"
    (English, ThinkingLabel) => "Thinking…"
    (SimplifiedChinese, ThinkingLabel) => "正在思考…"
    (TraditionalChinese, ThinkingLabel) => "正在思考…"
    (Japanese, ThinkingLabel) => "思考中…"
    (English, ThoughtLabel) => "Thought"
    (SimplifiedChinese, ThoughtLabel) => "思考过程"
    (TraditionalChinese, ThoughtLabel) => "思考過程"
    (Japanese, ThoughtLabel) => "思考過程"
    (English, SnapshotLabel) => "Snapshot"
    (SimplifiedChinese, SnapshotLabel) => "快照"
    (TraditionalChinese, SnapshotLabel) => "快照"
    (Japanese, SnapshotLabel) => "スナップショット"
    (English, JobId) => "Job ID"
    (SimplifiedChinese, JobId) => "任务 ID"
    (TraditionalChinese, JobId) => "任務 ID"
    (Japanese, JobId) => "ジョブ ID"
    (English, CopyJobId) => "Copy job ID"
    (SimplifiedChinese, CopyJobId) => "复制任务 ID"
    (TraditionalChinese, CopyJobId) => "複製任務 ID"
    (Japanese, CopyJobId) => "ジョブ ID をコピー"
    (English, YouLabel) => "You"
    (SimplifiedChinese, YouLabel) => "你"
    (TraditionalChinese, YouLabel) => "你"
    (Japanese, YouLabel) => "あなた"
    (English, AttachedImage) => "Attached image"
    (SimplifiedChinese, AttachedImage) => "附加图片"
    (TraditionalChinese, AttachedImage) => "附加圖片"
    (Japanese, AttachedImage) => "添付画像"
    (English, SentPrefix) => "Sent "
    (SimplifiedChinese, SentPrefix) => "发送于 "
    (TraditionalChinese, SentPrefix) => "傳送於 "
    (Japanese, SentPrefix) => "送信日時："
    (English, CopyMessage) => "Copy message"
    (SimplifiedChinese, CopyMessage) => "复制消息"
    (TraditionalChinese, CopyMessage) => "複製訊息"
    (Japanese, CopyMessage) => "メッセージをコピー"
    (English, CopyUserMessage) => "Copy user message"
    (SimplifiedChinese, CopyUserMessage) => "复制用户消息"
    (TraditionalChinese, CopyUserMessage) => "複製使用者訊息"
    (Japanese, CopyUserMessage) => "ユーザーメッセージをコピー"
    (English, CommittedPrefix) => "Committed "
    (SimplifiedChinese, CommittedPrefix) => "记录于 "
    (TraditionalChinese, CommittedPrefix) => "記錄於 "
    (Japanese, CommittedPrefix) => "記録日時："
    (English, CopyMarkdown) => "Copy Markdown"
    (SimplifiedChinese, CopyMarkdown) => "复制 Markdown"
    (TraditionalChinese, CopyMarkdown) => "複製 Markdown"
    (Japanese, CopyMarkdown) => "Markdown をコピー"
    (English, CopyAssistantMarkdown) => "Copy assistant message as Markdown"
    (SimplifiedChinese, CopyAssistantMarkdown) =>
      "以 Markdown 格式复制助手消息"
    (TraditionalChinese, CopyAssistantMarkdown) =>
      "以 Markdown 格式複製助手訊息"
    (Japanese, CopyAssistantMarkdown) =>
      "アシスタントのメッセージを Markdown としてコピー"
    (English, CompletedPrefix) => "Completed "
    (SimplifiedChinese, CompletedPrefix) => "完成于 "
    (TraditionalChinese, CompletedPrefix) => "完成於 "
    (Japanese, CompletedPrefix) => "完了日時："
    (English, ContextCompacted) => "Context compacted"
    (SimplifiedChinese, ContextCompacted) => "上下文已压缩"
    (TraditionalChinese, ContextCompacted) => "上下文已壓縮"
    (Japanese, ContextCompacted) => "コンテキストを圧縮しました"
    (English, SaveRun) => "Save & run"
    (SimplifiedChinese, SaveRun) => "保存并运行"
    (TraditionalChinese, SaveRun) => "儲存並執行"
    (Japanese, SaveRun) => "保存して実行"
    (English, SourceLabel) => "Source"
    (SimplifiedChinese, SourceLabel) => "源码"
    (TraditionalChinese, SourceLabel) => "原始碼"
    (Japanese, SourceLabel) => "ソース"
    (English, FilenameLabel) => "Filename"
    (SimplifiedChinese, FilenameLabel) => "文件名"
    (TraditionalChinese, FilenameLabel) => "檔名"
    (Japanese, FilenameLabel) => "ファイル名"
    (English, ChangeLabel) => "Change"
    (SimplifiedChinese, ChangeLabel) => "更改"
    (TraditionalChinese, ChangeLabel) => "更改"
    (Japanese, ChangeLabel) => "変更"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (TraditionalChinese, ChangesLabel) => "更改"
    (Japanese, ChangesLabel) => "変更"
    (English, ReadFiles) => "Read files"
    (SimplifiedChinese, ReadFiles) => "读取文件"
    (TraditionalChinese, ReadFiles) => "讀取檔案"
    (Japanese, ReadFiles) => "ファイルを読み取り"
    (English, EditFiles) => "Edit files"
    (SimplifiedChinese, EditFiles) => "编辑文件"
    (TraditionalChinese, EditFiles) => "編輯檔案"
    (Japanese, EditFiles) => "ファイルを編集"
    (English, WriteFiles) => "Write files"
    (SimplifiedChinese, WriteFiles) => "写入文件"
    (TraditionalChinese, WriteFiles) => "寫入檔案"
    (Japanese, WriteFiles) => "ファイルに書き込み"
    (English, RemoveFiles) => "Remove files"
    (SimplifiedChinese, RemoveFiles) => "移除文件"
    (TraditionalChinese, RemoveFiles) => "移除檔案"
    (Japanese, RemoveFiles) => "ファイルを削除"
    (English, ExecuteMbtx) => "Execute mbtx scripts"
    (SimplifiedChinese, ExecuteMbtx) => "执行 mbtx 脚本"
    (TraditionalChinese, ExecuteMbtx) => "執行 mbtx 指令碼"
    (Japanese, ExecuteMbtx) => "mbtx スクリプトを実行"
    (English, ExecuteCommands) => "Execute commands"
    (SimplifiedChinese, ExecuteCommands) => "执行命令"
    (TraditionalChinese, ExecuteCommands) => "執行命令"
    (Japanese, ExecuteCommands) => "コマンドを実行"
    (English, SearchWeb) => "Search the web"
    (SimplifiedChinese, SearchWeb) => "搜索网络"
    (TraditionalChinese, SearchWeb) => "搜尋網路"
    (Japanese, SearchWeb) => "ウェブを検索"
    (English, ViewImages) => "View images"
    (SimplifiedChinese, ViewImages) => "查看图片"
    (TraditionalChinese, ViewImages) => "檢視圖片"
    (Japanese, ViewImages) => "画像を表示"
    (English, GenerateImages) => "Generate images"
    (SimplifiedChinese, GenerateImages) => "生成图片"
    (TraditionalChinese, GenerateImages) => "生成圖片"
    (Japanese, GenerateImages) => "画像を生成"
    (English, ReviewCode) => "Review code"
    (SimplifiedChinese, ReviewCode) => "审阅代码"
    (TraditionalChinese, ReviewCode) => "審閱程式碼"
    (Japanese, ReviewCode) => "コードをレビュー"
    (English, CreateSubagents) => "Create subagents"
    (SimplifiedChinese, CreateSubagents) => "创建子智能体"
    (TraditionalChinese, CreateSubagents) => "建立子代理程式"
    (Japanese, CreateSubagents) => "サブエージェントを作成"
    (English, WaitSubagents) => "Wait for subagents"
    (SimplifiedChinese, WaitSubagents) => "等待子智能体"
    (TraditionalChinese, WaitSubagents) => "等待子代理程式"
    (Japanese, WaitSubagents) => "サブエージェントを待機"
    (English, SendSubagents) => "Send messages to subagents"
    (SimplifiedChinese, SendSubagents) => "向子智能体发送消息"
    (TraditionalChinese, SendSubagents) => "向子代理程式傳送訊息"
    (Japanese, SendSubagents) =>
      "サブエージェントにメッセージを送信"
    (English, ResumeSubagents) => "Resume subagents"
    (SimplifiedChinese, ResumeSubagents) => "恢复子智能体"
    (TraditionalChinese, ResumeSubagents) => "恢復子代理程式"
    (Japanese, ResumeSubagents) => "サブエージェントを再開"
    (English, AssignSubagents) => "Assign subagent tasks"
    (SimplifiedChinese, AssignSubagents) => "分配子智能体任务"
    (TraditionalChinese, AssignSubagents) => "分配子代理程式任務"
    (Japanese, AssignSubagents) =>
      "サブエージェントにタスクを割り当て"
    (English, StopSubagents) => "Stop subagents"
    (SimplifiedChinese, StopSubagents) => "停止子智能体"
    (TraditionalChinese, StopSubagents) => "停止子代理程式"
    (Japanese, StopSubagents) => "サブエージェントを停止"
    (English, CloseSubagents) => "Close subagents"
    (SimplifiedChinese, CloseSubagents) => "关闭子智能体"
    (TraditionalChinese, CloseSubagents) => "關閉子代理程式"
    (Japanese, CloseSubagents) => "サブエージェントを閉じる"
    (English, ListSubagents) => "List subagents"
    (SimplifiedChinese, ListSubagents) => "列出子智能体"
    (TraditionalChinese, ListSubagents) => "列出子代理程式"
    (Japanese, ListSubagents) => "サブエージェント一覧"
    (English, SubmitResults) => "Submit results"
    (SimplifiedChinese, SubmitResults) => "提交结果"
    (TraditionalChinese, SubmitResults) => "提交結果"
    (Japanese, SubmitResults) => "結果を送信"
    (English, SubmitReviews) => "Submit reviews"
    (SimplifiedChinese, SubmitReviews) => "提交审阅"
    (TraditionalChinese, SubmitReviews) => "提交審閱"
    (Japanese, SubmitReviews) => "レビューを送信"
    (English, UpdatePlan) => "Update plan"
    (SimplifiedChinese, UpdatePlan) => "更新计划"
    (TraditionalChinese, UpdatePlan) => "更新計劃"
    (Japanese, UpdatePlan) => "計画を更新"
    (English, UpdateGoal) => "Update goal"
    (SimplifiedChinese, UpdateGoal) => "更新目标"
    (TraditionalChinese, UpdateGoal) => "更新目標"
    (Japanese, UpdateGoal) => "目標を更新"
    (English, OtherTools) => "Other tool calls"
    (SimplifiedChinese, OtherTools) => "其他工具调用"
    (TraditionalChinese, OtherTools) => "其他工具呼叫"
    (Japanese, OtherTools) => "その他のツール呼び出し"
    (English, AssistantLabel) => "Assistant"
    (SimplifiedChinese, AssistantLabel) => "助手"
    (TraditionalChinese, AssistantLabel) => "助手"
    (Japanese, AssistantLabel) => "アシスタント"
    (English, ContextSummary) => "Context summary"
    (SimplifiedChinese, ContextSummary) => "上下文摘要"
    (TraditionalChinese, ContextSummary) => "上下文摘要"
    (Japanese, ContextSummary) => "コンテキストの要約"
    (English, WorkCompleted) => "Work completed"
    (SimplifiedChinese, WorkCompleted) => "工作已完成"
    (TraditionalChinese, WorkCompleted) => "工作已完成"
    (Japanese, WorkCompleted) => "作業が完了しました"
    (English, ViewActivity) => "View activity"
    (SimplifiedChinese, ViewActivity) => "查看活动"
    (TraditionalChinese, ViewActivity) => "檢視活動"
    (Japanese, ViewActivity) => "アクティビティを表示"
    (English, RequestedChanges) => "Requested changes"
    (SimplifiedChinese, RequestedChanges) => "请求的更改"
    (TraditionalChinese, RequestedChanges) => "請求的更改"
    (Japanese, RequestedChanges) => "要求された変更"
  }
}
