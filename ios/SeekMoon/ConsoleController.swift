import AuthenticationServices
import UIKit
import WebKit

@MainActor final class ConsoleController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let navigation = ConsoleNavigation()
    private let web: WKWebView
    let conversationView = UIView()
    private var canvasObservation: NSKeyValueObservation?
    private var scrollObservation: NSKeyValueObservation?
    private var composerCanvas: UIColor?
    private var dialogDim: CGFloat?
    private var lastInputHeight: CGFloat?
    let inputViewport = UIView()
    private var keyboardFrames: CADisplayLink?
    private lazy var keyboardLimit = inputViewport.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor)
    private lazy var resizeWebForKeyboard = web.bottomAnchor.constraint(equalTo: inputViewport.bottomAnchor)
    private lazy var fixedWebBottom = web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let statusCover = UIView()
    private let statusText = UILabel()
    private let recovery = UIStackView()
    private var slowLoad: Task<Void, Never>?
    let accountWeb: WKWebView
    private var account: String?
    private var archiveNavigation: WKNavigation?
    private var pendingNavigation: WKNavigation?
    private var failedPage: URL?
    private var loadingDocumentAt: URL?
    private var signIn: SignIn?
    private var downloads: [WKDownload: (temporaryFile: URL, filename: String)] = [:]
    private let lastPageKey = "console.lastPage"

    init(websiteDataStore: WKWebsiteDataStore? = nil) {
        let config = WKWebViewConfiguration()
        if let websiteDataStore { config.websiteDataStore = websiteDataStore }
        let storage = WKWebViewConfiguration()
        storage.websiteDataStore = config.websiteDataStore
        accountWeb = WKWebView(frame: .zero, configuration: storage)
        config.applicationNameForUserAgent = "SeekMoonIOS/0.1.0"
        web = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        web.navigationDelegate = self; web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        web.isInspectable = true
        #endif
        conversationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversationView)
        web.translatesAutoresizingMaskIntoConstraints = false
        conversationView.addSubview(web)
        inputViewport.translatesAutoresizingMaskIntoConstraints = false
        inputViewport.isUserInteractionEnabled = false
        conversationView.insertSubview(inputViewport, belowSubview: web)
        navigation.attach(to: self, web: web)
        // The page canvas continues behind the keyboard's transparent margins.
        // The input viewport ends at the top of its accessory bar.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let restingBottom = inputViewport.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        restingBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            conversationView.topAnchor.constraint(equalTo: view.topAnchor),
            conversationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.topAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.trailingAnchor),
            inputViewport.topAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.topAnchor),
            inputViewport.leadingAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.leadingAnchor),
            inputViewport.trailingAnchor.constraint(equalTo: conversationView.safeAreaLayoutGuide.trailingAnchor),
            restingBottom
        ])
        resizeWebForKeyboard.isActive = true
        for event in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardVisibilityChanged(_:)), name: event, object: nil)
        }
        for event in [UIResponder.keyboardDidChangeFrameNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(finishKeyboardAnimation), name: event, object: nil)
        }
        canvasObservation = web.observe(\.underPageBackgroundColor, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.paintCanvas() }
        }

        // The chat already moves its editor above the keyboard. WebKit also
        // tries to scroll the whole document to reveal the focused textarea.
        scrollObservation = web.scrollView.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.fixedWebBottom.isActive, self.keyboardLimit.isActive else { return }
                let scroll = self.web.scrollView
                if scroll.zoomScale == 1, !scroll.isZooming, scroll.contentOffset.y != 0 {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: 0), animated: false)
                }
            }
        }
        statusCover.backgroundColor = .systemBackground
        statusCover.accessibilityIdentifier = "console.loading"
        statusCover.frame = view.bounds
        statusCover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(statusCover)
        let retry = UIButton(type: .system)
        retry.setTitle(String(localized: "Retry"), for: .normal)
        retry.addAction(UIAction { [weak self] _ in self?.loadPage(self?.failedPage) }, for: .touchUpInside)
        let home = UIButton(type: .system)
        home.setTitle(String(localized: "Open Cloud"), for: .normal)
        home.addAction(UIAction { [weak self] _ in self?.loadPage(Console.home) }, for: .touchUpInside)
        if #available(iOS 26.0, *) {
            retry.configuration = .prominentGlass()
            home.configuration = .glass()
        }
        recovery.spacing = 20
        [retry, home].forEach(recovery.addArrangedSubview)
        statusText.numberOfLines = 0
        statusText.textAlignment = .center
        statusText.textColor = .label
        statusText.font = .preferredFont(forTextStyle: .body)
        statusText.adjustsFontForContentSizeCategory = true
        let status = UIStackView(arrangedSubviews: [indicator, statusText, recovery])
        status.axis = .vertical
        status.spacing = 12
        status.alignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        statusCover.addSubview(status)
        let safe = statusCover.safeAreaLayoutGuide
        NSLayoutConstraint.activate([status.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
                                     status.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
                                     status.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24)])
        NotificationCenter.default.addObserver(self, selector: #selector(rememberPage), name: UIApplication.didEnterBackgroundNotification, object: nil)
        let saved = UserDefaults.standard.url(forKey: lastPageKey)
        let destination = saved.flatMap { Console.isPage($0) ? $0 : nil } ?? Console.home
        failedPage = destination
        showLoading()
        // This fixed local document opens WebKit's existing first-party storage.
        // No console scripts or network request are needed to show the login buttons.
        accountWeb.navigationDelegate = self
        accountWeb.loadHTMLString(Self.accountDocument, baseURL: destination)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if keyboardFrames == nil { syncInputHeight() }
        navigation.layoutControls()
    }

    // Sample the keyboard animation UIKit is actually displaying. Changing
    // WKWebView's frame here would also animate its document scroll offset.
    @objc private func syncInputHeight() {
        guard fixedWebBottom.isActive else { return }
        let displayed = keyboardFrames == nil ? nil : inputViewport.layer.presentation()?.bounds.height
        let height = (displayed ?? inputViewport.bounds.height).rounded()
        guard height > 0, height != lastInputHeight else { return }
        lastInputHeight = height
        web.callAsyncJavaScript("document.documentElement.style.setProperty('--ios-chat-height', height + 'px')",
            arguments: ["height": height], in: nil, in: .defaultClient, completionHandler: nil)
    }

    func setComposerCanvas(_ color: UIColor?, dialogDim: CGFloat? = nil) {
        composerCanvas = color
        self.dialogDim = dialogDim
        // While a dialog owns the keyboard, resize its WebKit viewport normally.
        let tracksComposer = color != nil && dialogDim == nil
        if tracksComposer != fixedWebBottom.isActive {
            lastInputHeight = nil
            if tracksComposer {
                resizeWebForKeyboard.isActive = false
                fixedWebBottom.isActive = true
            } else {
                finishKeyboardAnimation()
                fixedWebBottom.isActive = false
                resizeWebForKeyboard.isActive = true
            }
            view.setNeedsLayout()
        }
        paintCanvas()
    }

    @objc private func keyboardVisibilityChanged(_ notification: Notification) {
        guard let window = view.window, window.isKeyWindow else { return }
        if let screen = notification.object as? UIScreen, screen !== window.windowScene?.screen { return }
        // WebKit's accessory can leave the guide above the home indicator
        // after hiding. Only a visible keyboard limits the resting viewport.
        if fixedWebBottom.isActive, keyboardFrames == nil {
            let link = CADisplayLink(target: self, selector: #selector(syncInputHeight))
            keyboardFrames = link
            link.add(to: .main, forMode: .common)
        }
        let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let onScreen = end.map { window.windowScene?.screen.coordinateSpace.bounds.intersects($0) == true } ?? false
        keyboardLimit.isActive = notification.name != UIResponder.keyboardWillHideNotification && onScreen
        view.layoutIfNeeded()
        syncInputHeight()
    }

    @objc private func finishKeyboardAnimation() {
        keyboardFrames?.invalidate()
        keyboardFrames = nil
        syncInputHeight()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finishKeyboardAnimation()
    }

    private func paintCanvas() {
        let color = composerCanvas ?? web.underPageBackgroundColor ?? .systemBackground
        let fill = color.cgColor.alpha > 0 ? color : .systemBackground
        // The WK dialog dims everything inside the web viewport. Continue the
        // same scrim into the safe areas, keeping the base under the glass opaque.
        inputViewport.backgroundColor = dialogDim == nil ? nil : fill
        conversationView.backgroundColor = dialogDim.map { fill.withAlphaComponent(1 - $0) } ?? fill
        view.backgroundColor = dialogDim == nil ? fill : .black
    }

    @discardableResult
    func loadLocalHTML(_ html: String, at url: URL) -> WKNavigation? {
        loadingDocumentAt = url
        return web.loadHTMLString(html, baseURL: url)
    }

    static let accountDocument = """
        <!doctype html><html data-seekmoon-account><head>
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'">
        </head><body></body></html>
        """

    @objc private func rememberPage() {
        if let page = web.url, Console.isPage(page),
           var parts = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            parts.query = nil
            parts.fragment = nil
            UserDefaults.standard.set(parts.url, forKey: lastPageKey)
        }
    }

    private func loadPage(_ page: URL?, preservingHistory: Bool = false) {
        let url = page.flatMap { Console.isPage($0) ? $0 : nil } ?? Console.home
        failedPage = url
        navigation.reset()
        showLoading()
        do {
            guard let archive = Bundle.main.url(forResource: "Console", withExtension: "webarchive") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            loadingDocumentAt = url
            let mime = "application/x-webarchive"
            if preservingHistory {
                pendingNavigation = web.load(data, mimeType: mime, characterEncodingName: "utf-8", baseURL: url)
            } else {
                let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
                pendingNavigation = web.loadSimulatedRequest(URLRequest(url: url), response: response, responseData: data)
            }
            archiveNavigation = pendingNavigation
        } catch {
            showError(error.localizedDescription, url: url)
        }
    }

    private func showLoading() {
        slowLoad?.cancel()
        statusCover.isHidden = false
        recovery.isHidden = true
        statusText.text = String(localized: "Opening SeekMoon…")
        indicator.startAnimating()
        slowLoad = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.statusText.text = String(localized: "Loading is taking longer than usual. You can wait or retry.")
            self?.recovery.isHidden = false
        }
    }

    func consoleDidRender() {
        slowLoad?.cancel()
        indicator.stopAnimating()
        statusCover.isHidden = true
    }

    private func showError(_ description: String, url: URL?) {
        slowLoad?.cancel()
        navigation.reset()
        if Console.isPage(url) { failedPage = url }
        indicator.stopAnimating()
        statusText.text = String(localized: "Couldn’t open SeekMoon.") + "\n" + description
        statusCover.isHidden = false
        recovery.isHidden = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if webView === accountWeb {
            decisionHandler(Console.isPage(url) && action.navigationType == .other ? .allow : .cancel)
            return
        }
        if url.scheme == "blob", action.shouldPerformDownload {
            let fromConsole = action.sourceFrame.isMainFrame && Console.isPage(webView.url)
            decisionHandler(fromConsole ? .download : .cancel)
            return
        }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if Console.owns(url), url.path == "/v2/auth/login" {
            decisionHandler(.cancel)
            if action.sourceFrame.isMainFrame && Console.isPage(web.url) { beginSignIn(fromWebPage: true) }
            return
        }
        if action.targetFrame?.isMainFrame == true, action.request.httpMethod == "GET", Console.isPage(url) {
            if url == loadingDocumentAt && action.navigationType == .other {
                loadingDocumentAt = nil
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                loadPage(url, preservingHistory: action.navigationType == .reload || action.navigationType == .backForward)
            }
            return
        }
        if action.targetFrame != nil && Console.owns(url) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated && ["https", "http", "mailto"].contains(url.scheme?.lowercased()), Console.isPage(web.url) {
            if Console.isPage(url) { loadPage(url) } else { UIApplication.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard response.isForMainFrame else { decisionHandler(.allow); return }
        guard Console.owns(response.response.url) else { decisionHandler(.cancel); return }
        if let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            decisionHandler(.cancel); showError("HTTP \(http.statusCode)", url: http.url); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === web else { return }
        if navigation !== pendingNavigation {
            if Console.isPage(webView.url) {
                failedPage = webView.url
                showLoading()
            }
        }
        pendingNavigation = navigation
        self.navigation.reset()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === accountWeb {
            Task {
                do {
                    account = try await accountWeb.evaluateJavaScript("localStorage.getItem('seekmoon.account.v1')") as? String
                    if archiveNavigation != nil { return }
                    let cookies = await accountWeb.configuration.websiteDataStore.httpCookieStore.allCookies()
                    let host = Console.origin.host!
                    let hasCookie = cookies.contains { cookie in
                        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        return domain == host || host.hasSuffix("." + domain)
                    }
                    if account != nil || hasCookie {
                        loadPage(failedPage)
                    } else {
                        consoleDidRender()
                        self.navigation.showWelcome(true)
                    }
                } catch { showError(error.localizedDescription, url: failedPage) }
            }
            return
        }
        rememberPage()
        if let navigation, navigation === archiveNavigation {
            Task {
                do {
                    try await Self.startFrontend(in: web, account: account)
                } catch {
                    if navigation === pendingNavigation { showError(error.localizedDescription, url: web.url) }
                }
            }
        } else if !Console.isPage(web.url) { consoleDidRender() }
    }

    static func startFrontend(in web: WKWebView, account: String?) async throws {
        if account != nil, !Console.isPage(web.url) { throw SignInError.callback }
        let started = try await web.callAsyncJavaScript("""
            const entry = document.querySelector('link#seekmoon-entry');
            if (!entry || entry.getAttribute('href') !== '/assets/frontend.js') return false;
            if (account !== null) {
                if (location.origin !== origin || !/^\\/(cloud(?:\\/|$)|device\\/)/.test(location.pathname)) return false;
                localStorage.setItem('seekmoon.account.v1', account);
            }
            const module = document.createElement('script');
            module.type = 'module';
            module.src = entry.href;
            entry.replaceWith(module);
            return true;
            """, arguments: ["account": account as Any? ?? NSNull(), "origin": Console.origin.absoluteString],
            in: nil, contentWorld: .defaultClient)
        guard started as? Bool == true else { throw SignInError.callback }
    }

    // An expired session or a completed web sign-out must also retire the
    // durable credential, otherwise a later launch would restore it.
    func retireAccountIfSignedOut() {
        guard let previous = account, Console.isPage(web.url) else { return }
        Task {
            guard let absent = try? await web.evaluateJavaScript("localStorage.getItem('seekmoon.account.v1') === null"),
                  absent as? Bool == true, account == previous else { return }
            account = nil
            _ = try? await accountWeb.callAsyncJavaScript("""
                if (localStorage.getItem('seekmoon.account.v1') === previous) localStorage.removeItem('seekmoon.account.v1')
                """, arguments: ["previous": previous], in: nil, contentWorld: .defaultClient)
        }
    }

    func acceptSignIn(_ session: String) async throws {
        try await Self.installAccount(session, in: accountWeb)
        account = session
        loadPage(web.url ?? failedPage, preservingHistory: web.url != nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error)
    }

    private func navigationFailed(_ navigation: WKNavigation?, _ error: Error) {
        let reason = error as NSError
        if reason.domain == NSURLErrorDomain && reason.code == NSURLErrorCancelled { return }
        if reason.domain == "WebKitErrorDomain" && reason.code == 102 { return }
        if let pendingNavigation, let navigation, pendingNavigation !== navigation && web.isLoading { return }
        showError(reason.localizedDescription, url: reason.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === accountWeb {
            accountWeb.loadHTMLString(Self.accountDocument, baseURL: failedPage ?? Console.home)
        } else {
            loadPage(webView.url ?? failedPage)
        }
    }

    static func installAccount(_ account: String, in webView: WKWebView) async throws {
        let installed = try await webView.callAsyncJavaScript("""
            if (location.origin !== origin || !(location.pathname === '/cloud' || location.pathname.startsWith('/cloud/') || location.pathname.startsWith('/device/'))) return false;
            localStorage.setItem('seekmoon.account.v1', account);
            return true;
            """, arguments: ["account": account, "origin": Console.origin.absoluteString], in: nil, contentWorld: .defaultClient)
        guard installed as? Bool == true else { throw SignInError.callback }
    }

    func beginSignIn(method: SignInMethod? = nil, fromWebPage: Bool = false) {
        guard signIn == nil, Console.isPage(web.url ?? accountWeb.url), let window = view.window else { return }
        let attempt = SignIn(window: window)
        signIn = attempt
        attempt.start(method: method) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { signIn = nil }
                do {
                    let session = try result.get()
                    try await acceptSignIn(session)
                } catch {
                    // The web-initiated flow marks its own login action as pending.
                    if fromWebPage && Console.isPage(web.url) { web.reload() }
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                    let alert = UIAlertController(title: String(localized: "Unable to sign in"), message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default)); present(alert, animated: true)
                }
            }
        }
    }
}

extension ConsoleController: WKDownloadDelegate {
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let temporaryFile = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        let basename = (suggestedFilename as NSString).lastPathComponent
        let filename = ["", ".", "..", "/"].contains(basename) ? "Download" : basename
        downloads[download] = (temporaryFile, filename)
        completionHandler(temporaryFile)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: download) else { return }
        do {
            try Self.saveDownload(file.temporaryFile, named: file.filename)
        } catch {
            try? FileManager.default.removeItem(at: file.temporaryFile)
            showDownloadError(error)
        }
    }

    private static func saveDownload(_ temporaryFile: URL, named filename: String) throws {
        let files = FileManager.default
        let folder = try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var candidate = filename
        var number = 2
        while true {
            do {
                try files.moveItem(at: temporaryFile, to: folder.appending(component: candidate))
                return
            } catch CocoaError.fileWriteFileExists {
                candidate = numberedFilename(filename, number: number)
                number += 1
            }
        }
    }

    private static func numberedFilename(_ filename: String, number: Int) -> String {
        let name = filename as NSString
        let counter = " (\(number))"
        let ext = name.pathExtension
        var ending = ext.isEmpty ? counter : counter + "." + ext
        var stem = name.deletingPathExtension
        if ending.utf8.count > Int(NAME_MAX) {
            stem = filename
            ending = counter
        }
        var remaining = Int(NAME_MAX) - ending.utf8.count
        let prefix = stem.prefix { character in
            remaining -= character.utf8.count
            return remaining >= 0
        }
        return prefix + ending
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = downloads.removeValue(forKey: download) {
            try? FileManager.default.removeItem(at: file.temporaryFile)
        }
        showDownloadError(error)
    }

    private func showDownloadError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn’t save download", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
