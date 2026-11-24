import CryptoKit
import WebKit
import XCTest
@testable import SeekMoon

@MainActor final class SeekMoonTests: XCTestCase {
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
