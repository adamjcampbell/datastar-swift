import Foundation

/// Emits Datastar v1 Server-Sent Events.
///
/// Construct a generator in your HTTP handler, hand `body` to your framework's
/// streaming response (with `Content-Type: text/event-stream`), then call the
/// event methods. Call `finish()` when you're done so the HTTP response ends.
///
/// The generator is `Sendable` — methods can be called from any task. Each call
/// emits a single, atomic SSE frame, so events never interleave.
public final class ServerSentEventGenerator: Sendable {
    /// The byte stream to attach to an HTTP response body.
    public let body: AsyncStream<ArraySlice<UInt8>>

    private let continuation: AsyncStream<ArraySlice<UInt8>>.Continuation

    public init() {
        let (stream, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream(
            of: ArraySlice<UInt8>.self,
            bufferingPolicy: .unbounded
        )
        self.body = stream
        self.continuation = continuation
    }

    /// Register a handler that fires when the consumer drops the body stream
    /// (e.g. the HTTP client disconnects) so the producer can cancel its work.
    ///
    /// The handler is NOT called when `finish()` runs — that path is the
    /// producer signalling an orderly end-of-stream.
    ///
    /// Setting this twice replaces the previous handler.
    public func onCancel(_ handler: @escaping @Sendable () -> Void) {
        continuation.onTermination = { @Sendable termination in
            if case .cancelled = termination {
                handler()
            }
        }
    }

    // MARK: - Elements

    /// Patch HTML elements into the DOM on the client.
    ///
    /// - Parameters:
    ///   - html: The HTML to patch. Multi-line content is split per-line automatically.
    ///   - selector: Optional CSS selector. When nil, the client targets elements
    ///     whose `id` matches the markup.
    ///   - mode: Patch strategy. Defaults to `.outer` (morph).
    ///   - useViewTransition: When true, the client uses the View Transitions API.
    ///   - namespace: DOM namespace for element creation. Defaults to `.html`.
    ///   - eventID: Optional SSE `id:` value.
    ///   - retryDuration: Optional SSE `retry:` value in milliseconds.
    public func patchElements(
        _ html: String,
        selector: String? = nil,
        mode: ElementPatchMode = .default,
        useViewTransition: Bool = DatastarDefaults.elementsUseViewTransitions,
        namespace: Namespace = .default,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) throws {
        try send(
            SSEFrame.patchElements(
                html: html,
                selector: selector,
                mode: mode,
                useViewTransition: useViewTransition,
                namespace: namespace,
                eventID: eventID,
                retryDuration: retryDuration
            )
        )
    }

    /// Convenience: patch-elements with `mode = .remove` targeting a selector.
    public func removeElements(
        selector: String,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) throws {
        try patchElements(
            "",
            selector: selector,
            mode: .remove,
            eventID: eventID,
            retryDuration: retryDuration
        )
    }

    // MARK: - Signals

    /// Patch signals on the client by encoding the given value as JSON.
    public func patchSignals<Signals: Encodable>(
        _ signals: Signals,
        onlyIfMissing: Bool = DatastarDefaults.patchSignalsOnlyIfMissing,
        eventID: String? = nil,
        retryDuration: Duration? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let json = try SSEFrame.encodeSignals(signals, encoder: encoder)
        try patchSignalsJSON(
            json,
            onlyIfMissing: onlyIfMissing,
            eventID: eventID,
            retryDuration: retryDuration
        )
    }

    /// Patch signals using a pre-serialized JSON string.
    public func patchSignalsJSON(
        _ json: String,
        onlyIfMissing: Bool = DatastarDefaults.patchSignalsOnlyIfMissing,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) throws {
        try send(
            SSEFrame.patchSignalsJSON(
                json: json,
                onlyIfMissing: onlyIfMissing,
                eventID: eventID,
                retryDuration: retryDuration
            )
        )
    }

    // MARK: - Lifecycle

    /// Close the body stream so the HTTP response ends. Idempotent.
    public func finish() {
        continuation.finish()
    }

    // MARK: - Pull API (v0.2 primary)

    /// Run a straight-line producer closure and get back an `AsyncSequence` of
    /// SSE bytes suitable for a streaming HTTP response body.
    ///
    /// Inside the closure, each `try await sse.patchElements(...)` /
    /// `sse.patchSignals(...)` call suspends until the body consumer reads the
    /// previous chunk, giving automatic backpressure. If the consumer
    /// disconnects, the next emit throws `CancellationError`, the closure
    /// exits, and the stream terminates cleanly.
    ///
    /// ```swift
    /// let body = ServerSentEventGenerator.stream { sse in
    ///     try await sse.patchElements(#"<div id="clock">12:00</div>"#, selector: "#clock", mode: .inner)
    ///     try await Task.sleep(for: .seconds(1))
    ///     try await sse.patchSignals(["count": 42])
    /// }
    /// // hand `body` to your framework's streaming response
    /// ```
    ///
    /// Use this for the common case. For handle-holder patterns (external
    /// observers, middleware, multi-producer), reach for the class-based
    /// API (`init()` + `sse.body`) instead.
    public static func stream(
        _ produce: @Sendable @escaping (SSEWriter) async throws -> Void
    ) -> DatastarSSEBody {
        let channel = PullChannel<ArraySlice<UInt8>>()
        let writer = SSEWriter(channel: channel)
        Task {
            do {
                try await produce(writer)
                await channel.finish(throwing: nil)
            } catch is CancellationError {
                await channel.finish(throwing: nil)
            } catch {
                await channel.finish(throwing: error)
            }
        }
        return DatastarSSEBody(channel: channel)
    }

    // MARK: - Internal

    private func send(_ event: SSEEvent) throws {
        let bytes = SSEEncoding.encode(event)
        let result = continuation.yield(bytes[...])
        switch result {
        case .enqueued:
            return
        case .dropped:
            assertionFailure("Datastar uses .unbounded buffering; .dropped should be unreachable")
        case .terminated:
            throw DatastarError.streamAlreadyFinished
        @unknown default:
            return
        }
    }
}
