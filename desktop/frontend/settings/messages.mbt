// Feature-owned UI messages; both built-in languages are exhaustive.

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
    (English, RegisterServer(server)) =>
      "Registers this machine at \{server} so your browser can drive it."
    (SimplifiedChinese, RegisterServer(server)) =>
      "将此设备注册到 \{server}，以便通过浏览器远程控制。"
    (English, UpdateTo(version)) => "Update to \{version}"
    (SimplifiedChinese, UpdateTo(version)) => "更新至 \{version}"
    (English, CannotInstallUpdate(version)) =>
      "\{version} is available, but this build cannot install updates."
    (SimplifiedChinese, CannotInstallUpdate(version)) =>
      "发现新版本 \{version}，但当前构建无法安装更新。"
    (English, RestartingVersion(version)) => "Restarting into \{version}…"
    (SimplifiedChinese, RestartingVersion(version)) =>
      "正在重启以使用 \{version}…"
    (English, DownloadProgress(version, percent, downloaded, total)) =>
      "Downloading \{version}… \{percent}% (\{downloaded} / \{total} MB)"
    (SimplifiedChinese, DownloadProgress(version, percent, downloaded, total)) =>
      "正在下载 \{version}… \{percent}%（\{downloaded} / \{total} MB）"
    (English, DownloadBytes(version, downloaded)) =>
      "Downloading \{version}… \{downloaded} MB"
    (SimplifiedChinese, DownloadBytes(version, downloaded)) =>
      "正在下载 \{version}… \{downloaded} MB"
    (English, DownloadVersion(version)) => "Downloading \{version}…"
    (SimplifiedChinese, DownloadVersion(version)) =>
      "正在下载 \{version}…"
    (English, Status) => "Status"
    (SimplifiedChinese, Status) => "状态"
    (English, Account) => "Account"
    (SimplifiedChinese, Account) => "账户"
    (English, SignOut) => "Sign out"
    (SimplifiedChinese, SignOut) => "退出登录"
    (English, SignOutDescription) =>
      "Signing out removes the ChatGPT credentials this desktop's Codex uses."
    (SimplifiedChinese, SignOutDescription) =>
      "退出登录将移除此桌面应用中 Codex 使用的 ChatGPT 凭据。"
    (English, SignIn) => "Sign in"
    (SimplifiedChinese, SignIn) => "登录"
    (English, SignInChatGPT) => "Sign in with ChatGPT"
    (SimplifiedChinese, SignInChatGPT) => "使用 ChatGPT 登录"
    (English, CodexAccountDescription) =>
      "Codex conversations run with your ChatGPT account."
    (SimplifiedChinese, CodexAccountDescription) =>
      "Codex 对话使用你的 ChatGPT 账户运行。"
    (English, SignInPage) => "Sign-in page"
    (SimplifiedChinese, SignInPage) => "登录页面"
    (English, Open) => "Open"
    (SimplifiedChinese, Open) => "打开"
    (English, CancelSignIn) => "Cancel sign-in"
    (SimplifiedChinese, CancelSignIn) => "取消登录"
    (English, FinishSignIn) =>
      "Finish signing in on the browser page, or cancel the attempt."
    (SimplifiedChinese, FinishSignIn) =>
      "请在浏览器页面完成登录，或取消本次登录。"
    (English, Configuration) => "Configuration"
    (SimplifiedChinese, Configuration) => "配置"
    (English, OpenConfig) => "Open config.toml"
    (SimplifiedChinese, OpenConfig) => "打开 config.toml"
    (English, ConfigDescription) =>
      "config.toml in this desktop's Codex home, created empty if missing. The app-server reads it at startup, so edits apply after the desktop restarts."
    (SimplifiedChinese, ConfigDescription) =>
      "打开此桌面应用 Codex 目录中的 config.toml；文件不存在时会创建空文件。应用服务在启动时读取配置，修改将在重启桌面应用后生效。"
    (English, RemoteControl) => "Remote control"
    (SimplifiedChinese, RemoteControl) => "远程控制"
    (English, CheckingSignIn) => "Checking sign-in…"
    (SimplifiedChinese, CheckingSignIn) => "正在检查登录状态…"
    (English, EnvironmentRelay) =>
      "Configured through the environment (OPENSEEK_RELAY_URL); sign-in is disabled."
    (SimplifiedChinese, EnvironmentRelay) =>
      "已通过环境变量 OPENSEEK_RELAY_URL 配置，登录功能已禁用。"
    (English, OnlineRelay) => "online — reachable from your browser"
    (SimplifiedChinese, OnlineRelay) => "在线，可通过浏览器访问"
    (English, ConnectingRelay) => "connecting to the relay…"
    (SimplifiedChinese, ConnectingRelay) => "正在连接中继服务…"
    (English, SignedInAs) => "Signed in as"
    (SimplifiedChinese, SignedInAs) => "已登录账户"
    (English, Disconnect) => "Disconnect"
    (SimplifiedChinese, Disconnect) => "断开连接"
    (English, ThisMachine) => "this machine"
    (SimplifiedChinese, ThisMachine) => "此设备"
    (English, DevicePage) => "Device page"
    (SimplifiedChinese, DevicePage) => "设备页面"
    (English, RegisterRelay) =>
      "Registers this machine so your browser can drive it through the relay."
    (SimplifiedChinese, RegisterRelay) =>
      "注册此设备，以便通过中继服务在浏览器中远程控制。"
    (English, WaitingBrowser) => "Waiting for the browser…"
    (SimplifiedChinese, WaitingBrowser) => "正在等待浏览器…"
    (English, ConnectGitHub) => "Connect with GitHub"
    (SimplifiedChinese, ConnectGitHub) => "使用 GitHub 连接"
    (English, Cancel) => "Cancel"
    (SimplifiedChinese, Cancel) => "取消"
    (English, Problem) => "Problem"
    (SimplifiedChinese, Problem) => "问题"
    (English, CheckingUpdate) => "Checking…"
    (SimplifiedChinese, CheckingUpdate) => "正在检查…"
    (English, UpToDate) => "You are up to date."
    (SimplifiedChinese, UpToDate) => "已是最新版本。"
    (English, DeepseekHint) =>
      "Requests go straight to api.deepseek.com with your key."
    (SimplifiedChinese, DeepseekHint) =>
      "请求使用你的密钥直接发送至 api.deepseek.com。"
    (English, GlmHint) => "Requests go straight to api.z.ai with your key."
    (SimplifiedChinese, GlmHint) =>
      "请求使用你的密钥直接发送至 api.z.ai。"
    (English, OpenRouterHint) =>
      "DeepSeek requests go through OpenRouter with your key."
    (SimplifiedChinese, OpenRouterHint) =>
      "DeepSeek 请求使用你的密钥通过 OpenRouter 发送。"
    (English, CustomHint) =>
      "Any OpenAI-compatible chat-completions URL; key optional."
    (SimplifiedChinese, CustomHint) =>
      "支持任意兼容 OpenAI 的 chat-completions URL；密钥可选。"
    (English, DeepseekStepOne) => "Open platform.deepseek.com and sign in."
    (SimplifiedChinese, DeepseekStepOne) =>
      "打开 platform.deepseek.com 并登录。"
    (English, CreateKey) => "Create an API key under API Keys."
    (SimplifiedChinese, CreateKey) => "在 API Keys 页面创建 API 密钥。"
    (English, DeepseekPasteKey) =>
      "Paste it into the DeepSeek API key field below and save."
    (SimplifiedChinese, DeepseekPasteKey) =>
      "将密钥粘贴至下方 DeepSeek API 密钥输入框并保存。"
    (English, GlmStepOne) => "Open z.ai and sign in."
    (SimplifiedChinese, GlmStepOne) => "打开 z.ai 并登录。"
    (English, GlmPasteKey) =>
      "Paste it into the GLM API key field below and save."
    (SimplifiedChinese, GlmPasteKey) =>
      "将密钥粘贴至下方 GLM API 密钥输入框并保存。"
    (English, OpenRouterStepOne) => "Open openrouter.ai and create an API key."
    (SimplifiedChinese, OpenRouterStepOne) =>
      "打开 openrouter.ai 并创建 API 密钥。"
    (English, OpenRouterPasteKey) => "Paste the OpenRouter API key and save."
    (SimplifiedChinese, OpenRouterPasteKey) =>
      "粘贴 OpenRouter API 密钥并保存。"
    (English, StartEndpoint) =>
      "Start an OpenAI-compatible endpoint (Ollama, LM Studio, a proxy…)."
    (SimplifiedChinese, StartEndpoint) =>
      "启动兼容 OpenAI 的服务端点（Ollama、LM Studio、代理服务等）。"
    (English, EnterEndpoint) => "Enter its chat-completions URL below."
    (SimplifiedChinese, EnterEndpoint) =>
      "在下方输入其 chat-completions URL。"
    (English, OptionalEndpointKey) =>
      "Add the endpoint's key if it requires one."
    (SimplifiedChinese, OptionalEndpointKey) =>
      "如果端点需要密钥，请填写密钥。"
    (English, OwnProviderDescription) =>
      "SeekMoon does not provide a hosted API. Requests go straight from this machine to your own model provider, billed to your account. Your API key is stored only on this machine — SeekMoon never reads it."
    (SimplifiedChinese, OwnProviderDescription) =>
      "SeekMoon 不提供托管 API。请求从此设备直接发送至你选择的模型服务商，费用由你的账户承担。API 密钥仅保存在此设备上，SeekMoon 不会读取它。"
    (English, DeepseekKeysLink) => "platform.deepseek.com → API Keys"
    (SimplifiedChinese, DeepseekKeysLink) =>
      "platform.deepseek.com → API 密钥"
    (English, GlmKeysLink) => "z.ai → API Keys"
    (SimplifiedChinese, GlmKeysLink) => "z.ai → API 密钥"
    (English, ApiEndpoint) => "API endpoint"
    (SimplifiedChinese, ApiEndpoint) => "API 端点"
    (English, DeepseekOfficial) => "DeepSeek official (your API key)"
    (SimplifiedChinese, DeepseekOfficial) => "DeepSeek 官方"
    (English, GlmOfficial) => "Z.AI GLM (your API key)"
    (SimplifiedChinese, GlmOfficial) => "Z.AI GLM"
    (English, CustomUrl) => "Custom URL"
    (SimplifiedChinese, CustomUrl) => "自定义 URL"
    (English, EndpointUrl) => "Endpoint URL"
    (SimplifiedChinese, EndpointUrl) => "端点 URL"
    (English, DeepseekApiKey) => "DeepSeek API key"
    (SimplifiedChinese, DeepseekApiKey) => "DeepSeek API 密钥"
    (English, GlmApiKey) => "GLM API key"
    (SimplifiedChinese, GlmApiKey) => "GLM API 密钥"
    (English, OpenRouterApiKey) => "OpenRouter API key"
    (SimplifiedChinese, OpenRouterApiKey) => "OpenRouter API 密钥"
    (English, CustomApiKey) => "Custom API key"
    (SimplifiedChinese, CustomApiKey) => "自定义 API 密钥"
    (English, SavedKey) => "saved — enter to replace"
    (SimplifiedChinese, SavedKey) => "已保存，输入新密钥可替换"
    (English, ApiKey) => "API key"
    (SimplifiedChinese, ApiKey) => "API 密钥"
    (English, SaveApiKey) => "Save API key"
    (SimplifiedChinese, SaveApiKey) => "保存 API 密钥"
    (English, KeyStorageDescription) =>
      "Stored on this machine and sent only with API requests. SeekMoon never reads it."
    (SimplifiedChinese, KeyStorageDescription) =>
      "保存在此设备上，仅随 API 请求发送。SeekMoon 不会读取它。"
    (English, Language) => "Language"
    (SimplifiedChinese, Language) => "语言"
    (English, LanguageDescription) =>
      "Language for app controls. System follows your preferred languages."
    (SimplifiedChinese, LanguageDescription) =>
      "应用界面的语言。选择“跟随系统”将使用系统的首选语言。"
    (English, System) => "System"
    (SimplifiedChinese, System) => "跟随系统"
    (English, Settings) => "Settings"
    (SimplifiedChinese, Settings) => "设置"
    (English, Preferences) => "Preferences"
    (SimplifiedChinese, Preferences) => "偏好设置"
    (English, Interface) => "Interface"
    (SimplifiedChinese, Interface) => "界面"
    (English, Engine) => "Engine"
    (SimplifiedChinese, Engine) => "引擎"
    (English, MaxSteps) => "Max steps"
    (SimplifiedChinese, MaxSteps) => "最大步数"
    (English, MaxStepsDescription) => "How many agent steps one turn may take."
    (SimplifiedChinese, MaxStepsDescription) =>
      "每轮任务允许执行的最大步骤数。"
    (English, Followup) => "Follow-up messages"
    (SimplifiedChinese, Followup) => "后续消息"
    (English, Steer) => "Steer"
    (SimplifiedChinese, Steer) => "立即引导"
    (English, Queue) => "Queue"
    (SimplifiedChinese, Queue) => "加入队列"
    (English, FollowupDescription) =>
      "Default for messages sent while a task is running. Change it for one message beside the send button."
    (SimplifiedChinese, FollowupDescription) =>
      "任务运行期间发送消息的默认方式。可在发送按钮旁为单条消息更改。"
    (English, Theme) => "Theme"
    (SimplifiedChinese, Theme) => "主题"
    (English, Light) => "Light"
    (SimplifiedChinese, Light) => "浅色"
    (English, Dark) => "Dark"
    (SimplifiedChinese, Dark) => "深色"
    (English, ThemeDescription) =>
      "Used by the app, editor, and terminal. System follows the OS appearance."
    (SimplifiedChinese, ThemeDescription) =>
      "应用于界面、编辑器和终端。选择“跟随系统”将使用系统外观。"
    (English, FontSize) => "Font size"
    (SimplifiedChinese, FontSize) => "字号"
    (English, FontSizeDescription) =>
      "Scales app text; code uses a visually matched monospace size."
    (SimplifiedChinese, FontSizeDescription) =>
      "调整界面文字大小；代码使用视觉大小相近的等宽字体。"
    (English, NotificationCorner) => "Notification corner"
    (SimplifiedChinese, NotificationCorner) => "通知位置"
    (English, BottomRight) => "Bottom right"
    (SimplifiedChinese, BottomRight) => "右下角"
    (English, BottomLeft) => "Bottom left"
    (SimplifiedChinese, BottomLeft) => "左下角"
    (English, TopRight) => "Top right"
    (SimplifiedChinese, TopRight) => "右上角"
    (English, TopLeft) => "Top left"
    (SimplifiedChinese, TopLeft) => "左上角"
    (English, NotificationDescription) => "Where error notifications pop up."
    (SimplifiedChinese, NotificationDescription) =>
      "错误通知的显示位置。"
    (English, FileTreeLayout) => "File tree layout"
    (SimplifiedChinese, FileTreeLayout) => "文件树布局"
    (English, RightSidebar) => "Right sidebar"
    (SimplifiedChinese, RightSidebar) => "右侧边栏"
    (English, BottomPanel) => "Bottom panel"
    (SimplifiedChinese, BottomPanel) => "底部面板"
    (English, FileTreeDescription) =>
      "Where the editor panel docks its file tree."
    (SimplifiedChinese, FileTreeDescription) =>
      "编辑器面板中文件树的停靠位置。"
    (English, Diagnostics) => "Diagnostics"
    (SimplifiedChinese, Diagnostics) => "诊断"
    (English, FpsOverlay) => "FPS overlay"
    (SimplifiedChinese, FpsOverlay) => "帧率浮层"
    (English, On) => "On"
    (SimplifiedChinese, On) => "开启"
    (English, Off) => "Off"
    (SimplifiedChinese, Off) => "关闭"
    (English, FpsDescription) =>
      "Show FPS and frame intervals at the top of the window. Off by default."
    (SimplifiedChinese, FpsDescription) =>
      "在窗口顶部显示帧率和帧间隔。默认关闭。"
    (English, RemoteAccess) => "Remote access"
    (SimplifiedChinese, RemoteAccess) => "远程访问"
    (English, Updates) => "Updates"
    (SimplifiedChinese, Updates) => "更新"
    (English, CheckUpdates) => "Check for updates"
    (SimplifiedChinese, CheckUpdates) => "检查更新"
    (English, LoadingSettings) => "Loading runtime settings…"
    (SimplifiedChinese, LoadingSettings) => "正在加载运行设置…"
    (English, RuntimeSettings) => "Runtime settings for the SeekMoon engine."
    (SimplifiedChinese, RuntimeSettings) => "SeekMoon 引擎的运行设置。"
    (English, DeepseekKey) => "Enter a DeepSeek API key to start."
    (SimplifiedChinese, DeepseekKey) =>
      "输入 DeepSeek API 密钥以开始使用。"
    (English, GlmKey) => "Enter a GLM API key to start."
    (SimplifiedChinese, GlmKey) => "输入 GLM API 密钥以开始使用。"
    (English, OpenRouterKey) => "Enter an OpenRouter API key to start."
    (SimplifiedChinese, OpenRouterKey) =>
      "输入 OpenRouter API 密钥以开始使用。"
    (English, CustomEndpoint) =>
      "Enter a chat-completions endpoint URL to start."
    (SimplifiedChinese, CustomEndpoint) =>
      "输入 chat-completions 端点 URL 以开始使用。"
    (English, CurrentVersion(version)) => "Current version: \{version}."
    (SimplifiedChinese, CurrentVersion(version)) =>
      "当前版本：\{version}。"
    (English, LanguageStorageFailed(detail)) =>
      "Could not access the language preference: \{detail}"
    (SimplifiedChinese, LanguageStorageFailed(detail)) =>
      "无法访问语言偏好设置：\{detail}"
  }
}
