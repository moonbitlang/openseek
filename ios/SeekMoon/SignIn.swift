import AuthenticationServices
import Network

final class CallbackListener {
    private let listener: NWListener
    private let flow: AccountFlow
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var consumed = false

    init(flow: AccountFlow) throws {
        self.flow = flow
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start(ready: @escaping (UInt16) -> Void, failed: @escaping (Error) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: if let port = self?.listener.port { ready(port.rawValue) }
            case .failed(let error): failed(error)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            let key = ObjectIdentifier(connection)
            connections[key] = connection
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state { self?.connections.removeValue(forKey: key) }
            }
            connection.start(queue: .main)
            read(connection, prefix: Data())
        }
        listener.start(queue: .main)
    }

    private func read(_ connection: NWConnection, prefix: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - prefix.count) { [weak self] chunk, _, ended, error in
            guard let self, let chunk, error == nil else { connection.cancel(); return }
            let buffer = prefix + chunk
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count < 8192 && !ended { read(connection, prefix: buffer) } else { connection.cancel() }
                return
            }
            let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let request = lines[0].split(separator: " ")
            let expectedHost = listener.port.map { "127.0.0.1:\($0.rawValue)" }
            let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            let status: String
            if !consumed, let expectedHost, hosts == [expectedHost], request.count == 3, request[0] == "GET",
               let location = flow.browserReturn(target: String(request[1])) {
                consumed = true
                status = "302 Found\r\nLocation: \(location.absoluteString)"
            } else { status = "404 Not Found" }
            let response = "HTTP/1.1 \(status)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func stop() {
        listener.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class SignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow
    private let flow = AccountFlow(scheme: Bundle.main.bundleIdentifier!)
    private var listener: CallbackListener?
    private var browser: ASWebAuthenticationSession?
    private var timeout: Task<Void, Never>?
    private var completion: ((Result<String, Error>) -> Void)?

    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }

    func start(method: SignInMethod?, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        do {
            let listener = try CallbackListener(flow: flow)
            self.listener = listener
            listener.start(ready: { [weak self] port in self?.open(port: port, method: method) }, failed: { [weak self] error in self?.finish(.failure(error)) })
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                self?.finish(.failure(SignInError.timeout))
            }
        } catch { finish(.failure(error)) }
    }

    private func open(port: UInt16, method: SignInMethod?) {
        let session = ASWebAuthenticationSession(url: flow.startURL(port: port, method: method), callback: .customScheme(flow.scheme)) { [weak self] url, error in
            Task { @MainActor [weak self] in
                guard let self, completion != nil else { return }
                listener?.stop(); timeout?.cancel()
                do {
                    if let error { throw error }
                    guard let url else { throw SignInError.callback }
                    let request = try flow.exchangeRequest(code: flow.code(from: url))
                    let transport = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
                    defer { transport.finishTasksAndInvalidate() }
                    let (data, response) = try await transport.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw SignInError.exchange((response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    finish(.success(try Account.serialized(from: data)))
                } catch { finish(.failure(error)) }
            }
        }
        session.presentationContextProvider = self
        browser = session
        if !session.start() { finish(.failure(SignInError.unavailable)) }
    }

    private func finish(_ result: Result<String, Error>) {
        let callback = completion; completion = nil
        timeout?.cancel(); listener?.stop(); browser?.cancel(); browser = nil
        callback?(result)
    }
}
