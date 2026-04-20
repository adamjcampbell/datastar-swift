/// An `AsyncSequence` of SSE chunks produced by `ServerSentEventGenerator.stream(_:)`.
///
/// Hand this to your HTTP framework's streaming response body. Backpressure
/// flows naturally from the framework's pull cadence back to the producer
/// closure: each `try await sse.patchElements(...)` call in the closure waits
/// until the body consumer has taken the previous chunk.
public struct DatastarSSEBody: AsyncSequence, Sendable {
    public typealias Element = ArraySlice<UInt8>
    public typealias Failure = any Error

    let channel: PullChannel<ArraySlice<UInt8>>

    public func makeAsyncIterator() -> Iterator { Iterator(channel: channel) }

    public struct Iterator: AsyncIteratorProtocol {
        let channel: PullChannel<ArraySlice<UInt8>>

        public mutating func next() async throws -> ArraySlice<UInt8>? {
            try await channel.receive()
        }
    }
}
