// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  SearchLabel
  TextSearch
  CodeSearch
  TextLabel
  CodeLabel
  MatchCase
  WholeWord
  RegularExpression
  RepairingPattern
  FixPattern
  PatternRepair
  NoHistory
  PatternInstruction
  RepairInstruction
  SubmitRepair
  SubmitLabel
  ThinkingLabel
  ValidationPassed
  ValidationUnavailable
  ValidationFailed
  ValidationUnknown
  SuggestedPattern
  RequiresValidation
  UsePattern
  DiscardLabel
  InvalidRegex
  InvalidGlob
  UnreadableWorkspace
  RipgrepUnavailable
  InvalidPattern
  SemanticUnavailable
  NothingToSearch
  SearchFailed
  NoMatches
  TextSearchDescription
  CodeSearchDescription
  ResultsCleared
  SearchingLabel
  ResultLimit
  IncompleteResults
  IncludeFiles
  ExcludeFiles
  IncludeExample
  ExcludeExample
  PatternLabel
  ToggleDetails
  RefreshLabel
  ClearResults
  ClearLabel
  CollapseAll
  NoCheckout
  OpenCheckoutDescription
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, SearchLabel) => "Search"
    (Spanish, SearchLabel) => "Buscar"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (TraditionalChinese, SearchLabel) => "搜尋"
    (Japanese, SearchLabel) => "検索"
    (English, TextSearch) => "Text search"
    (Spanish, TextSearch) => "Búsqueda de texto"
    (SimplifiedChinese, TextSearch) => "文本搜索"
    (TraditionalChinese, TextSearch) => "文字搜尋"
    (Japanese, TextSearch) => "テキスト検索"
    (English, CodeSearch) => "Code search"
    (Spanish, CodeSearch) => "Búsqueda de código"
    (SimplifiedChinese, CodeSearch) => "代码搜索"
    (TraditionalChinese, CodeSearch) => "程式碼搜尋"
    (Japanese, CodeSearch) => "コード検索"
    (English, TextLabel) => "Text"
    (Spanish, TextLabel) => "Texto"
    (SimplifiedChinese, TextLabel) => "文本"
    (TraditionalChinese, TextLabel) => "文字"
    (Japanese, TextLabel) => "テキスト"
    (English, CodeLabel) => "Code"
    (Spanish, CodeLabel) => "Código"
    (SimplifiedChinese, CodeLabel) => "代码"
    (TraditionalChinese, CodeLabel) => "程式碼"
    (Japanese, CodeLabel) => "コード"
    (English, MatchCase) => "Match Case"
    (Spanish, MatchCase) => "Distinguir mayúsculas y minúsculas"
    (SimplifiedChinese, MatchCase) => "区分大小写"
    (TraditionalChinese, MatchCase) => "區分大小寫"
    (Japanese, MatchCase) => "大文字と小文字を区別"
    (English, WholeWord) => "Match Whole Word"
    (Spanish, WholeWord) => "Solo palabras completas"
    (SimplifiedChinese, WholeWord) => "全字匹配"
    (TraditionalChinese, WholeWord) => "全字匹配"
    (Japanese, WholeWord) => "単語単位で一致"
    (English, RegularExpression) => "Use Regular Expression"
    (Spanish, RegularExpression) => "Usar expresión regular"
    (SimplifiedChinese, RegularExpression) => "使用正则表达式"
    (TraditionalChinese, RegularExpression) => "使用正規表示式"
    (Japanese, RegularExpression) => "正規表現を使用"
    (English, RepairingPattern) => "Pattern Repair in progress"
    (Spanish, RepairingPattern) => "Reparación de patrón en curso"
    (SimplifiedChinese, RepairingPattern) => "正在修复模式"
    (TraditionalChinese, RepairingPattern) => "正在修復模式"
    (Japanese, RepairingPattern) => "パターンを修正中"
    (English, FixPattern) => "Fix Pattern"
    (Spanish, FixPattern) => "Corregir patrón"
    (SimplifiedChinese, FixPattern) => "修复模式"
    (TraditionalChinese, FixPattern) => "修復模式"
    (Japanese, FixPattern) => "パターンを修正"
    (English, PatternRepair) => "PATTERN REPAIR"
    (Spanish, PatternRepair) => "REPARACIÓN DE PATRÓN"
    (SimplifiedChinese, PatternRepair) => "模式修复"
    (TraditionalChinese, PatternRepair) => "模式修復"
    (Japanese, PatternRepair) => "パターンの修正"
    (English, NoHistory) => "One request, no history"
    (Spanish, NoHistory) => "Una solicitud, sin historial"
    (SimplifiedChinese, NoHistory) => "单次请求，不保留历史"
    (TraditionalChinese, NoHistory) => "單次請求，不保留歷史"
    (Japanese, NoHistory) =>
      "単発のリクエスト、履歴は保持されません"
    (English, PatternInstruction) =>
      "What should this pattern match? e.g. allow labelled arguments"
    (Spanish, PatternInstruction) =>
      "¿Qué debe encontrar este patrón? Por ejemplo, permitir argumentos con etiqueta"
    (SimplifiedChinese, PatternInstruction) =>
      "此模式应匹配什么？例如：允许标签参数"
    (TraditionalChinese, PatternInstruction) =>
      "此模式應匹配什麼？例如：允許標籤引數"
    (Japanese, PatternInstruction) =>
      "何に一致するパターンですか？例：ラベル付き引数を許可"
    (English, RepairInstruction) => "Pattern repair instruction"
    (Spanish, RepairInstruction) => "Instrucción de reparación del patrón"
    (SimplifiedChinese, RepairInstruction) => "模式修复说明"
    (TraditionalChinese, RepairInstruction) => "模式修復說明"
    (Japanese, RepairInstruction) => "パターン修正の説明"
    (English, SubmitRepair) => "Submit pattern repair"
    (Spanish, SubmitRepair) => "Enviar reparación del patrón"
    (SimplifiedChinese, SubmitRepair) => "提交模式修复"
    (TraditionalChinese, SubmitRepair) => "提交模式修復"
    (Japanese, SubmitRepair) => "パターン修正を送信"
    (English, SubmitLabel) => "Submit"
    (Spanish, SubmitLabel) => "Enviar"
    (SimplifiedChinese, SubmitLabel) => "提交"
    (TraditionalChinese, SubmitLabel) => "提交"
    (Japanese, SubmitLabel) => "送信"
    (English, ThinkingLabel) => "Thinking"
    (Spanish, ThinkingLabel) => "Pensando"
    (SimplifiedChinese, ThinkingLabel) => "思考中"
    (TraditionalChinese, ThinkingLabel) => "思考中"
    (Japanese, ThinkingLabel) => "思考中"
    (English, ValidationPassed) => "Validation passed"
    (Spanish, ValidationPassed) => "Validación superada"
    (SimplifiedChinese, ValidationPassed) => "验证通过"
    (TraditionalChinese, ValidationPassed) => "驗證透過"
    (Japanese, ValidationPassed) => "検証済み"
    (English, ValidationUnavailable) => "Validation unavailable"
    (Spanish, ValidationUnavailable) => "Validación no disponible"
    (SimplifiedChinese, ValidationUnavailable) => "验证不可用"
    (TraditionalChinese, ValidationUnavailable) => "驗證不可用"
    (Japanese, ValidationUnavailable) => "検証できません"
    (English, ValidationFailed) => "Validation failed"
    (Spanish, ValidationFailed) => "Validación fallida"
    (SimplifiedChinese, ValidationFailed) => "验证失败"
    (TraditionalChinese, ValidationFailed) => "驗證失敗"
    (Japanese, ValidationFailed) => "検証に失敗しました"
    (English, ValidationUnknown) => "Validation status unknown"
    (Spanish, ValidationUnknown) => "Estado de validación desconocido"
    (SimplifiedChinese, ValidationUnknown) => "验证状态未知"
    (TraditionalChinese, ValidationUnknown) => "驗證狀態未知"
    (Japanese, ValidationUnknown) => "検証状態が不明です"
    (English, SuggestedPattern) => "SUGGESTED PATTERN"
    (Spanish, SuggestedPattern) => "PATRÓN SUGERIDO"
    (SimplifiedChinese, SuggestedPattern) => "建议的模式"
    (TraditionalChinese, SuggestedPattern) => "建議的模式"
    (Japanese, SuggestedPattern) => "提案されたパターン"
    (English, RequiresValidation) =>
      "This candidate cannot be applied until validation passes."
    (Spanish, RequiresValidation) =>
      "No se puede aplicar este candidato hasta que supere la validación."
    (SimplifiedChinese, RequiresValidation) =>
      "通过验证后才能应用此候选模式。"
    (TraditionalChinese, RequiresValidation) =>
      "透過驗證後才能應用此候選模式。"
    (Japanese, RequiresValidation) =>
      "検証に成功した候補のみ適用できます。"
    (English, UsePattern) => "Use pattern"
    (Spanish, UsePattern) => "Usar patrón"
    (SimplifiedChinese, UsePattern) => "使用此模式"
    (TraditionalChinese, UsePattern) => "使用此模式"
    (Japanese, UsePattern) => "このパターンを使用"
    (English, DiscardLabel) => "Discard"
    (Spanish, DiscardLabel) => "Descartar"
    (SimplifiedChinese, DiscardLabel) => "放弃"
    (TraditionalChinese, DiscardLabel) => "放棄"
    (Japanese, DiscardLabel) => "破棄"
    (English, InvalidRegex) => "Invalid regular expression"
    (Spanish, InvalidRegex) => "Expresión regular no válida"
    (SimplifiedChinese, InvalidRegex) => "正则表达式无效"
    (TraditionalChinese, InvalidRegex) => "正規表示式無效"
    (Japanese, InvalidRegex) => "無効な正規表現"
    (English, InvalidGlob) => "Invalid file pattern"
    (Spanish, InvalidGlob) => "Patrón de archivo no válido"
    (SimplifiedChinese, InvalidGlob) => "文件匹配模式无效"
    (TraditionalChinese, InvalidGlob) => "檔案匹配模式無效"
    (Japanese, InvalidGlob) => "無効なファイルパターン"
    (English, UnreadableWorkspace) => "Workspace is not readable"
    (Spanish, UnreadableWorkspace) => "No se puede leer el espacio de trabajo"
    (SimplifiedChinese, UnreadableWorkspace) => "无法读取工作区"
    (TraditionalChinese, UnreadableWorkspace) => "無法讀取工作區"
    (Japanese, UnreadableWorkspace) =>
      "ワークスペースを読み取れません"
    (English, RipgrepUnavailable) => "Bundled ripgrep is unavailable"
    (Spanish, RipgrepUnavailable) => "El ripgrep incluido no está disponible"
    (SimplifiedChinese, RipgrepUnavailable) => "内置 ripgrep 不可用"
    (TraditionalChinese, RipgrepUnavailable) => "內建 ripgrep 不可用"
    (Japanese, RipgrepUnavailable) =>
      "同梱の ripgrep が利用できません"
    (English, InvalidPattern) => "Invalid code pattern"
    (Spanish, InvalidPattern) => "Patrón de código no válido"
    (SimplifiedChinese, InvalidPattern) => "代码模式无效"
    (TraditionalChinese, InvalidPattern) => "程式碼模式無效"
    (Japanese, InvalidPattern) => "無効なコードパターン"
    (English, SemanticUnavailable) => "Semantic search is unavailable"
    (Spanish, SemanticUnavailable) =>
      "La búsqueda semántica no está disponible"
    (SimplifiedChinese, SemanticUnavailable) => "语义搜索不可用"
    (TraditionalChinese, SemanticUnavailable) => "語義搜尋不可用"
    (Japanese, SemanticUnavailable) =>
      "セマンティック検索が利用できません"
    (English, NothingToSearch) => "Nothing to search"
    (Spanish, NothingToSearch) => "No hay nada que buscar"
    (SimplifiedChinese, NothingToSearch) => "没有可搜索的内容"
    (TraditionalChinese, NothingToSearch) => "沒有可搜尋的內容"
    (Japanese, NothingToSearch) => "検索対象がありません"
    (English, SearchFailed) => "Search failed"
    (Spanish, SearchFailed) => "La búsqueda falló"
    (SimplifiedChinese, SearchFailed) => "搜索失败"
    (TraditionalChinese, SearchFailed) => "搜尋失敗"
    (Japanese, SearchFailed) => "検索に失敗しました"
    (English, NoMatches) => "No matches found."
    (Spanish, NoMatches) => "No se encontraron coincidencias."
    (SimplifiedChinese, NoMatches) => "未找到匹配项。"
    (TraditionalChinese, NoMatches) => "未找到匹配項。"
    (Japanese, NoMatches) => "一致する項目が見つかりません。"
    (English, TextSearchDescription) =>
      "Search across files in the current checkout."
    (Spanish, TextSearchDescription) =>
      "Buscar en los archivos de la copia de trabajo actual."
    (SimplifiedChinese, TextSearchDescription) =>
      "在当前检出目录中跨文件搜索。"
    (TraditionalChinese, TextSearchDescription) =>
      "在當前檢出目錄中跨檔案搜尋。"
    (Japanese, TextSearchDescription) =>
      "現在のチェックアウト内のファイルを横断検索します。"
    (English, CodeSearchDescription) =>
      "Search MoonBit code patterns in the current checkout."
    (Spanish, CodeSearchDescription) =>
      "Buscar patrones de código MoonBit en la copia de trabajo actual."
    (SimplifiedChinese, CodeSearchDescription) =>
      "在当前检出目录中搜索 MoonBit 代码模式。"
    (TraditionalChinese, CodeSearchDescription) =>
      "在當前檢出目錄中搜尋 MoonBit 程式碼模式。"
    (Japanese, CodeSearchDescription) =>
      "現在のチェックアウト内で MoonBit コードパターンを検索します。"
    (English, ResultsCleared) =>
      "Search results cleared. Press Enter to search again."
    (Spanish, ResultsCleared) =>
      "Se borraron los resultados. Pulsa Enter para buscar de nuevo."
    (SimplifiedChinese, ResultsCleared) =>
      "搜索结果已清空。按 Enter 重新搜索。"
    (TraditionalChinese, ResultsCleared) =>
      "搜尋結果已清空。按 Enter 重新搜尋。"
    (Japanese, ResultsCleared) =>
      "検索結果をクリアしました。Enter キーで再検索します。"
    (English, SearchingLabel) => "Searching…"
    (Spanish, SearchingLabel) => "Buscando…"
    (SimplifiedChinese, SearchingLabel) => "正在搜索…"
    (TraditionalChinese, SearchingLabel) => "正在搜尋…"
    (Japanese, SearchingLabel) => "検索中…"
    (English, ResultLimit) =>
      "Only the first 20,000 matches are shown. Narrow the search to see more."
    (Spanish, ResultLimit) =>
      "Solo se muestran las primeras 20 000 coincidencias. Acota la búsqueda para ver más."
    (SimplifiedChinese, ResultLimit) =>
      "仅显示前 20,000 个匹配项。请缩小搜索范围以查看更多结果。"
    (TraditionalChinese, ResultLimit) =>
      "僅顯示前 20,000 個匹配項。請縮小搜尋範圍以檢視更多結果。"
    (Japanese, ResultLimit) =>
      "最初の 20,000 件のみ表示しています。検索範囲を絞り込んでください。"
    (English, IncompleteResults) =>
      "Results may be incomplete — some files could not be searched."
    (Spanish, IncompleteResults) =>
      "Los resultados pueden estar incompletos: no se pudo buscar en algunos archivos."
    (SimplifiedChinese, IncompleteResults) =>
      "部分文件无法搜索，结果可能不完整。"
    (TraditionalChinese, IncompleteResults) =>
      "部分檔案無法搜尋，結果可能不完整。"
    (Japanese, IncompleteResults) =>
      "一部のファイルを検索できなかったため、結果が不完全な可能性があります。"
    (English, IncludeFiles) => "files to include"
    (Spanish, IncludeFiles) => "archivos que incluir"
    (SimplifiedChinese, IncludeFiles) => "包含的文件"
    (TraditionalChinese, IncludeFiles) => "包含的檔案"
    (Japanese, IncludeFiles) => "含めるファイル"
    (English, ExcludeFiles) => "files to exclude"
    (Spanish, ExcludeFiles) => "archivos que excluir"
    (SimplifiedChinese, ExcludeFiles) => "排除的文件"
    (TraditionalChinese, ExcludeFiles) => "排除的檔案"
    (Japanese, ExcludeFiles) => "除外するファイル"
    (English, IncludeExample) => "e.g. src/**, *.mbt"
    (Spanish, IncludeExample) => "p. ej., src/**, *.mbt"
    (SimplifiedChinese, IncludeExample) => "例如 src/**, *.mbt"
    (TraditionalChinese, IncludeExample) => "例如 src/**, *.mbt"
    (Japanese, IncludeExample) => "例：src/**, *.mbt"
    (English, ExcludeExample) => "e.g. **/*.snap, generated/**"
    (Spanish, ExcludeExample) => "p. ej., **/*.snap, generated/**"
    (SimplifiedChinese, ExcludeExample) => "例如 **/*.snap, generated/**"
    (TraditionalChinese, ExcludeExample) => "例如 **/*.snap, generated/**"
    (Japanese, ExcludeExample) => "例：**/*.snap, generated/**"
    (English, PatternLabel) => "pattern"
    (Spanish, PatternLabel) => "patrón"
    (SimplifiedChinese, PatternLabel) => "模式"
    (TraditionalChinese, PatternLabel) => "模式"
    (Japanese, PatternLabel) => "パターン"
    (English, ToggleDetails) => "Toggle Search Details"
    (Spanish, ToggleDetails) => "Mostrar u ocultar detalles de búsqueda"
    (SimplifiedChinese, ToggleDetails) => "展开或收起搜索详情"
    (TraditionalChinese, ToggleDetails) => "展開或收起搜尋詳情"
    (Japanese, ToggleDetails) => "検索の詳細を展開・折りたたむ"
    (English, RefreshLabel) => "Refresh"
    (Spanish, RefreshLabel) => "Actualizar"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (English, ClearResults) => "Clear Search Results"
    (Spanish, ClearResults) => "Borrar resultados de búsqueda"
    (SimplifiedChinese, ClearResults) => "清空搜索结果"
    (TraditionalChinese, ClearResults) => "清空搜尋結果"
    (Japanese, ClearResults) => "検索結果をクリア"
    (English, ClearLabel) => "Clear"
    (Spanish, ClearLabel) => "Borrar"
    (SimplifiedChinese, ClearLabel) => "清空"
    (TraditionalChinese, ClearLabel) => "清空"
    (Japanese, ClearLabel) => "クリア"
    (English, CollapseAll) => "Collapse All"
    (Spanish, CollapseAll) => "Contraer todo"
    (SimplifiedChinese, CollapseAll) => "全部折叠"
    (TraditionalChinese, CollapseAll) => "全部摺疊"
    (Japanese, CollapseAll) => "すべて折りたたむ"
    (English, NoCheckout) => "No checkout available"
    (Spanish, NoCheckout) => "No hay una copia de trabajo disponible"
    (SimplifiedChinese, NoCheckout) => "没有可用的检出目录"
    (TraditionalChinese, NoCheckout) => "沒有可用的檢出目錄"
    (Japanese, NoCheckout) =>
      "利用可能なチェックアウトがありません"
    (English, OpenCheckoutDescription) =>
      "Open a conversation or task with a checkout to search its files."
    (Spanish, OpenCheckoutDescription) =>
      "Abre una conversación o tarea con una copia de trabajo para buscar en sus archivos."
    (SimplifiedChinese, OpenCheckoutDescription) =>
      "打开具有检出目录的对话或任务，即可搜索其中的文件。"
    (TraditionalChinese, OpenCheckoutDescription) =>
      "開啟具有檢出目錄的對話或任務，即可搜尋其中的檔案。"
    (Japanese, OpenCheckoutDescription) =>
      "チェックアウトを持つチャットまたはタスクを開くと、ファイルを検索できます。"
  }
}
