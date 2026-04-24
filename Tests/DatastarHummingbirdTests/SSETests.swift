import Hummingbird
import HummingbirdTesting
import Testing
@testable import DatastarHummingbird

@Suite("Response.datastarSSE wire output and headers")
struct SSETests {
    @Test("Sets the three ADR-mandated SSE response headers")
    func headersMatchADR() async throws {
        let router = Router()
        router.get("/stream") { _, _ -> Response in
            .datastarSSE { _ in }
        }
        let app = Application(router: router)
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/stream", method: .get)
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "text/event-stream")
            #expect(response.headers[.cacheControl] == "no-cache")
            #expect(response.headers[.connection] == "keep-alive")
        }
    }

    @Test("Generator methods produce the expected SSE wire bytes in the response body")
    func generatorEmitsExpectedBytes() async throws {
        let router = Router()
        router.get("/stream") { _, _ -> Response in
            .datastarSSE { sse in
                try await sse.patchElements(
                    "<div>Hi</div>",
                    options: .init(selector: "#msg", mode: .inner)
                )
                try await sse.patchSignals(#"{"count":1}"#)
            }
        }
        let app = Application(router: router)
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/stream", method: .get)
            #expect(response.status == .ok)
            let body = String(buffer: response.body)
            #expect(body == """
            event: datastar-patch-elements
            data: selector #msg
            data: mode inner
            data: elements <div>Hi</div>

            event: datastar-patch-signals
            data: signals {"count":1}


            """)
        }
    }

    @Test("executeScript emits the append-to-body frame on the wire")
    func executeScriptWire() async throws {
        let router = Router()
        router.get("/stream") { _, _ -> Response in
            .datastarSSE { sse in
                try await sse.executeScript("boot()", options: .init(autoRemove: false))
            }
        }
        let app = Application(router: router)
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/stream", method: .get)
            let body = String(buffer: response.body)
            #expect(body.contains("data: selector body"))
            #expect(body.contains("data: mode append"))
            #expect(body.contains("data: elements <script>boot()</script>"))
        }
    }
}
