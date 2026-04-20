import AsyncAlgorithms

/// An `AsyncSequence` of SSE chunks produced by `ServerSentEventGenerator.stream(_:)`.
///
/// Hand this to your HTTP framework's streaming response body. Backpressure
/// flows naturally from the framework's pull cadence back to the producer
/// closure: each `try await sse.patchElements(...)` call in the closure waits
/// until the body consumer has taken the previous chunk.
///
/// When the consumer drops the iterator (e.g. the client disconnects and the
/// framework tears down its body-reading task), the class-based `Iterator`'s
/// `deinit` cancels the producer Task so the closure can exit promptly and
/// nothing leaks.
public struct DatastarSSEBody: AsyncSequence, Sendable {
    public typealias Element = ArraySlice<UInt8>
    public typealias Failure = any Error

    let channel: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>
    let producer: Task<Void, Never>

    public func makeAsyncIterator() -> Iterator {
        Iterator(channel: channel, producer: producer)
    }

    public final class Iterator: AsyncIteratorProtocol {
        var base: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>.AsyncIterator
        let producer: Task<Void, Never>

        fileprivate init(
            channel: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>,
            producer: Task<Void, Never>
        ) {
            self.base = channel.makeAsyncIterator()
            self.producer = producer
        }

        public func next() async throws -> ArraySlice<UInt8>? {
            try await base.next()
        }

        deinit {
            producer.cancel()
        }
    }
}
