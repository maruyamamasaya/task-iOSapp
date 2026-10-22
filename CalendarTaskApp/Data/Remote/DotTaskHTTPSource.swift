import Foundation

// A future supported native authentication adapter must implement this contract.
// It must verify the account identity; caller-supplied user_id is not authentication.
@MainActor protocol DotTaskRequestAuthorizing {
    func request(for endpoint: URL, account: String) async throws -> URLRequest
}

@MainActor protocol DotTaskHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum DotTaskHTTPError: LocalizedError {
    case invalidEndpoint, invalidAuthorization, authenticationRequired, forbidden
    case invalidResponse, unexpectedStatus(Int), responseTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "接続先の設定が正しくありません。"
        case .invalidAuthorization: "認証済みリクエストを確認できませんでした。"
        case .authenticationRequired: "タスクの取得には再認証が必要です。"
        case .forbidden: "このタスク一覧へのアクセス権限がありません。"
        case .invalidResponse: "タスク API から正しい JSON 応答を受信できませんでした。"
        case .unexpectedStatus(let code): "タスク API がエラーを返しました（\(code)）。"
        case .responseTooLarge: "タスク API の応答サイズが上限を超えています。"
        }
    }
}

// No endpoint or token is shipped in AppDependencies. This adapter remains unused
// until native authentication and the list API contract have been verified.
@MainActor struct DotTaskHTTPSource: DotTaskSource {
    let source: String
    let account: String
    let endpoint: URL
    let authorization: any DotTaskRequestAuthorizing
    let transport: any DotTaskHTTPTransport
    static let maximumResponseBytes = 5 * 1024 * 1024

    func fetch() async throws -> DotTaskFeed {
        guard endpoint.scheme == "https", endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.fragment == nil, endpoint.query == nil,
              !source.isEmpty, !account.isEmpty else { throw DotTaskHTTPError.invalidEndpoint }
        var request = try await authorization.request(for: endpoint, account: account)
        guard request.url == endpoint, (request.httpMethod ?? "GET") == "GET",
              request.httpBody == nil, request.httpBodyStream == nil else {
            throw DotTaskHTTPError.invalidAuthorization
        }
        // No cookie jar, shared HTTP cache, or injected Sites identity headers.
        let forbiddenHeaders = ["cookie", "oai-sites-authorization", "host"]
        guard !(request.allHTTPHeaderFields ?? [:]).keys.contains(where: {
            forbiddenHeaders.contains($0.lowercased()) || $0.lowercased().hasPrefix("oai-authenticated-")
        }) else { throw DotTaskHTTPError.invalidAuthorization }
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard response.url == endpoint else { throw DotTaskHTTPError.invalidResponse }
        switch response.statusCode {
        case 401: throw DotTaskHTTPError.authenticationRequired
        case 403: throw DotTaskHTTPError.forbidden
        case 200: break
        default: throw DotTaskHTTPError.unexpectedStatus(response.statusCode)
        }
        guard response.mimeType?.lowercased() == "application/json" else {
            throw DotTaskHTTPError.invalidResponse
        }
        guard data.count <= Self.maximumResponseBytes else { throw DotTaskHTTPError.responseTooLarge }
        return try DotTaskFeedDecoder.decode(data)
    }
}

// Refuse even same-origin redirects. A sign-in HTML page must never look like
// a successful fetch and credentials must never be forwarded to another origin.
private final class DotTaskRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class URLSessionDotTaskTransport: DotTaskHTTPTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: DotTaskRedirectBlocker(), delegateQueue: nil)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DotTaskHTTPError.invalidResponse }
        return (data, response)
    }
    deinit { session.invalidateAndCancel() }
}
