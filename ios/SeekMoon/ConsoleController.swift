import AuthenticationServices
import UIKit
import WebKit

@MainActor final class ConsoleController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let web: WKWebView
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let errorView = UIStackView()
    private let errorText = UILabel()
    private var failedPage: URL?
    private var signIn: SignIn?
    private let lastPageKey = "console.lastPage"

    init() {
        let config = WKWebViewConfiguration()
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
        web.scrollView.contentInsetAdjustmentBehavior = .always
        #if DEBUG
        web.isInspectable = true
        #endif
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        let safe = view.safeAreaLayoutGuide
        let keyboard = view.keyboardLayoutGuide
        keyboard.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
        ])

        indicator.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(indicator)
        NSLayoutConstraint.activate([indicator.centerXAnchor.constraint(equalTo: safe.centerXAnchor), indicator.centerYAnchor.constraint(equalTo: safe.centerYAnchor)])
        let retry = UIButton(type: .system); retry.setTitle("Retry", for: .normal)
        retry.addAction(UIAction { [weak self] _ in self?.loadPage(self?.failedPage) }, for: .touchUpInside)
        let home = UIButton(type: .system); home.setTitle("Open Cloud", for: .normal)
        home.addAction(UIAction { [weak self] _ in self?.loadPage(Console.home) }, for: .touchUpInside)
        errorText.numberOfLines = 0; errorText.textAlignment = .center
        errorText.font = .preferredFont(forTextStyle: .body); errorText.adjustsFontForContentSizeCategory = true
        errorView.axis = .vertical; errorView.spacing = 12; errorView.alignment = .center
        [errorText, retry, home].forEach(errorView.addArrangedSubview)
        errorView.isHidden = true; errorView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(errorView)
        NSLayoutConstraint.activate([errorView.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
                                     errorView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
                                     errorView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24)])
        NotificationCenter.default.addObserver(self, selector: #selector(rememberPage), name: UIApplication.didEnterBackgroundNotification, object: nil)
        loadPage(UserDefaults.standard.url(forKey: lastPageKey))
    }

    @objc private func rememberPage() {
        if let page = web.url, Console.isPage(page) {
            UserDefaults.standard.set(Console.origin.appending(path: page.path), forKey: lastPageKey)
        }
    }

    private func loadPage(_ page: URL?) {
        let url = page.flatMap { Console.isPage($0) ? $0 : nil } ?? Console.home
        failedPage = url; web.isHidden = false; errorView.isHidden = true; indicator.startAnimating()
        web.load(URLRequest(url: url))
    }

    private func showError(_ description: String, url: URL?) {
        if Console.isPage(url) { failedPage = url }
        indicator.stopAnimating(); web.isHidden = true
        errorText.text = "Couldn't open SeekMoon.\n\(description)"; errorView.isHidden = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if Console.owns(url), url.path == "/v2/auth/login" {
            decisionHandler(.cancel)
            if action.sourceFrame.isMainFrame && Console.isPage(web.url) { beginSignIn() }
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        indicator.stopAnimating(); rememberPage()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }

    private func navigationFailed(_ error: Error) {
        let reason = error as NSError
        if reason.domain == NSURLErrorDomain && reason.code == NSURLErrorCancelled { return }
        if reason.domain == "WebKitErrorDomain" && reason.code == 102 { return }
        showError(reason.localizedDescription, url: reason.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadPage(webView.url) }

    static func installAccount(_ account: String, in webView: WKWebView) async throws {
        let installed = try await webView.callAsyncJavaScript("""
            if (location.origin !== origin || !(location.pathname === '/cloud' || location.pathname.startsWith('/cloud/') || location.pathname.startsWith('/device/'))) return false;
            localStorage.setItem('seekmoon.account.v1', account);
            return true;
            """, arguments: ["account": account, "origin": Console.origin.absoluteString], in: nil, contentWorld: .defaultClient)
        guard installed as? Bool == true else { throw SignInError.callback }
    }

    private func beginSignIn() {
        guard signIn == nil, let window = view.window else { return }
        let attempt = SignIn(window: window)
        signIn = attempt
        attempt.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { signIn = nil }
                do {
                    let session = try result.get()
                    try await Self.installAccount(session, in: web)
                    web.reload()
                } catch {
                    if Console.isPage(web.url) { web.reload() }
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                    let alert = UIAlertController(title: "Unable to sign in", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
                }
            }
        }
    }
}
