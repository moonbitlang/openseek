// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  ReasoningPrefix
  NewChat
  RestoreCodex
  ArchiveCodex
  UnknownLabel
  NoMatchingPr
  HideTerminal
  ShowTerminal
  TerminalPlacement
  ShowFiles
  FilesDirectory
  EnableFullCodex
  EnableFullQuestion
  FullAccessWarning
  CancelLabel
  EnableFullAccess
  CompactContext
  ReviewChanges
  SteerPlaceholder
  RebuildWorktree
  AskCodex
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, ReasoningPrefix) => "Reasoning effort: "
    (Spanish, ReasoningPrefix) => "Esfuerzo de razonamiento: "
    (SimplifiedChinese, ReasoningPrefix) => "推理强度："
    (TraditionalChinese, ReasoningPrefix) => "推理強度："
    (Japanese, ReasoningPrefix) => "推論の強度："
    (English, NewChat) => "New chat"
    (Spanish, NewChat) => "Nueva conversación"
    (SimplifiedChinese, NewChat) => "新建对话"
    (TraditionalChinese, NewChat) => "新建對話"
    (Japanese, NewChat) => "新しいチャット"
    (English, RestoreCodex) => "Restore this Codex conversation to the sidebar"
    (Spanish, RestoreCodex) =>
      "Restaurar esta conversación de Codex en la barra lateral"
    (SimplifiedChinese, RestoreCodex) => "将此 Codex 对话恢复到侧边栏"
    (TraditionalChinese, RestoreCodex) =>
      "將此 Codex 對話恢復到側邊欄"
    (Japanese, RestoreCodex) =>
      "この Codex チャットをサイドバーに復元"
    (English, ArchiveCodex) => "Archive Codex conversation"
    (Spanish, ArchiveCodex) => "Archivar conversación de Codex"
    (SimplifiedChinese, ArchiveCodex) => "归档 Codex 对话"
    (TraditionalChinese, ArchiveCodex) => "歸檔 Codex 對話"
    (Japanese, ArchiveCodex) => "Codex チャットをアーカイブ"
    (English, UnknownLabel) => "Unknown"
    (Spanish, UnknownLabel) => "Desconocido"
    (SimplifiedChinese, UnknownLabel) => "未知"
    (TraditionalChinese, UnknownLabel) => "未知"
    (Japanese, UnknownLabel) => "不明"
    (English, NoMatchingPr) => "No matching pull request"
    (Spanish, NoMatchingPr) => "No hay ninguna solicitud de cambios coincidente"
    (SimplifiedChinese, NoMatchingPr) => "没有匹配的拉取请求"
    (TraditionalChinese, NoMatchingPr) => "沒有匹配的拉取請求"
    (Japanese, NoMatchingPr) =>
      "一致するプルリクエストはありません"
    (English, HideTerminal) => "Hide terminal"
    (Spanish, HideTerminal) => "Ocultar terminal"
    (SimplifiedChinese, HideTerminal) => "隐藏终端"
    (TraditionalChinese, HideTerminal) => "隱藏終端"
    (Japanese, HideTerminal) => "ターミナルを非表示"
    (English, ShowTerminal) => "Show terminal"
    (Spanish, ShowTerminal) => "Mostrar terminal"
    (SimplifiedChinese, ShowTerminal) => "显示终端"
    (TraditionalChinese, ShowTerminal) => "顯示終端"
    (Japanese, ShowTerminal) => "ターミナルを表示"
    (English, TerminalPlacement) =>
      "Terminal requires an available Codex task placement"
    (Spanish, TerminalPlacement) =>
      "La terminal requiere una ubicación disponible para la tarea de Codex"
    (SimplifiedChinese, TerminalPlacement) =>
      "终端需要可用的 Codex 任务运行目录"
    (TraditionalChinese, TerminalPlacement) =>
      "終端需要可用的 Codex 任務執行目錄"
    (Japanese, TerminalPlacement) =>
      "ターミナルには有効な Codex タスクの作業ディレクトリが必要です"
    (English, ShowFiles) => "Show files"
    (Spanish, ShowFiles) => "Mostrar archivos"
    (SimplifiedChinese, ShowFiles) => "显示文件"
    (TraditionalChinese, ShowFiles) => "顯示檔案"
    (Japanese, ShowFiles) => "ファイルを表示"
    (English, FilesDirectory) => "Files require a Codex working directory"
    (Spanish, FilesDirectory) =>
      "Los archivos requieren un directorio de trabajo de Codex"
    (SimplifiedChinese, FilesDirectory) =>
      "文件视图需要 Codex 工作目录"
    (TraditionalChinese, FilesDirectory) =>
      "檔案檢視需要 Codex 工作目錄"
    (Japanese, FilesDirectory) =>
      "ファイル表示には Codex の作業ディレクトリが必要です"
    (English, EnableFullCodex) => "Enable full Codex access"
    (Spanish, EnableFullCodex) => "Habilitar acceso completo para Codex"
    (SimplifiedChinese, EnableFullCodex) => "启用 Codex 完全访问权限"
    (TraditionalChinese, EnableFullCodex) =>
      "啟用 Codex 完全訪問許可權"
    (Japanese, EnableFullCodex) => "Codex のフルアクセスを有効化"
    (English, EnableFullQuestion) => "Enable full access?"
    (Spanish, EnableFullQuestion) => "¿Habilitar acceso completo?"
    (SimplifiedChinese, EnableFullQuestion) => "启用完全访问权限？"
    (TraditionalChinese, EnableFullQuestion) => "啟用完全訪問許可權？"
    (Japanese, EnableFullQuestion) =>
      "フルアクセスを有効にしますか？"
    (English, FullAccessWarning) =>
      "Codex will be able to access the internet and read or modify any file on this computer without asking. Approve for me is safer because it keeps the workspace sandbox in place."
    (Spanish, FullAccessWarning) =>
      "Codex podrá acceder a Internet y leer o modificar cualquier archivo de este equipo sin preguntar. Aprobar por mí es más seguro porque mantiene el aislamiento del espacio de trabajo."
    (SimplifiedChinese, FullAccessWarning) =>
      "Codex 将能够无需询问就访问互联网、读取或修改此电脑上的任何文件。“代我审批”会保留工作区沙盒，因此更加安全。"
    (TraditionalChinese, FullAccessWarning) =>
      "Codex 將能夠無需詢問就訪問網際網路、讀取或修改此電腦上的任何檔案。“代我審批”會保留工作區沙盒，因此更加安全。"
    (Japanese, FullAccessWarning) =>
      "Codex は確認なしにインターネットにアクセスし、このコンピューター上のすべてのファイルを読み取り・変更できるようになります。「代理で承認」はワークスペースのサンドボックスを維持するため、より安全です。"
    (English, CancelLabel) => "Cancel"
    (Spanish, CancelLabel) => "Cancelar"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, EnableFullAccess) => "Enable full access"
    (Spanish, EnableFullAccess) => "Habilitar acceso completo"
    (SimplifiedChinese, EnableFullAccess) => "启用完全访问权限"
    (TraditionalChinese, EnableFullAccess) => "啟用完全訪問許可權"
    (Japanese, EnableFullAccess) => "フルアクセスを有効化"
    (English, CompactContext) =>
      "Summarize and shrink this conversation's context"
    (Spanish, CompactContext) =>
      "Resumir y reducir el contexto de esta conversación"
    (SimplifiedChinese, CompactContext) =>
      "总结并压缩此对话的上下文"
    (TraditionalChinese, CompactContext) =>
      "總結並壓縮此對話的上下文"
    (Japanese, CompactContext) =>
      "このチャットのコンテキストを要約・圧縮"
    (English, ReviewChanges) => "Review staged, unstaged, and untracked changes"
    (Spanish, ReviewChanges) =>
      "Revisar cambios preparados, sin preparar y archivos sin seguimiento"
    (SimplifiedChinese, ReviewChanges) =>
      "审阅已暂存、未暂存和未跟踪的更改"
    (TraditionalChinese, ReviewChanges) =>
      "審閱已暫存、未暫存和未跟蹤的更改"
    (Japanese, ReviewChanges) =>
      "ステージ済み・未ステージ・未追跡の変更をレビュー"
    (English, SteerPlaceholder) =>
      "Steer the running task — your message joins it at the next step."
    (Spanish, SteerPlaceholder) =>
      "Orientar la tarea en curso: tu mensaje se incorporará en el siguiente paso."
    (SimplifiedChinese, SteerPlaceholder) =>
      "引导正在运行的任务，消息将在下一步加入。"
    (TraditionalChinese, SteerPlaceholder) =>
      "引導正在執行的任務，訊息將在下一步加入。"
    (Japanese, SteerPlaceholder) =>
      "実行中のタスクに指示します。メッセージは次のステップで追加されます。"
    (English, RebuildWorktree) =>
      "Rebuild this task's worktree before continuing."
    (Spanish, RebuildWorktree) =>
      "Reconstruir el worktree de esta tarea antes de continuar."
    (SimplifiedChinese, RebuildWorktree) =>
      "重建此任务的工作树后才能继续。"
    (TraditionalChinese, RebuildWorktree) =>
      "重建此任務的工作樹後才能繼續。"
    (Japanese, RebuildWorktree) =>
      "続行するには、このタスクのワークツリーを再作成してください。"
    (English, AskCodex) =>
      "Ask Codex to inspect, edit, or explain this workspace."
    (Spanish, AskCodex) =>
      "Pide a Codex que examine, edite o explique este espacio de trabajo."
    (SimplifiedChinese, AskCodex) =>
      "让 Codex 检查、编辑或解释此工作区。"
    (TraditionalChinese, AskCodex) =>
      "讓 Codex 檢查、編輯或解釋此工作區。"
    (Japanese, AskCodex) =>
      "このワークスペースの調査・編集・説明を Codex に依頼。"
  }
}
