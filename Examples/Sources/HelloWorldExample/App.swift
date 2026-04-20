import Datastar
import Foundation
import Hummingbird
import NIOCore

private let indexHTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>datastar-swift · Hello World</title>
    <script type="module" src="https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0/bundles/datastar.js"></script>
    <style>
        body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; max-width: 40rem; margin: auto; }
        input, button { padding: 0.5rem 0.75rem; font-size: 1rem; }
        button { margin-left: 0.5rem; }
        #message { margin-top: 2rem; font-size: 1.75rem; font-weight: 600; min-height: 2.5rem; }
    </style>
</head>
<body data-signals="{delay: 200}">
    <h1>datastar-swift — Hello World</h1>
    <p>
        Delay (ms):
        <input type="number" data-bind:delay min="0" max="2000" step="50" />
        <button data-on:click="@get('/hello-world')">Start</button>
    </p>
    <div id="message"></div>
    <p style="color:#666; font-size:0.875rem;">
        Clicking Start issues a GET to <code>/hello-world?datastar=…</code>.
        The server streams <code>datastar-patch-elements</code> frames, one character at a time.
    </p>
</body>
</html>
"""

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
            let raw = request.uri.queryParameters["datastar"].map(String.init) ?? #"{"delay":200}"#
            let signals = try JSONDecoder().decode(HelloSignals.self, from: Data(raw.utf8))

            let message = "Hello, world!"
            let delayMs = max(0, Int(signals.delay))

            let body = ServerSentEventGenerator.stream { emit in
                for i in 1...message.count {
                    let prefix = String(message.prefix(i))
                    try await emit(.patchElements(#"<div id="message">\#(prefix)</div>"#))
                    try await Task.sleep(for: .milliseconds(delayMs))
                }
            }

            return Response(
                status: .ok,
                headers: [
                    .contentType: "text/event-stream",
                    .cacheControl: "no-cache",
                ],
                body: ResponseBody(asyncSequence: body.map { ByteBuffer(bytes: $0) })
            )
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
