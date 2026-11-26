import CryptoKit
import SwiftUI
import WebKit
import XCTest
@testable import SeekMoon

@MainActor final class SeekMoonTests: XCTestCase {
    func testSignedOutStartupUsesLocalWelcomeAndCoversAnEmptyConsoleUntilItRenders() async throws {
        let controller = ConsoleController(websiteDataStore: .nonPersistent())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let web = try XCTUnwrap(controller.conversationView.subviews.compactMap { $0 as? WKWebView }.first)
        let cover = try XCTUnwrap(controller.view.subviews.first { $0.accessibilityIdentifier == "console.loading" })
        let welcome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.conversationView.accessibilityElementsHidden && cover.isHidden
        }, object: nil)
        await fulfillment(of: [welcome], timeout: 10)
        let local = try await web.evaluateJavaScript("document.documentElement.hasAttribute('data-seekmoon-account') && performance.getEntriesByType('resource').length === 0")
        XCTAssertEqual(local as? Bool, true)
        try await ConsoleController.installAccount("fixture", in: web)

        let url = try XCTUnwrap(web.url)
        web.loadHTMLString("<html style='background:#191919'><body><div id='app'></div></body></html>", baseURL: url)
        let waiting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !web.isLoading && !controller.conversationView.accessibilityElementsHidden && !cover.isHidden
        }, object: nil)
        await fulfillment(of: [waiting], timeout: 10)
        let stored = try await web.evaluateJavaScript("localStorage.getItem('seekmoon.account.v1')")
        XCTAssertEqual(stored as? String, "fixture")
        _ = try await web.evaluateJavaScript("document.querySelector('#app').textContent = 'Conversation'")
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in cover.isHidden }, object: nil)
        await fulfillment(of: [rendered], timeout: 10)
        var white: CGFloat = 0
        XCTAssertTrue(web.underPageBackgroundColor.resolvedColor(with: web.traitCollection).getWhite(&white, alpha: nil))
        XCTAssertEqual(white, 25.0 / 255.0, accuracy: 0.005, "The status and home indicator areas should match the page canvas")
    }

    @available(iOS 26.0, *)
    func testChatMenuReplacesWebControlAndYieldsToModal() async throws {
        let controller = ConsoleController(websiteDataStore: .nonPersistent())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        let previousKey = scene.keyWindow
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            previousKey?.makeKey()
        }
        let conversation = controller.conversationView
        let web = try XCTUnwrap(conversation.subviews.compactMap { $0 as? WKWebView }.first)
        let button = try XCTUnwrap(conversation.subviews.compactMap { $0 as? ConsoleMenuButton }.first)
        let welcome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in conversation.accessibilityElementsHidden }, object: nil)
        await fulfillment(of: [welcome], timeout: 10)

        let url = try XCTUnwrap(web.url)
        web.loadHTMLString("""
            <html data-theme="dark"><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>[data-theme=dark]{color-scheme:dark} [data-theme=light]{color-scheme:light}
            .sidebar-toggle { position:fixed; left:15px; top:8px; width:36px; height:36px }
            .composer-inner {position:absolute;bottom:10px;height:50px;width:90%}</style></head>
            <body><div id="app" class="app sidebar-collapsed"><button class="sidebar-toggle">Menu</button>
            <aside><div class="sidebar-group-content" id="section:cloud.chats:fixture"></div></aside>
            <div class="content"><button class="right-panel-toggle" title="Files">Files</button>
            <main><div class="topbar"><h1>New chat</h1><span>Ready</span>
            <button title="Export" onclick="document.querySelector('dialog').showModal()">Export</button>
            <button title="Busy" disabled>Busy</button></div><div class="transcript"></div>
            <div class="composer"><div class="composer-inner"><textarea id="task"></textarea></div></div></main></div></div>
            <dialog id="session-import-dialog"><input placeholder="Share link"></dialog></body></html>
            """, baseURL: url)
        func waitForButton(visible: Bool) async {
            let state = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isHidden != visible }, object: nil)
            await fulfillment(of: [state], timeout: 5)
        }
        await waitForButton(visible: true)
        let replaced = try await web.evaluateJavaScript("""
            const anchor = document.querySelector('.sidebar-toggle');
            getComputedStyle(anchor).opacity === '0' && anchor.getAttribute('aria-hidden') === 'true' && anchor.tabIndex === -1
            """)
        XCTAssertEqual(replaced as? Bool, true)
        XCTAssertEqual(button.frame.size, CGSize(width: 36, height: 36))
        XCTAssertEqual(button.frame.minY, web.frame.minY + web.scrollView.adjustedContentInset.top + 8, accuracy: 1)
        XCTAssertEqual(button.overrideUserInterfaceStyle, .dark)
        XCTAssertTrue(conversation.hitTest(CGPoint(x: button.frame.minX - 3, y: button.frame.midY), with: nil) === button)
        XCTAssertEqual(Set(button.menu?.children.map(\.title) ?? []), ["Export", "Files"])
        let hidden = try await web.evaluateJavaScript("""
            ['.topbar h1', '.topbar span', '.topbar button', '.right-panel-toggle']
                .every(selector => getComputedStyle(document.querySelector(selector)).visibility === 'hidden')
            """)
        XCTAssertEqual(hidden as? Bool, true)
        let opened = try await web.callAsyncJavaScript("return window.consoleNavigationAction('header', 'Export')",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(opened as? Bool, true)
        let covered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !button.isUserInteractionEnabled }, object: nil)
        await fulfillment(of: [covered], timeout: 5)
        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(button.isAccessibilityElement)
        XCTAssertLessThan(try XCTUnwrap(conversation.subviews.firstIndex(of: button)), try XCTUnwrap(conversation.subviews.firstIndex(of: web)))
        let preserved = try await web.evaluateJavaScript("""
            document.documentElement.hasAttribute('data-ios-glass-composer') &&
            getComputedStyle(document.querySelector('.topbar')).visibility === 'hidden' &&
            getComputedStyle(document.querySelector('.right-panel-toggle')).visibility === 'hidden' &&
            getComputedStyle(document.querySelector('.composer-inner'), '::before').color === 'rgb(0, 0, 0)'
            """)
        XCTAssertEqual(preserved as? Bool, true)
        _ = try await web.evaluateJavaScript("document.documentElement.dataset.theme = 'light'")
        let light = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.overrideUserInterfaceStyle == .light }, object: nil)
        await fulfillment(of: [light], timeout: 5)
        var white: CGFloat = 0, opacity: CGFloat = 0
        XCTAssertTrue(try XCTUnwrap(conversation.backgroundColor).getWhite(&white, alpha: &opacity))
        XCTAssertEqual(white * opacity, 0.5, accuracy: 0.01)
        _ = try await web.evaluateJavaScript("document.querySelector('dialog').close()")
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in button.isUserInteractionEnabled }, object: nil)
        await fulfillment(of: [restored], timeout: 5)
        XCTAssertTrue(button.isAccessibilityElement)
        XCTAssertTrue(try XCTUnwrap(conversation.backgroundColor).getWhite(&white, alpha: &opacity))
        XCTAssertEqual(white * opacity, 1, accuracy: 0.01)
        XCTAssertEqual(button.overrideUserInterfaceStyle, .light)
    }

    @available(iOS 26.0, *)
    func testComposerAndNativeDeviceSettingsShareTheLivePage() async throws {
        let controller = ConsoleController(websiteDataStore: .nonPersistent())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        let previousKey = scene.keyWindow
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            previousKey?.makeKey()
        }
        let shell = controller.conversationView
        let web = try XCTUnwrap(shell.subviews.compactMap { $0 as? WKWebView }.first)
        let glass = try XCTUnwrap(shell.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        func waitUntil(_ condition: @escaping () -> Bool) async {
            let check = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
            await fulfillment(of: [check], timeout: 8)
        }
        await waitUntil { shell.accessibilityElementsHidden }
        web.loadHTMLString("""
            <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>:root{color-scheme:dark;--color-bg-canvas:#191919}.composer-inner{position:absolute;bottom:10px;height:50px;width:90%}</style>
            <div id="app"><main><section class="composer"><div class="composer-inner"><button id="attach">+</button>
            <div class="composer-input"><textarea id="task"></textarea></div></div></section></main></div>
            <dialog id="management-dialog"><button data-slot="dialog-close" onclick="this.parentNode.close()">Done</button>
            <button class="settings-tab" aria-selected="true" aria-controls="settings-panel-devices">Devices</button>
            <button class="settings-tab" aria-selected="false" aria-controls="settings-panel-engine">Engine</button>
            <button class="settings-tab" id="settings-tab-account" aria-selected="false" aria-controls="settings-panel-account">Account</button>
            <section id="settings-panel-account" hidden><section class="form-section">
            <div class="form-row"><span class="form-row-label">Account</span><div class="form-row-controls"><span>Test user</span></div></div>
            <div class="form-row"><span class="form-row-label">Sharing</span><div class="form-row-controls">
            <button role="switch" aria-label="Sharing" aria-checked="false" onclick="this.setAttribute('aria-checked','true')"></button>
            </div></div></section></section>
            <section id="settings-panel-devices"><section class="form-section"><div class="form-row">
            <div class="form-row-label">Test Mac</div><div class="form-row-controls"><span>Online</span>
            <button class="danger" onclick="confirmDevice.showModal()">Remove</button></div></div></section></section>
            <section id="settings-panel-engine" hidden><input type="password" value="local-test-value"></section></dialog>
            <dialog id="confirmDevice"><button onclick="confirmDevice.close()">Cancel</button></dialog>
            <script>
            for (const tab of document.querySelectorAll('.settings-tab')) tab.onclick = () => {
                for (const item of document.querySelectorAll('.settings-tab')) {
                    item.setAttribute('aria-selected', String(item === tab));
                    document.getElementById(item.getAttribute('aria-controls')).hidden = item !== tab;
                }
            };
            </script>
            """, baseURL: try XCTUnwrap(web.url))
        await waitUntil { !glass.isHidden }
        XCTAssertTrue(glass.effect is UIGlassEffect)
        XCTAssertFalse(glass.isUserInteractionEnabled)
        XCTAssertFalse(web.isOpaque)
        XCTAssertEqual(glass.frame.height, 50, accuracy: 1)
        let canvas = try XCTUnwrap(shell.backgroundColor)
        var white: CGFloat = 0
        XCTAssertTrue(canvas.getWhite(&white, alpha: nil))
        XCTAssertEqual(white, 0, accuracy: 0.005)
        XCTAssertEqual(shell.frame.maxY, controller.view.bounds.maxY, accuracy: 1)
        // Resize between WebKit frames. The glass must stay under the editor
        // without waiting for a second geometry message from JavaScript.
        let originalBottom = glass.frame.maxY
        let restingWebFrame = web.frame
        let viewport = controller.inputViewport
        let shorter = viewport.heightAnchor.constraint(equalToConstant: viewport.bounds.height - 180)
        shorter.isActive = true
        controller.view.layoutIfNeeded()
        XCTAssertEqual(glass.frame.maxY, originalBottom - 180, accuracy: 1)
        XCTAssertEqual(web.frame, restingWebFrame)
        XCTAssertEqual(shell.frame.maxY, controller.view.bounds.maxY, accuracy: 1)
        shorter.isActive = false
        controller.view.layoutIfNeeded()
        XCTAssertEqual(glass.frame.maxY, originalBottom, accuracy: 1)
        let editable = try await web.evaluateJavaScript("""
            const task = document.querySelector('#task');
            task.value = '草稿 🌓'; task.setSelectionRange(0, 2);
            const add = document.querySelector('#attach'), r = add.getBoundingClientRect();
            document.elementFromPoint(r.x+r.width/2, r.y+r.height/2) === add
            """)
        XCTAssertEqual(editable as? Bool, true)
        _ = try await web.evaluateJavaScript("document.querySelector('.composer-inner').style.height = '90px'")
        await waitUntil { glass.frame.height == 90 }
        func settings() -> UIHostingController<ConsoleSettingsScreen>? {
            controller.children.compactMap { $0 as? UIHostingController<ConsoleSettingsScreen> }.first
        }
        _ = try await web.evaluateJavaScript("document.querySelector('#management-dialog').showModal()")
        await waitUntil { settings() != nil && glass.isHidden }
        let screen = try XCTUnwrap(settings()?.rootView)
        let row = try XCTUnwrap(screen.page.rows.first)
        XCTAssertEqual(row.title, "Test Mac")
        XCTAssertEqual(row.values, ["Online"])
        let remove = try XCTUnwrap(row.controls.first)
        XCTAssertTrue(remove.danger)
        screen.perform(remove.id)
        await waitUntil { settings() == nil }
        let confirming = try await web.evaluateJavaScript("confirmDevice.open")
        XCTAssertEqual(confirming as? Bool, true)
        _ = try await web.evaluateJavaScript("confirmDevice.querySelector('button').click()")
        await waitUntil { settings() != nil }
        screen.perform(try XCTUnwrap(screen.page.sections.first { $0.label == "Engine" }).id)
        await waitUntil { settings()?.rootView.page.hosted == true && !shell.accessibilityElementsHidden }
        XCTAssertEqual(settings()?.rootView.page.rows.count, 0)
        let value = try await web.evaluateJavaScript("document.querySelector('#settings-panel-engine input').value")
        XCTAssertEqual(value as? String, "local-test-value")
        screen.overview()
        await waitUntil { settings()?.rootView.page.overview == true && shell.accessibilityElementsHidden }
        let home = try XCTUnwrap(settings()?.rootView)
        let sharing = try XCTUnwrap(home.page.accountPreferences.first?.controls.first)
        XCTAssertFalse(sharing.selected)
        home.perform(sharing.id)
        await waitUntil { settings()?.rootView.page.accountPreferences.first?.controls.first?.selected == true }
        screen.perform(screen.page.close)
        await waitUntil { settings() == nil && !glass.isHidden }
        let draft = try await web.evaluateJavaScript("task.value")
        XCTAssertEqual(draft as? String, "草稿 🌓")
    }

    func testAttachmentCameraPurposeIsInAppBundle() throws {
        let purpose = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testConsoleBlobDownloadsSaveTheirBytesWithoutOverwritingAnEarlierExport() async throws {
        for key in ["UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"] {
            XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: key) as? Bool, true)
        }
        let web = WKWebView()
        let loaded = DocumentLoaded()
        web.navigationDelegate = loaded
        web.loadHTMLString("<title>Console</title>", baseURL: Console.home)
        await fulfillment(of: [loaded.loaded], timeout: 10)

        let controller = ConsoleController()
        web.navigationDelegate = controller
        let name = UUID().uuidString
        let documents = URL.documentsDirectory
        let html = documents.appending(component: name + ".html")
        let binary = documents.appending(component: name + ".bin")
        let copy = documents.appending(component: name + " (2).html")
        let longPrefix = name.padding(toLength: 245, withPad: "x", startingAt: 0)
        let longFile = documents.appending(component: longPrefix + "文件.bin")
        let longCopy = documents.appending(component: longPrefix + " (2).bin")
        defer {
            for url in [html, binary, copy, longFile, longCopy] { try? FileManager.default.removeItem(at: url) }
        }
        let original = Data("previous export".utf8)
        try original.write(to: html)
        XCTAssertEqual(longFile.lastPathComponent.utf8.count, 255)
        try original.write(to: longFile)
        for (filename, type, bytes, destination) in [
            (html.lastPathComponent, "text/html;charset=utf-8", Data("<p>conversation</p>".utf8), copy),
            (binary.lastPathComponent, "application/octet-stream", Data([0, 255, 128]), binary),
            (longFile.lastPathComponent, "application/octet-stream", Data([1, 2, 3]), longCopy)
        ] {
            _ = try await web.callAsyncJavaScript("""
                const link = document.createElement('a');
                link.href = URL.createObjectURL(new Blob([new Uint8Array(bytes)], {type}));
                link.download = filename;
                link.click();
                setTimeout(() => URL.revokeObjectURL(link.href), 1000);
                """, arguments: ["filename": filename, "type": type, "bytes": Array(bytes)], in: nil, contentWorld: .page)
            let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: destination.path)
            }, object: nil)
            await fulfillment(of: [saved], timeout: 8)
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
        XCTAssertEqual(try Data(contentsOf: html), original)
        XCTAssertEqual(try Data(contentsOf: longFile), original)
        XCTAssertEqual(web.url, Console.home)
        withExtendedLifetime(controller) {}
    }

    func testLoginReturnsThroughOneTimeLoopbackAndUsesTheSameVerifierForExchange() async throws {
        let flow = AccountFlow(scheme: "com.example.seekmoon.test")
        let listener = try CallbackListener(flow: flow)
        defer { listener.stop() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.start(ready: { continuation.resume(returning: $0) }, failed: { continuation.resume(throwing: $0) })
        }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func get(_ path: String) async throws -> HTTPURLResponse {
            let (_, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            return try XCTUnwrap(response as? HTTPURLResponse)
        }
        let stray = try await get("/cb?state=other&code=unused")
        XCTAssertEqual(stray.statusCode, 404)
        let target = "/cb?state=\(flow.state)&code=test%2Bvalue%3D"
        let accepted = try await get(target)
        XCTAssertEqual(accepted.statusCode, 302)
        let url = try XCTUnwrap(accepted.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)))
        let request = try flow.exchangeRequest(code: flow.code(from: url))
        let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["code"], "test+value=")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://seekmoon.moonbitlang.com/v2/auth/account/exchange")
        let verifier = try XCTUnwrap(body["code_verifier"])
        let start = flow.startURL(port: port)
        let query = try XCTUnwrap(URLComponents(url: start, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "port" }?.value, String(port))
        let sent = try XCTUnwrap(query.first { $0.name == "code_challenge" }?.value)
        let standard = sent.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="
        XCTAssertEqual(Data(base64Encoded: standard), Data(SHA256.hash(data: Data(verifier.utf8))))
        XCTAssertFalse(start.absoluteString.contains(verifier))
        let repeated = try await get(target)
        XCTAssertEqual(repeated.statusCode, 404)
    }

    func testEmailAndGitHubReturnToTheSamePKCEAccountStart() throws {
        let flow = AccountFlow(scheme: "com.example.seekmoon.test")
        let start = flow.startURL(port: 49152)
        for (method, path) in [(SignInMethod.email, "/v2/auth/login"), (.github, "/v2/auth/github")] {
            let url = flow.startURL(port: 49152, method: method)
            XCTAssertTrue(Console.owns(url))
            XCTAssertEqual(url.path, path)
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "prompt" }?.value, "select_account")
            let target = try XCTUnwrap(query.first { $0.name == "return_to" }?.value)
            XCTAssertEqual(URL(string: target, relativeTo: Console.origin)?.absoluteURL, start)
            XCTAssertFalse(url.absoluteString.contains(flow.verifier))
        }
    }

    func testDeclineAndUnrelatedCallbackNeverProduceAnAuthorizationCode() throws {
        let flow = AccountFlow(scheme: "com.example.seekmoon.test")
        let denied = try XCTUnwrap(flow.browserReturn(target: "/cb?state=\(flow.state)&error=access_denied"))
        XCTAssertThrowsError(try flow.code(from: denied)) { XCTAssertEqual($0 as? SignInError, .denied) }
        XCTAssertNil(flow.browserReturn(target: "/cb?state=\(flow.state)&code=a&code=b"))
        let wrongHost = try XCTUnwrap(URL(string: "\(flow.scheme)://other/complete?state=\(flow.state)&code=test"))
        XCTAssertThrowsError(try flow.code(from: wrongHost))
    }

    func testSidebarTracksTheDragUsesFiftyFivePercentAfterRotationAndKeepsTheDraft() async throws {
        let web = WKWebView()
        let loaded = DocumentLoaded()
        web.navigationDelegate = loaded
        web.loadHTMLString("<textarea id='task'></textarea>", baseURL: Console.home)
        await fulfillment(of: [loaded.loaded], timeout: 10)
        _ = try await web.evaluateJavaScript("document.querySelector('#task').value = 'Unsent draft'")

        let catalog = ConsoleCatalog(chats: [], tools: [], projects: [], canCreate: true, canImport: true,
                                     canRetry: false, inWorkspace: false, notice: "", account: "", avatar: nil)
        let panel = ConsoleNavigator(model: NavigationModel(catalog), perform: { _, _ in }, close: {})
        let closed = expectation(description: "Sidebar closed")
        let drawer = SidebarDrawer(panel: panel, conversation: web) { closed.fulfill() }
        drawer.view.frame = CGRect(x: 0, y: 0, width: 400, height: 874)
        drawer.view.layoutIfNeeded()
        drawer.track(openingDistance: 60)
        XCTAssertEqual(web.transform.tx, 60, accuracy: 0.01)
        drawer.settle(open: true, animated: false)
        XCTAssertEqual(web.transform.tx, 220, accuracy: 0.01)
        drawer.view.frame.size = CGSize(width: 874, height: 400)
        drawer.view.setNeedsLayout()
        drawer.view.layoutIfNeeded()
        XCTAssertEqual(web.transform.tx, 480.7, accuracy: 0.01)
        drawer.settle(open: false, animated: false)
        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(web.transform, .identity)
        let draft = try await web.evaluateJavaScript("document.querySelector('#task').value")
        XCTAssertEqual(draft as? String, "Unsent draft")
    }

    func testOfflineDeviceOffersCloudWithoutTreatingRetryAsSignIn() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        let controller = ConsoleController()
        let navigation = ConsoleNavigation()
        navigation.attach(to: controller, web: web)
        let device = Console.origin.appending(path: "device/test/chat")
        let fixture = "<section class='portal-card'><button class='button primary'>Refresh</button><button class='button secondary'>Sign out</button></section>"
        for (url, expected) in [(device, true), (URL(string: "https://example.invalid/device/test/chat")!, false)] {
            let document = DocumentLoaded()
            web.navigationDelegate = document
            web.loadHTMLString(fixture, baseURL: url)
            await fulfillment(of: [document.loaded], timeout: 10)
            let home = try await web.evaluateJavaScript("document.querySelector('.portal-card a')?.href || ''")
            XCTAssertEqual(home as? String, expected ? Console.home.absoluteString : "")
            XCTAssertFalse(web.accessibilityElementsHidden)
        }
        withExtendedLifetime(controller) {}
    }

    func testSlowCloudSendShowsOneBubbleAndRestoresDraftOnRejection() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 800), configuration: config)
        let controller = ConsoleController(websiteDataStore: .nonPersistent())
        let navigation = ConsoleNavigation()
        navigation.attach(to: controller, web: web)
        let document = DocumentLoaded()
        web.navigationDelegate = document
        web.loadHTMLString("""
            <!doctype html><html lang="en"><meta name="viewport" content="width=device-width, initial-scale=1">
            <div id="app"><main><section id="transcript" data-transcript-session="draft:1">
            <div id="stream"><div class="empty">Welcome</div></div></section>
            <section class="composer"><div class="composer-inner"><div class="composer-input">
            <textarea id="task">Same message</textarea></div><div class="composer-actions">
            <button id="send" title="Send" onclick="window.sends++; setTimeout(() => { task.disabled = send.disabled = true }, 0)">Send</button>
            </div></div></section></main></div>
            """, baseURL: Console.home)
        await fulfillment(of: [document.loaded], timeout: 10)
        let states = try await web.callAsyncJavaScript("""
            const tick = () => new Promise(resolve => setTimeout(resolve, 30));
            const pending = () => stream.getAttribute('data-ios-outgoing') === task.value;
            window.sends = 0;
            send.click();
            send.click();
            await tick();
            const sending = window.sends === 1 && pending() && getComputedStyle(stream.firstElementChild).display === 'none'
                && getComputedStyle(task).opacity === '0' && task.value === 'Same message';
            task.disabled = send.disabled = false;
            await tick();
            const retry = !pending() && task.value === 'Same message' && getComputedStyle(task).opacity === '1';
            send.click();
            await tick();
            const resent = pending();
            task.value = '';
            task.disabled = false;
            send.outerHTML = '<button id="stop">Stop</button>';
            await tick();
            const awaitingHistory = stream.getAttribute('data-ios-outgoing') === 'Same message'
                && !document.querySelector('[data-ios-sending]');
            stream.innerHTML = '<div id="turn-s1" class="msg user"><div class="user-bubble">Same message</div></div>';
            await tick();
            return [sending, retry, resent, awaitingHistory, !stream.hasAttribute('data-ios-outgoing') && stream.children.length === 1];
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(states as? [Bool], [true, true, true, true, true])
        withExtendedLifetime(controller) {}
    }

    func testIPhoneHidesClientInstallPromotionsAndPreservesFileDownloads() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        let controller = ConsoleController(websiteDataStore: .nonPersistent())
        let navigation = ConsoleNavigation()
        navigation.attach(to: controller, web: web)
        let document = DocumentLoaded()
        web.navigationDelegate = document
        web.loadHTMLString("""
            <aside><div class="sidebar-footer"><button class="sidebar-button">下载客户端</button></div></aside>
            <section class="cloud-home-downloads">Download apps</section>
            <a download="chat.html" href="blob:fixture">Export chat</a>
            """, baseURL: Console.home)
        await fulfillment(of: [document.loaded], timeout: 10)
        let visible = try await web.evaluateJavaScript("""
            ['.sidebar-button', '.cloud-home-downloads', 'a[download]'].map(s =>
                getComputedStyle(document.querySelector(s)).display !== 'none')
            """)
        XCTAssertEqual(visible as? [Bool], [false, false, true])
        withExtendedLifetime(controller) {}
    }

    func testOnlyAConsolePageReceivesTheAccountInWebKit() async throws {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        let payload = #"{"token":"ts_fixture","user":{"user_id":"42","login":"O'Brien","avatar_url":""}}"#
        let account = try Account.serialized(from: Data(payload.utf8))
        for (url, allowed) in [(Console.home, true), (Console.origin.appending(path: "other"), false), (URL(string: "https://example.invalid/cloud")!, false)] {
            let document = DocumentLoaded(); web.navigationDelegate = document
            _ = web.loadHTMLString("<title>Fixture</title>", baseURL: url)
            await fulfillment(of: [document.loaded], timeout: 10)
            _ = try await web.evaluateJavaScript("localStorage.clear()")
            if allowed {
                try await ConsoleController.installAccount(account, in: web)
                let stored = try await web.evaluateJavaScript("JSON.parse(localStorage.getItem('seekmoon.account.v1')).user.login")
                XCTAssertEqual(stored as? String, "O'Brien")
            } else {
                do { try await ConsoleController.installAccount(account, in: web); XCTFail("Account written outside console") } catch {}
                let empty = try await web.evaluateJavaScript("localStorage.getItem('seekmoon.account.v1') === null")
                XCTAssertEqual(empty as? Bool, true)
            }
        }
        XCTAssertThrowsError(try Account.serialized(from: Data(payload.replacingOccurrences(of: "ts_fixture", with: "invalid").utf8)))
    }
}

private final class DocumentLoaded: NSObject, WKNavigationDelegate {
    let loaded = XCTestExpectation(description: "WebKit finished loading the test page")
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
