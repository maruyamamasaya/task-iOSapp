import Foundation
import CryptoKit
import Security

public enum BridgeNetworkError: Error { case invalidConfiguration, unavailable, unauthorized, conflict, unexpectedResponse }

private final class PinnedSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let pin: String
    init(pin: String) { self.pin = pin }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == pin else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        // Exact pre-approved leaf pin establishes pairing; no system trust-store modification.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

// Not instantiated by current app. Pairing material must be separately approved and Keychain-backed.
public final class HTTPSBridgeTransport: BridgeTransport, @unchecked Sendable {
    private let base: URL
    private let bearer: String
    private let session: URLSession
    private let pinnedDelegate: PinnedSessionDelegate
    public init(base: URL, certificateSHA256: String, bearer: String) throws {
        guard base.scheme == "https", let host = base.host,
              (host.hasSuffix(".local") || Self.isPrivateIPv4(host)),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/",
              certificateSHA256.count == 64, certificateSHA256.allSatisfy({ $0.isHexDigit }),
              !bearer.isEmpty, !bearer.contains("\r"), !bearer.contains("\n") else { throw BridgeNetworkError.invalidConfiguration }
        self.base = base; self.bearer = bearer
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForRequest = 10
        pinnedDelegate = PinnedSessionDelegate(pin: certificateSHA256.lowercased())
        session = URLSession(configuration: config, delegate: pinnedDelegate, delegateQueue: nil)
    }
    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
    }
    private func request<T: Decodable>(_ path: String, operation: CompletionOperation? = nil, initialFeed: BridgeFeed? = nil, dailyInput: String? = nil, type: T.Type) async throws -> T {
        let url = base.appending(path: path)
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let operation {
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(operation)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let initialFeed {
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(initialFeed)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let dailyInput {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(["inputJSON": dailyInput])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url else { throw BridgeNetworkError.unexpectedResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw BridgeNetworkError.unauthorized }
        if response.statusCode == 409 { throw BridgeNetworkError.conflict }
        guard [200, 202].contains(response.statusCode), response.mimeType == "application/json", data.count <= 1024 * 1024 else { throw BridgeNetworkError.unexpectedResponse }
        return try JSONDecoder().decode(type, from: data)
    }
    public func fetch() async throws -> BridgeFeed { try await request("v1/tasks", type: BridgeFeed.self) }
    public func submit(_ operation: CompletionOperation) async throws -> OperationReceipt { try await request("v1/operations", operation: operation, type: OperationReceipt.self) }
    public func receipt(for operationId: UUID) async throws -> OperationReceipt { try await request("v1/operations/" + operationId.uuidString.lowercased(), type: OperationReceipt.self) }
    public func registerInitialFeed(_ feed: BridgeFeed) async throws -> BridgeFeed { try await request("v1/bootstrap", initialFeed: feed, type: BridgeFeed.self) }
    public func exchangeDailyBrief(inputJSON: String) async throws -> Data {
        let response = try await request("v1/daily-brief", dailyInput: inputJSON, type: DailyBriefResponse.self)
        return try JSONEncoder().encode(response)
    }
    public func fetchDailyAudio(sha256: String) async throws -> Data {
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { throw BridgeNetworkError.invalidConfiguration }
        let url = base.appending(path: "v1/daily-audio/" + sha256)
        var request = URLRequest(url: url)
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request, delegate: pinnedDelegate)
        guard let response = response as? HTTPURLResponse, response.url == url,
              response.statusCode == 200, response.mimeType == "audio/wav",
              response.expectedContentLength <= 12 * 1024 * 1024 else { throw BridgeNetworkError.unexpectedResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 12 * 1024 * 1024 else { throw BridgeNetworkError.unexpectedResponse }
            data.append(byte)
        }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw BridgeNetworkError.unexpectedResponse
        }
        return data
    }
    private struct DailyBriefResponse: Codable {
        struct Brief: Codable {
            let date: String
            let timeZone: String
            let contextID: String
            let kind: String
            let text: String
            let generatedAt: String
            let briefID: String?
            let audio: Audio?
            struct Audio: Codable { let sha256: String; let byteCount: Int; let contentType: String; let duration: Double }
        }
        let brief: Brief?
    }
    public func cancelRequests() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }
}
