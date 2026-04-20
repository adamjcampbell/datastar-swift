import Foundation
import Testing
@testable import Datastar

@Suite("patchSignals")
struct PatchSignalsTests {
    struct Example: Encodable {
        let count: Int
    }

    @Test("Encodable payload emits single-line JSON by default")
    func encodableSingleLine() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchSignals(Example(count: 42))
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-signals
        data: signals {"count":42}


        """)
    }

    @Test("patchSignalsJSON accepts a raw pre-serialized string")
    func rawJSON() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchSignalsJSON(#"{"a":1}"#)
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-signals
        data: signals {"a":1}


        """)
    }

    @Test("onlyIfMissing=true emits the line; false is suppressed")
    func onlyIfMissing() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchSignalsJSON(#"{"a":1}"#, onlyIfMissing: true)
        let out = await collect(sse)
        #expect(out.contains("data: onlyIfMissing true\n"))

        let sse2 = ServerSentEventGenerator()
        try sse2.patchSignalsJSON(#"{"a":1}"#, onlyIfMissing: false)
        let out2 = await collect(sse2)
        #expect(!out2.contains("onlyIfMissing"))
    }

    @Test("Multi-line JSON is split into one data: signals line per source line")
    func multilineJSON() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchSignalsJSON("{\n  \"a\": 1\n}")
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-signals
        data: signals {
        data: signals   "a": 1
        data: signals }


        """)
    }

    @Test("eventID and retryDuration are emitted")
    func idAndRetry() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchSignalsJSON(
            #"{"x":1}"#,
            eventID: "sig-1",
            retryDuration: .milliseconds(3000)
        )
        let out = await collect(sse)
        #expect(out.contains("id: sig-1\n"))
        #expect(out.contains("retry: 3000\n"))
    }
}
