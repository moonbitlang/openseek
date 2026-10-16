// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  OneMatch
  OneFolder
  FoldersLabel
  AddProjectTitle
  ChooseFolder
  CloseLabel
  ClosePicker
  NewFolder
  NameLabel
  LoadingLabel
  FolderPath
  EnterFolderPath
  CancelPathEditing
  NewFolderName
  CancelLabel
  CreatingLabel
  CreateLabel
  LoadingFolders
  OnlyAMoment
  NoMatchingFolders
  TryAnotherPath
  NoFolders
  CreateOrAdd
  AddProjectLabel
  CurrentFolder
  LocationLabel
  ThisPc
  EditPath
  EditCurrentPath
  OpenRoot
  OpenRootFolder
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, OneMatch) => "1 match"
    (Spanish, OneMatch) => "1 coincidencia"
    (SimplifiedChinese, OneMatch) => "1 个匹配项"
    (TraditionalChinese, OneMatch) => "1 個匹配項"
    (Japanese, OneMatch) => "1 件の一致"
    (English, OneFolder) => "1 folder"
    (Spanish, OneFolder) => "1 carpeta"
    (SimplifiedChinese, OneFolder) => "1 个文件夹"
    (TraditionalChinese, OneFolder) => "1 個資料夾"
    (Japanese, OneFolder) => "1 フォルダー"
    (English, FoldersLabel) => "Folders"
    (Spanish, FoldersLabel) => "Carpetas"
    (SimplifiedChinese, FoldersLabel) => "文件夹"
    (TraditionalChinese, FoldersLabel) => "資料夾"
    (Japanese, FoldersLabel) => "フォルダー"
    (English, AddProjectTitle) => "Add a project"
    (Spanish, AddProjectTitle) => "Añadir un proyecto"
    (SimplifiedChinese, AddProjectTitle) => "添加项目"
    (TraditionalChinese, AddProjectTitle) => "新增專案"
    (Japanese, AddProjectTitle) => "プロジェクトを追加"
    (English, ChooseFolder) => "Choose a folder to use as a project workspace."
    (Spanish, ChooseFolder) =>
      "Elige una carpeta para usarla como espacio de trabajo del proyecto."
    (SimplifiedChinese, ChooseFolder) =>
      "选择一个文件夹作为项目工作区。"
    (TraditionalChinese, ChooseFolder) =>
      "選擇一個資料夾作為專案工作區。"
    (Japanese, ChooseFolder) =>
      "プロジェクトのワークスペースにするフォルダーを選択してください。"
    (English, CloseLabel) => "Close"
    (Spanish, CloseLabel) => "Cerrar"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (TraditionalChinese, CloseLabel) => "關閉"
    (Japanese, CloseLabel) => "閉じる"
    (English, ClosePicker) => "Close project picker"
    (Spanish, ClosePicker) => "Cerrar selector de proyectos"
    (SimplifiedChinese, ClosePicker) => "关闭项目选择器"
    (TraditionalChinese, ClosePicker) => "關閉專案選擇器"
    (Japanese, ClosePicker) => "プロジェクト選択を閉じる"
    (English, NewFolder) => "New folder"
    (Spanish, NewFolder) => "Nueva carpeta"
    (SimplifiedChinese, NewFolder) => "新建文件夹"
    (TraditionalChinese, NewFolder) => "新建資料夾"
    (Japanese, NewFolder) => "新しいフォルダー"
    (English, NameLabel) => "Name"
    (Spanish, NameLabel) => "Nombre"
    (SimplifiedChinese, NameLabel) => "名称"
    (TraditionalChinese, NameLabel) => "名稱"
    (Japanese, NameLabel) => "名前"
    (English, LoadingLabel) => "Loading…"
    (Spanish, LoadingLabel) => "Cargando…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (TraditionalChinese, LoadingLabel) => "正在載入…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, FolderPath) => "Folder path"
    (Spanish, FolderPath) => "Ruta de la carpeta"
    (SimplifiedChinese, FolderPath) => "文件夹路径"
    (TraditionalChinese, FolderPath) => "資料夾路徑"
    (Japanese, FolderPath) => "フォルダーのパス"
    (English, EnterFolderPath) => "Enter a folder path"
    (Spanish, EnterFolderPath) => "Introduce una ruta de carpeta"
    (SimplifiedChinese, EnterFolderPath) => "输入文件夹路径"
    (TraditionalChinese, EnterFolderPath) => "輸入資料夾路徑"
    (Japanese, EnterFolderPath) => "フォルダーのパスを入力"
    (English, CancelPathEditing) => "Cancel path editing"
    (Spanish, CancelPathEditing) => "Cancelar edición de ruta"
    (SimplifiedChinese, CancelPathEditing) => "取消路径编辑"
    (TraditionalChinese, CancelPathEditing) => "取消路徑編輯"
    (Japanese, CancelPathEditing) => "パスの編集をキャンセル"
    (English, NewFolderName) => "New folder name"
    (Spanish, NewFolderName) => "Nombre de la nueva carpeta"
    (SimplifiedChinese, NewFolderName) => "新文件夹名称"
    (TraditionalChinese, NewFolderName) => "新資料夾名稱"
    (Japanese, NewFolderName) => "新しいフォルダー名"
    (English, CancelLabel) => "Cancel"
    (Spanish, CancelLabel) => "Cancelar"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, CreatingLabel) => "Creating…"
    (Spanish, CreatingLabel) => "Creando…"
    (SimplifiedChinese, CreatingLabel) => "正在创建…"
    (TraditionalChinese, CreatingLabel) => "正在建立…"
    (Japanese, CreatingLabel) => "作成中…"
    (English, CreateLabel) => "Create"
    (Spanish, CreateLabel) => "Crear"
    (SimplifiedChinese, CreateLabel) => "创建"
    (TraditionalChinese, CreateLabel) => "建立"
    (Japanese, CreateLabel) => "作成"
    (English, LoadingFolders) => "Loading folders…"
    (Spanish, LoadingFolders) => "Cargando carpetas…"
    (SimplifiedChinese, LoadingFolders) => "正在加载文件夹…"
    (TraditionalChinese, LoadingFolders) => "正在載入資料夾…"
    (Japanese, LoadingFolders) => "フォルダーを読み込み中…"
    (English, OnlyAMoment) => "This should only take a moment."
    (Spanish, OnlyAMoment) => "Esto solo debería tardar un momento."
    (SimplifiedChinese, OnlyAMoment) => "请稍候。"
    (TraditionalChinese, OnlyAMoment) => "請稍候。"
    (Japanese, OnlyAMoment) => "しばらくお待ちください。"
    (English, NoMatchingFolders) => "No matching folders"
    (Spanish, NoMatchingFolders) => "No hay carpetas coincidentes"
    (SimplifiedChinese, NoMatchingFolders) => "没有匹配的文件夹"
    (TraditionalChinese, NoMatchingFolders) => "沒有匹配的資料夾"
    (Japanese, NoMatchingFolders) =>
      "一致するフォルダーがありません"
    (English, TryAnotherPath) =>
      "Try a different name or enter a complete path."
    (Spanish, TryAnotherPath) =>
      "Prueba otro nombre o introduce una ruta completa."
    (SimplifiedChinese, TryAnotherPath) =>
      "请尝试其他名称或输入完整路径。"
    (TraditionalChinese, TryAnotherPath) =>
      "請嘗試其他名稱或輸入完整路徑。"
    (Japanese, TryAnotherPath) =>
      "別の名前を試すか、完全なパスを入力してください。"
    (English, NoFolders) => "No folders here"
    (Spanish, NoFolders) => "No hay carpetas aquí"
    (SimplifiedChinese, NoFolders) => "此处没有文件夹"
    (TraditionalChinese, NoFolders) => "此處沒有資料夾"
    (Japanese, NoFolders) => "ここにはフォルダーがありません"
    (English, CreateOrAdd) =>
      "Create a folder here, or add this location as-is."
    (Spanish, CreateOrAdd) =>
      "Crea una carpeta aquí o añade esta ubicación tal como está."
    (SimplifiedChinese, CreateOrAdd) =>
      "在此创建文件夹，或直接添加当前位置。"
    (TraditionalChinese, CreateOrAdd) =>
      "在此建立資料夾，或直接新增當前位置。"
    (Japanese, CreateOrAdd) =>
      "ここにフォルダーを作成するか、現在の場所を追加してください。"
    (English, AddProjectLabel) => "Add project"
    (Spanish, AddProjectLabel) => "Añadir proyecto"
    (SimplifiedChinese, AddProjectLabel) => "添加项目"
    (TraditionalChinese, AddProjectLabel) => "新增專案"
    (Japanese, AddProjectLabel) => "プロジェクトを追加"
    (English, CurrentFolder) => "Current folder"
    (Spanish, CurrentFolder) => "Carpeta actual"
    (SimplifiedChinese, CurrentFolder) => "当前文件夹"
    (TraditionalChinese, CurrentFolder) => "當前資料夾"
    (Japanese, CurrentFolder) => "現在のフォルダー"
    (English, LocationLabel) => "Location"
    (Spanish, LocationLabel) => "Ubicación"
    (SimplifiedChinese, LocationLabel) => "位置"
    (TraditionalChinese, LocationLabel) => "位置"
    (Japanese, LocationLabel) => "場所"
    (English, ThisPc) => "This PC"
    (Spanish, ThisPc) => "Este equipo"
    (SimplifiedChinese, ThisPc) => "此电脑"
    (TraditionalChinese, ThisPc) => "此電腦"
    (Japanese, ThisPc) => "このコンピューター"
    (English, EditPath) => "Edit path (⌘L)"
    (Spanish, EditPath) => "Editar ruta (⌘L)"
    (SimplifiedChinese, EditPath) => "编辑路径（⌘L）"
    (TraditionalChinese, EditPath) => "編輯路徑（⌘L）"
    (Japanese, EditPath) => "パスを編集（⌘L）"
    (English, EditCurrentPath) => "Edit current path"
    (Spanish, EditCurrentPath) => "Editar ruta actual"
    (SimplifiedChinese, EditCurrentPath) => "编辑当前路径"
    (TraditionalChinese, EditCurrentPath) => "編輯當前路徑"
    (Japanese, EditCurrentPath) => "現在のパスを編集"
    (English, OpenRoot) => "Open root"
    (Spanish, OpenRoot) => "Abrir raíz"
    (SimplifiedChinese, OpenRoot) => "打开根目录"
    (TraditionalChinese, OpenRoot) => "開啟根目錄"
    (Japanese, OpenRoot) => "ルートディレクトリを開く"
    (English, OpenRootFolder) => "Open root folder"
    (Spanish, OpenRootFolder) => "Abrir carpeta raíz"
    (SimplifiedChinese, OpenRootFolder) => "打开根文件夹"
    (TraditionalChinese, OpenRootFolder) => "開啟根資料夾"
    (Japanese, OpenRootFolder) => "ルートフォルダーを開く"
  }
}
