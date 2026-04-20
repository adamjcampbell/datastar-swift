import Testing
@testable import Datastar

@Suite("SSE wire format")
struct SSEEncodingTests {
    @Test("Event with a single data line ends with a blank line")
    func singleDataLine() {
        let bytes = SSEEncoding.encode(
            SSEEvent(name: "x", id: nil, retry: nil, data: ["hello"])
        )
        let out = String(decoding: bytes, as: UTF8.self)
        #expect(out == "event: x\ndata: hello\n\n")
    }

    @Test("Event with id and retry emits them in order")
    func idAndRetry() {
        let bytes = SSEEncoding.encode(
            SSEEvent(
                name: "x",
                id: "42",
                retry: .milliseconds(2500),
                data: ["a", "b"]
            )
        )
        let out = String(decoding: bytes, as: UTF8.self)
        #expect(out == "event: x\nid: 42\nretry: 2500\ndata: a\ndata: b\n\n")
    }

    @Test("Empty id is suppressed")
    func emptyIDSuppressed() {
        let bytes = SSEEncoding.encode(
            SSEEvent(name: "x", id: "", retry: nil, data: ["a"])
        )
        let out = String(decoding: bytes, as: UTF8.self)
        #expect(out == "event: x\ndata: a\n\n")
    }

    @Test("Retry duration is emitted in milliseconds, truncated toward zero")
    func retryMilliseconds() {
        let bytes = SSEEncoding.encode(
            SSEEvent(name: "x", id: nil, retry: .microseconds(1_999_999), data: [])
        )
        let out = String(decoding: bytes, as: UTF8.self)
        #expect(out.contains("retry: 1999\n"))
    }

    @Test("Zero data lines still emits the terminating blank line")
    func noDataLines() {
        let bytes = SSEEncoding.encode(
            SSEEvent(name: "x", id: nil, retry: nil, data: [])
        )
        let out = String(decoding: bytes, as: UTF8.self)
        #expect(out == "event: x\n\n")
    }
}
