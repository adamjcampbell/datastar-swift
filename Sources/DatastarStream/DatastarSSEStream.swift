import AsyncAlgorithms
import Datastar

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
///    let stream = DatastarSSEStream { emit in
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
///    let stream = DatastarSSEStream(
///        domainEvents.map { DatastarEvent.PatchElements(render($0)) }
///    )
///    ```
public struct DatastarSSEStream: AsyncSequence, Sendable {
    public typealias Element = ArraySlice<UInt8>
    public typealias Failure = any Error
    public typealias AsyncIterator =
        AsyncThrowingChannel<ArraySlice<UInt8>, any Error>.AsyncIterator

    private let channel: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>
    private let _taskLifetime: TaskHolder

    /// Designated init — straight-line producer closure with full backpressure.
    public init(_ produce: @Sendable @escaping (Emitter) async throws -> Void) {
        let channel = AsyncThrowingChannel<ArraySlice<UInt8>, any Error>()
        self.channel = channel
        let task = Task {
            do {
                try await produce(Emitter(channel: channel))
                channel.finish()
            } catch is CancellationError {
                channel.finish()
            } catch {
                channel.fail(error)
            }
        }
        self._taskLifetime = TaskHolder(task)
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
        channel.makeAsyncIterator()
    }

    /// Handed to the closure passed into `DatastarSSEStream { emit in ... }`.
    /// Accepts either the enum-case shorthand (`.patchElements(...)`) via the
    /// concrete overload, or any bare payload struct
    /// (`DatastarEvent.PatchElements(...)`) via the generic overload.
    public struct Emitter: Sendable {
        let channel: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>

        public func callAsFunction(_ event: DatastarEvent) async throws {
            await channel.send(SSEEncoding.encode(event.toWireEvent())[...])
            try Task.checkCancellation()
        }

        public func callAsFunction<E: DatastarEventConvertible>(_ event: E) async throws {
            try await self(event.toDatastarEvent())
        }
    }
}

/// Private reference-counted anchor. When the last `DatastarSSEStream` holding
/// this is dropped, `deinit` fires and cancels the producer Task — preventing
/// the task from staying parked on `channel.send` forever.
private final class TaskHolder: Sendable {
    let task: Task<Void, Never>
    init(_ task: Task<Void, Never>) { self.task = task }
    deinit { task.cancel() }
}
