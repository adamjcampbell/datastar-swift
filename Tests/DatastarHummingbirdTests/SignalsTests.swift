import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import DatastarHummingbird

private struct Signals: Codable, Equatable, Sendable {
    var count: Int = 0
    var name: String = ""

    // Default-tolerant decoding so `{}` decodes to Signals() — mirrors the
    // intent of the extractor's empty-body fallback.
    init() {}
    init(count: Int, name: String) { self.count = count; self.name = name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

@Suite("Request.datastarSignals method-aware extractor")
struct SignalsTests {
    private func makeRouter() -> Router<BasicRequestContext> {
        let router = Router()
        // One echo route; the method-aware extractor picks the right source per verb.
        for method in [HTTPRequest.Method.get, .delete, .post, .put, .patch] {
            router.on("/signals", method: method) { request, context -> Response in
                var request = request
                let signals = try await request.datastarSignals(as: Signals.self, context: context)
                let body = try JSONEncoder().encode(signals)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
                )
            }
        }
        return router
    }

    @Test(
        "Method dispatch: GET/DELETE read from ?datastar= query; POST/PUT/PATCH read body",
        arguments: [
            (HTTPRequest.Method.get, "query"),
            (.delete, "query"),
            (.post, "body"),
            (.put, "body"),
            (.patch, "body"),
        ] as [(HTTPRequest.Method, String)]
    )
    func methodDispatch(method: HTTPRequest.Method, source: String) async throws {
        let payload = Signals(count: 42, name: "ada")
        let json = try JSONEncoder().encode(payload)
        let jsonString = String(decoding: json, as: UTF8.self)

        let app = Application(router: makeRouter())
        try await app.test(.router) { client in
            let response: TestResponse
            if source == "query" {
                let encoded = jsonString.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ) ?? jsonString
                response = try await client.execute(
                    uri: "/signals?datastar=\(encoded)",
                    method: method
                )
            } else {
                response = try await client.execute(
                    uri: "/signals",
                    method: method,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(bytes: json)
                )
            }
            #expect(response.status == .ok)
            let decoded = try JSONDecoder().decode(Signals.self, from: response.body)
            #expect(decoded == payload)
        }
    }

    @Test("Missing GET query parameter decodes as empty JSON")
    func missingQueryFallsBackToEmpty() async throws {
        let app = Application(router: makeRouter())
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/signals", method: .get)
            #expect(response.status == .ok)
            let decoded = try JSONDecoder().decode(Signals.self, from: response.body)
            #expect(decoded == Signals())
        }
    }

    @Test("Empty POST body decodes as empty JSON")
    func emptyBodyFallsBackToEmpty() async throws {
        let app = Application(router: makeRouter())
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/signals", method: .post)
            #expect(response.status == .ok)
            let decoded = try JSONDecoder().decode(Signals.self, from: response.body)
            #expect(decoded == Signals())
        }
    }
}
