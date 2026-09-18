// Feature-owned UI messages; all built-in languages are exhaustive.

///|
/// Settings-page messages, kept independent of the application model.
pub(all) enum Message {
  DevicePageDescription(String, String)
  RegisterServer(String)
  UpdateTo(String)
  CannotInstallUpdate(String)
  RestartingVersion(String)
  DownloadProgress(String, Int, Int, Int)
  DownloadBytes(String, Int)
  DownloadVersion(String)
  Status
  Account
  SignOut
  SignOutDescription
  SignIn
  SignInChatGPT
  CodexAccountDescription
  SignInPage
  Open
  CancelSignIn
  FinishSignIn
  Configuration
  OpenConfig
  ConfigDescription
  RemoteControl
  CheckingSignIn
  EnvironmentRelay
  OnlineRelay
  ConnectingRelay
  SignedInAs
  Disconnect
  ThisMachine
  DevicePage
  RegisterRelay
  WaitingBrowser
  ConnectGitHub
  Cancel
  Problem
  CheckingUpdate
  UpToDate
  DeepseekHint
  GlmHint
  OpenRouterHint
  CustomHint
  DeepseekStepOne
  CreateKey
  DeepseekPasteKey
  GlmStepOne
  GlmPasteKey
  OpenRouterStepOne
  OpenRouterPasteKey
  StartEndpoint
  EnterEndpoint
  OptionalEndpointKey
  OwnProviderDescription
  DeepseekKeysLink
  GlmKeysLink
  ApiEndpoint
  DeepseekOfficial
  GlmOfficial
  CustomUrl
  EndpointUrl
  DeepseekApiKey
  GlmApiKey
  OpenRouterApiKey
  CustomApiKey
  SavedKey
  ApiKey
  SaveApiKey
  KeyStorageDescription
  Language
  LanguageDescription
  System
  Settings
  Preferences
  Interface
  Engine
  MaxSteps
  MaxStepsDescription
  Followup
  Steer
  Queue
  FollowupDescription
  Theme
  Light
  Dark
  ThemeDescription
  FontSize
  FontSizeDescription
  NotificationCorner
  BottomRight
  BottomLeft
  TopRight
  TopLeft
  NotificationDescription
  FileTreeLayout
  RightSidebar
  BottomPanel
  FileTreeDescription
  Diagnostics
  FpsOverlay
  On
  Off
  FpsDescription
  RemoteAccess
  Updates
  CheckUpdates
  LoadingSettings
  RuntimeSettings
  DeepseekKey
  GlmKey
  OpenRouterKey
  CustomEndpoint
  CurrentVersion(String)
  LanguageStorageFailed(String)
}

///|
/// Render one Settings message in a built-in language.
///
/// ```mbt check
/// test {
///   assert_eq(@settings.text(@i18n.SimplifiedChinese, Language), "语言")
///   assert_eq(@settings.text(@i18n.English, Language), "Language")
/// }
/// ```
pub fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, DevicePageDescription(name, url)) =>
      "\{name} — open \{url} in a signed-in browser."
    (SimplifiedChinese, DevicePageDescription(name, url)) =>
      "\{name} — 在已登录的浏览器中打开 \{url}。"
    (TraditionalChinese, DevicePageDescription(name, url)) =>
      "\{name} — 在已登入的瀏覽器中開啟 \{url}。"
    (Japanese, DevicePageDescription(name, url)) =>
      "\{name} — ログイン済みのブラウザーで \{url} を開いてください。"
    (English, RegisterServer(server)) =>
      "Registers this machine at \{server} so your browser can drive it."
    (SimplifiedChinese, RegisterServer(server)) =>
      "将此设备注册到 \{server}，以便通过浏览器远程控制。"
    (TraditionalChinese, RegisterServer(server)) =>
      "將此裝置註冊到 \{server}，以便透過瀏覽器遠端控制。"
    (Japanese, RegisterServer(server)) =>
      "このデバイスを \{server} に登録し、ブラウザーからリモート操作できるようにします。"
    (English, UpdateTo(version)) => "Update to \{version}"
    (SimplifiedChinese, UpdateTo(version)) => "更新至 \{version}"
    (TraditionalChinese, UpdateTo(version)) => "更新至 \{version}"
    (Japanese, UpdateTo(version)) => "\{version} に更新"
    (English, CannotInstallUpdate(version)) =>
      "\{version} is available, but this build cannot install updates."
    (SimplifiedChinese, CannotInstallUpdate(version)) =>
      "发现新版本 \{version}，但当前构建无法安装更新。"
    (TraditionalChinese, CannotInstallUpdate(version)) =>
      "發現新版本 \{version}，但當前構建無法安裝更新。"
    (Japanese, CannotInstallUpdate(version)) =>
      "新しいバージョン \{version} がありますが、このビルドでは更新をインストールできません。"
    (English, RestartingVersion(version)) => "Restarting into \{version}…"
    (SimplifiedChinese, RestartingVersion(version)) =>
      "正在重启以使用 \{version}…"
    (TraditionalChinese, RestartingVersion(version)) =>
      "正在重啟以使用 \{version}…"
    (Japanese, RestartingVersion(version)) =>
      "\{version} を使用するために再起動中…"
    (English, DownloadProgress(version, percent, downloaded, total)) =>
      "Downloading \{version}… \{percent}% (\{downloaded} / \{total} MB)"
    (SimplifiedChinese, DownloadProgress(version, percent, downloaded, total)) =>
      "正在下载 \{version}… \{percent}%（\{downloaded} / \{total} MB）"
    (TraditionalChinese, DownloadProgress(version, percent, downloaded, total)) =>
      "正在下載 \{version}… \{percent}%（\{downloaded} / \{total} MB）"
    (Japanese, DownloadProgress(version, percent, downloaded, total)) =>
      "\{version} をダウンロード中… \{percent}%（\{downloaded} / \{total} MB）"
    (English, DownloadBytes(version, downloaded)) =>
      "Downloading \{version}… \{downloaded} MB"
    (SimplifiedChinese, DownloadBytes(version, downloaded)) =>
      "正在下载 \{version}… \{downloaded} MB"
    (TraditionalChinese, DownloadBytes(version, downloaded)) =>
      "正在下載 \{version}… \{downloaded} MB"
    (Japanese, DownloadBytes(version, downloaded)) =>
      "\{version} をダウンロード中… \{downloaded} MB"
    (English, DownloadVersion(version)) => "Downloading \{version}…"
    (SimplifiedChinese, DownloadVersion(version)) =>
      "正在下载 \{version}…"
    (TraditionalChinese, DownloadVersion(version)) =>
      "正在下載 \{version}…"
    (Japanese, DownloadVersion(version)) =>
      "\{version} をダウンロード中…"
    (English, Status) => "Status"
    (SimplifiedChinese, Status) => "状态"
    (TraditionalChinese, Status) => "狀態"
    (Japanese, Status) => "状態"
    (English, Account) => "Account"
    (SimplifiedChinese, Account) => "账户"
    (TraditionalChinese, Account) => "帳戶"
    (Japanese, Account) => "アカウント"
    (English, SignOut) => "Sign out"
    (SimplifiedChinese, SignOut) => "退出登录"
    (TraditionalChinese, SignOut) => "退出登入"
    (Japanese, SignOut) => "ログアウト"
    (English, SignOutDescription) =>
      "Signing out removes the ChatGPT credentials this desktop's Codex uses."
    (SimplifiedChinese, SignOutDescription) =>
      "退出登录将移除此桌面应用中 Codex 使用的 ChatGPT 凭据。"
    (TraditionalChinese, SignOutDescription) =>
      "退出登入將移除此桌面應用中 Codex 使用的 ChatGPT 憑據。"
    (Japanese, SignOutDescription) =>
      "ログアウトすると、このデスクトップの Codex が使用する ChatGPT の認証情報が削除されます。"
    (English, SignIn) => "Sign in"
    (SimplifiedChinese, SignIn) => "登录"
    (TraditionalChinese, SignIn) => "登入"
    (Japanese, SignIn) => "ログイン"
    (English, SignInChatGPT) => "Sign in with ChatGPT"
    (SimplifiedChinese, SignInChatGPT) => "使用 ChatGPT 登录"
    (TraditionalChinese, SignInChatGPT) => "使用 ChatGPT 登入"
    (Japanese, SignInChatGPT) => "ChatGPT でログイン"
    (English, CodexAccountDescription) =>
      "Codex conversations run with your ChatGPT account."
    (SimplifiedChinese, CodexAccountDescription) =>
      "Codex 对话使用你的 ChatGPT 账户运行。"
    (TraditionalChinese, CodexAccountDescription) =>
      "Codex 對話使用你的 ChatGPT 帳戶執行。"
    (Japanese, CodexAccountDescription) =>
      "Codex チャットはあなたの ChatGPT アカウントで実行されます。"
    (English, SignInPage) => "Sign-in page"
    (SimplifiedChinese, SignInPage) => "登录页面"
    (TraditionalChinese, SignInPage) => "登入頁面"
    (Japanese, SignInPage) => "ログインページ"
    (English, Open) => "Open"
    (SimplifiedChinese, Open) => "打开"
    (TraditionalChinese, Open) => "開啟"
    (Japanese, Open) => "開く"
    (English, CancelSignIn) => "Cancel sign-in"
    (SimplifiedChinese, CancelSignIn) => "取消登录"
    (TraditionalChinese, CancelSignIn) => "取消登入"
    (Japanese, CancelSignIn) => "ログインをキャンセル"
    (English, FinishSignIn) =>
      "Finish signing in on the browser page, or cancel the attempt."
    (SimplifiedChinese, FinishSignIn) =>
      "请在浏览器页面完成登录，或取消本次登录。"
    (TraditionalChinese, FinishSignIn) =>
      "請在瀏覽器頁面完成登入，或取消本次登入。"
    (Japanese, FinishSignIn) =>
      "ブラウザーでログインを完了するか、今回のログインをキャンセルしてください。"
    (English, Configuration) => "Configuration"
    (SimplifiedChinese, Configuration) => "配置"
    (TraditionalChinese, Configuration) => "配置"
    (Japanese, Configuration) => "構成"
    (English, OpenConfig) => "Open config.toml"
    (SimplifiedChinese, OpenConfig) => "打开 config.toml"
    (TraditionalChinese, OpenConfig) => "開啟 config.toml"
    (Japanese, OpenConfig) => "config.toml を開く"
    (English, ConfigDescription) =>
      "config.toml in this desktop's Codex home, created empty if missing. The app-server reads it at startup, so edits apply after the desktop restarts."
    (SimplifiedChinese, ConfigDescription) =>
      "打开此桌面应用 Codex 目录中的 config.toml；文件不存在时会创建空文件。应用服务在启动时读取配置，修改将在重启桌面应用后生效。"
    (TraditionalChinese, ConfigDescription) =>
      "開啟此桌面應用 Codex 目錄中的 config.toml；檔案不存在時會建立空檔案。應用服務在啟動時讀取配置，修改將在重啟桌面應用後生效。"
    (Japanese, ConfigDescription) =>
      "このデスクトップの Codex ディレクトリにある config.toml を開きます。存在しない場合は空のファイルを作成します。アプリサーバーは起動時に設定を読み込むため、変更は再起動後に適用されます。"
    (English, RemoteControl) => "Remote control"
    (SimplifiedChinese, RemoteControl) => "远程控制"
    (TraditionalChinese, RemoteControl) => "遠端控制"
    (Japanese, RemoteControl) => "リモート操作"
    (English, CheckingSignIn) => "Checking sign-in…"
    (SimplifiedChinese, CheckingSignIn) => "正在检查登录状态…"
    (TraditionalChinese, CheckingSignIn) => "正在檢查登入狀態…"
    (Japanese, CheckingSignIn) => "ログイン状態を確認中…"
    (English, EnvironmentRelay) =>
      "Configured through the environment (OPENSEEK_RELAY_URL); sign-in is disabled."
    (SimplifiedChinese, EnvironmentRelay) =>
      "已通过环境变量 OPENSEEK_RELAY_URL 配置，登录功能已禁用。"
    (TraditionalChinese, EnvironmentRelay) =>
      "已透過環境變數 OPENSEEK_RELAY_URL 配置，登入功能已禁用。"
    (Japanese, EnvironmentRelay) =>
      "環境変数 OPENSEEK_RELAY_URL で設定済みのため、ログインは無効です。"
    (English, OnlineRelay) => "online — reachable from your browser"
    (SimplifiedChinese, OnlineRelay) => "在线，可通过浏览器访问"
    (TraditionalChinese, OnlineRelay) => "線上，可透過瀏覽器訪問"
    (Japanese, OnlineRelay) =>
      "オンライン、ブラウザーからアクセス可能"
    (English, ConnectingRelay) => "connecting to the relay…"
    (SimplifiedChinese, ConnectingRelay) => "正在连接中继服务…"
    (TraditionalChinese, ConnectingRelay) => "正在連線中繼服務…"
    (Japanese, ConnectingRelay) => "リレーサービスに接続中…"
    (English, SignedInAs) => "Signed in as"
    (SimplifiedChinese, SignedInAs) => "已登录账户"
    (TraditionalChinese, SignedInAs) => "已登入帳戶"
    (Japanese, SignedInAs) => "ログイン中のアカウント"
    (English, Disconnect) => "Disconnect"
    (SimplifiedChinese, Disconnect) => "断开连接"
    (TraditionalChinese, Disconnect) => "斷開連線"
    (Japanese, Disconnect) => "切断"
    (English, ThisMachine) => "this machine"
    (SimplifiedChinese, ThisMachine) => "此设备"
    (TraditionalChinese, ThisMachine) => "此裝置"
    (Japanese, ThisMachine) => "このデバイス"
    (English, DevicePage) => "Device page"
    (SimplifiedChinese, DevicePage) => "设备页面"
    (TraditionalChinese, DevicePage) => "裝置頁面"
    (Japanese, DevicePage) => "デバイスページ"
    (English, RegisterRelay) =>
      "Registers this machine so your browser can drive it through the relay."
    (SimplifiedChinese, RegisterRelay) =>
      "注册此设备，以便通过中继服务在浏览器中远程控制。"
    (TraditionalChinese, RegisterRelay) =>
      "註冊此裝置，以便透過中繼服務在瀏覽器中遠端控制。"
    (Japanese, RegisterRelay) =>
      "このデバイスを登録し、リレーサービス経由でブラウザーからリモート操作します。"
    (English, WaitingBrowser) => "Waiting for the browser…"
    (SimplifiedChinese, WaitingBrowser) => "正在等待浏览器…"
    (TraditionalChinese, WaitingBrowser) => "正在等待瀏覽器…"
    (Japanese, WaitingBrowser) => "ブラウザーを待機中…"
    (English, ConnectGitHub) => "Connect with GitHub"
    (SimplifiedChinese, ConnectGitHub) => "使用 GitHub 连接"
    (TraditionalChinese, ConnectGitHub) => "使用 GitHub 連線"
    (Japanese, ConnectGitHub) => "GitHub で接続"
    (English, Cancel) => "Cancel"
    (SimplifiedChinese, Cancel) => "取消"
    (TraditionalChinese, Cancel) => "取消"
    (Japanese, Cancel) => "キャンセル"
    (English, Problem) => "Problem"
    (SimplifiedChinese, Problem) => "问题"
    (TraditionalChinese, Problem) => "問題"
    (Japanese, Problem) => "質問"
    (English, CheckingUpdate) => "Checking…"
    (SimplifiedChinese, CheckingUpdate) => "正在检查…"
    (TraditionalChinese, CheckingUpdate) => "正在檢查…"
    (Japanese, CheckingUpdate) => "確認中…"
    (English, UpToDate) => "You are up to date."
    (SimplifiedChinese, UpToDate) => "已是最新版本。"
    (TraditionalChinese, UpToDate) => "已是最新版本。"
    (Japanese, UpToDate) => "最新バージョンです。"
    (English, DeepseekHint) =>
      "Requests go straight to api.deepseek.com with your key."
    (SimplifiedChinese, DeepseekHint) =>
      "请求使用你的密钥直接发送至 api.deepseek.com。"
    (TraditionalChinese, DeepseekHint) =>
      "請求使用你的金鑰直接傳送至 api.deepseek.com。"
    (Japanese, DeepseekHint) =>
      "リクエストはあなたのキーを使用して api.deepseek.com に直接送信されます。"
    (English, GlmHint) => "Requests go straight to api.z.ai with your key."
    (SimplifiedChinese, GlmHint) =>
      "请求使用你的密钥直接发送至 api.z.ai。"
    (TraditionalChinese, GlmHint) =>
      "請求使用你的金鑰直接傳送至 api.z.ai。"
    (Japanese, GlmHint) =>
      "リクエストはあなたのキーを使用して api.z.ai に直接送信されます。"
    (English, OpenRouterHint) =>
      "DeepSeek requests go through OpenRouter with your key."
    (SimplifiedChinese, OpenRouterHint) =>
      "DeepSeek 请求使用你的密钥通过 OpenRouter 发送。"
    (TraditionalChinese, OpenRouterHint) =>
      "DeepSeek 請求使用你的金鑰透過 OpenRouter 傳送。"
    (Japanese, OpenRouterHint) =>
      "DeepSeek へのリクエストは、あなたのキーで OpenRouter 経由で送信されます。"
    (English, CustomHint) =>
      "Any OpenAI-compatible chat-completions URL; key optional."
    (SimplifiedChinese, CustomHint) =>
      "支持任意兼容 OpenAI 的 chat-completions URL；密钥可选。"
    (TraditionalChinese, CustomHint) =>
      "支援任意相容 OpenAI 的 chat-completions URL；金鑰可選。"
    (Japanese, CustomHint) =>
      "OpenAI 互換の chat-completions URL に対応しています。キーは任意です。"
    (English, DeepseekStepOne) => "Open platform.deepseek.com and sign in."
    (SimplifiedChinese, DeepseekStepOne) =>
      "打开 platform.deepseek.com 并登录。"
    (TraditionalChinese, DeepseekStepOne) =>
      "開啟 platform.deepseek.com 並登入。"
    (Japanese, DeepseekStepOne) =>
      "platform.deepseek.com を開いてログインしてください。"
    (English, CreateKey) => "Create an API key under API Keys."
    (SimplifiedChinese, CreateKey) => "在 API Keys 页面创建 API 密钥。"
    (TraditionalChinese, CreateKey) => "在 API Keys 頁面建立 API 金鑰。"
    (Japanese, CreateKey) =>
      "API Keys ページで API キーを作成してください。"
    (English, DeepseekPasteKey) =>
      "Paste it into the DeepSeek API key field below and save."
    (SimplifiedChinese, DeepseekPasteKey) =>
      "将密钥粘贴至下方 DeepSeek API 密钥输入框并保存。"
    (TraditionalChinese, DeepseekPasteKey) =>
      "將金鑰貼上至下方 DeepSeek API 金鑰輸入框並儲存。"
    (Japanese, DeepseekPasteKey) =>
      "下の DeepSeek API キー欄に貼り付けて保存してください。"
    (English, GlmStepOne) => "Open z.ai and sign in."
    (SimplifiedChinese, GlmStepOne) => "打开 z.ai 并登录。"
    (TraditionalChinese, GlmStepOne) => "開啟 z.ai 並登入。"
    (Japanese, GlmStepOne) =>
      "z.ai を開いてログインしてください。"
    (English, GlmPasteKey) =>
      "Paste it into the GLM API key field below and save."
    (SimplifiedChinese, GlmPasteKey) =>
      "将密钥粘贴至下方 GLM API 密钥输入框并保存。"
    (TraditionalChinese, GlmPasteKey) =>
      "將金鑰貼上至下方 GLM API 金鑰輸入框並儲存。"
    (Japanese, GlmPasteKey) =>
      "下の GLM API キー欄に貼り付けて保存してください。"
    (English, OpenRouterStepOne) => "Open openrouter.ai and create an API key."
    (SimplifiedChinese, OpenRouterStepOne) =>
      "打开 openrouter.ai 并创建 API 密钥。"
    (TraditionalChinese, OpenRouterStepOne) =>
      "開啟 openrouter.ai 並建立 API 金鑰。"
    (Japanese, OpenRouterStepOne) =>
      "openrouter.ai を開いて API キーを作成してください。"
    (English, OpenRouterPasteKey) => "Paste the OpenRouter API key and save."
    (SimplifiedChinese, OpenRouterPasteKey) =>
      "粘贴 OpenRouter API 密钥并保存。"
    (TraditionalChinese, OpenRouterPasteKey) =>
      "貼上 OpenRouter API 金鑰並儲存。"
    (Japanese, OpenRouterPasteKey) =>
      "OpenRouter API キーを貼り付けて保存してください。"
    (English, StartEndpoint) =>
      "Start an OpenAI-compatible endpoint (Ollama, LM Studio, a proxy…)."
    (SimplifiedChinese, StartEndpoint) =>
      "启动兼容 OpenAI 的服务端点（Ollama、LM Studio、代理服务等）。"
    (TraditionalChinese, StartEndpoint) =>
      "啟動相容 OpenAI 的服務端點（Ollama、LM Studio、代理服務等）。"
    (Japanese, StartEndpoint) =>
      "OpenAI 互換のエンドポイント（Ollama、LM Studio、プロキシなど）を起動してください。"
    (English, EnterEndpoint) => "Enter its chat-completions URL below."
    (SimplifiedChinese, EnterEndpoint) =>
      "在下方输入其 chat-completions URL。"
    (TraditionalChinese, EnterEndpoint) =>
      "在下方輸入其 chat-completions URL。"
    (Japanese, EnterEndpoint) =>
      "その chat-completions URL を下に入力してください。"
    (English, OptionalEndpointKey) =>
      "Add the endpoint's key if it requires one."
    (SimplifiedChinese, OptionalEndpointKey) =>
      "如果端点需要密钥，请填写密钥。"
    (TraditionalChinese, OptionalEndpointKey) =>
      "如果端點需要金鑰，請填寫金鑰。"
    (Japanese, OptionalEndpointKey) =>
      "エンドポイントにキーが必要な場合は入力してください。"
    (English, OwnProviderDescription) =>
      "SeekMoon does not provide a hosted API. Requests go straight from this machine to your own model provider, billed to your account. Your API key is stored only on this machine — SeekMoon never reads it."
    (SimplifiedChinese, OwnProviderDescription) =>
      "SeekMoon 不提供托管 API。请求从此设备直接发送至你选择的模型服务商，费用由你的账户承担。API 密钥仅保存在此设备上，SeekMoon 不会读取它。"
    (TraditionalChinese, OwnProviderDescription) =>
      "SeekMoon 不提供託管 API。請求從此裝置直接傳送至你選擇的模型服務商，費用由你的帳戶承擔。API 金鑰僅儲存在此裝置上，SeekMoon 不會讀取它。"
    (Japanese, OwnProviderDescription) =>
      "SeekMoon はホスト型 API を提供していません。リクエストはこのデバイスから選択したモデルプロバイダーに直接送信され、料金はあなたのアカウントに請求されます。API キーはこのデバイスにのみ保存され、SeekMoon が読み取ることはありません。"
    (English, DeepseekKeysLink) => "platform.deepseek.com → API Keys"
    (SimplifiedChinese, DeepseekKeysLink) =>
      "platform.deepseek.com → API 密钥"
    (TraditionalChinese, DeepseekKeysLink) =>
      "platform.deepseek.com → API 金鑰"
    (Japanese, DeepseekKeysLink) => "platform.deepseek.com → API キー"
    (English, GlmKeysLink) => "z.ai → API Keys"
    (SimplifiedChinese, GlmKeysLink) => "z.ai → API 密钥"
    (TraditionalChinese, GlmKeysLink) => "z.ai → API 金鑰"
    (Japanese, GlmKeysLink) => "z.ai → API キー"
    (English, ApiEndpoint) => "API endpoint"
    (SimplifiedChinese, ApiEndpoint) => "API 端点"
    (TraditionalChinese, ApiEndpoint) => "API 端點"
    (Japanese, ApiEndpoint) => "API エンドポイント"
    (English, DeepseekOfficial) => "DeepSeek official (your API key)"
    (SimplifiedChinese, DeepseekOfficial) => "DeepSeek 官方"
    (TraditionalChinese, DeepseekOfficial) => "DeepSeek 官方"
    (Japanese, DeepseekOfficial) => "DeepSeek 公式"
    (English, GlmOfficial) => "Z.AI GLM (your API key)"
    (SimplifiedChinese, GlmOfficial) => "Z.AI GLM"
    (TraditionalChinese, GlmOfficial) => "Z.AI GLM"
    (Japanese, GlmOfficial) => "Z.AI GLM"
    (English, CustomUrl) => "Custom URL"
    (SimplifiedChinese, CustomUrl) => "自定义 URL"
    (TraditionalChinese, CustomUrl) => "自定義 URL"
    (Japanese, CustomUrl) => "カスタム URL"
    (English, EndpointUrl) => "Endpoint URL"
    (SimplifiedChinese, EndpointUrl) => "端点 URL"
    (TraditionalChinese, EndpointUrl) => "端點 URL"
    (Japanese, EndpointUrl) => "エンドポイント URL"
    (English, DeepseekApiKey) => "DeepSeek API key"
    (SimplifiedChinese, DeepseekApiKey) => "DeepSeek API 密钥"
    (TraditionalChinese, DeepseekApiKey) => "DeepSeek API 金鑰"
    (Japanese, DeepseekApiKey) => "DeepSeek API キー"
    (English, GlmApiKey) => "GLM API key"
    (SimplifiedChinese, GlmApiKey) => "GLM API 密钥"
    (TraditionalChinese, GlmApiKey) => "GLM API 金鑰"
    (Japanese, GlmApiKey) => "GLM API キー"
    (English, OpenRouterApiKey) => "OpenRouter API key"
    (SimplifiedChinese, OpenRouterApiKey) => "OpenRouter API 密钥"
    (TraditionalChinese, OpenRouterApiKey) => "OpenRouter API 金鑰"
    (Japanese, OpenRouterApiKey) => "OpenRouter API キー"
    (English, CustomApiKey) => "Custom API key"
    (SimplifiedChinese, CustomApiKey) => "自定义 API 密钥"
    (TraditionalChinese, CustomApiKey) => "自定義 API 金鑰"
    (Japanese, CustomApiKey) => "カスタム API キー"
    (English, SavedKey) => "saved — enter to replace"
    (SimplifiedChinese, SavedKey) => "已保存，输入新密钥可替换"
    (TraditionalChinese, SavedKey) => "已儲存，輸入新金鑰可替換"
    (Japanese, SavedKey) =>
      "保存済み — 新しいキーを入力すると置き換えます"
    (English, ApiKey) => "API key"
    (SimplifiedChinese, ApiKey) => "API 密钥"
    (TraditionalChinese, ApiKey) => "API 金鑰"
    (Japanese, ApiKey) => "API キー"
    (English, SaveApiKey) => "Save API key"
    (SimplifiedChinese, SaveApiKey) => "保存 API 密钥"
    (TraditionalChinese, SaveApiKey) => "儲存 API 金鑰"
    (Japanese, SaveApiKey) => "API キーを保存"
    (English, KeyStorageDescription) =>
      "Stored on this machine and sent only with API requests. SeekMoon never reads it."
    (SimplifiedChinese, KeyStorageDescription) =>
      "保存在此设备上，仅随 API 请求发送。SeekMoon 不会读取它。"
    (TraditionalChinese, KeyStorageDescription) =>
      "儲存在此裝置上，僅隨 API 請求傳送。SeekMoon 不會讀取它。"
    (Japanese, KeyStorageDescription) =>
      "このデバイスに保存され、API リクエストでのみ送信されます。SeekMoon が読み取ることはありません。"
    (English, Language) => "Language"
    (SimplifiedChinese, Language) => "语言"
    (TraditionalChinese, Language) => "語言"
    (Japanese, Language) => "言語"
    (English, LanguageDescription) =>
      "Language for app controls. System follows your preferred languages."
    (SimplifiedChinese, LanguageDescription) =>
      "应用界面的语言。选择“跟随系统”将使用系统的首选语言。"
    (TraditionalChinese, LanguageDescription) =>
      "應用介面的語言。選擇“跟隨系統”將使用系統的首選語言。"
    (Japanese, LanguageDescription) =>
      "アプリの表示言語です。「システムに従う」ではシステムの優先言語を使用します。"
    (English, System) => "System"
    (SimplifiedChinese, System) => "跟随系统"
    (TraditionalChinese, System) => "跟隨系統"
    (Japanese, System) => "システムに従う"
    (English, Settings) => "Settings"
    (SimplifiedChinese, Settings) => "设置"
    (TraditionalChinese, Settings) => "設定"
    (Japanese, Settings) => "設定"
    (English, Preferences) => "Preferences"
    (SimplifiedChinese, Preferences) => "偏好设置"
    (TraditionalChinese, Preferences) => "偏好設定"
    (Japanese, Preferences) => "環境設定"
    (English, Interface) => "Interface"
    (SimplifiedChinese, Interface) => "界面"
    (TraditionalChinese, Interface) => "介面"
    (Japanese, Interface) => "インターフェース"
    (English, Engine) => "Engine"
    (SimplifiedChinese, Engine) => "引擎"
    (TraditionalChinese, Engine) => "引擎"
    (Japanese, Engine) => "エンジン"
    (English, MaxSteps) => "Max steps"
    (SimplifiedChinese, MaxSteps) => "最大步数"
    (TraditionalChinese, MaxSteps) => "最大步數"
    (Japanese, MaxSteps) => "最大ステップ数"
    (English, MaxStepsDescription) => "How many agent steps one turn may take."
    (SimplifiedChinese, MaxStepsDescription) =>
      "每轮任务允许执行的最大步骤数。"
    (TraditionalChinese, MaxStepsDescription) =>
      "每輪任務允許執行的最大步驟數。"
    (Japanese, MaxStepsDescription) =>
      "1 ターンでエージェントが実行できる最大ステップ数。"
    (English, Followup) => "Follow-up messages"
    (SimplifiedChinese, Followup) => "后续消息"
    (TraditionalChinese, Followup) => "後續訊息"
    (Japanese, Followup) => "追加メッセージ"
    (English, Steer) => "Steer"
    (SimplifiedChinese, Steer) => "立即引导"
    (TraditionalChinese, Steer) => "立即引導"
    (Japanese, Steer) => "今すぐ指示"
    (English, Queue) => "Queue"
    (SimplifiedChinese, Queue) => "加入队列"
    (TraditionalChinese, Queue) => "加入佇列"
    (Japanese, Queue) => "キューに追加"
    (English, FollowupDescription) =>
      "Default for messages sent while a task is running. Change it for one message beside the send button."
    (SimplifiedChinese, FollowupDescription) =>
      "任务运行期间发送消息的默认方式。可在发送按钮旁为单条消息更改。"
    (TraditionalChinese, FollowupDescription) =>
      "任務執行期間傳送訊息的預設方式。可在傳送按鈕旁為單條訊息更改。"
    (Japanese, FollowupDescription) =>
      "タスク実行中に送信するメッセージの既定の処理方法です。送信ボタンの隣でメッセージごとに変更できます。"
    (English, Theme) => "Theme"
    (SimplifiedChinese, Theme) => "主题"
    (TraditionalChinese, Theme) => "主題"
    (Japanese, Theme) => "テーマ"
    (English, Light) => "Light"
    (SimplifiedChinese, Light) => "浅色"
    (TraditionalChinese, Light) => "淺色"
    (Japanese, Light) => "ライト"
    (English, Dark) => "Dark"
    (SimplifiedChinese, Dark) => "深色"
    (TraditionalChinese, Dark) => "深色"
    (Japanese, Dark) => "ダーク"
    (English, ThemeDescription) =>
      "Used by the app, editor, and terminal. System follows the OS appearance."
    (SimplifiedChinese, ThemeDescription) =>
      "应用于界面、编辑器和终端。选择“跟随系统”将使用系统外观。"
    (TraditionalChinese, ThemeDescription) =>
      "應用於介面、編輯器和終端。選擇“跟隨系統”將使用系統外觀。"
    (Japanese, ThemeDescription) =>
      "アプリ、エディター、ターミナルに適用します。「システムに従う」では OS の外観を使用します。"
    (English, FontSize) => "Font size"
    (SimplifiedChinese, FontSize) => "字号"
    (TraditionalChinese, FontSize) => "字型大小"
    (Japanese, FontSize) => "フォントサイズ"
    (English, FontSizeDescription) =>
      "Scales app text; code uses a visually matched monospace size."
    (SimplifiedChinese, FontSizeDescription) =>
      "调整界面文字大小；代码使用视觉大小相近的等宽字体。"
    (TraditionalChinese, FontSizeDescription) =>
      "調整介面文字大小；程式碼使用視覺大小相近的等寬字型。"
    (Japanese, FontSizeDescription) =>
      "UI の文字サイズを調整します。コードには見た目のサイズを合わせた等幅フォントを使用します。"
    (English, NotificationCorner) => "Notification corner"
    (SimplifiedChinese, NotificationCorner) => "通知位置"
    (TraditionalChinese, NotificationCorner) => "通知位置"
    (Japanese, NotificationCorner) => "通知の位置"
    (English, BottomRight) => "Bottom right"
    (SimplifiedChinese, BottomRight) => "右下角"
    (TraditionalChinese, BottomRight) => "右下角"
    (Japanese, BottomRight) => "右下"
    (English, BottomLeft) => "Bottom left"
    (SimplifiedChinese, BottomLeft) => "左下角"
    (TraditionalChinese, BottomLeft) => "左下角"
    (Japanese, BottomLeft) => "左下"
    (English, TopRight) => "Top right"
    (SimplifiedChinese, TopRight) => "右上角"
    (TraditionalChinese, TopRight) => "右上角"
    (Japanese, TopRight) => "右上"
    (English, TopLeft) => "Top left"
    (SimplifiedChinese, TopLeft) => "左上角"
    (TraditionalChinese, TopLeft) => "左上角"
    (Japanese, TopLeft) => "左上"
    (English, NotificationDescription) => "Where error notifications pop up."
    (SimplifiedChinese, NotificationDescription) =>
      "错误通知的显示位置。"
    (TraditionalChinese, NotificationDescription) =>
      "錯誤通知的顯示位置。"
    (Japanese, NotificationDescription) =>
      "エラー通知を表示する位置。"
    (English, FileTreeLayout) => "File tree layout"
    (SimplifiedChinese, FileTreeLayout) => "文件树布局"
    (TraditionalChinese, FileTreeLayout) => "檔案樹佈局"
    (Japanese, FileTreeLayout) => "ファイルツリーの配置"
    (English, RightSidebar) => "Right sidebar"
    (SimplifiedChinese, RightSidebar) => "右侧边栏"
    (TraditionalChinese, RightSidebar) => "右側邊欄"
    (Japanese, RightSidebar) => "右サイドバー"
    (English, BottomPanel) => "Bottom panel"
    (SimplifiedChinese, BottomPanel) => "底部面板"
    (TraditionalChinese, BottomPanel) => "底部面板"
    (Japanese, BottomPanel) => "下部パネル"
    (English, FileTreeDescription) =>
      "Where the editor panel docks its file tree."
    (SimplifiedChinese, FileTreeDescription) =>
      "编辑器面板中文件树的停靠位置。"
    (TraditionalChinese, FileTreeDescription) =>
      "編輯器面板中檔案樹的停靠位置。"
    (Japanese, FileTreeDescription) =>
      "エディターパネル内のファイルツリーの配置。"
    (English, Diagnostics) => "Diagnostics"
    (SimplifiedChinese, Diagnostics) => "诊断"
    (TraditionalChinese, Diagnostics) => "診斷"
    (Japanese, Diagnostics) => "診断"
    (English, FpsOverlay) => "FPS overlay"
    (SimplifiedChinese, FpsOverlay) => "帧率浮层"
    (TraditionalChinese, FpsOverlay) => "幀率浮層"
    (Japanese, FpsOverlay) => "FPS 表示"
    (English, On) => "On"
    (SimplifiedChinese, On) => "开启"
    (TraditionalChinese, On) => "開啟"
    (Japanese, On) => "オン"
    (English, Off) => "Off"
    (SimplifiedChinese, Off) => "关闭"
    (TraditionalChinese, Off) => "關閉"
    (Japanese, Off) => "オフ"
    (English, FpsDescription) =>
      "Show FPS and frame intervals at the top of the window. Off by default."
    (SimplifiedChinese, FpsDescription) =>
      "在窗口顶部显示帧率和帧间隔。默认关闭。"
    (TraditionalChinese, FpsDescription) =>
      "在視窗頂部顯示幀率和幀間隔。預設關閉。"
    (Japanese, FpsDescription) =>
      "ウィンドウ上部に FPS とフレーム間隔を表示します。既定ではオフです。"
    (English, RemoteAccess) => "Remote access"
    (SimplifiedChinese, RemoteAccess) => "远程访问"
    (TraditionalChinese, RemoteAccess) => "遠端存取"
    (Japanese, RemoteAccess) => "リモートアクセス"
    (English, Updates) => "Updates"
    (SimplifiedChinese, Updates) => "更新"
    (TraditionalChinese, Updates) => "更新"
    (Japanese, Updates) => "更新"
    (English, CheckUpdates) => "Check for updates"
    (SimplifiedChinese, CheckUpdates) => "检查更新"
    (TraditionalChinese, CheckUpdates) => "檢查更新"
    (Japanese, CheckUpdates) => "更新を確認"
    (English, LoadingSettings) => "Loading runtime settings…"
    (SimplifiedChinese, LoadingSettings) => "正在加载运行设置…"
    (TraditionalChinese, LoadingSettings) => "正在載入執行設定…"
    (Japanese, LoadingSettings) => "実行設定を読み込み中…"
    (English, RuntimeSettings) => "Runtime settings for the SeekMoon engine."
    (SimplifiedChinese, RuntimeSettings) => "SeekMoon 引擎的运行设置。"
    (TraditionalChinese, RuntimeSettings) => "SeekMoon 引擎的執行設定。"
    (Japanese, RuntimeSettings) => "SeekMoon エンジンの実行設定。"
    (English, DeepseekKey) => "Enter a DeepSeek API key to start."
    (SimplifiedChinese, DeepseekKey) =>
      "输入 DeepSeek API 密钥以开始使用。"
    (TraditionalChinese, DeepseekKey) =>
      "輸入 DeepSeek API 金鑰以開始使用。"
    (Japanese, DeepseekKey) =>
      "利用を開始するには DeepSeek API キーを入力してください。"
    (English, GlmKey) => "Enter a GLM API key to start."
    (SimplifiedChinese, GlmKey) => "输入 GLM API 密钥以开始使用。"
    (TraditionalChinese, GlmKey) => "輸入 GLM API 金鑰以開始使用。"
    (Japanese, GlmKey) =>
      "利用を開始するには GLM API キーを入力してください。"
    (English, OpenRouterKey) => "Enter an OpenRouter API key to start."
    (SimplifiedChinese, OpenRouterKey) =>
      "输入 OpenRouter API 密钥以开始使用。"
    (TraditionalChinese, OpenRouterKey) =>
      "輸入 OpenRouter API 金鑰以開始使用。"
    (Japanese, OpenRouterKey) =>
      "利用を開始するには OpenRouter API キーを入力してください。"
    (English, CustomEndpoint) =>
      "Enter a chat-completions endpoint URL to start."
    (SimplifiedChinese, CustomEndpoint) =>
      "输入 chat-completions 端点 URL 以开始使用。"
    (TraditionalChinese, CustomEndpoint) =>
      "輸入 chat-completions 端點 URL 以開始使用。"
    (Japanese, CustomEndpoint) =>
      "利用を開始するには chat-completions エンドポイント URL を入力してください。"
    (English, CurrentVersion(version)) => "Current version: \{version}."
    (SimplifiedChinese, CurrentVersion(version)) =>
      "当前版本：\{version}。"
    (TraditionalChinese, CurrentVersion(version)) =>
      "當前版本：\{version}。"
    (Japanese, CurrentVersion(version)) =>
      "現在のバージョン：\{version}。"
    (English, LanguageStorageFailed(detail)) =>
      "Could not access the language preference: \{detail}"
    (SimplifiedChinese, LanguageStorageFailed(detail)) =>
      "无法访问语言偏好设置：\{detail}"
    (TraditionalChinese, LanguageStorageFailed(detail)) =>
      "無法訪問語言偏好設定：\{detail}"
    (Japanese, LanguageStorageFailed(detail)) =>
      "言語設定にアクセスできません：\{detail}"
  }
}
