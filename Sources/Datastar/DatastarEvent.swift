import Foundation

/// A single Datastar event, in value form.
///
/// Three cases matching the protocol's three user-facing event types. Users
/// typically construct these via the ergonomic static methods
/// (`.patchElements(...)`, `.patchSignals(...)`, `.executeScript(...)`) or
/// the nested payload structs (`DatastarEvent.PatchElements(...)`), and emit
/// them through a `ServerSentEventGenerator` — either the Hummingbird
/// specialization (`DatastarHummingbird`) or a custom framework adapter
/// built on the generic core.
public enum DatastarEvent: Sendable {
    case patchElements(PatchElements)
    case patchSignals(PatchSignals)
    case executeScript(ExecuteScript)
}

// MARK: - Nested payload structs

extension DatastarEvent {
    public struct PatchElements: Sendable {
        public struct Options: Sendable {
            public var selector: String?
            public var mode: ElementPatchMode
            public var useViewTransition: Bool
            public var namespace: Namespace
            public var eventID: String?
            public var retryDuration: Duration?

            public init(
                selector: String? = nil,
                mode: ElementPatchMode = .outer,
                useViewTransition: Bool = false,
                namespace: Namespace = .html,
                eventID: String? = nil,
                retryDuration: Duration? = nil
            ) {
                self.selector = selector
                self.mode = mode
                self.useViewTransition = useViewTransition
                self.namespace = namespace
                self.eventID = eventID
                self.retryDuration = retryDuration
            }
        }

        public var elements: String
        public var options: Options

        public init(_ elements: String = "", options: Options = .init()) {
            self.elements = elements
            self.options = options
        }
    }

    public struct PatchSignals: Sendable {
        public struct Options: Sendable {
            public var onlyIfMissing: Bool
            public var eventID: String?
            public var retryDuration: Duration?

            public init(
                onlyIfMissing: Bool = false,
                eventID: String? = nil,
                retryDuration: Duration? = nil
            ) {
                self.onlyIfMissing = onlyIfMissing
                self.eventID = eventID
                self.retryDuration = retryDuration
            }
        }

        public var signals: String
        public var options: Options

        public init(_ signals: String, options: Options = .init()) {
            self.signals = signals
            self.options = options
        }

        /// Serialize an `Encodable` value to a JSON signals frame.
        /// Prepositional label avoids type-inference ambiguity with `(_ signals: String)`.
        public init<Value: Encodable>(
            encoding value: Value,
            options: Options = .init(),
            encoder: JSONEncoder = JSONEncoder()
        ) throws {
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            self.init(json, options: options)
        }
    }

    /// Sugar over `PatchElements` that injects a `<script>` tag appended to `<body>`.
    /// By default the script removes itself after execution via `data-effect="el.remove()"`.
    public struct ExecuteScript: Sendable {
        public struct Options: Sendable {
            public var autoRemove: Bool
            public var attributes: [String]
            public var eventID: String?
            public var retryDuration: Duration?

            public init(
                autoRemove: Bool = true,
                attributes: [String] = [],
                eventID: String? = nil,
                retryDuration: Duration? = nil
            ) {
                self.autoRemove = autoRemove
                self.attributes = attributes
                self.eventID = eventID
                self.retryDuration = retryDuration
            }
        }

        public var script: String
        public var options: Options

        public init(_ script: String, options: Options = .init()) {
            self.script = script
            self.options = options
        }
    }
}

// MARK: - Ergonomic static constructors (flat-kwargs sugar)

extension DatastarEvent {
    /// Patch HTML elements into the DOM on the client.
    public static func patchElements(
        _ elements: String = "",
        selector: String? = nil,
        mode: ElementPatchMode = .outer,
        useViewTransition: Bool = false,
        namespace: Namespace = .html,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .patchElements(PatchElements(
            elements,
            options: .init(
                selector: selector,
                mode: mode,
                useViewTransition: useViewTransition,
                namespace: namespace,
                eventID: eventID,
                retryDuration: retryDuration
            )
        ))
    }

    /// Patch signals by encoding an `Encodable` value as JSON.
    public static func patchSignals<Value: Encodable>(
        encoding value: Value,
        onlyIfMissing: Bool = false,
        eventID: String? = nil,
        retryDuration: Duration? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> DatastarEvent {
        .patchSignals(try PatchSignals(
            encoding: value,
            options: .init(
                onlyIfMissing: onlyIfMissing,
                eventID: eventID,
                retryDuration: retryDuration
            ),
            encoder: encoder
        ))
    }

    /// Patch signals using a pre-serialized JSON string.
    public static func patchSignalsJSON(
        _ signals: String,
        onlyIfMissing: Bool = false,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .patchSignals(PatchSignals(
            signals,
            options: .init(
                onlyIfMissing: onlyIfMissing,
                eventID: eventID,
                retryDuration: retryDuration
            )
        ))
    }

    /// Execute JavaScript in the browser. Sugar over a `patchElements` frame
    /// that appends a `<script>` element to `<body>`.
    public static func executeScript(
        _ script: String,
        autoRemove: Bool = true,
        attributes: [String] = [],
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .executeScript(ExecuteScript(
            script,
            options: .init(
                autoRemove: autoRemove,
                attributes: attributes,
                eventID: eventID,
                retryDuration: retryDuration
            )
        ))
    }
}

// MARK: - DatastarEventConvertible

/// A type that can be converted to a `DatastarEvent`.
///
/// Lets `ServerSentEventGenerator.emit(_:)` accept both the enum-case
/// shorthand (`.patchElements(...)`) and bare payload structs
/// (`DatastarEvent.PatchElements(...)`) uniformly, so events pulled from
/// an upstream `AsyncSequence` or built via the flat-kwargs factories
/// plug in without conversion.
public protocol DatastarEventConvertible: Sendable {
    func toDatastarEvent() -> DatastarEvent
}

extension DatastarEvent: DatastarEventConvertible {
    public func toDatastarEvent() -> DatastarEvent { self }
}

extension DatastarEvent.PatchElements: DatastarEventConvertible {
    public func toDatastarEvent() -> DatastarEvent { .patchElements(self) }
}

extension DatastarEvent.PatchSignals: DatastarEventConvertible {
    public func toDatastarEvent() -> DatastarEvent { .patchSignals(self) }
}

extension DatastarEvent.ExecuteScript: DatastarEventConvertible {
    public func toDatastarEvent() -> DatastarEvent { .executeScript(self) }
}

// MARK: - Wire-format conversion

extension DatastarEvent {
    /// Build the wire-format SSE frame. Internal plumbing used by
    /// `ServerSentEventGenerator` to produce on-wire bytes.
    func toServerSentEvent() -> ServerSentEvent {
        switch self {
        case .patchElements(let p): return p.toServerSentEvent()
        case .patchSignals(let p):  return p.toServerSentEvent()
        case .executeScript(let e): return e.toServerSentEvent()
        }
    }
}

extension DatastarEvent.PatchElements {
    func toServerSentEvent() -> ServerSentEvent {
        var data: [String] = []
        if let selector = options.selector, !selector.isEmpty {
            data.append(DatalineLiteral.selector + selector)
        }
        if options.mode != .default {
            data.append(DatalineLiteral.mode + options.mode.rawValue)
        }
        if options.namespace != .default {
            data.append(DatalineLiteral.namespace + options.namespace.rawValue)
        }
        if options.useViewTransition != DatastarDefaults.elementsUseViewTransitions {
            data.append(DatalineLiteral.useViewTransition + String(options.useViewTransition))
        }
        if !elements.isEmpty {
            for line in elements.split(separator: "\n", omittingEmptySubsequences: false) {
                data.append(DatalineLiteral.elements + String(line))
            }
        }
        return ServerSentEvent(
            name: DatastarEventType.patchElements.rawValue,
            id: options.eventID,
            retry: options.retryDuration?.omittingSSERetryDefault,
            data: data
        )
    }
}

extension DatastarEvent.PatchSignals {
    func toServerSentEvent() -> ServerSentEvent {
        var data: [String] = []
        if options.onlyIfMissing != DatastarDefaults.patchSignalsOnlyIfMissing {
            data.append(DatalineLiteral.onlyIfMissing + String(options.onlyIfMissing))
        }
        for line in signals.split(separator: "\n", omittingEmptySubsequences: false) {
            data.append(DatalineLiteral.signals + String(line))
        }
        return ServerSentEvent(
            name: DatastarEventType.patchSignals.rawValue,
            id: options.eventID,
            retry: options.retryDuration?.omittingSSERetryDefault,
            data: data
        )
    }
}

extension DatastarEvent.ExecuteScript {
    func toServerSentEvent() -> ServerSentEvent {
        // Render a <script> element and emit it as a patch-elements frame
        // with selector=body, mode=append — the ADR rendering of
        // ExecuteScript. `data-effect="el.remove()"` is auto-injected when
        // `autoRemove` is true and the caller hasn't supplied their own
        // `data-effect`. User-supplied attributes appear in the given order;
        // the ADR mandates that the attributes be added to the tag but does
        // not constrain their sequence.
        var tag = "<script"
        if options.autoRemove
            && !options.attributes.contains(where: { $0.hasPrefix("data-effect=") })
        {
            tag += " data-effect=\"el.remove()\""
        }
        for attr in options.attributes {
            tag += " " + attr
        }
        tag += ">\(script)</script>"

        let patch = DatastarEvent.PatchElements(
            tag,
            options: .init(
                selector: "body",
                mode: .append,
                eventID: options.eventID,
                retryDuration: options.retryDuration
            )
        )
        return patch.toServerSentEvent()
    }
}

// MARK: - Retry-default omission

extension Duration {
    /// Returns `nil` when this duration equals the SSE retry default (1000 ms),
    /// matching the ADR wire-format rule "omit `retry:` when equal to the default".
    fileprivate var omittingSSERetryDefault: Duration? {
        self == DatastarDefaults.sseRetryDuration ? nil : self
    }
}
