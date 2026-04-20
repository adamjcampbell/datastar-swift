import Datastar
import Foundation
import Hummingbird
import NIOCore

private let indexHTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>datastar-swift · Activity Feed</title>
    <script type="module" src="https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0/bundles/datastar.js"></script>
    <style>
        body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; max-width: 50rem; margin: auto; }
        input, button { padding: 0.4rem 0.75rem; font-size: 1rem; }
        button { margin-right: 0.25rem; }
        .counters { margin: 1.25rem 0; font-size: 1rem; }
        .counters span { font-variant-numeric: tabular-nums; font-weight: 600; }
        ul#feed { list-style: none; padding: 0; border-top: 1px solid #eee; }
        ul#feed li { padding: 0.5rem 0.75rem; border-bottom: 1px solid #eee; font-family: ui-monospace, monospace; font-size: 0.9rem; }
        ul#feed li.done { background: #f0fdf4; }
        ul#feed li.warn { background: #fefce8; }
        ul#feed li.fail { background: #fef2f2; }
        ul#feed li.info { background: #eff6ff; }
    </style>
</head>
<body data-signals="{total: 0, done: 0, warn: 0, fail: 0, info: 0, count: 5, interval: 200}">
    <h1>datastar-swift — Activity Feed</h1>

    <p>
        Bulk:
        count <input type="number" data-bind:count min="1" max="50" style="width:4rem" />
        ×
        interval <input type="number" data-bind:interval min="0" max="2000" step="50" style="width:5rem" /> ms
        <button data-on:click="@post('/event/generate')">Generate</button>
    </p>

    <p>
        Single:
        <button data-on:click="@post('/event/done')">done</button>
        <button data-on:click="@post('/event/warn')">warn</button>
        <button data-on:click="@post('/event/fail')">fail</button>
        <button data-on:click="@post('/event/info')">info</button>
    </p>

    <div class="counters">
        total <span data-text="$total"></span> ·
        done <span data-text="$done"></span> ·
        warn <span data-text="$warn"></span> ·
        fail <span data-text="$fail"></span> ·
        info <span data-text="$info"></span>
    </div>

    <ul id="feed"></ul>
</body>
</html>
"""

private enum Status: String, CaseIterable, Sendable {
    case done, warn, fail, info
}

/// Full signals payload sent by the client with every request.
/// Counters are owned by the client; the server reads them, increments, and sends back.
private struct ActivitySignals: Codable, Sendable {
    var total: Int = 0
    var done: Int = 0
    var warn: Int = 0
    var fail: Int = 0
    var info: Int = 0
    var count: Int = 5
    var interval: Int = 200
}

extension ActivitySignals {
    mutating func bump(_ status: Status) {
        total += 1
        switch status {
        case .done: done += 1
        case .warn: warn += 1
        case .fail: fail += 1
        case .info: info += 1
        }
    }
}

private func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

private func entryHTML(status: Status, index: Int) -> String {
    let ts = isoTimestamp()
    return #"<li class="\#(status.rawValue)">[\#(ts)] \#(status.rawValue) #\#(index)</li>"#
}

private func emit(
    status: Status,
    index: Int,
    signals: inout ActivitySignals,
    sse: SSEWriter
) async throws {
    signals.bump(status)
    try await sse.patchElements(entryHTML(status: status, index: index), selector: "#feed", mode: .prepend)
    try await sse.patchSignals(signals)
}

private func readSignals(from request: Request) async throws -> ActivitySignals {
    let buffer = try await request.body.collect(upTo: 1 << 16) // 64 KiB cap
    let bytes = Data(buffer: buffer)
    if bytes.isEmpty {
        return ActivitySignals()
    }
    return try DatastarSignals.decode(ActivitySignals.self, fromBody: bytes)
}

private func streamingResponse(_ body: DatastarSSEBody) -> Response {
    Response(
        status: .ok,
        headers: [
            .contentType: "text/event-stream",
            .cacheControl: "no-cache",
        ],
        body: ResponseBody(asyncSequence: body.map { ByteBuffer(bytes: $0) })
    )
}

@main
struct ActivityFeedApp {
    static func main() async throws {
        let router = Router()

        router.get("/") { _, _ -> Response in
            Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: ResponseBody(byteBuffer: ByteBuffer(string: indexHTML))
            )
        }

        for status in Status.allCases {
            router.post("/event/\(status.rawValue)") { request, _ -> Response in
                let initialSignals = try await readSignals(from: request)
                let body = ServerSentEventGenerator.stream { sse in
                    var signals = initialSignals
                    try await emit(status: status, index: signals.total + 1, signals: &signals, sse: sse)
                }
                return streamingResponse(body)
            }
        }

        router.post("/event/generate") { request, _ -> Response in
            let initialSignals = try await readSignals(from: request)
            let count = max(1, min(50, initialSignals.count))
            let interval = max(0, min(2000, initialSignals.interval))

            let body = ServerSentEventGenerator.stream { sse in
                var signals = initialSignals
                for _ in 0..<count {
                    let status = Status.allCases.randomElement() ?? .info
                    try await emit(status: status, index: signals.total + 1, signals: &signals, sse: sse)
                    try await Task.sleep(for: .milliseconds(interval))
                }
            }
            return streamingResponse(body)
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: 8081),
                serverName: "datastar-swift/ActivityFeedExample"
            )
        )
        try await app.runService()
    }
}
