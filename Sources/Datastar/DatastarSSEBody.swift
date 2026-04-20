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

    let source: AnyDatastarEventSource
    let producer: Task<Void, Never>?

    /// Build from any `AsyncSequence` of values convertible to `DatastarEvent`.
    public init<Source: AsyncSequence & Sendable>(_ events: Source)
    where Source.Element: DatastarEventConvertible {
        self.source = AnyDatastarEventSource(events)
        self.producer = nil
    }

    /// Build from a straight-line producer closure. Each `try await emit(...)`
    /// suspends until the consumer pulls the previous chunk, so the producer
    /// paces itself to the client automatically.
    public init(_ produce: @Sendable @escaping (Emitter) async throws -> Void) {
        let channel = AsyncThrowingChannel<DatastarEvent, any Error>()
        let emitter = Emitter(channel: channel)
        let producer = Task {
            do {
                try await produce(emitter)
                channel.finish()
            } catch is CancellationError {
                channel.finish()
            } catch {
                channel.fail(error)
            }
        }
        self.source = AnyDatastarEventSource(channel)
        self.producer = producer
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(source: source.makeAsyncIterator(), producer: producer)
    }

    public final class Iterator: AsyncIteratorProtocol {
        var base: AnyDatastarEventSource.AsyncIterator
        let producer: Task<Void, Never>?

        init(source: AnyDatastarEventSource.AsyncIterator, producer: Task<Void, Never>?) {
            self.base = source
            self.producer = producer
        }

        public func next() async throws -> ArraySlice<UInt8>? {
            guard let event = try await base.next() else { return nil }
            return SSEEncoding.encode(event.toWireEvent())[...]
        }

        deinit {
            producer?.cancel()
        }
    }

    /// Handed to the closure passed into `DatastarSSEBody { emit in ... }`.
    /// Call with any `DatastarEventConvertible` — the enum case shorthand
    /// (`.patchElements(...)`), the bare nested struct
    /// (`DatastarEvent.PatchElements(...)`), or a `DatastarEvent` value.
    public struct Emitter: Sendable {
        let channel: AsyncThrowingChannel<DatastarEvent, any Error>

        /// Primary overload — lets `.patchElements(...)` / `.patchSignals(...)` /
        /// `.executeScript(...)` dot-syntax resolve against `DatastarEvent`.
        public func callAsFunction(_ event: DatastarEvent) async throws {
            await channel.send(event)
            try Task.checkCancellation()
        }

        /// Convenience overload — accepts bare payload structs
        /// (`DatastarEvent.PatchElements(...)` etc.) without a wrap.
        public func callAsFunction<E: DatastarEventConvertible>(_ event: E) async throws {
            await channel.send(event.toDatastarEvent())
            try Task.checkCancellation()
        }
    }
}

// MARK: - Type erasure

/// Thin `Sendable` type-erasure wrapper so `DatastarSSEBody` can be a concrete
/// (non-generic) public type regardless of what the caller's source sequence is.
struct AnyDatastarEventSource: AsyncSequence, Sendable {
    typealias Element = DatastarEvent
    typealias Failure = any Error

    private let makeIterator_: @Sendable () -> AsyncIterator

    init<Source: AsyncSequence & Sendable>(_ source: Source)
    where Source.Element: DatastarEventConvertible {
        self.makeIterator_ = { AsyncIterator(source.makeAsyncIterator()) }
    }

    func makeAsyncIterator() -> AsyncIterator { makeIterator_() }

    final class AsyncIterator: AsyncIteratorProtocol {
        private var next_: () async throws -> DatastarEvent?

        init<Iter: AsyncIteratorProtocol>(_ base: Iter)
        where Iter.Element: DatastarEventConvertible {
            var copy = base
            self.next_ = { try await copy.next()?.toDatastarEvent() }
        }

        func next() async throws -> DatastarEvent? {
            try await next_()
        }
    }
}
