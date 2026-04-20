import AsyncAlgorithms
import Foundation

/// The writer handed to the closure of `ServerSentEventGenerator.stream(_:)`.
///
/// Each emit method is `async throws` and suspends until the HTTP consumer
/// reads the previous chunk — so the producer naturally paces itself to the
/// client's read rate. If the consumer disconnects, the class iterator inside
/// `DatastarSSEBody` cancels the producer Task; the next `Task.sleep`-like
/// await point in the producer closure throws `CancellationError` and the
/// closure exits.
public struct SSEWriter: Sendable {
    let channel: AsyncThrowingChannel<ArraySlice<UInt8>, any Error>

    /// Patch HTML elements into the DOM on the client. See `ServerSentEventGenerator.patchElements`
    /// on the class-based API for parameter semantics — the two entry points emit byte-identical frames.
    public func patchElements(
        _ html: String,
        selector: String? = nil,
        mode: ElementPatchMode = .default,
        useViewTransition: Bool = DatastarDefaults.elementsUseViewTransitions,
        namespace: Namespace = .default,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) async throws {
        try await emit(
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
    ) async throws {
        try await patchElements(
            "",
            selector: selector,
            mode: .remove,
            eventID: eventID,
            retryDuration: retryDuration
        )
    }

    /// Patch signals by encoding the given value as JSON.
    public func patchSignals<Signals: Encodable>(
        _ signals: Signals,
        onlyIfMissing: Bool = DatastarDefaults.patchSignalsOnlyIfMissing,
        eventID: String? = nil,
        retryDuration: Duration? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        let json = try SSEFrame.encodeSignals(signals, encoder: encoder)
        try await patchSignalsJSON(
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
    ) async throws {
        try await emit(
            SSEFrame.patchSignalsJSON(
                json: json,
                onlyIfMissing: onlyIfMissing,
                eventID: eventID,
                retryDuration: retryDuration
            )
        )
    }

    private func emit(_ event: SSEEvent) async throws {
        // AsyncThrowingChannel.send is `async` (non-throwing) and silently
        // returns if the sending task is cancelled — the user's producer
        // closure will observe cancellation at its next throwing await
        // (typically Task.sleep).
        await channel.send(SSEEncoding.encode(event)[...])
    }
}
