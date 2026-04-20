import Foundation
import Testing
@testable import Datastar

@Suite("ServerSentEventGenerator.stream (pull API)")
struct StreamAPITests {
    // MARK: Helpers

    static func collect(_ body: DatastarSSEBody) async throws -> String {
        var bytes: [UInt8] = []
        for try await chunk in body {
            bytes.append(contentsOf: chunk)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Happy path

    @Test("Emits the expected SSE frames and finishes cleanly")
    func happyPath() async throws {
        let body = ServerSentEventGenerator.stream { sse in
            try await sse.patchElements("<p>one</p>")
            try await sse.patchElements("<p>two</p>")
        }
        let output = try await Self.collect(body)
        #expect(output == """
        event: datastar-patch-elements
        data: elements <p>one</p>

        event: datastar-patch-elements
        data: elements <p>two</p>


        """)
    }

    @Test("Wire-format parity with the class-based API")
    func wireFormatParity() async throws {
        // Drive both APIs with identical inputs and assert identical output.
        let body = ServerSentEventGenerator.stream { sse in
            try await sse.patchElements(
                "<div>\n  <p>hi</p>\n</div>",
                selector: "#target",
                mode: .inner,
                useViewTransition: true,
                namespace: .svg,
                eventID: "42",
                retryDuration: .milliseconds(2500)
            )
        }
        let pullOutput = try await Self.collect(body)

        let push = ServerSentEventGenerator()
        try push.patchElements(
            "<div>\n  <p>hi</p>\n</div>",
            selector: "#target",
            mode: .inner,
            useViewTransition: true,
            namespace: .svg,
            eventID: "42",
            retryDuration: .milliseconds(2500)
        )
        push.finish()
        var pushBytes: [UInt8] = []
        for await chunk in push.body {
            pushBytes.append(contentsOf: chunk)
        }
        let pushOutput = String(decoding: pushBytes, as: UTF8.self)

        #expect(pullOutput == pushOutput)
    }

    // MARK: Backpressure

    @Test("Producer waits for the consumer (rendezvous semantics)")
    func backpressure() async throws {
        let body = ServerSentEventGenerator.stream { sse in
            // Emit three events as fast as possible — each should park until
            // the consumer pulls.
            for i in 1...3 {
                try await sse.patchElements("<p>\(i)</p>")
            }
        }

        let start = ContinuousClock().now
        var iter = body.makeAsyncIterator()
        _ = try await iter.next()
        try await Task.sleep(for: .milliseconds(100))
        _ = try await iter.next()
        try await Task.sleep(for: .milliseconds(100))
        _ = try await iter.next()
        let elapsed = ContinuousClock().now - start
        #expect(elapsed >= .milliseconds(180), "consumer pacing should dictate total time")
    }

    // MARK: Cancellation

    @Test("Cancelling the consumer task cancels the producer closure")
    func consumerCancellation() async throws {
        // Record how many emissions completed before cancellation fires.
        let emissions = EmissionCounter()

        let body = ServerSentEventGenerator.stream { sse in
            while true {
                try await sse.patchElements("<p>tick</p>")
                await emissions.bump()
            }
        }

        let consumer = Task {
            var count = 0
            for try await _ in body {
                count += 1
                if count == 3 { return }
            }
        }
        _ = try await consumer.value
        // Give the producer a tick to observe cancellation and exit.
        try await Task.sleep(for: .milliseconds(20))
        let count = await emissions.count
        #expect(count < 100, "producer should stop shortly after the consumer exits, not run forever (observed \(count))")
    }

    // MARK: Error propagation

    struct TestError: Error, Equatable {}

    @Test("Producer errors surface on the consumer's next()")
    func producerErrorPropagates() async throws {
        let body = ServerSentEventGenerator.stream { sse in
            try await sse.patchElements("<p>before</p>")
            throw TestError()
        }

        var iter = body.makeAsyncIterator()
        _ = try await iter.next() // first frame
        await #expect(throws: TestError.self) {
            _ = try await iter.next()
        }
    }

    // MARK: Signals

    @Test("patchSignals encodes via JSONEncoder and emits a signals frame")
    func patchSignals() async throws {
        struct Example: Encodable { let count: Int }
        let body = ServerSentEventGenerator.stream { sse in
            try await sse.patchSignals(Example(count: 7))
        }
        let output = try await Self.collect(body)
        #expect(output == """
        event: datastar-patch-signals
        data: signals {"count":7}


        """)
    }

    @Test("removeElements emits a selector + mode=remove frame")
    func removeElementsConvenience() async throws {
        let body = ServerSentEventGenerator.stream { sse in
            try await sse.removeElements(selector: "#gone")
        }
        let output = try await Self.collect(body)
        #expect(output == """
        event: datastar-patch-elements
        data: selector #gone
        data: mode remove


        """)
    }
}

// Thread-safe counter for the cancellation test.
actor EmissionCounter {
    private(set) var count: Int = 0
    func bump() { count += 1 }
}
