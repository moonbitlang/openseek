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
    (English, OneFolder) => "1 folder"
    (SimplifiedChinese, OneFolder) => "1 个文件夹"
    (English, FoldersLabel) => "Folders"
    (SimplifiedChinese, FoldersLabel) => "文件夹"
    (English, AddProjectTitle) => "Add a project"
    (SimplifiedChinese, AddProjectTitle) => "添加项目"
    (English, ChooseFolder) => "Choose a folder to use as a project workspace."
    (SimplifiedChinese, ChooseFolder) =>
      "选择一个文件夹作为项目工作区。"
    (English, CloseLabel) => "Close"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (English, ClosePicker) => "Close project picker"
    (SimplifiedChinese, ClosePicker) => "关闭项目选择器"
    (English, NewFolder) => "New folder"
    (SimplifiedChinese, NewFolder) => "新建文件夹"
    (English, NameLabel) => "Name"
    (SimplifiedChinese, NameLabel) => "名称"
    (English, LoadingLabel) => "Loading…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (English, FolderPath) => "Folder path"
    (SimplifiedChinese, FolderPath) => "文件夹路径"
    (English, EnterFolderPath) => "Enter a folder path"
    (SimplifiedChinese, EnterFolderPath) => "输入文件夹路径"
    (English, CancelPathEditing) => "Cancel path editing"
    (SimplifiedChinese, CancelPathEditing) => "取消路径编辑"
    (English, NewFolderName) => "New folder name"
    (SimplifiedChinese, NewFolderName) => "新文件夹名称"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, CreatingLabel) => "Creating…"
    (SimplifiedChinese, CreatingLabel) => "正在创建…"
    (English, CreateLabel) => "Create"
    (SimplifiedChinese, CreateLabel) => "创建"
    (English, LoadingFolders) => "Loading folders…"
    (SimplifiedChinese, LoadingFolders) => "正在加载文件夹…"
    (English, OnlyAMoment) => "This should only take a moment."
    (SimplifiedChinese, OnlyAMoment) => "请稍候。"
    (English, NoMatchingFolders) => "No matching folders"
    (SimplifiedChinese, NoMatchingFolders) => "没有匹配的文件夹"
    (English, TryAnotherPath) =>
      "Try a different name or enter a complete path."
    (SimplifiedChinese, TryAnotherPath) =>
      "请尝试其他名称或输入完整路径。"
    (English, NoFolders) => "No folders here"
    (SimplifiedChinese, NoFolders) => "此处没有文件夹"
    (English, CreateOrAdd) =>
      "Create a folder here, or add this location as-is."
    (SimplifiedChinese, CreateOrAdd) =>
      "在此创建文件夹，或直接添加当前位置。"
    (English, AddProjectLabel) => "Add project"
    (SimplifiedChinese, AddProjectLabel) => "添加项目"
    (English, CurrentFolder) => "Current folder"
    (SimplifiedChinese, CurrentFolder) => "当前文件夹"
    (English, LocationLabel) => "Location"
    (SimplifiedChinese, LocationLabel) => "位置"
    (English, ThisPc) => "This PC"
    (SimplifiedChinese, ThisPc) => "此电脑"
    (English, EditPath) => "Edit path (⌘L)"
    (SimplifiedChinese, EditPath) => "编辑路径（⌘L）"
    (English, EditCurrentPath) => "Edit current path"
    (SimplifiedChinese, EditCurrentPath) => "编辑当前路径"
    (English, OpenRoot) => "Open root"
    (SimplifiedChinese, OpenRoot) => "打开根目录"
    (English, OpenRootFolder) => "Open root folder"
    (SimplifiedChinese, OpenRootFolder) => "打开根文件夹"
  }
}
