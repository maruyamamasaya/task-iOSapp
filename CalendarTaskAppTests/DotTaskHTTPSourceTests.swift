import XCTest
@testable import CalendarTaskApp

@MainActor final class DotTaskHTTPSourceTests: XCTestCase {
    final class Authorizer: DotTaskRequestAuthorizing {
        var receivedAccount: String?
        var replacementURL: URL?
        var extraHeaders: [String: String] = [:]
        func request(for endpoint: URL, account: String) async throws -> URLRequest {
            receivedAccount = account
            var request = URLRequest(url: replacementURL ?? endpoint)
            // Synthetic test value; no production credential.
            request.setValue("Bearer test-only", forHTTPHeaderField: "Authorization")
            for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
            return request
        }
    }
    final class Transport: DotTaskHTTPTransport {
        var request: URLRequest?
        var status = 200
        var contentType = "application/json"
        var data = Data(FixtureDotTaskSource.json.utf8)
        var responseURL: URL?
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            self.request = request
            return (data, HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": contentType])!)
        }
    }
    let endpoint = URL(string: "https://example.invalid/api/tasks")!
    func source(_ auth: Authorizer, _ transport: Transport, url: URL? = nil) -> DotTaskHTTPSource {
        DotTaskHTTPSource(source: "test", account: "account-one", endpoint: url ?? endpoint,
                          authorization: auth, transport: transport)
    }
    func testAuthorizedJSONFetchDoesNotUseCookieOrHTTPCache() async throws {
        let auth = Authorizer(), transport = Transport()
        let feed = try await source(auth, transport).fetch()
        XCTAssertEqual(feed.tasks.count, 2)
        XCTAssertEqual(auth.receivedAccount, "account-one")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(transport.request?.httpShouldHandleCookies, false)
        XCTAssertEqual(transport.request?.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testRejectsUnsafeEndpointAndAuthorizationBeforeTransport() async {
        for url in ["http://example.invalid/api/tasks", "https://name:password@example.invalid/api/tasks", "https://example.invalid/api/tasks?token=x"] {
            let auth = Authorizer(), transport = Transport()
            do { _ = try await source(auth, transport, url: URL(string: url)!).fetch(); XCTFail("accepted unsafe endpoint") }
            catch { XCTAssertNil(transport.request) }
        }
        for header in ["Cookie", "OAI-Sites-Authorization", "oai-authenticated-user-id"] {
            let auth = Authorizer(), transport = Transport()
            auth.extraHeaders[header] = "test-only"
            do { _ = try await source(auth, transport).fetch(); XCTFail("accepted internal identity") }
            catch { XCTAssertNil(transport.request) }
        }
        let auth = Authorizer(), transport = Transport()
        auth.replacementURL = URL(string: "https://other.invalid/api/tasks")
        do { _ = try await source(auth, transport).fetch(); XCTFail("accepted changed URL") }
        catch { XCTAssertNil(transport.request) }
    }
    func testRejectsAuthErrorsRedirectsHTMLAndInvalidJSON() async {
        for status in [401, 403, 302, 404, 500] {
            let auth = Authorizer(), transport = Transport()
            transport.status = status
            do { _ = try await source(auth, transport).fetch(); XCTFail("accepted status \(status)") }
            catch let error as DotTaskHTTPError {
                switch (status, error) {
                case (401, .authenticationRequired), (403, .forbidden): break
                case (_, .unexpectedStatus(let actual)): XCTAssertEqual(actual, status)
                default: XCTFail("wrong error")
                }
            } catch { XCTFail("unexpected error") }
        }
        let auth = Authorizer(), transport = Transport()
        transport.contentType = "text/html"
        do { _ = try await source(auth, transport).fetch(); XCTFail("accepted HTML") } catch {}
        transport.contentType = "application/json"
        transport.data = Data("broken".utf8)
        do { _ = try await source(auth, transport).fetch(); XCTFail("accepted invalid JSON") } catch {}
        transport.data = Data(FixtureDotTaskSource.json.utf8)
        transport.responseURL = URL(string: "https://other.invalid/api/tasks")
        do { _ = try await source(auth, transport).fetch(); XCTFail("accepted redirected response") } catch {}
    }
}
