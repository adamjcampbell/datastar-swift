/// ADR-named active SSE generator, generic over its transport writer.
///
/// The generator owns a `Writer` by value and mutates it through the
/// `mutating` methods. Each method encodes a Datastar event as SSE bytes and
/// hands them to the stored `sink`, which knows how to push them into that
/// writer. Specific adapters provide convenience inits that bind the generic
/// to a concrete writer type and supply the matching sink — for example,
/// `DatastarHummingbird` specializes `Writer == any ResponseBodyWriter`.
///
/// Move-only (`~Copyable`): uniquely owns its writer, so it cannot be
/// duplicated into multiple live instances emitting concurrently. Pass as
/// `inout` to helpers (the Hummingbird adapter threads it through `inout`
/// into the response-body closure) or use `consuming` to hand off ownership.
public struct ServerSentEventGenerator<Writer>: ~Copyable {
    public var writer: Writer

    @usableFromInline
    let sink: @Sendable (inout Writer, ArraySlice<UInt8>) async throws -> Void

    @inlinable
    public init(
        _ writer: consuming Writer,
        sink: @escaping @Sendable (inout Writer, ArraySlice<UInt8>) async throws -> Void
    ) {
        self.writer = writer
        self.sink = sink
    }

    // MARK: - ADR operations

    public mutating func patchElements(
        _ elements: String = "",
        options: DatastarEvent.PatchElements.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.PatchElements(elements, options: options))
    }

    public mutating func patchSignals(
        _ signals: String,
        options: DatastarEvent.PatchSignals.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.PatchSignals(signals, options: options))
    }

    public mutating func executeScript(
        _ script: String,
        options: DatastarEvent.ExecuteScript.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.ExecuteScript(script, options: options))
    }

    // MARK: - Pre-built event emission

    /// Emit any `DatastarEventConvertible` — lets callers use the flat-kwargs
    /// factories (`.patchElements("x", selector: "y")`), payload struct literals,
    /// or events pulled from an upstream `AsyncSequence`.
    public mutating func emit<E: DatastarEventConvertible>(_ event: E) async throws {
        let bytes = event.toDatastarEvent().toServerSentEvent().encoded()
        try await sink(&writer, ArraySlice(bytes))
    }
}

extension ServerSentEventGenerator: Sendable where Writer: Sendable {}
