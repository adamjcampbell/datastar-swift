/// An SSE event generator, generic over its transport writer.
///
/// The generator owns a `Writer` by value and mutates it through its
/// `mutating` methods. Each event method encodes its payload to the SSE
/// wire format and hands the bytes to the stored `sink`, which knows how
/// to push them through that specific writer type. Framework adapters
/// supply convenience initializers that bind a concrete writer and its
/// matching sink — for example, `DatastarHummingbird` specializes
/// `Writer == any ResponseBodyWriter`.
///
/// Move-only (`~Copyable`): the generator uniquely owns its writer and
/// cannot be duplicated. Pass it as `inout` to helpers, or use
/// `consuming` to hand off ownership.
public struct ServerSentEventGenerator<Writer>: ~Copyable {
    /// The transport writer this generator emits bytes through.
    public var writer: Writer

    @usableFromInline
    let sink: @Sendable (inout Writer, ArraySlice<UInt8>) async throws -> Void

    /// Create a generator that forwards encoded SSE bytes to `sink`.
    ///
    /// - Parameters:
    ///   - writer: The transport target to emit events through.
    ///   - sink: A closure that pushes an encoded SSE chunk into `writer`.
    ///     Invoked once per emitted event.
    @inlinable
    public init(
        _ writer: consuming Writer,
        sink: @escaping @Sendable (inout Writer, ArraySlice<UInt8>) async throws -> Void
    ) {
        self.writer = writer
        self.sink = sink
    }

    // MARK: - Event emission

    /// Patch HTML elements into the DOM on the client.
    ///
    /// - Parameters:
    ///   - elements: HTML to patch. Defaults to `""` for pairing with
    ///     `mode: .remove`, which deletes the targeted element without
    ///     providing replacement markup.
    ///   - options: Targeting and delivery options (selector, mode,
    ///     namespace, view transition, event id, retry duration).
    public mutating func patchElements(
        _ elements: String = "",
        options: DatastarEvent.PatchElements.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.PatchElements(elements, options: options))
    }

    /// Patch client-side signals with a JSON Merge Patch (RFC 7386) document.
    ///
    /// - Parameters:
    ///   - signals: A JSON object describing the patch. Use `null` values
    ///     to remove keys.
    ///   - options: Delivery options (`onlyIfMissing`, event id, retry
    ///     duration).
    public mutating func patchSignals(
        _ signals: String,
        options: DatastarEvent.PatchSignals.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.PatchSignals(signals, options: options))
    }

    /// Execute a JavaScript snippet in the browser.
    ///
    /// Delivered as a `<script>` element appended to `<body>`. By default
    /// the element self-removes after execution via
    /// `data-effect="el.remove()"`.
    ///
    /// - Parameters:
    ///   - script: JavaScript source to run.
    ///   - options: Script-tag options (`autoRemove`, `attributes`, event
    ///     id, retry duration).
    public mutating func executeScript(
        _ script: String,
        options: DatastarEvent.ExecuteScript.Options = .init()
    ) async throws {
        try await emit(DatastarEvent.ExecuteScript(script, options: options))
    }

    // MARK: - Generic emission

    /// Emit a pre-built event.
    ///
    /// Useful for events pulled from an `AsyncSequence` or constructed
    /// via the flat-keyword-argument factories on `DatastarEvent`
    /// (for example `.patchElements("<p/>", selector: "#x")`).
    ///
    /// - Parameter event: Any value convertible to a `DatastarEvent`.
    public mutating func emit<E: DatastarEventConvertible>(_ event: E) async throws {
        let bytes = event.toDatastarEvent().toServerSentEvent().encoded()
        try await sink(&writer, ArraySlice(bytes))
    }
}

extension ServerSentEventGenerator: Sendable where Writer: Sendable {}
