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
        var data: [String] = []
        if let selector, !selector.isEmpty {
            data.append(DatalineLiteral.selector + selector)
        }
        if mode != .default {
            data.append(DatalineLiteral.mode + mode.rawValue)
        }
        if namespace != .default {
            data.append(DatalineLiteral.namespace + namespace.rawValue)
        }
        if useViewTransition != DatastarDefaults.elementsUseViewTransitions {
            data.append(DatalineLiteral.useViewTransition + String(useViewTransition))
        }
        if !html.isEmpty {
            for line in html.split(separator: "\n", omittingEmptySubsequences: false) {
                data.append(DatalineLiteral.elements + String(line))
            }
        }

        try send(
            SSEEvent(
                name: DatastarEventType.patchElements.rawValue,
                id: eventID,
                retry: retryDuration,
                data: data
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
        let data: Data
        do {
            data = try encoder.encode(signals)
        } catch {
            throw DatastarError.encodingFailed(underlying: error)
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatastarError.encodingFailed(
                underlying: CocoaError(.fileReadInapplicableStringEncoding)
            )
        }
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
        var data: [String] = []
        if onlyIfMissing != DatastarDefaults.patchSignalsOnlyIfMissing {
            data.append(DatalineLiteral.onlyIfMissing + String(onlyIfMissing))
        }
        for line in json.split(separator: "\n", omittingEmptySubsequences: false) {
            data.append(DatalineLiteral.signals + String(line))
        }

        try send(
            SSEEvent(
                name: DatastarEventType.patchSignals.rawValue,
                id: eventID,
                retry: retryDuration,
                data: data
            )
        )
    }

    // MARK: - Lifecycle

    /// Close the body stream so the HTTP response ends. Idempotent.
    public func finish() {
        continuation.finish()
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
