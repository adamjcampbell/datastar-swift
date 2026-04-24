import Testing
@testable import Datastar

@Suite("ServerSentEventGenerator<Writer> generic path")
struct GeneratorGenericTests {
    // An in-memory collector writer — no framework dep, demonstrates the generic API.
    struct Collector {
        var bytes: [UInt8] = []
    }

    @Test("Emits the expected SSE wire output when specialized over an in-memory collector")
    func genericCollectorWrite() async throws {
        var sse = ServerSentEventGenerator<Collector>(Collector()) { collector, bytes in
            collector.bytes.append(contentsOf: bytes)
        }
        try await sse.patchElements("<p>hi</p>", options: .init(selector: "#t", mode: .inner))
        try await sse.patchSignals(#"{"count":1}"#)

        let output = String(decoding: sse.writer.bytes, as: UTF8.self)
        #expect(output == """
        event: datastar-patch-elements
        data: selector #t
        data: mode inner
        data: elements <p>hi</p>

        event: datastar-patch-signals
        data: signals {"count":1}


        """)
    }

    @Test("emit(_:) accepts pre-built events from the flat-kwargs factories")
    func genericCollectorEmitPreBuilt() async throws {
        var sse = ServerSentEventGenerator<Collector>(Collector()) { collector, bytes in
            collector.bytes.append(contentsOf: bytes)
        }
        try await sse.emit(DatastarEvent.patchElements("<p>a</p>"))
        let output = String(decoding: sse.writer.bytes, as: UTF8.self)
        #expect(output.contains("data: elements <p>a</p>"))
    }
}
