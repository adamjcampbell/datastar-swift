import Foundation

/// Shared SSE-framing logic for the push class and the pull writer.
/// Both entry points produce identical wire output by going through this helper.
enum SSEFrame {
    static func patchElements(
        html: String,
        selector: String?,
        mode: ElementPatchMode,
        useViewTransition: Bool,
        namespace: Namespace,
        eventID: String?,
        retryDuration: Duration?
    ) -> SSEEvent {
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

    static func patchSignalsJSON(
        json: String,
        onlyIfMissing: Bool,
        eventID: String?,
        retryDuration: Duration?
    ) -> SSEEvent {
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

    static func encodeSignals<Signals: Encodable>(
        _ signals: Signals,
        encoder: JSONEncoder
    ) throws -> String {
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
        return json
    }
}
