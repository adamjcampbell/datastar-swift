// DO NOT EDIT — generated from sdk/datastar-sdk-config-v1.json.
// Regenerate with: swift Scripts/generate-constants.swift

import Foundation

/// The mode in which an element is patched into the DOM.
public enum ElementPatchMode: String, Sendable, CaseIterable, Codable {
    /// Morphs the element into the existing element.
    case outer
    /// Replaces the inner HTML of the existing element.
    case inner
    /// Removes the existing element.
    case remove
    /// Replaces the existing element with the new element.
    case replace
    /// Prepends the element inside to the existing element.
    case prepend
    /// Appends the element inside the existing element.
    case append
    /// Inserts the element before the existing element.
    case before
    /// Inserts the element after the existing element.
    case after

    public static let `default`: ElementPatchMode = .outer
}

/// The namespace in which elements are created.
public enum Namespace: String, Sendable, CaseIterable, Codable {
    /// HTML namespace for standard HTML elements.
    case html
    /// SVG namespace for SVG elements.
    case svg
    /// MathML namespace for mathematical notation.
    case mathml

    public static let `default`: Namespace = .html
}

/// SSE event types emitted by Datastar servers.
public enum DatastarEventType: String, Sendable, CaseIterable {
    /// An event for patching HTML elements into the DOM.
    case patchElements = "datastar-patch-elements"
    /// An event for patching signals.
    case patchSignals = "datastar-patch-signals"
}

/// Protocol-level defaults shared across every Datastar SDK.
public enum DatastarDefaults {
    /// Default SSE retry duration (1000 ms).
    public static let sseRetryDuration: Duration = .milliseconds(1000)
    /// Whether element patches use the View Transitions API by default.
    public static let elementsUseViewTransitions: Bool = false
    /// Whether signal patches only set missing signals by default.
    public static let patchSignalsOnlyIfMissing: Bool = false
    /// Query parameter name and form key used for signals.
    public static let datastarKey: String = "datastar"
}

/// Dataline literal prefixes used on the SSE wire (each includes the trailing space).
enum DatalineLiteral {
    static let selector = "selector "
    static let mode = "mode "
    static let elements = "elements "
    static let useViewTransition = "useViewTransition "
    static let namespace = "namespace "
    static let signals = "signals "
    static let onlyIfMissing = "onlyIfMissing "
}
