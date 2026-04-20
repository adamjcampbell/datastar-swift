import Foundation
import Testing
@testable import Datastar

@Suite("ServerSentEventGenerator.stream")
struct StreamAPITests {
    // MARK: Happy path

    @Test("Emits the expected sequence of frames and finishes cleanly")
    func happyPath() async throws {
        let body = ServerSentEventGenerator.stream { emit in
            try await emit(.patchElements("<p>one</p>"))
            try await emit(.patchElements("<p>two</p>"))
        }
        let output = try await collect(body)
        #expect(output == """
        event: datastar-patch-elements
        data: elements <p>one</p>

        event: datastar-patch-elements
        data: elements <p>two</p>


        """)
    }

    // MARK: Build from an arbitrary AsyncSequence<DatastarEvent>

    @Test("DatastarSSEBody(_:) accepts any async sequence of DatastarEvents")
    func fromAsyncSequence() async throws {
        let events = AsyncStream<DatastarEvent> { cont in
            cont.yield(.patchElements("<p>a</p>"))
            cont.yield(.patchElements("<p>b</p>"))
            cont.finish()
        }
        let body = DatastarSSEBody(events)
        let output = try await collect(body)
        #expect(output.contains("data: elements <p>a</p>"))
        #expect(output.contains("data: elements <p>b</p>"))
    }

    // MARK: Backpressure

    @Test("Producer waits for the consumer (rendezvous semantics)")
    func backpressure() async throws {
        let body = ServerSentEventGenerator.stream { emit in
            for i in 1...3 {
                try await emit(.patchElements("<p>\(i)</p>"))
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
        #expect(elapsed >= .milliseconds(180),
                "consumer pacing should dictate total time (elapsed \(elapsed))")
    }

    // MARK: Cancellation

    @Test("Consumer dropping the iterator cancels the producer closure and releases it")
    func consumerDropCancelsProducer() async throws {
        let producerExited = EmissionCounter()

        let body = ServerSentEventGenerator.stream { emit in
            defer { Task { await producerExited.bump() } }
            while true {
                try await emit(.patchElements("<p>tick</p>"))
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        var count = 0
        for try await _ in body {
            count += 1
            if count == 3 { break }
        }

        var exitedCount = 0
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(10))
            exitedCount = await producerExited.count
            if exitedCount > 0 { break }
        }
        #expect(exitedCount == 1,
                "producer closure must exit after the consumer drops the iterator (did not exit within 500ms)")
    }

    @Test("Consumer task cancellation unblocks a parked receive")
    func consumerTaskCancellationUnblocksReceive() async throws {
        let body = ServerSentEventGenerator.stream { _ in
            try await Task.sleep(for: .seconds(60))
        }

        let consumer = Task {
            for try await _ in body {}
        }

        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()

        let returned = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = try? await consumer.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return false
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return false
        }
        #expect(returned, "consumer task should return (not hang) after cancellation")
    }

    // MARK: Error propagation

    struct TestError: Error, Equatable {}

    @Test("Producer errors surface on the consumer's next()")
    func producerErrorPropagates() async throws {
        let body = ServerSentEventGenerator.stream { emit in
            try await emit(.patchElements("<p>before</p>"))
            throw TestError()
        }

        var iter = body.makeAsyncIterator()
        _ = try await iter.next()
        await #expect(throws: TestError.self) {
            _ = try await iter.next()
        }
    }
}

actor EmissionCounter {
    private(set) var count: Int = 0
    func bump() { count += 1 }
}
