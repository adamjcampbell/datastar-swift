import Datastar
import DatastarHummingbird
import Foundation
import Hummingbird
import NIOCore

private let indexHTML: String = {
    let url = Bundle.module.url(forResource: "index", withExtension: "html")!
    return try! String(contentsOf: url, encoding: .utf8)
}()

private struct HelloSignals: Decodable {
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

        router.get("/hello-world") { request, _ -> Response in
            let signals = try request.datastarSignals(as: HelloSignals.self)
            let message = "Hello, world!"
            let delayMs = max(0, Int(signals.delay))
            return .datastarSSE { writer in
                for i in 1...message.count {
                    try await writer.emit(.patchElements(#"<div id="message">\#(message.prefix(i))</div>"#))
                    try await Task.sleep(for: .milliseconds(delayMs))
                }
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
