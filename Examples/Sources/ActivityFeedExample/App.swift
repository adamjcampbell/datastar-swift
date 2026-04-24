import DatastarHummingbird
import Foundation
import Hummingbird

private let indexHTML: String = {
    let url = Bundle.module.url(forResource: "index", withExtension: "html")!
    return try! String(contentsOf: url, encoding: .utf8)
}()

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

private typealias HummingbirdSSE = ServerSentEventGenerator<any ResponseBodyWriter>

private func appendActivity(
    status: Status,
    index: Int,
    signals: inout ActivitySignals,
    sse: inout HummingbirdSSE
) async throws {
    signals.bump(status)
    try await sse.patchElements(
        entryHTML(status: status, index: index),
        options: .init(selector: "#feed", mode: .prepend)
    )
    try await sse.emit(try DatastarEvent.patchSignals(encoding: signals))
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
            router.post("/event/\(status.rawValue)") { request, context -> Response in
                var req = request
                let initialSignals = try await req.datastarSignals(as: ActivitySignals.self, context: context)
                return .datastarSSE { [initialSignals] sse in
                    var signals = initialSignals
                    try await appendActivity(status: status, index: signals.total + 1, signals: &signals, sse: &sse)
                }
            }
        }

        router.post("/event/generate") { request, context -> Response in
            var req = request
            let initialSignals = try await req.datastarSignals(as: ActivitySignals.self, context: context)
            let count = max(1, min(50, initialSignals.count))
            let interval = max(0, min(2000, initialSignals.interval))
            return .datastarSSE { [initialSignals] sse in
                var signals = initialSignals
                for _ in 0..<count {
                    let status = Status.allCases.randomElement() ?? .info
                    try await appendActivity(status: status, index: signals.total + 1, signals: &signals, sse: &sse)
                    try await Task.sleep(for: .milliseconds(interval))
                }
            }
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
