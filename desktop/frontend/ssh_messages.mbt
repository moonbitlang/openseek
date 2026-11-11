///|
priv enum SshMessage {
  Connected
  ConnectionFailed
  Disconnected
  Connecting
  Authenticating
  AuthenticationRequired
  Downloading
  Installing
  EnterPassword
  CancelConnection
  RetryConnection
  AddProject
  ConnectionDetails
  HostConnectionDetails(String)
  NoHosts
  AddHost
  ConnectionsLocal
  ThisComputer
  ProjectLocation
  RenameHost
  RenameHelp
  AddHostHelp
  SshCommand
  DisplayName
  OptionalDisplayName
  Preview
  ConfigHelp
  Cancel
  Saving
  SaveName
  AddAndConnect
  OriginalCommand
  RemoveHostQuestion
  RemoveHostHelp
  Removing
  RemoveHost
  Rename
  CloseDialog
  PasswordFor(String)
  PassphraseFor(String)
  ConfirmIdentity
  AuthenticationFailed
  HidePassword
  ShowPassword
  Hide
  Show
  SecretHelp
  Accept
  TryAgain
  Continue
  AuthKeys
  ProtocolRequiresLocalUpdate(String, Int32, Int32)
  ProtocolRequiresRemoteUpdate(String, Int32, Int32)
  ProtocolVersionMissing(String, Int32)
}

///|
fn ssh_text(locale : @i18n.Locale, message : SshMessage) -> String {
  match (locale, message) {
    (English, Connected) => "Connected"
    (Spanish, Connected) => "Conectado"
    (SimplifiedChinese, Connected) => "已连接"
    (TraditionalChinese, Connected) => "已連線"
    (Japanese, Connected) => "接続済み"
    (English, ConnectionFailed) => "Connection failed"
    (Spanish, ConnectionFailed) => "Error de conexión"
    (SimplifiedChinese, ConnectionFailed) => "连接失败"
    (TraditionalChinese, ConnectionFailed) => "連線失敗"
    (Japanese, ConnectionFailed) => "接続に失敗しました"
    (English, Disconnected) => "Disconnected"
    (Spanish, Disconnected) => "Desconectado"
    (SimplifiedChinese, Disconnected) => "已断开连接"
    (TraditionalChinese, Disconnected) => "已中斷連線"
    (Japanese, Disconnected) => "未接続"
    (English, Connecting) => "Connecting…"
    (Spanish, Connecting) => "Conectando…"
    (SimplifiedChinese, Connecting) => "正在连接…"
    (TraditionalChinese, Connecting) => "正在連線…"
    (Japanese, Connecting) => "接続中…"
    (English, Authenticating) => "Authenticating…"
    (Spanish, Authenticating) => "Autenticando…"
    (SimplifiedChinese, Authenticating) => "正在验证身份…"
    (TraditionalChinese, Authenticating) => "正在驗證身分…"
    (Japanese, Authenticating) => "認証中…"
    (English, AuthenticationRequired) => "Authentication required"
    (Spanish, AuthenticationRequired) => "Se requiere autenticación"
    (SimplifiedChinese, AuthenticationRequired) => "需要身份验证"
    (TraditionalChinese, AuthenticationRequired) => "需要身分驗證"
    (Japanese, AuthenticationRequired) => "認証が必要です"
    (English, Downloading) => "Downloading OpenSeek…"
    (Spanish, Downloading) => "Descargando OpenSeek…"
    (SimplifiedChinese, Downloading) => "正在下载 OpenSeek…"
    (TraditionalChinese, Downloading) => "正在下載 OpenSeek…"
    (Japanese, Downloading) => "OpenSeek をダウンロード中…"
    (English, Installing) => "Running openseek setup…"
    (Spanish, Installing) => "Ejecutando openseek setup…"
    (SimplifiedChinese, Installing) => "正在运行 openseek setup…"
    (TraditionalChinese, Installing) => "正在執行 openseek setup…"
    (Japanese, Installing) => "openseek setup を実行中…"
    (English, EnterPassword) => "Enter password"
    (Spanish, EnterPassword) => "Introducir contraseña"
    (SimplifiedChinese, EnterPassword) => "输入密码"
    (TraditionalChinese, EnterPassword) => "輸入密碼"
    (Japanese, EnterPassword) => "パスワードを入力"
    (English, CancelConnection) => "Cancel connection"
    (Spanish, CancelConnection) => "Cancelar conexión"
    (SimplifiedChinese, CancelConnection) => "取消连接"
    (TraditionalChinese, CancelConnection) => "取消連線"
    (Japanese, CancelConnection) => "接続をキャンセル"
    (English, RetryConnection) => "Retry connection"
    (Spanish, RetryConnection) => "Reintentar conexión"
    (SimplifiedChinese, RetryConnection) => "重试连接"
    (TraditionalChinese, RetryConnection) => "重試連線"
    (Japanese, RetryConnection) => "接続を再試行"
    (English, AddProject) => "Add project"
    (Spanish, AddProject) => "Añadir proyecto"
    (SimplifiedChinese, AddProject) => "添加项目"
    (TraditionalChinese, AddProject) => "新增專案"
    (Japanese, AddProject) => "プロジェクトを追加"
    (English, ConnectionDetails) => "Connection details"
    (Spanish, ConnectionDetails) => "Detalles de conexión"
    (SimplifiedChinese, ConnectionDetails) => "连接详情"
    (TraditionalChinese, ConnectionDetails) => "連線詳細資訊"
    (Japanese, ConnectionDetails) => "接続の詳細"
    (English, HostConnectionDetails(host)) => "Connection details for \{host}"
    (Spanish, HostConnectionDetails(host)) => "Detalles de conexión de \{host}"
    (SimplifiedChinese, HostConnectionDetails(host)) =>
      "\{host} 的连接详情"
    (TraditionalChinese, HostConnectionDetails(host)) =>
      "\{host} 的連線詳細資訊"
    (Japanese, HostConnectionDetails(host)) => "\{host} の接続の詳細"
    (English, NoHosts) => "Connect a host to work on its projects over SSH."
    (Spanish, NoHosts) =>
      "Conecta un host para trabajar en sus proyectos mediante SSH."
    (SimplifiedChinese, NoHosts) =>
      "连接主机，通过 SSH 处理其项目。"
    (TraditionalChinese, NoHosts) =>
      "連線至主機，透過 SSH 處理其專案。"
    (Japanese, NoHosts) =>
      "ホストに接続すると、SSH 経由でそのプロジェクトを操作できます。"
    (English, AddHost) => "Add SSH host"
    (Spanish, AddHost) => "Añadir host SSH"
    (SimplifiedChinese, AddHost) => "添加 SSH 主机"
    (TraditionalChinese, AddHost) => "新增 SSH 主機"
    (Japanese, AddHost) => "SSH ホストを追加"
    (English, ConnectionsLocal) => "Connections stay on this computer."
    (Spanish, ConnectionsLocal) => "Las conexiones permanecen en este equipo."
    (SimplifiedChinese, ConnectionsLocal) =>
      "连接仅保留在此计算机上。"
    (TraditionalChinese, ConnectionsLocal) =>
      "連線僅保留在此電腦上。"
    (Japanese, ConnectionsLocal) =>
      "接続情報はこのコンピュータにのみ保存されます。"
    (English, ThisComputer) => "This computer"
    (Spanish, ThisComputer) => "Este equipo"
    (SimplifiedChinese, ThisComputer) => "此计算机"
    (TraditionalChinese, ThisComputer) => "此電腦"
    (Japanese, ThisComputer) => "このコンピュータ"
    (English, ProjectLocation) => "Project location"
    (Spanish, ProjectLocation) => "Ubicación del proyecto"
    (SimplifiedChinese, ProjectLocation) => "项目位置"
    (TraditionalChinese, ProjectLocation) => "專案位置"
    (Japanese, ProjectLocation) => "プロジェクトの場所"
    (English, RenameHost) => "Rename SSH host"
    (Spanish, RenameHost) => "Cambiar nombre del host SSH"
    (SimplifiedChinese, RenameHost) => "重命名 SSH 主机"
    (TraditionalChinese, RenameHost) => "重新命名 SSH 主機"
    (Japanese, RenameHost) => "SSH ホストの名前を変更"
    (English, RenameHelp) =>
      "This name appears beside projects and in host lists."
    (Spanish, RenameHelp) =>
      "Este nombre aparece junto a los proyectos y en las listas de hosts."
    (SimplifiedChinese, RenameHelp) =>
      "此名称显示在项目旁和主机列表中。"
    (TraditionalChinese, RenameHelp) =>
      "此名稱顯示於專案旁及主機清單中。"
    (Japanese, RenameHelp) =>
      "この名前はプロジェクトの横やホスト一覧に表示されます。"
    (English, AddHostHelp) =>
      "Paste your SSH command. Choose a name to recognize this host."
    (Spanish, AddHostHelp) =>
      "Pega tu comando SSH. Elige un nombre para identificar este host."
    (SimplifiedChinese, AddHostHelp) =>
      "粘贴 SSH 命令，并选择一个便于识别此主机的名称。"
    (TraditionalChinese, AddHostHelp) =>
      "貼上 SSH 指令，並選擇一個便於識別此主機的名稱。"
    (Japanese, AddHostHelp) =>
      "SSH コマンドを貼り付け、このホストを識別しやすい名前を付けてください。"
    (English, SshCommand) => "SSH command"
    (Spanish, SshCommand) => "Comando SSH"
    (SimplifiedChinese, SshCommand) => "SSH 命令"
    (TraditionalChinese, SshCommand) => "SSH 指令"
    (Japanese, SshCommand) => "SSH コマンド"
    (English, DisplayName) => "Display name"
    (Spanish, DisplayName) => "Nombre para mostrar"
    (SimplifiedChinese, DisplayName) => "显示名称"
    (TraditionalChinese, DisplayName) => "顯示名稱"
    (Japanese, DisplayName) => "表示名"
    (English, OptionalDisplayName) => "Display name (optional)"
    (Spanish, OptionalDisplayName) => "Nombre para mostrar (opcional)"
    (SimplifiedChinese, OptionalDisplayName) => "显示名称（可选）"
    (TraditionalChinese, OptionalDisplayName) => "顯示名稱（選填）"
    (Japanese, OptionalDisplayName) => "表示名（任意）"
    (English, Preview) => "Preview"
    (Spanish, Preview) => "Vista previa"
    (SimplifiedChinese, Preview) => "预览"
    (TraditionalChinese, Preview) => "預覽"
    (Japanese, Preview) => "プレビュー"
    (English, ConfigHelp) =>
      "Uses your SSH configuration. You will be prompted if authentication is required."
    (Spanish, ConfigHelp) =>
      "Se utiliza tu configuración SSH. Se te avisará si se requiere autenticación."
    (SimplifiedChinese, ConfigHelp) =>
      "使用你的 SSH 配置。需要身份验证时会提示你。"
    (TraditionalChinese, ConfigHelp) =>
      "使用你的 SSH 設定。需要身分驗證時會提示你。"
    (Japanese, ConfigHelp) =>
      "SSH 設定を使用します。認証が必要な場合は入力を求められます。"
    (English, Cancel) => "Cancel"
    (Spanish, Cancel) => "Cancelar"
    (SimplifiedChinese, Cancel) => "取消"
    (TraditionalChinese, Cancel) => "取消"
    (Japanese, Cancel) => "キャンセル"
    (English, Saving) => "Saving…"
    (Spanish, Saving) => "Guardando…"
    (SimplifiedChinese, Saving) => "正在保存…"
    (TraditionalChinese, Saving) => "正在儲存…"
    (Japanese, Saving) => "保存中…"
    (English, SaveName) => "Save name"
    (Spanish, SaveName) => "Guardar nombre"
    (SimplifiedChinese, SaveName) => "保存名称"
    (TraditionalChinese, SaveName) => "儲存名稱"
    (Japanese, SaveName) => "名前を保存"
    (English, AddAndConnect) => "Add and connect"
    (Spanish, AddAndConnect) => "Añadir y conectar"
    (SimplifiedChinese, AddAndConnect) => "添加并连接"
    (TraditionalChinese, AddAndConnect) => "新增並連線"
    (Japanese, AddAndConnect) => "追加して接続"
    (English, OriginalCommand) => "Original SSH command"
    (Spanish, OriginalCommand) => "Comando SSH original"
    (SimplifiedChinese, OriginalCommand) => "原始 SSH 命令"
    (TraditionalChinese, OriginalCommand) => "原始 SSH 指令"
    (Japanese, OriginalCommand) => "元の SSH コマンド"
    (English, RemoveHostQuestion) => "Remove SSH host?"
    (Spanish, RemoveHostQuestion) => "¿Quitar el host SSH?"
    (SimplifiedChinese, RemoveHostQuestion) => "移除 SSH 主机？"
    (TraditionalChinese, RemoveHostQuestion) => "移除 SSH 主機？"
    (Japanese, RemoveHostQuestion) => "SSH ホストを削除しますか？"
    (English, RemoveHostHelp) =>
      "Remove this host from this computer. Its connection and running tasks will stop. Remote files, projects and conversation history will remain on the host."
    (Spanish, RemoveHostHelp) =>
      "Quita este host de este equipo. Se detendrán su conexión y las tareas en ejecución. Los archivos remotos, los proyectos y el historial de conversaciones permanecerán en el host."
    (SimplifiedChinese, RemoveHostHelp) =>
      "从此计算机移除此主机。其连接和正在运行的任务将停止。远程文件、项目和对话历史将保留在主机上。"
    (TraditionalChinese, RemoveHostHelp) =>
      "從此電腦移除此主機。其連線和執行中的工作將停止。遠端檔案、專案和對話記錄將保留在主機上。"
    (Japanese, RemoveHostHelp) =>
      "このコンピュータからこのホストを削除します。接続と実行中のタスクは停止します。リモートのファイル、プロジェクト、会話履歴はホストに残ります。"
    (English, Removing) => "Removing…"
    (Spanish, Removing) => "Quitando…"
    (SimplifiedChinese, Removing) => "正在移除…"
    (TraditionalChinese, Removing) => "正在移除…"
    (Japanese, Removing) => "削除中…"
    (English, RemoveHost) => "Remove host"
    (Spanish, RemoveHost) => "Quitar host"
    (SimplifiedChinese, RemoveHost) => "移除主机"
    (TraditionalChinese, RemoveHost) => "移除主機"
    (Japanese, RemoveHost) => "ホストを削除"
    (English, Rename) => "Rename"
    (Spanish, Rename) => "Cambiar nombre"
    (SimplifiedChinese, Rename) => "重命名"
    (TraditionalChinese, Rename) => "重新命名"
    (Japanese, Rename) => "名前を変更"
    (English, CloseDialog) => "Close SSH dialog"
    (Spanish, CloseDialog) => "Cerrar diálogo SSH"
    (SimplifiedChinese, CloseDialog) => "关闭 SSH 对话框"
    (TraditionalChinese, CloseDialog) => "關閉 SSH 對話方塊"
    (Japanese, CloseDialog) => "SSH ダイアログを閉じる"
    (English, PasswordFor(target)) => "Password for \{target}"
    (Spanish, PasswordFor(target)) => "Contraseña de \{target}"
    (SimplifiedChinese, PasswordFor(target)) => "\{target} 的密码"
    (TraditionalChinese, PasswordFor(target)) => "\{target} 的密碼"
    (Japanese, PasswordFor(target)) => "\{target} のパスワード"
    (English, PassphraseFor(target)) => "Passphrase for \{target}"
    (Spanish, PassphraseFor(target)) => "Frase de contraseña de \{target}"
    (SimplifiedChinese, PassphraseFor(target)) => "\{target} 的密钥口令"
    (TraditionalChinese, PassphraseFor(target)) => "\{target} 的金鑰密語"
    (Japanese, PassphraseFor(target)) => "\{target} のパスフレーズ"
    (English, ConfirmIdentity) => "Confirm host identity"
    (Spanish, ConfirmIdentity) => "Confirmar identidad del host"
    (SimplifiedChinese, ConfirmIdentity) => "确认主机身份"
    (TraditionalChinese, ConfirmIdentity) => "確認主機身分"
    (Japanese, ConfirmIdentity) => "ホストの身元を確認"
    (English, AuthenticationFailed) =>
      "Authentication failed. Enter your password again."
    (Spanish, AuthenticationFailed) =>
      "Error de autenticación. Introduce tu contraseña de nuevo."
    (SimplifiedChinese, AuthenticationFailed) =>
      "身份验证失败。请重新输入密码。"
    (TraditionalChinese, AuthenticationFailed) =>
      "身分驗證失敗。請重新輸入密碼。"
    (Japanese, AuthenticationFailed) =>
      "認証に失敗しました。パスワードを再入力してください。"
    (English, HidePassword) => "Hide password"
    (Spanish, HidePassword) => "Ocultar contraseña"
    (SimplifiedChinese, HidePassword) => "隐藏密码"
    (TraditionalChinese, HidePassword) => "隱藏密碼"
    (Japanese, HidePassword) => "パスワードを隠す"
    (English, ShowPassword) => "Show password"
    (Spanish, ShowPassword) => "Mostrar contraseña"
    (SimplifiedChinese, ShowPassword) => "显示密码"
    (TraditionalChinese, ShowPassword) => "顯示密碼"
    (Japanese, ShowPassword) => "パスワードを表示"
    (English, Hide) => "Hide"
    (Spanish, Hide) => "Ocultar"
    (SimplifiedChinese, Hide) => "隐藏"
    (TraditionalChinese, Hide) => "隱藏"
    (Japanese, Hide) => "隠す"
    (English, Show) => "Show"
    (Spanish, Show) => "Mostrar"
    (SimplifiedChinese, Show) => "显示"
    (TraditionalChinese, Show) => "顯示"
    (Japanese, Show) => "表示"
    (English, SecretHelp) => "Used for this connection only. Not saved."
    (Spanish, SecretHelp) =>
      "Solo se utiliza para esta conexión. No se guarda."
    (SimplifiedChinese, SecretHelp) => "仅用于此次连接，不会保存。"
    (TraditionalChinese, SecretHelp) =>
      "僅用於此次連線，不會儲存。"
    (Japanese, SecretHelp) =>
      "この接続にのみ使用され、保存されません。"
    (English, Accept) => "Accept"
    (Spanish, Accept) => "Aceptar"
    (SimplifiedChinese, Accept) => "接受"
    (TraditionalChinese, Accept) => "接受"
    (Japanese, Accept) => "承認"
    (English, TryAgain) => "Try again"
    (Spanish, TryAgain) => "Reintentar"
    (SimplifiedChinese, TryAgain) => "重试"
    (TraditionalChinese, TryAgain) => "重試"
    (Japanese, TryAgain) => "再試行"
    (English, Continue) => "Continue"
    (Spanish, Continue) => "Continuar"
    (SimplifiedChinese, Continue) => "继续"
    (TraditionalChinese, Continue) => "繼續"
    (Japanese, Continue) => "続行"
    (English, AuthKeys) => "Enter to continue · Esc to cancel"
    (Spanish, AuthKeys) => "Intro para continuar · Esc para cancelar"
    (SimplifiedChinese, AuthKeys) => "按 Enter 继续 · 按 Esc 取消"
    (TraditionalChinese, AuthKeys) => "按 Enter 繼續 · 按 Esc 取消"
    (Japanese, AuthKeys) => "Enter で続行 · Esc でキャンセル"
    (English, ProtocolRequiresLocalUpdate(host, expected, remote)) =>
      "Cannot connect to SSH host “\{host}”: the local SeekMoon and remote openseek-app-server use incompatible protocol versions. Local requires: \{expected}; remote reported: \{remote}. Update SeekMoon on this computer to a version compatible with the remote server, then reconnect."
    (Spanish, ProtocolRequiresLocalUpdate(host, expected, remote)) =>
      "No se puede conectar al host SSH «\{host}»: SeekMoon local y openseek-app-server remoto usan versiones de protocolo incompatibles. Versión requerida localmente: \{expected}; indicada por el servidor: \{remote}. Actualiza SeekMoon en este equipo a una versión compatible con el servidor remoto y vuelve a conectar."
    (SimplifiedChinese, ProtocolRequiresLocalUpdate(host, expected, remote)) =>
      "无法连接 SSH 主机“\{host}”：本机 SeekMoon 与远端 openseek-app-server 的通信协议不兼容。本机需要协议版本：\{expected}；远端报告：\{remote}。请将本机 SeekMoon 更新到与远端服务兼容的版本，然后重新连接。"
    (TraditionalChinese, ProtocolRequiresLocalUpdate(host, expected, remote)) =>
      "無法連線 SSH 主機「\{host}」：本機 SeekMoon 與遠端 openseek-app-server 的通訊協定不相容。本機需要協定版本：\{expected}；遠端回報：\{remote}。請將本機 SeekMoon 更新至與遠端服務相容的版本，然後重新連線。"
    (Japanese, ProtocolRequiresLocalUpdate(host, expected, remote)) =>
      "SSH ホスト「\{host}」に接続できません。ローカルの SeekMoon とリモートの openseek-app-server の通信プロトコルに互換性がありません。ローカルが必要とするバージョン：\{expected}、リモートの報告：\{remote}。このコンピュータの SeekMoon をリモートサーバーと互換性のあるバージョンに更新して、再接続してください。"
    (English, ProtocolRequiresRemoteUpdate(host, expected, remote)) =>
      "Cannot connect to SSH host “\{host}”: the local SeekMoon and remote openseek-app-server use incompatible protocol versions. Local requires: \{expected}; remote reported: \{remote}. Update the remote openseek-app-server to a version compatible with this SeekMoon build, then reconnect. If using a custom remote command, check which executable it starts."
    (Spanish, ProtocolRequiresRemoteUpdate(host, expected, remote)) =>
      "No se puede conectar al host SSH «\{host}»: SeekMoon local y openseek-app-server remoto usan versiones de protocolo incompatibles. Versión requerida localmente: \{expected}; indicada por el servidor: \{remote}. Actualiza openseek-app-server remoto a una versión compatible con esta compilación de SeekMoon y vuelve a conectar. Si usas un comando remoto personalizado, comprueba qué ejecutable inicia."
    (SimplifiedChinese, ProtocolRequiresRemoteUpdate(host, expected, remote)) =>
      "无法连接 SSH 主机“\{host}”：本机 SeekMoon 与远端 openseek-app-server 的通信协议不兼容。本机需要协议版本：\{expected}；远端报告：\{remote}。请将远端 openseek-app-server 更新到与本机 SeekMoon 兼容的版本，然后重新连接。如果配置了自定义远端启动命令，请检查它实际启动的程序。"
    (TraditionalChinese, ProtocolRequiresRemoteUpdate(host, expected, remote)) =>
      "無法連線 SSH 主機「\{host}」：本機 SeekMoon 與遠端 openseek-app-server 的通訊協定不相容。本機需要協定版本：\{expected}；遠端回報：\{remote}。請將遠端 openseek-app-server 更新至與本機 SeekMoon 相容的版本，然後重新連線。如果設定了自訂遠端啟動命令，請檢查它實際啟動的程式。"
    (Japanese, ProtocolRequiresRemoteUpdate(host, expected, remote)) =>
      "SSH ホスト「\{host}」に接続できません。ローカルの SeekMoon とリモートの openseek-app-server の通信プロトコルに互換性がありません。ローカルが必要とするバージョン：\{expected}、リモートの報告：\{remote}。リモートの openseek-app-server をこの SeekMoon と互換性のあるバージョンに更新して、再接続してください。カスタムのリモート起動コマンドを使用している場合は、実際に起動する実行ファイルを確認してください。"
    (English, ProtocolVersionMissing(host, expected)) =>
      "Cannot connect to SSH host “\{host}”: the local SeekMoon and remote openseek-app-server use incompatible protocol versions. Local requires: \{expected}; remote reported: not provided or invalid. Update the remote openseek-app-server to a version compatible with this SeekMoon build, then reconnect. If using a custom remote command, check which executable it starts."
    (Spanish, ProtocolVersionMissing(host, expected)) =>
      "No se puede conectar al host SSH «\{host}»: SeekMoon local y openseek-app-server remoto usan versiones de protocolo incompatibles. Versión requerida localmente: \{expected}; indicada por el servidor: ausente o no válido. Actualiza openseek-app-server remoto a una versión compatible con esta compilación de SeekMoon y vuelve a conectar. Si usas un comando remoto personalizado, comprueba qué ejecutable inicia."
    (SimplifiedChinese, ProtocolVersionMissing(host, expected)) =>
      "无法连接 SSH 主机“\{host}”：本机 SeekMoon 与远端 openseek-app-server 的通信协议不兼容。本机需要协议版本：\{expected}；远端报告：未提供有效协议版本。请将远端 openseek-app-server 更新到与本机 SeekMoon 兼容的版本，然后重新连接。如果配置了自定义远端启动命令，请检查它实际启动的程序。"
    (TraditionalChinese, ProtocolVersionMissing(host, expected)) =>
      "無法連線 SSH 主機「\{host}」：本機 SeekMoon 與遠端 openseek-app-server 的通訊協定不相容。本機需要協定版本：\{expected}；遠端回報：未提供有效協定版本。請將遠端 openseek-app-server 更新至與本機 SeekMoon 相容的版本，然後重新連線。如果設定了自訂遠端啟動命令，請檢查它實際啟動的程式。"
    (Japanese, ProtocolVersionMissing(host, expected)) =>
      "SSH ホスト「\{host}」に接続できません。ローカルの SeekMoon とリモートの openseek-app-server の通信プロトコルに互換性がありません。ローカルが必要とするバージョン：\{expected}、リモートの報告：有効なバージョンがありません。リモートの openseek-app-server をこの SeekMoon と互換性のあるバージョンに更新して、再接続してください。カスタムのリモート起動コマンドを使用している場合は、実際に起動する実行ファイルを確認してください。"
  }
}
