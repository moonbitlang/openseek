import CryptoKit
import WebKit
import XCTest
@testable import SeekMoon

@MainActor final class SeekMoonTests: XCTestCase {
    func testPackagedConsoleRestoresAndReloadsDeviceRoutes() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let defaults = UserDefaults.standard
        let key = "console.lastPage"
        let previous = defaults.url(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        let start = Console.origin.appending(path: "cloud")
        defaults.set(start, forKey: key)

        let controller = ConsoleController(dataStore: store)
        controller.loadViewIfNeeded()
        let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
        try await waitForFrontend(web, at: start)
        let route = try XCTUnwrap(URL(string: "/device/d/chat/session/a%2Fb", relativeTo: Console.origin)?.absoluteURL)
        _ = try await web.evaluateJavaScript("location.assign('/device/d/chat/session/a%2Fb'); true")
        try await waitForFrontend(web, at: route)
        XCTAssertEqual(defaults.url(forKey: key), route)
        _ = try await web.evaluateJavaScript("window.beforeReload = true")
        web.reload()
        try await waitForFrontend(web, at: route)
        XCTAssertEqual(web.backForwardList.backItem?.url, start)
        web.goBack()
        try await waitForFrontend(web, at: start)
        web.goForward()
        try await waitForFrontend(web, at: route)

        let restored = ConsoleController(dataStore: store)
        restored.loadViewIfNeeded()
        let reopened = try XCTUnwrap(restored.view.subviews.compactMap { $0 as? WKWebView }.first)
        try await waitForFrontend(reopened, at: route)
        withExtendedLifetime((controller, restored)) {}
    }

    func testBrowserArchiveRendersAndLoadsLazyAssetsAtAnUnreachableOrigin() async throws {
        // Rebase only the archive's URL keys. The unmodified HTML, JavaScript and styles
        // cannot fall back to the hosted console if a packaged subresource is missing.
        let file = try XCTUnwrap(Bundle.main.url(forResource: "Console", withExtension: "webarchive"))
        let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
        var archive = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
        var resources = try XCTUnwrap(archive["WebSubresources"] as? [[String: Any]])
        let offline = URL(string: "https://seekmoon.invalid")!
        for index in resources.indices {
            let original = try XCTUnwrap(resources[index]["WebResourceURL"] as? String)
            XCTAssertTrue(original.hasPrefix(Console.origin.absoluteString + "/"))
            resources[index]["WebResourceURL"] = offline.absoluteString + original.dropFirst(Console.origin.absoluteString.count)
        }
        archive["WebSubresources"] = resources
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        let url = offline.appending(path: "cloud")
        web.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: url)
        try await waitForFrontend(web, at: url)
        let assetsLoaded = try await web.callAsyncJavaScript("""
            const viewer = await fetch('/assets/viz/index.html');
            const mermaid = await import('/assets/mermaid/mermaid.esm.min.mjs');
            return (await viewer.text()).includes('OpenSeek session viewer') && typeof mermaid.default.render === 'function';
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(assetsLoaded as? Bool, true)
    }

    private func waitForFrontend(_ web: WKWebView, at url: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(25)
        while ContinuousClock.now < deadline {
            if !web.isLoading, web.url == url,
               (try? await web.evaluateJavaScript("!window.beforeReload && document.querySelector('#app')?.childElementCount > 0 && document.styleSheets.length > 0")) as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let state = try? await web.evaluateJavaScript("[location.href, document.readyState, document.body?.innerText?.slice(0, 150), window.beforeReload ?? false]")
        XCTFail("Packaged frontend did not render at \(url): \(String(describing: state))")
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

    func testDeclineAndUnrelatedCallbackNeverProduceAnAuthorizationCode() throws {
        let flow = AccountFlow(scheme: "com.example.seekmoon.test")
        let denied = try XCTUnwrap(flow.browserReturn(target: "/cb?state=\(flow.state)&error=access_denied"))
        XCTAssertThrowsError(try flow.code(from: denied)) { XCTAssertEqual($0 as? SignInError, .denied) }
        XCTAssertNil(flow.browserReturn(target: "/cb?state=\(flow.state)&code=a&code=b"))
        let wrongHost = try XCTUnwrap(URL(string: "\(flow.scheme)://other/complete?state=\(flow.state)&code=test"))
        XCTAssertThrowsError(try flow.code(from: wrongHost))
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
