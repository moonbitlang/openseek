import CryptoKit
import Foundation

enum Console {
    static let origin = URL(string: "https://seekmoon.moonbitlang.com")!
    static let home = origin.appending(path: "cloud")

    static func owns(_ url: URL?) -> Bool {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "https" && parts.host?.lowercased() == origin.host &&
            (parts.port == nil || parts.port == 443) && parts.user == nil && parts.password == nil
    }

    static func isPage(_ url: URL?) -> Bool {
        guard owns(url), let path = url?.path else { return false }
        return path == "/cloud" || path.hasPrefix("/cloud/") || path.hasPrefix("/device/")
    }
}

enum SignInError: LocalizedError, Equatable {
    case callback, denied, unavailable, timeout, exchange(Int), account

    var errorDescription: String? {
        switch self {
        case .callback: return "The sign-in reply did not match this attempt. Please try again."
        case .denied: return "Sign-in was declined."
        case .unavailable: return "Unable to start system sign-in. Please try again."
        case .timeout: return "Sign-in timed out. Please try again."
        case .exchange(let status): return "The sign-in service returned HTTP \(status)."
        case .account: return "The sign-in service did not return a valid SeekMoon account."
        }
    }
}

struct AccountFlow {
    let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let verifier = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    let scheme: String

    func startURL(port: UInt16) -> URL {
        var parts = URLComponents(url: Console.origin.appending(path: "v2/auth/account/start"), resolvingAgainstBaseURL: false)!
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        parts.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge", value: challenge),
                            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "port", value: String(port))]
        return parts.url!
    }

    func browserReturn(target: String) -> URL? {
        guard let parts = URLComponents(string: target), parts.scheme == nil, parts.host == nil,
              parts.percentEncodedPath == "/cb", parts.fragment == nil, let query = parts.queryItems,
              query.filter({ $0.name == "state" }).map(\.value) == [state] else { return nil }
        let codes = query.filter { $0.name == "code" }
        let errors = query.filter { $0.name == "error" }
        let reply: URLQueryItem
        if codes.count == 1, let code = codes[0].value, !code.isEmpty, errors.isEmpty {
            reply = URLQueryItem(name: "code", value: code)
        } else if codes.isEmpty, errors.count == 1 {
            reply = URLQueryItem(name: "error", value: "denied")
        } else { return nil }
        var result = URLComponents()
        result.scheme = scheme; result.host = "oauth"; result.path = "/complete"
        result.queryItems = [URLQueryItem(name: "state", value: state), reply]
        return result.url
    }

    func code(from url: URL) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
              parts.host == "oauth", parts.percentEncodedPath == "/complete", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil, let query = parts.queryItems,
              query.filter({ $0.name == "state" }).map(\.value) == [state] else { throw SignInError.callback }
        if query.contains(where: { $0.name == "error" }) { throw SignInError.denied }
        let codes = query.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else { throw SignInError.callback }
        return code
    }

    func exchangeRequest(code: String) throws -> URLRequest {
        var request = URLRequest(url: Console.origin.appending(path: "v2/auth/account/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code, "code_verifier": verifier]); request.timeoutInterval = 30
        return request
    }
}

struct Account: Codable {
    struct User: Codable { let user_id: String; let login: String; let avatar_url: String }
    let token: String
    let user: User

    static func serialized(from data: Data) throws -> String {
        guard let session = try? JSONDecoder().decode(Self.self, from: data), session.token.hasPrefix("ts_"), session.token.count > 3,
              !session.user.user_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !session.user.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SignInError.account }
        return String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
    }
}
