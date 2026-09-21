// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum Message {
  IndexingFiles
  SearchingSymbols
  FileSearchFailed
  SymbolSearchFailed
  NoFiles
  NoSymbols
  SearchWorkspaceFiles
  SearchFiles
  Files
  SearchWorkspaceSymbols
  SearchSymbols
  Symbols
}

///|
fn Message::text(self : Message, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (English, IndexingFiles) => "Indexing files…"
    (Spanish, IndexingFiles) => "Indexando archivos…"
    (SimplifiedChinese, IndexingFiles) => "正在索引文件…"
    (TraditionalChinese, IndexingFiles) => "正在索引檔案…"
    (Japanese, IndexingFiles) => "ファイルをインデックス中…"
    (English, SearchingSymbols) => "Searching symbols…"
    (Spanish, SearchingSymbols) => "Buscando símbolos…"
    (SimplifiedChinese, SearchingSymbols) => "正在搜索符号…"
    (TraditionalChinese, SearchingSymbols) => "正在搜尋符號…"
    (Japanese, SearchingSymbols) => "シンボルを検索中…"
    (English, FileSearchFailed) => "File search failed"
    (Spanish, FileSearchFailed) => "La búsqueda de archivos falló"
    (SimplifiedChinese, FileSearchFailed) => "文件搜索失败"
    (TraditionalChinese, FileSearchFailed) => "檔案搜尋失敗"
    (Japanese, FileSearchFailed) => "ファイル検索に失敗しました"
    (English, SymbolSearchFailed) => "Symbol search failed"
    (Spanish, SymbolSearchFailed) => "La búsqueda de símbolos falló"
    (SimplifiedChinese, SymbolSearchFailed) => "符号搜索失败"
    (TraditionalChinese, SymbolSearchFailed) => "符號搜尋失敗"
    (Japanese, SymbolSearchFailed) => "シンボル検索に失敗しました"
    (English, NoFiles) => "No files found"
    (Spanish, NoFiles) => "No se encontraron archivos"
    (SimplifiedChinese, NoFiles) => "未找到文件"
    (TraditionalChinese, NoFiles) => "未找到檔案"
    (Japanese, NoFiles) => "ファイルが見つかりません"
    (English, NoSymbols) => "No symbols found"
    (Spanish, NoSymbols) => "No se encontraron símbolos"
    (SimplifiedChinese, NoSymbols) => "未找到符号"
    (TraditionalChinese, NoSymbols) => "未找到符號"
    (Japanese, NoSymbols) => "シンボルが見つかりません"
    (English, SearchWorkspaceFiles) => "Search workspace files"
    (Spanish, SearchWorkspaceFiles) => "Buscar archivos del espacio de trabajo"
    (SimplifiedChinese, SearchWorkspaceFiles) => "搜索工作区文件"
    (TraditionalChinese, SearchWorkspaceFiles) => "搜尋工作區檔案"
    (Japanese, SearchWorkspaceFiles) =>
      "ワークスペースのファイルを検索"
    (English, SearchFiles) => "Search files"
    (Spanish, SearchFiles) => "Buscar archivos"
    (SimplifiedChinese, SearchFiles) => "搜索文件"
    (TraditionalChinese, SearchFiles) => "搜尋檔案"
    (Japanese, SearchFiles) => "ファイルを検索"
    (English, Files) => "Files"
    (Spanish, Files) => "Archivos"
    (SimplifiedChinese, Files) => "文件"
    (TraditionalChinese, Files) => "檔案"
    (Japanese, Files) => "ファイル"
    (English, SearchWorkspaceSymbols) => "Search workspace symbols"
    (Spanish, SearchWorkspaceSymbols) =>
      "Buscar símbolos del espacio de trabajo"
    (SimplifiedChinese, SearchWorkspaceSymbols) => "搜索工作区符号"
    (TraditionalChinese, SearchWorkspaceSymbols) => "搜尋工作區符號"
    (Japanese, SearchWorkspaceSymbols) =>
      "ワークスペースのシンボルを検索"
    (English, SearchSymbols) => "Search symbols"
    (Spanish, SearchSymbols) => "Buscar símbolos"
    (SimplifiedChinese, SearchSymbols) => "搜索符号"
    (TraditionalChinese, SearchSymbols) => "搜尋符號"
    (Japanese, SearchSymbols) => "シンボルを検索"
    (English, Symbols) => "Symbols"
    (Spanish, Symbols) => "Símbolos"
    (SimplifiedChinese, Symbols) => "符号"
    (TraditionalChinese, Symbols) => "符號"
    (Japanese, Symbols) => "シンボル"
  }
}
