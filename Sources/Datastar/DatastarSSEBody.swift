import AsyncAlgorithms

/// An `AsyncSequence` of SSE chunks — the HTTP response body for a Datastar
/// stream. Hand this to your framework's streaming response body.
///
/// Build it in either of two ways:
///
/// 1. **Trailing-closure init** for straight-line producers. Backpressure
///    flows automatically: each `try await emit(...)` call suspends until
///    the body consumer pulls the previous chunk. Consumer-drop cancels
///    the producer Task cleanly.
///
///    ```swift
///    let body = DatastarSSEBody { emit in
///        try await emit(.patchElements("<p>hi</p>"))
///        try await Task.sleep(for: .seconds(1))
///        try await emit(.executeScript("boot()"))
///    }
///    ```
///
/// 2. **From any `AsyncSequence`** of `DatastarEventConvertible`. Useful when
///    events originate from a domain stream, pub/sub subscription, file
///    watcher, or upstream API.
///
///    ```swift
///    let body = DatastarSSEBody(
///        domainEvents.map { DatastarEvent.PatchElements(render($0)) }
///    )
///    ```
public struct DatastarSSEBody: AsyncSequence, Sendable {
    public typealias Element = ArraySlice<UInt8>
    public typealias Failure = any Error

    private let channel: AsyncThrowingChannel<DatastarEvent, any Error>
    private let producer: Task<Void, Never>

    /// Designated init — straight-line producer closure with full backpressure.
    public init(_ produce: @Sendable @escaping (Emitter) async throws -> Void) {
        let channel = AsyncThrowingChannel<DatastarEvent, any Error>()
        self.channel = channel
        self.producer = Task {
            do {
                try await produce(Emitter(channel: channel))
                channel.finish()
            } catch is CancellationError {
                channel.finish()
            } catch {
                channel.fail(error)
            }
        }
    }

    /// Convenience init — adapts any `AsyncSequence` of convertibles by
    /// delegating to the designated init with a draining closure.
    public init<Source: AsyncSequence & Sendable>(_ events: Source)
    where Source.Element: DatastarEventConvertible {
        self.init { emit in
            for try await event in events {
                try await emit(event)
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iter: channel.makeAsyncIterator(), producer: producer)
    }

    public final class AsyncIterator: AsyncIteratorProtocol {
        var iter: AsyncThrowingChannel<DatastarEvent, any Error>.AsyncIterator
        let producer: Task<Void, Never>

        init(
            iter: AsyncThrowingChannel<DatastarEvent, any Error>.AsyncIterator,
            producer: Task<Void, Never>
        ) {
            self.iter = iter
            self.producer = producer
        }

        public func next() async throws -> ArraySlice<UInt8>? {
            try await iter.next().map { SSEEncoding.encode($0.toWireEvent())[...] }
        }

        deinit { producer.cancel() }
    }

    /// Handed to the closure passed into `DatastarSSEBody { emit in ... }`.
    /// Accepts the enum-case shorthand (`.patchElements(...)`) via the
    /// concrete overload, or any bare payload struct
    /// (`DatastarEvent.PatchElements(...)`) via the generic overload.
    public struct Emitter: Sendable {
        let channel: AsyncThrowingChannel<DatastarEvent, any Error>

        public func callAsFunction(_ event: DatastarEvent) async throws {
            await channel.send(event)
            try Task.checkCancellation()
        }

        public func callAsFunction<E: DatastarEventConvertible>(_ event: E) async throws {
            try await self(event.toDatastarEvent())
        }
    }
}
