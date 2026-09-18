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
    (SimplifiedChinese, OneMatch) => "1 个匹配项"
    (Japanese, OneMatch) => "1 件の一致"
    (English, OneFolder) => "1 folder"
    (SimplifiedChinese, OneFolder) => "1 个文件夹"
    (Japanese, OneFolder) => "1 フォルダー"
    (English, FoldersLabel) => "Folders"
    (SimplifiedChinese, FoldersLabel) => "文件夹"
    (Japanese, FoldersLabel) => "フォルダー"
    (English, AddProjectTitle) => "Add a project"
    (SimplifiedChinese, AddProjectTitle) => "添加项目"
    (Japanese, AddProjectTitle) => "プロジェクトを追加"
    (English, ChooseFolder) => "Choose a folder to use as a project workspace."
    (SimplifiedChinese, ChooseFolder) =>
      "选择一个文件夹作为项目工作区。"
    (Japanese, ChooseFolder) =>
      "プロジェクトのワークスペースにするフォルダーを選択してください。"
    (English, CloseLabel) => "Close"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (Japanese, CloseLabel) => "閉じる"
    (English, ClosePicker) => "Close project picker"
    (SimplifiedChinese, ClosePicker) => "关闭项目选择器"
    (Japanese, ClosePicker) => "プロジェクト選択を閉じる"
    (English, NewFolder) => "New folder"
    (SimplifiedChinese, NewFolder) => "新建文件夹"
    (Japanese, NewFolder) => "新しいフォルダー"
    (English, NameLabel) => "Name"
    (SimplifiedChinese, NameLabel) => "名称"
    (Japanese, NameLabel) => "名前"
    (English, LoadingLabel) => "Loading…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, FolderPath) => "Folder path"
    (SimplifiedChinese, FolderPath) => "文件夹路径"
    (Japanese, FolderPath) => "フォルダーのパス"
    (English, EnterFolderPath) => "Enter a folder path"
    (SimplifiedChinese, EnterFolderPath) => "输入文件夹路径"
    (Japanese, EnterFolderPath) => "フォルダーのパスを入力"
    (English, CancelPathEditing) => "Cancel path editing"
    (SimplifiedChinese, CancelPathEditing) => "取消路径编辑"
    (Japanese, CancelPathEditing) => "パスの編集をキャンセル"
    (English, NewFolderName) => "New folder name"
    (SimplifiedChinese, NewFolderName) => "新文件夹名称"
    (Japanese, NewFolderName) => "新しいフォルダー名"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, CreatingLabel) => "Creating…"
    (SimplifiedChinese, CreatingLabel) => "正在创建…"
    (Japanese, CreatingLabel) => "作成中…"
    (English, CreateLabel) => "Create"
    (SimplifiedChinese, CreateLabel) => "创建"
    (Japanese, CreateLabel) => "作成"
    (English, LoadingFolders) => "Loading folders…"
    (SimplifiedChinese, LoadingFolders) => "正在加载文件夹…"
    (Japanese, LoadingFolders) => "フォルダーを読み込み中…"
    (English, OnlyAMoment) => "This should only take a moment."
    (SimplifiedChinese, OnlyAMoment) => "请稍候。"
    (Japanese, OnlyAMoment) => "しばらくお待ちください。"
    (English, NoMatchingFolders) => "No matching folders"
    (SimplifiedChinese, NoMatchingFolders) => "没有匹配的文件夹"
    (Japanese, NoMatchingFolders) =>
      "一致するフォルダーがありません"
    (English, TryAnotherPath) =>
      "Try a different name or enter a complete path."
    (SimplifiedChinese, TryAnotherPath) =>
      "请尝试其他名称或输入完整路径。"
    (Japanese, TryAnotherPath) =>
      "別の名前を試すか、完全なパスを入力してください。"
    (English, NoFolders) => "No folders here"
    (SimplifiedChinese, NoFolders) => "此处没有文件夹"
    (Japanese, NoFolders) => "ここにはフォルダーがありません"
    (English, CreateOrAdd) =>
      "Create a folder here, or add this location as-is."
    (SimplifiedChinese, CreateOrAdd) =>
      "在此创建文件夹，或直接添加当前位置。"
    (Japanese, CreateOrAdd) =>
      "ここにフォルダーを作成するか、現在の場所を追加してください。"
    (English, AddProjectLabel) => "Add project"
    (SimplifiedChinese, AddProjectLabel) => "添加项目"
    (Japanese, AddProjectLabel) => "プロジェクトを追加"
    (English, CurrentFolder) => "Current folder"
    (SimplifiedChinese, CurrentFolder) => "当前文件夹"
    (Japanese, CurrentFolder) => "現在のフォルダー"
    (English, LocationLabel) => "Location"
    (SimplifiedChinese, LocationLabel) => "位置"
    (Japanese, LocationLabel) => "場所"
    (English, ThisPc) => "This PC"
    (SimplifiedChinese, ThisPc) => "此电脑"
    (Japanese, ThisPc) => "このコンピューター"
    (English, EditPath) => "Edit path (⌘L)"
    (SimplifiedChinese, EditPath) => "编辑路径（⌘L）"
    (Japanese, EditPath) => "パスを編集（⌘L）"
    (English, EditCurrentPath) => "Edit current path"
    (SimplifiedChinese, EditCurrentPath) => "编辑当前路径"
    (Japanese, EditCurrentPath) => "現在のパスを編集"
    (English, OpenRoot) => "Open root"
    (SimplifiedChinese, OpenRoot) => "打开根目录"
    (Japanese, OpenRoot) => "ルートディレクトリを開く"
    (English, OpenRootFolder) => "Open root folder"
    (SimplifiedChinese, OpenRootFolder) => "打开根文件夹"
    (Japanese, OpenRootFolder) => "ルートフォルダーを開く"
  }
}
