// Feature-owned UI messages; all locales are exhaustive.

///|
pub(all) enum Message {
  ReadonlyCode
  ReadonlyMarkdown
  TableOfContents
  ItemSeparator
  ExpandSection
  CollapseSection
  FileComparison
  OriginalFile
  ModifiedFile
  ResizeDiffPanes
  CannotComputeDiff
  InvalidDiff
  EditorContextMenu
  ShowContextMenu
  PeekLabel
  GoDefinition
  PeekDefinition
  GoReferences
  PeekReferences
  NoDefinition
  NoDefinitions
  NoReferences
  CannotOpenDefinition
  CannotOpenReference
  NoPreview
  OriginalSource
  ShowSource
  ShowDocumentation
  CollapseDocumentation
  ExpandDocumentation
  LoadingLabel
  LoadingPreview
  DefinitionsLabel
  ReferencesLabel
  DefinitionPreview
  ReferencePreview
  LoadingDefinitions
  LoadingReferences
  CopyLabel
  NoResults
  AddFeedback
  FeedbackLabel
  CancelFeedback
  CancelLabel
  AddFeedbackBatch
  ApplyFeedbackShortcut
  ApplyFeedback
  CollapseLabel
  ExpandLabel
  AgentReview
  AddToComment
  EditLabel
  RemoveLabel
  ShareComment
  AcceptLabel
  RemoveComment
  DeleteLabel
  AddComment
}

///|
pub fn text(locale : Language, message : Message) -> String {
  match (locale, message) {
    (English, ReadonlyCode) => "Readonly code viewer"
    (Spanish, ReadonlyCode) => "Visor de código de solo lectura"
    (SimplifiedChinese, ReadonlyCode) => "只读代码查看器"
    (TraditionalChinese, ReadonlyCode) => "唯讀程式碼檢視器"
    (Japanese, ReadonlyCode) => "読み取り専用コードビューアー"
    (English, ReadonlyMarkdown) => "Readonly Markdown viewer"
    (Spanish, ReadonlyMarkdown) => "Visor de Markdown de solo lectura"
    (SimplifiedChinese, ReadonlyMarkdown) => "只读 Markdown 查看器"
    (TraditionalChinese, ReadonlyMarkdown) => "唯讀 Markdown 檢視器"
    (Japanese, ReadonlyMarkdown) =>
      "読み取り専用 Markdown ビューアー"
    (English, TableOfContents) => "Table of contents"
    (Spanish, TableOfContents) => "Tabla de contenido"
    (SimplifiedChinese, TableOfContents) => "目录"
    (TraditionalChinese, TableOfContents) => "目錄"
    (Japanese, TableOfContents) => "目次"
    (English, ItemSeparator) => "MoonBit item separator"
    (Spanish, ItemSeparator) => "Separador de elementos de MoonBit"
    (SimplifiedChinese, ItemSeparator) => "MoonBit 项目分隔线"
    (TraditionalChinese, ItemSeparator) => "MoonBit 項目分隔線"
    (Japanese, ItemSeparator) => "MoonBit 項目の区切り"
    (English, ExpandSection) => "Expand section"
    (Spanish, ExpandSection) => "Expandir sección"
    (SimplifiedChinese, ExpandSection) => "展开章节"
    (TraditionalChinese, ExpandSection) => "展開章節"
    (Japanese, ExpandSection) => "セクションを展開"
    (English, CollapseSection) => "Collapse section"
    (Spanish, CollapseSection) => "Contraer sección"
    (SimplifiedChinese, CollapseSection) => "折叠章节"
    (TraditionalChinese, CollapseSection) => "摺疊章節"
    (Japanese, CollapseSection) => "セクションを折りたたむ"
    (English, FileComparison) => "File comparison"
    (Spanish, FileComparison) => "Comparación de archivos"
    (SimplifiedChinese, FileComparison) => "文件比较"
    (TraditionalChinese, FileComparison) => "檔案比較"
    (Japanese, FileComparison) => "ファイル比較"
    (English, OriginalFile) => "Original file"
    (Spanish, OriginalFile) => "Archivo original"
    (SimplifiedChinese, OriginalFile) => "原始文件"
    (TraditionalChinese, OriginalFile) => "原始檔案"
    (Japanese, OriginalFile) => "元のファイル"
    (English, ModifiedFile) => "Modified file"
    (Spanish, ModifiedFile) => "Archivo modificado"
    (SimplifiedChinese, ModifiedFile) => "修改后的文件"
    (TraditionalChinese, ModifiedFile) => "修改後的檔案"
    (Japanese, ModifiedFile) => "変更後のファイル"
    (English, ResizeDiffPanes) => "Resize diff panes"
    (Spanish, ResizeDiffPanes) =>
      "Ajustar tamaño de los paneles de diferencias"
    (SimplifiedChinese, ResizeDiffPanes) => "调整差异窗格大小"
    (TraditionalChinese, ResizeDiffPanes) => "調整差異窗格大小"
    (Japanese, ResizeDiffPanes) => "差分ペインのサイズを変更"
    (English, CannotComputeDiff) => "Unable to compute this diff."
    (Spanish, CannotComputeDiff) => "No se pudieron calcular estas diferencias."
    (SimplifiedChinese, CannotComputeDiff) => "无法计算此差异。"
    (TraditionalChinese, CannotComputeDiff) => "無法計算此差異。"
    (Japanese, CannotComputeDiff) => "この差分を計算できません。"
    (English, InvalidDiff) => "The diff provider returned an invalid result."
    (Spanish, InvalidDiff) =>
      "El proveedor de diferencias devolvió un resultado no válido."
    (SimplifiedChinese, InvalidDiff) =>
      "差异提供程序返回了无效结果。"
    (TraditionalChinese, InvalidDiff) =>
      "差異提供程式返回了無效結果。"
    (Japanese, InvalidDiff) =>
      "差分プロバイダーが無効な結果を返しました。"
    (English, EditorContextMenu) => "Editor Context Menu"
    (Spanish, EditorContextMenu) => "Menú contextual del editor"
    (SimplifiedChinese, EditorContextMenu) => "编辑器上下文菜单"
    (TraditionalChinese, EditorContextMenu) => "編輯器快顯選單"
    (Japanese, EditorContextMenu) =>
      "エディターのコンテキストメニュー"
    (English, ShowContextMenu) => "Show Editor Context Menu"
    (Spanish, ShowContextMenu) => "Mostrar menú contextual del editor"
    (SimplifiedChinese, ShowContextMenu) => "显示编辑器上下文菜单"
    (TraditionalChinese, ShowContextMenu) => "顯示編輯器快顯選單"
    (Japanese, ShowContextMenu) =>
      "エディターのコンテキストメニューを表示"
    (English, PeekLabel) => "Peek"
    (Spanish, PeekLabel) => "Vista rápida"
    (SimplifiedChinese, PeekLabel) => "速览"
    (TraditionalChinese, PeekLabel) => "速覽"
    (Japanese, PeekLabel) => "ピーク"
    (English, GoDefinition) => "Go to Definition"
    (Spanish, GoDefinition) => "Ir a la definición"
    (SimplifiedChinese, GoDefinition) => "转到定义"
    (TraditionalChinese, GoDefinition) => "轉到定義"
    (Japanese, GoDefinition) => "定義へ移動"
    (English, PeekDefinition) => "Peek Definition"
    (Spanish, PeekDefinition) => "Vista rápida de la definición"
    (SimplifiedChinese, PeekDefinition) => "速览定义"
    (TraditionalChinese, PeekDefinition) => "速覽定義"
    (Japanese, PeekDefinition) => "定義をピーク"
    (English, GoReferences) => "Go to References"
    (Spanish, GoReferences) => "Ir a las referencias"
    (SimplifiedChinese, GoReferences) => "转到引用"
    (TraditionalChinese, GoReferences) => "轉到引用"
    (Japanese, GoReferences) => "参照へ移動"
    (English, PeekReferences) => "Peek References"
    (Spanish, PeekReferences) => "Vista rápida de las referencias"
    (SimplifiedChinese, PeekReferences) => "速览引用"
    (TraditionalChinese, PeekReferences) => "速覽引用"
    (Japanese, PeekReferences) => "参照をピーク"
    (English, NoDefinition) => "No definition found"
    (Spanish, NoDefinition) => "No se encontró ninguna definición"
    (SimplifiedChinese, NoDefinition) => "未找到定义"
    (TraditionalChinese, NoDefinition) => "未找到定義"
    (Japanese, NoDefinition) => "定義が見つかりません"
    (English, NoDefinitions) => "No definitions found"
    (Spanish, NoDefinitions) => "No se encontraron definiciones"
    (SimplifiedChinese, NoDefinitions) => "未找到定义"
    (TraditionalChinese, NoDefinitions) => "未找到定義"
    (Japanese, NoDefinitions) => "定義が見つかりません"
    (English, NoReferences) => "No references found"
    (Spanish, NoReferences) => "No se encontraron referencias"
    (SimplifiedChinese, NoReferences) => "未找到引用"
    (TraditionalChinese, NoReferences) => "未找到引用"
    (Japanese, NoReferences) => "参照が見つかりません"
    (English, CannotOpenDefinition) => "Unable to open definition"
    (Spanish, CannotOpenDefinition) => "No se pudo abrir la definición"
    (SimplifiedChinese, CannotOpenDefinition) => "无法打开定义"
    (TraditionalChinese, CannotOpenDefinition) => "無法開啟定義"
    (Japanese, CannotOpenDefinition) => "定義を開けません"
    (English, CannotOpenReference) => "Unable to open reference"
    (Spanish, CannotOpenReference) => "No se pudo abrir la referencia"
    (SimplifiedChinese, CannotOpenReference) => "无法打开引用"
    (TraditionalChinese, CannotOpenReference) => "無法開啟引用"
    (Japanese, CannotOpenReference) => "参照を開けません"
    (English, NoPreview) => "No preview available"
    (Spanish, NoPreview) => "No hay vista previa disponible"
    (SimplifiedChinese, NoPreview) => "没有可用的预览"
    (TraditionalChinese, NoPreview) => "沒有可用的預覽"
    (Japanese, NoPreview) => "プレビューはありません"
    (English, OriginalSource) => "Original source"
    (Spanish, OriginalSource) => "Código fuente original"
    (SimplifiedChinese, OriginalSource) => "原始源码"
    (TraditionalChinese, OriginalSource) => "原始原始碼"
    (Japanese, OriginalSource) => "元のソース"
    (English, ShowSource) => "Show original source"
    (Spanish, ShowSource) => "Mostrar código fuente original"
    (SimplifiedChinese, ShowSource) => "显示原始源码"
    (TraditionalChinese, ShowSource) => "顯示原始原始碼"
    (Japanese, ShowSource) => "元のソースを表示"
    (English, ShowDocumentation) => "Show rendered documentation"
    (Spanish, ShowDocumentation) => "Mostrar documentación renderizada"
    (SimplifiedChinese, ShowDocumentation) => "显示渲染后的文档"
    (TraditionalChinese, ShowDocumentation) => "顯示渲染後的文件"
    (Japanese, ShowDocumentation) =>
      "レンダリングされたドキュメントを表示"
    (English, CollapseDocumentation) => "Collapse API documentation"
    (Spanish, CollapseDocumentation) => "Contraer documentación de la API"
    (SimplifiedChinese, CollapseDocumentation) => "折叠 API 文档"
    (TraditionalChinese, CollapseDocumentation) => "摺疊 API 文件"
    (Japanese, CollapseDocumentation) =>
      "API ドキュメントを折りたたむ"
    (English, ExpandDocumentation) => "Expand API documentation"
    (Spanish, ExpandDocumentation) => "Expandir documentación de la API"
    (SimplifiedChinese, ExpandDocumentation) => "展开 API 文档"
    (TraditionalChinese, ExpandDocumentation) => "展開 API 文件"
    (Japanese, ExpandDocumentation) => "API ドキュメントを展開"
    (English, LoadingLabel) => "Loading..."
    (Spanish, LoadingLabel) => "Cargando..."
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (TraditionalChinese, LoadingLabel) => "正在載入…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, LoadingPreview) => "Loading preview…"
    (Spanish, LoadingPreview) => "Cargando vista previa…"
    (SimplifiedChinese, LoadingPreview) => "正在加载预览…"
    (TraditionalChinese, LoadingPreview) => "正在載入預覽…"
    (Japanese, LoadingPreview) => "プレビューを読み込み中…"
    (English, DefinitionsLabel) => "Definitions"
    (Spanish, DefinitionsLabel) => "Definiciones"
    (SimplifiedChinese, DefinitionsLabel) => "定义"
    (TraditionalChinese, DefinitionsLabel) => "定義"
    (Japanese, DefinitionsLabel) => "定義"
    (English, ReferencesLabel) => "References"
    (Spanish, ReferencesLabel) => "Referencias"
    (SimplifiedChinese, ReferencesLabel) => "引用"
    (TraditionalChinese, ReferencesLabel) => "引用"
    (Japanese, ReferencesLabel) => "参照"
    (English, DefinitionPreview) => "Definition preview"
    (Spanish, DefinitionPreview) => "Vista previa de la definición"
    (SimplifiedChinese, DefinitionPreview) => "定义预览"
    (TraditionalChinese, DefinitionPreview) => "定義預覽"
    (Japanese, DefinitionPreview) => "定義のプレビュー"
    (English, ReferencePreview) => "Reference preview"
    (Spanish, ReferencePreview) => "Vista previa de la referencia"
    (SimplifiedChinese, ReferencePreview) => "引用预览"
    (TraditionalChinese, ReferencePreview) => "引用預覽"
    (Japanese, ReferencePreview) => "参照のプレビュー"
    (English, LoadingDefinitions) => "Loading definitions…"
    (Spanish, LoadingDefinitions) => "Cargando definiciones…"
    (SimplifiedChinese, LoadingDefinitions) => "正在加载定义…"
    (TraditionalChinese, LoadingDefinitions) => "正在載入定義…"
    (Japanese, LoadingDefinitions) => "定義を読み込み中…"
    (English, LoadingReferences) => "Loading references…"
    (Spanish, LoadingReferences) => "Cargando referencias…"
    (SimplifiedChinese, LoadingReferences) => "正在加载引用…"
    (TraditionalChinese, LoadingReferences) => "正在載入引用…"
    (Japanese, LoadingReferences) => "参照を読み込み中…"
    (English, CopyLabel) => "Copy"
    (Spanish, CopyLabel) => "Copiar"
    (SimplifiedChinese, CopyLabel) => "复制"
    (TraditionalChinese, CopyLabel) => "複製"
    (Japanese, CopyLabel) => "コピー"
    (English, NoResults) => "No results found"
    (Spanish, NoResults) => "No se encontraron resultados"
    (SimplifiedChinese, NoResults) => "未找到结果"
    (TraditionalChinese, NoResults) => "未找到結果"
    (Japanese, NoResults) => "結果が見つかりません"
    (English, AddFeedback) => "Add feedback"
    (Spanish, AddFeedback) => "Añadir comentario"
    (SimplifiedChinese, AddFeedback) => "添加反馈"
    (TraditionalChinese, AddFeedback) => "新增回饋"
    (Japanese, AddFeedback) => "フィードバックを追加"
    (English, FeedbackLabel) => "Feedback"
    (Spanish, FeedbackLabel) => "Comentarios"
    (SimplifiedChinese, FeedbackLabel) => "反馈"
    (TraditionalChinese, FeedbackLabel) => "回饋"
    (Japanese, FeedbackLabel) => "フィードバック"
    (English, CancelFeedback) => "Cancel feedback (Escape)"
    (Spanish, CancelFeedback) => "Cancelar comentario (Escape)"
    (SimplifiedChinese, CancelFeedback) => "取消反馈（Escape）"
    (TraditionalChinese, CancelFeedback) => "取消回饋（Escape）"
    (Japanese, CancelFeedback) =>
      "フィードバックをキャンセル（Escape）"
    (English, CancelLabel) => "Cancel"
    (Spanish, CancelLabel) => "Cancelar"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, AddFeedbackBatch) => "Add feedback to the batch (Enter)"
    (Spanish, AddFeedbackBatch) => "Añadir comentario al lote (Enter)"
    (SimplifiedChinese, AddFeedbackBatch) => "将反馈加入批次（Enter）"
    (TraditionalChinese, AddFeedbackBatch) => "將回饋加入批次（Enter）"
    (Japanese, AddFeedbackBatch) =>
      "フィードバックをまとめて追加（Enter）"
    (English, ApplyFeedbackShortcut) => "Apply all feedback (Alt+Enter)"
    (Spanish, ApplyFeedbackShortcut) =>
      "Aplicar todos los comentarios (Alt+Enter)"
    (SimplifiedChinese, ApplyFeedbackShortcut) =>
      "应用所有反馈（Alt+Enter）"
    (TraditionalChinese, ApplyFeedbackShortcut) =>
      "套用所有回饋（Alt+Enter）"
    (Japanese, ApplyFeedbackShortcut) =>
      "すべてのフィードバックを適用（Alt+Enter）"
    (English, ApplyFeedback) => "Apply all feedback"
    (Spanish, ApplyFeedback) => "Aplicar todos los comentarios"
    (SimplifiedChinese, ApplyFeedback) => "应用所有反馈"
    (TraditionalChinese, ApplyFeedback) => "套用所有回饋"
    (Japanese, ApplyFeedback) => "すべてのフィードバックを適用"
    (English, CollapseLabel) => "Collapse"
    (Spanish, CollapseLabel) => "Contraer"
    (SimplifiedChinese, CollapseLabel) => "折叠"
    (TraditionalChinese, CollapseLabel) => "摺疊"
    (Japanese, CollapseLabel) => "折りたたむ"
    (English, ExpandLabel) => "Expand"
    (Spanish, ExpandLabel) => "Expandir"
    (SimplifiedChinese, ExpandLabel) => "展开"
    (TraditionalChinese, ExpandLabel) => "展開"
    (Japanese, ExpandLabel) => "展開"
    (English, AgentReview) => "Agent Review"
    (Spanish, AgentReview) => "Revisión del agente"
    (SimplifiedChinese, AgentReview) => "智能体审阅"
    (TraditionalChinese, AgentReview) => "代理程式審閱"
    (Japanese, AgentReview) => "エージェントレビュー"
    (English, AddToComment) => "Add to Comment"
    (Spanish, AddToComment) => "Añadir al comentario"
    (SimplifiedChinese, AddToComment) => "添加到评论"
    (TraditionalChinese, AddToComment) => "新增到評論"
    (Japanese, AddToComment) => "コメントに追加"
    (English, EditLabel) => "Edit"
    (Spanish, EditLabel) => "Editar"
    (SimplifiedChinese, EditLabel) => "编辑"
    (TraditionalChinese, EditLabel) => "編輯"
    (Japanese, EditLabel) => "編集"
    (English, RemoveLabel) => "Remove"
    (Spanish, RemoveLabel) => "Quitar"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (TraditionalChinese, RemoveLabel) => "移除"
    (Japanese, RemoveLabel) => "削除"
    (English, ShareComment) => "Share comment with agent"
    (Spanish, ShareComment) => "Compartir comentario con el agente"
    (SimplifiedChinese, ShareComment) => "与智能体分享评论"
    (TraditionalChinese, ShareComment) => "與代理程式分享評論"
    (Japanese, ShareComment) => "コメントをエージェントと共有"
    (English, AcceptLabel) => "Accept"
    (Spanish, AcceptLabel) => "Aceptar"
    (SimplifiedChinese, AcceptLabel) => "接受"
    (TraditionalChinese, AcceptLabel) => "接受"
    (Japanese, AcceptLabel) => "承認"
    (English, RemoveComment) => "Remove agent comment"
    (Spanish, RemoveComment) => "Quitar comentario del agente"
    (SimplifiedChinese, RemoveComment) => "移除智能体评论"
    (TraditionalChinese, RemoveComment) => "移除代理程式評論"
    (Japanese, RemoveComment) => "エージェントのコメントを削除"
    (English, DeleteLabel) => "Delete"
    (Spanish, DeleteLabel) => "Eliminar"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (TraditionalChinese, DeleteLabel) => "刪除"
    (Japanese, DeleteLabel) => "削除"
    (English, AddComment) => "Add a comment…"
    (Spanish, AddComment) => "Añadir un comentario…"
    (SimplifiedChinese, AddComment) => "添加评论…"
    (TraditionalChinese, AddComment) => "新增評論…"
    (Japanese, AddComment) => "コメントを追加…"
  }
}
