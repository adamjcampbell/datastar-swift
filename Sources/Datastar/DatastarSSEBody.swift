import AsyncAlgorithms

/// An `AsyncSequence` of SSE chunks built from a source `AsyncSequence<DatastarEvent>`.
///
/// Hand this to your HTTP framework's streaming response body. Backpressure
/// (when the source supports it) flows naturally from the framework's pull
/// cadence back to the source.
///
/// When the consumer drops the iterator (e.g. client disconnects and the
/// framework tears down its body-reading task), the class-based `Iterator`'s
/// `deinit` cancels the producer Task — if one was created by
/// `ServerSentEventGenerator.stream(_:)` — so any straight-line producer
/// closure exits promptly.
public struct DatastarSSEBody: AsyncSequence, Sendable {
    public typealias Element = ArraySlice<UInt8>
    public typealias Failure = any Error

    let source: AnyDatastarEventSource
    let producer: Task<Void, Never>?

    /// Build from any `AsyncSequence<DatastarEvent>`.
    public init<Source: AsyncSequence & Sendable>(_ events: Source)
    where Source.Element == DatastarEvent {
        self.source = AnyDatastarEventSource(events)
        self.producer = nil
    }

    /// Internal initializer used by `ServerSentEventGenerator.stream(_:)` —
    /// wires the iterator's deinit to cancel the producer Task.
    init(source: AnyDatastarEventSource, producer: Task<Void, Never>) {
        self.source = source
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
}

// MARK: - Type erasure

/// Thin Sendable type-erasure wrapper so `DatastarSSEBody` can be a concrete
/// (non-generic) public type regardless of what the caller's source sequence is.
struct AnyDatastarEventSource: AsyncSequence, Sendable {
    typealias Element = DatastarEvent
    typealias Failure = any Error

    private let makeIterator_: @Sendable () -> AsyncIterator

    init<Source: AsyncSequence & Sendable>(_ source: Source)
    where Source.Element == DatastarEvent {
        self.makeIterator_ = { AsyncIterator(source.makeAsyncIterator()) }
    }

    func makeAsyncIterator() -> AsyncIterator { makeIterator_() }

    final class AsyncIterator: AsyncIteratorProtocol {
        private var next_: () async throws -> DatastarEvent?

        init<Iter: AsyncIteratorProtocol>(_ base: Iter) where Iter.Element == DatastarEvent {
            var copy = base
            self.next_ = { try await copy.next() }
        }

        func next() async throws -> DatastarEvent? {
            try await next_()
        }
    }
}
