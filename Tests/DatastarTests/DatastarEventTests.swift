import Foundation
import Testing
@testable import Datastar

@Suite("DatastarEvent wire format")
struct DatastarEventTests {
    // Helper: render a single event via stream() and collect the bytes.
    static func renderToString(_ event: DatastarEvent) async throws -> String {
        try await renderBytes(event)
    }

    // Overload for Rust-style struct-literal call sites (PatchElements, PatchSignals, ExecuteScript):
    static func renderToString<E: DatastarEventConvertible>(_ event: E) async throws -> String {
        try await renderBytes(event)
    }

    private static func renderBytes(_ event: some DatastarEventConvertible) async throws -> String {
        let body = DatastarSSEBody { emit in
            try await emit(event)
        }
        var bytes: [UInt8] = []
        for try await chunk in body {
            bytes.append(contentsOf: chunk)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: patchElements

    @Test("Defaults-only patch omits selector/mode/namespace/view-transition")
    func patchElementsDefaults() async throws {
        let out = try await Self.renderToString(.patchElements("<p>hi</p>"))
        #expect(out == "event: datastar-patch-elements\ndata: elements <p>hi</p>\n\n")
    }

    @Test("Selector is emitted when provided")
    func patchElementsSelector() async throws {
        let out = try await Self.renderToString(.patchElements("<p>hi</p>", selector: "#target"))
        #expect(out == """
        event: datastar-patch-elements
        data: selector #target
        data: elements <p>hi</p>


        """)
    }

    @Test(
        "Each non-default mode is emitted",
        arguments: [
            ElementPatchMode.inner,
            .remove, .replace, .prepend, .append, .before, .after,
        ]
    )
    func patchElementsModes(mode: ElementPatchMode) async throws {
        let out = try await Self.renderToString(.patchElements("<p>x</p>", mode: mode))
        #expect(out.contains("data: mode \(mode.rawValue)\n"))
    }

    @Test("Outer (default) mode is suppressed")
    func patchElementsDefaultModeSuppressed() async throws {
        let out = try await Self.renderToString(.patchElements("<p>x</p>", mode: .outer))
        #expect(!out.contains("data: mode"))
    }

    @Test("SVG namespace is emitted, html is not")
    func patchElementsNamespace() async throws {
        let svg = try await Self.renderToString(.patchElements("<circle/>", namespace: .svg))
        #expect(svg.contains("data: namespace svg\n"))

        let html = try await Self.renderToString(.patchElements("<p>x</p>", namespace: .html))
        #expect(!html.contains("data: namespace"))
    }

    @Test("useViewTransition=true is emitted; false is suppressed")
    func patchElementsViewTransition() async throws {
        let on = try await Self.renderToString(.patchElements("<p>x</p>", useViewTransition: true))
        #expect(on.contains("data: useViewTransition true\n"))

        let off = try await Self.renderToString(.patchElements("<p>x</p>", useViewTransition: false))
        #expect(!off.contains("useViewTransition"))
    }

    @Test("Multi-line HTML is split into one data line per source line")
    func patchElementsMultilineHTML() async throws {
        let out = try await Self.renderToString(.patchElements("<div>\n  <p>hi</p>\n</div>"))
        #expect(out == """
        event: datastar-patch-elements
        data: elements <div>
        data: elements   <p>hi</p>
        data: elements </div>


        """)
    }

    @Test("eventID and retryDuration are emitted in SSE id/retry lines")
    func patchElementsEventIDAndRetry() async throws {
        let out = try await Self.renderToString(.patchElements(
            "<p>x</p>",
            eventID: "abc",
            retryDuration: .milliseconds(5000)
        ))
        #expect(out.contains("id: abc\n"))
        #expect(out.contains("retry: 5000\n"))
    }

    @Test("Remove via patchElements with mode=.remove — the Rust-style way")
    func removeViaPatchElements() async throws {
        let out = try await Self.renderToString(.patchElements("", selector: "#gone", mode: .remove))
        #expect(out == """
        event: datastar-patch-elements
        data: selector #gone
        data: mode remove


        """)
    }

    // MARK: patchSignals

    @Test("patchSignals(encoding:) encodes an Encodable struct as a single-line JSON signals frame")
    func patchSignalsEncodable() async throws {
        struct Example: Encodable { let count: Int }
        let event = try DatastarEvent.patchSignals(encoding: Example(count: 42))
        let out = try await Self.renderToString(event)
        #expect(out == """
        event: datastar-patch-signals
        data: signals {"count":42}


        """)
    }

    @Test("PatchSignals(encoding:) init produces byte-identical output to the enum static")
    func patchSignalsEncodableInitParity() async throws {
        struct Example: Encodable { let count: Int }
        let viaInit = try DatastarEvent.PatchSignals(encoding: Example(count: 42))
        let viaStatic = try DatastarEvent.patchSignals(encoding: Example(count: 42))
        let a = try await Self.renderToString(viaInit)
        let b = try await Self.renderToString(viaStatic)
        #expect(a == b)
    }

    @Test("Struct-literal call site produces same bytes as the enum-case shorthand")
    func structLiteralParity() async throws {
        let viaStruct = DatastarEvent.PatchElements("<p>x</p>", selector: "#t", mode: .inner)
        let viaCase = DatastarEvent.patchElements("<p>x</p>", selector: "#t", mode: .inner)
        let a = try await Self.renderToString(viaStruct)
        let b = try await Self.renderToString(viaCase)
        #expect(a == b)
    }

    @Test("patchSignalsJSON accepts a pre-serialized JSON string")
    func patchSignalsJSON() async throws {
        let out = try await Self.renderToString(.patchSignalsJSON(#"{"a":1}"#))
        #expect(out == """
        event: datastar-patch-signals
        data: signals {"a":1}


        """)
    }

    @Test("onlyIfMissing=true emits the line; false is suppressed")
    func patchSignalsOnlyIfMissing() async throws {
        let on = try await Self.renderToString(.patchSignalsJSON(#"{"a":1}"#, onlyIfMissing: true))
        #expect(on.contains("data: onlyIfMissing true\n"))

        let off = try await Self.renderToString(.patchSignalsJSON(#"{"a":1}"#, onlyIfMissing: false))
        #expect(!off.contains("onlyIfMissing"))
    }

    @Test("Multi-line JSON is split into one data: signals line per source line")
    func patchSignalsMultilineJSON() async throws {
        let out = try await Self.renderToString(.patchSignalsJSON("{\n  \"a\": 1\n}"))
        #expect(out == """
        event: datastar-patch-signals
        data: signals {
        data: signals   "a": 1
        data: signals }


        """)
    }

    @Test("Remove signals via JSON null values — the Rust-style way")
    func removeSignalsViaJSON() async throws {
        let out = try await Self.renderToString(.patchSignalsJSON(#"{"stale":null}"#))
        #expect(out.contains(#"data: signals {"stale":null}"#))
    }

    // MARK: executeScript

    @Test("executeScript with defaults injects data-effect=el.remove() and targets body with mode=append")
    func executeScriptDefaults() async throws {
        let out = try await Self.renderToString(.executeScript("console.log('hi')"))
        #expect(out == """
        event: datastar-patch-elements
        data: selector body
        data: mode append
        data: elements <script data-effect="el.remove()">console.log('hi')</script>


        """)
    }

    @Test("executeScript with autoRemove=false omits the self-remove attribute")
    func executeScriptAutoRemoveFalse() async throws {
        let out = try await Self.renderToString(.executeScript("foo()", autoRemove: false))
        #expect(out.contains(#"data: elements <script>foo()</script>"#))
        #expect(!out.contains("data-effect"))
    }

    @Test("executeScript emits user-provided attributes in sorted order with HTML escaping")
    func executeScriptAttributes() async throws {
        let out = try await Self.renderToString(.executeScript(
            "boot()",
            autoRemove: false,
            attributes: ["type": "module", "data-src": "x & y"]
        ))
        #expect(out.contains(#"data: elements <script data-src="x &amp; y" type="module">boot()</script>"#))
    }

    @Test("executeScript splits a multi-line script onto multiple elements data lines")
    func executeScriptMultiline() async throws {
        let script = "line1();\nline2();"
        let out = try await Self.renderToString(.executeScript(script, autoRemove: false))
        #expect(out == """
        event: datastar-patch-elements
        data: selector body
        data: mode append
        data: elements <script>line1();
        data: elements line2();</script>


        """)
    }
}
