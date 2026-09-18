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
    (TraditionalChinese, Connecting) => "Codex — 正在連線…"
    (Japanese, Connecting) => "Codex — 接続中…"
    (English, Unavailable) => "Codex unavailable"
    (SimplifiedChinese, Unavailable) => "Codex 不可用"
    (TraditionalChinese, Unavailable) => "Codex 不可用"
    (Japanese, Unavailable) => "Codex は利用できません"
    (English, SignIn) => "Sign in to Codex…"
    (SimplifiedChinese, SignIn) => "登录 Codex…"
    (TraditionalChinese, SignIn) => "登入 Codex…"
    (Japanese, SignIn) => "Codex にログイン…"
    (English, LoadingModels) => "Codex — loading models…"
    (SimplifiedChinese, LoadingModels) => "Codex — 正在加载模型…"
    (TraditionalChinese, LoadingModels) => "Codex — 正在載入模型…"
    (Japanese, LoadingModels) => "Codex — モデルを読み込み中…"
    (English, CommandLabel) => "Command"
    (SimplifiedChinese, CommandLabel) => "命令"
    (TraditionalChinese, CommandLabel) => "命令"
    (Japanese, CommandLabel) => "コマンド"
    (English, FileChanges) => "File changes"
    (SimplifiedChinese, FileChanges) => "文件更改"
    (TraditionalChinese, FileChanges) => "檔案更改"
    (Japanese, FileChanges) => "ファイルの変更"
    (English, WebSearch) => "Web search: "
    (SimplifiedChinese, WebSearch) => "网页搜索："
    (TraditionalChinese, WebSearch) => "網頁搜尋："
    (Japanese, WebSearch) => "ウェブ検索："
    (English, ViewedImagePrefix) => "Viewed image: "
    (SimplifiedChinese, ViewedImagePrefix) => "已查看图片："
    (TraditionalChinese, ViewedImagePrefix) => "已檢視圖片："
    (Japanese, ViewedImagePrefix) => "表示した画像："
    (English, Compacted) => "Compacted conversation context"
    (SimplifiedChinese, Compacted) => "已压缩对话上下文"
    (TraditionalChinese, Compacted) => "已壓縮對話上下文"
    (Japanese, Compacted) =>
      "チャットのコンテキストを圧縮しました"
    (English, ChangedFiles) => "Changed files"
    (SimplifiedChinese, ChangedFiles) => "已更改文件"
    (TraditionalChinese, ChangedFiles) => "已更改檔案"
    (Japanese, ChangedFiles) => "変更したファイル"
    (English, SearchedWeb) => "Searched the web"
    (SimplifiedChinese, SearchedWeb) => "已搜索网页"
    (TraditionalChinese, SearchedWeb) => "已搜尋網頁"
    (Japanese, SearchedWeb) => "ウェブを検索しました"
    (English, ViewedImage) => "Viewed image"
    (SimplifiedChinese, ViewedImage) => "已查看图片"
    (TraditionalChinese, ViewedImage) => "已檢視圖片"
    (Japanese, ViewedImage) => "画像を表示しました"
    (English, GenerateImage) => "Generate image"
    (SimplifiedChinese, GenerateImage) => "生成图片"
    (TraditionalChinese, GenerateImage) => "生成圖片"
    (Japanese, GenerateImage) => "画像を生成"
    (English, WaitLabel) => "Wait"
    (SimplifiedChinese, WaitLabel) => "等待"
    (TraditionalChinese, WaitLabel) => "等待"
    (Japanese, WaitLabel) => "待機"
    (English, EnteredReview) => "Entered review mode"
    (SimplifiedChinese, EnteredReview) => "已进入审阅模式"
    (TraditionalChinese, EnteredReview) => "已進入審閱模式"
    (Japanese, EnteredReview) => "レビューモードに入りました"
    (English, ExitedReview) => "Exited review mode"
    (SimplifiedChinese, ExitedReview) => "已退出审阅模式"
    (TraditionalChinese, ExitedReview) => "已退出審閱模式"
    (Japanese, ExitedReview) => "レビューモードを終了しました"
    (English, CreateSubagent) => "Create subagent"
    (SimplifiedChinese, CreateSubagent) => "创建子智能体"
    (TraditionalChinese, CreateSubagent) => "建立子代理程式"
    (Japanese, CreateSubagent) => "サブエージェントを作成"
    (English, WaitSubagents) => "Wait for subagents"
    (SimplifiedChinese, WaitSubagents) => "等待子智能体"
    (TraditionalChinese, WaitSubagents) => "等待子代理程式"
    (Japanese, WaitSubagents) => "サブエージェントを待機"
    (English, SendSubagent) => "Send message to subagent"
    (SimplifiedChinese, SendSubagent) => "向子智能体发送消息"
    (TraditionalChinese, SendSubagent) => "向子代理程式傳送訊息"
    (Japanese, SendSubagent) =>
      "サブエージェントにメッセージを送信"
    (English, ResumeSubagent) => "Resume subagent"
    (SimplifiedChinese, ResumeSubagent) => "恢复子智能体"
    (TraditionalChinese, ResumeSubagent) => "恢復子代理程式"
    (Japanese, ResumeSubagent) => "サブエージェントを再開"
    (English, AssignSubagent) => "Assign subagent task"
    (SimplifiedChinese, AssignSubagent) => "分配子智能体任务"
    (TraditionalChinese, AssignSubagent) => "分配子代理程式任務"
    (Japanese, AssignSubagent) =>
      "サブエージェントにタスクを割り当て"
    (English, StopSubagent) => "Stop subagent"
    (SimplifiedChinese, StopSubagent) => "停止子智能体"
    (TraditionalChinese, StopSubagent) => "停止子代理程式"
    (Japanese, StopSubagent) => "サブエージェントを停止"
    (English, CloseSubagent) => "Close subagent"
    (SimplifiedChinese, CloseSubagent) => "关闭子智能体"
    (TraditionalChinese, CloseSubagent) => "關閉子代理程式"
    (Japanese, CloseSubagent) => "サブエージェントを閉じる"
    (English, ListSubagents) => "List subagents"
    (SimplifiedChinese, ListSubagents) => "列出子智能体"
    (TraditionalChinese, ListSubagents) => "列出子代理程式"
    (Japanese, ListSubagents) => "サブエージェント一覧"
  }
}
