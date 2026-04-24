import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import DatastarHummingbird

private struct Signals: Codable, Equatable, Sendable {
    var name: String = ""

    init(name: String = "") { self.name = name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

@Suite("Router Datastar sugar")
struct RouterSugarTests {
    @Test("datastarGet decodes query signals and emits via the generator")
    func getRouteWithQuerySignals() async throws {
        let router = Router()
        router.datastarGet("/stream", signals: Signals.self) { signals, sse in
            try await sse.patchElements(
                "<p>\(signals.name)</p>",
                options: .init(selector: "#greeting", mode: .inner)
            )
        }

        let payload = Signals(name: "ada")
        let encoded = try JSONEncoder().encode(payload)
        let jsonString = String(decoding: encoded, as: UTF8.self)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let app = Application(router: router)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/stream?datastar=\(jsonString)",
                method: .get
            )
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            let body = String(buffer: response.body)
            #expect(body == """
            event: datastar-patch-elements
            data: selector #greeting
            data: mode inner
            data: elements <p>ada</p>


            """)
        }
    }

    @Test("datastarPost decodes body signals and emits via the generator")
    func postRouteWithBodySignals() async throws {
        let router = Router()
        router.datastarPost("/submit", signals: Signals.self) { signals, sse in
            try await sse.patchElements(
                "<p>\(signals.name)</p>",
                options: .init(selector: "#out", mode: .inner)
            )
        }

        let payload = Signals(name: "grace")
        let body = try JSONEncoder().encode(payload)

        let app = Application(router: router)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/submit",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            )
            #expect(response.status == .ok)
            let out = String(buffer: response.body)
            #expect(out.contains("data: elements <p>grace</p>"))
        }
    }
}
