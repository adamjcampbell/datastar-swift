import DatastarHummingbird
import Foundation
import Hummingbird

private let indexHTML: String = {
    let url = Bundle.module.url(forResource: "index", withExtension: "html")!
    return try! String(contentsOf: url, encoding: .utf8)
}()

private struct HelloSignals: Decodable, Sendable {
    var delay: Double
}

@main
struct HelloWorldApp {
    static func main() async throws {
        let router = Router()

        router.get("/") { _, _ -> Response in
            Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: ResponseBody(byteBuffer: ByteBuffer(string: indexHTML))
            )
        }

        router.datastarGet("/hello-world", signals: HelloSignals.self) { signals, sse in
            let message = "Hello, world!"
            let delayMs = max(0, Int(signals.delay))
            for i in 1...message.count {
                try await sse.patchElements(#"<div id="message">\#(message.prefix(i))</div>"#)
                try await Task.sleep(for: .milliseconds(delayMs))
            }
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: 8080),
                serverName: "datastar-swift/HelloWorldExample"
            )
        )
        try await app.runService()
    }
}
