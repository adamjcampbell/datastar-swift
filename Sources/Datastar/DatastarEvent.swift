import Foundation

/// A single Datastar event, in value form.
///
/// Three cases matching the protocol's three user-facing event types. Users
/// typically construct these via the ergonomic static methods
/// (`.patchElements(...)`, `.patchSignals(...)`, `.executeScript(...)`) and
/// emit them through either `ServerSentEventGenerator.stream { ... }` or
/// any `AsyncSequence<DatastarEvent>` passed to `DatastarSSEBody.init`.
public enum DatastarEvent: Sendable {
    case patchElements(PatchElements)
    case patchSignals(PatchSignals)
    case executeScript(ExecuteScript)
}

// MARK: - Nested struct payloads

extension DatastarEvent {
    public struct PatchElements: Sendable {
        public var html: String
        public var selector: String?
        public var mode: ElementPatchMode
        public var useViewTransition: Bool
        public var namespace: Namespace
        public var eventID: String?
        public var retryDuration: Duration?

        public init(
            html: String,
            selector: String? = nil,
            mode: ElementPatchMode = .outer,
            useViewTransition: Bool = false,
            namespace: Namespace = .html,
            eventID: String? = nil,
            retryDuration: Duration? = nil
        ) {
            self.html = html
            self.selector = selector
            self.mode = mode
            self.useViewTransition = useViewTransition
            self.namespace = namespace
            self.eventID = eventID
            self.retryDuration = retryDuration
        }
    }

    public struct PatchSignals: Sendable {
        public var json: String
        public var onlyIfMissing: Bool
        public var eventID: String?
        public var retryDuration: Duration?

        public init(
            json: String,
            onlyIfMissing: Bool = false,
            eventID: String? = nil,
            retryDuration: Duration? = nil
        ) {
            self.json = json
            self.onlyIfMissing = onlyIfMissing
            self.eventID = eventID
            self.retryDuration = retryDuration
        }
    }

    /// Sugar over `PatchElements` that injects a `<script>` tag appended to `<body>`.
    /// By default the script removes itself after execution via `data-effect="el.remove()"`.
    public struct ExecuteScript: Sendable {
        public var script: String
        public var autoRemove: Bool
        public var attributes: [String: String]
        public var eventID: String?
        public var retryDuration: Duration?

        public init(
            script: String,
            autoRemove: Bool = true,
            attributes: [String: String] = [:],
            eventID: String? = nil,
            retryDuration: Duration? = nil
        ) {
            self.script = script
            self.autoRemove = autoRemove
            self.attributes = attributes
            self.eventID = eventID
            self.retryDuration = retryDuration
        }
    }
}

// MARK: - Ergonomic constructors

extension DatastarEvent {
    /// Patch HTML elements into the DOM on the client.
    public static func patchElements(
        _ html: String,
        selector: String? = nil,
        mode: ElementPatchMode = .outer,
        useViewTransition: Bool = false,
        namespace: Namespace = .html,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .patchElements(PatchElements(
            html: html,
            selector: selector,
            mode: mode,
            useViewTransition: useViewTransition,
            namespace: namespace,
            eventID: eventID,
            retryDuration: retryDuration
        ))
    }

    /// Patch signals by encoding an `Encodable` value as JSON.
    public static func patchSignals<T: Encodable>(
        _ value: T,
        onlyIfMissing: Bool = false,
        eventID: String? = nil,
        retryDuration: Duration? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> DatastarEvent {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return .patchSignals(PatchSignals(
            json: json,
            onlyIfMissing: onlyIfMissing,
            eventID: eventID,
            retryDuration: retryDuration
        ))
    }

    /// Patch signals using a pre-serialized JSON string.
    public static func patchSignalsJSON(
        _ json: String,
        onlyIfMissing: Bool = false,
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .patchSignals(PatchSignals(
            json: json,
            onlyIfMissing: onlyIfMissing,
            eventID: eventID,
            retryDuration: retryDuration
        ))
    }

    /// Execute JavaScript in the browser. Sugar over a `patchElements` frame
    /// that appends a `<script>` element to `<body>`.
    public static func executeScript(
        _ script: String,
        autoRemove: Bool = true,
        attributes: [String: String] = [:],
        eventID: String? = nil,
        retryDuration: Duration? = nil
    ) -> DatastarEvent {
        .executeScript(ExecuteScript(
            script: script,
            autoRemove: autoRemove,
            attributes: attributes,
            eventID: eventID,
            retryDuration: retryDuration
        ))
    }
}

// MARK: - Wire-format conversion (internal)

extension DatastarEvent {
    /// Convert to the internal wire-format SSE event. Consumed by
    /// `DatastarSSEBody.Iterator` during emission.
    internal func toWireEvent() -> SSEEvent {
        switch self {
        case .patchElements(let p): return p.toWireEvent()
        case .patchSignals(let p):  return p.toWireEvent()
        case .executeScript(let e): return e.toWireEvent()
        }
    }
}

extension DatastarEvent.PatchElements {
    internal func toWireEvent() -> SSEEvent {
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
        return SSEEvent(
            name: DatastarEventType.patchElements.rawValue,
            id: eventID,
            retry: retryDuration,
            data: data
        )
    }
}

extension DatastarEvent.PatchSignals {
    internal func toWireEvent() -> SSEEvent {
        var data: [String] = []
        if onlyIfMissing != DatastarDefaults.patchSignalsOnlyIfMissing {
            data.append(DatalineLiteral.onlyIfMissing + String(onlyIfMissing))
        }
        for line in json.split(separator: "\n", omittingEmptySubsequences: false) {
            data.append(DatalineLiteral.signals + String(line))
        }
        return SSEEvent(
            name: DatastarEventType.patchSignals.rawValue,
            id: eventID,
            retry: retryDuration,
            data: data
        )
    }
}

extension DatastarEvent.ExecuteScript {
    internal func toWireEvent() -> SSEEvent {
        // Build a <script> element with the configured attributes and optional
        // auto-remove behavior, then emit as patch-elements with mode=.append
        // targeting <body>. Matches the byte-for-byte wire format of the Go
        // and Rust SDKs for the same inputs.
        var attrs = attributes
        if autoRemove && attrs["data-effect"] == nil {
            attrs["data-effect"] = "el.remove()"
        }
        var tag = "<script"
        for key in attrs.keys.sorted() {
            tag += " \(key)=\"\(Self.htmlAttrEscape(attrs[key]!))\""
        }
        tag += ">\(script)</script>"

        let patch = DatastarEvent.PatchElements(
            html: tag,
            selector: "body",
            mode: .append,
            eventID: eventID,
            retryDuration: retryDuration
        )
        return patch.toWireEvent()
    }

    private static func htmlAttrEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}
