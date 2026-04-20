import AsyncAlgorithms

/// Namespace for the SDK's primary entry point.
///
/// This is a zero-storage enum — it exists only to hold `stream(_:)` (the
/// closure-based builder) under a name that matches the ADR-mandated type
/// name across Datastar SDKs.
public enum ServerSentEventGenerator {
    /// Build a `DatastarSSEBody` from a straight-line producer closure.
    ///
    /// Inside the closure, `try await emit(.patchElements(...))` (and
    /// siblings) suspend until the HTTP consumer pulls the previous chunk,
    /// giving automatic backpressure. If the consumer disconnects, the
    /// producer Task is cancelled and the next `emit` call or other
    /// throwing await surfaces `CancellationError`; the closure exits
    /// and the stream terminates cleanly.
    ///
    /// For cases where events come from an existing `AsyncSequence` (domain
    /// events, file watchers, upstream APIs), use `DatastarSSEBody.init(_:)`
    /// directly instead.
    public static func stream(
        _ produce: @Sendable @escaping (Emitter) async throws -> Void
    ) -> DatastarSSEBody {
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
        return DatastarSSEBody(
            source: AnyDatastarEventSource(channel),
            producer: producer
        )
    }

    /// Handed to the closure passed into `stream(_:)`. Call it with each
    /// `DatastarEvent` to emit; it suspends until the consumer pulls.
    public struct Emitter: Sendable {
        let channel: AsyncThrowingChannel<DatastarEvent, any Error>

        public func callAsFunction(_ event: DatastarEvent) async throws {
            await channel.send(event)
            try Task.checkCancellation()
        }
    }
}
