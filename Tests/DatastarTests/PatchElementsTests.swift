import Testing
@testable import Datastar

@Suite("patchElements")
struct PatchElementsTests {
    @Test("Defaults-only patch omits selector/mode/namespace/view-transition")
    func defaultsOnly() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<p>hi</p>")
        let out = await collect(sse)
        #expect(out == "event: datastar-patch-elements\ndata: elements <p>hi</p>\n\n")
    }

    @Test("Selector is emitted when provided")
    func withSelector() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<p>hi</p>", selector: "#target")
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-elements
        data: selector #target
        data: elements <p>hi</p>


        """.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    @Test(
        "Each non-default mode is emitted",
        arguments: [
            ElementPatchMode.inner,
            .remove,
            .replace,
            .prepend,
            .append,
            .before,
            .after,
        ]
    )
    func nonDefaultModes(mode: ElementPatchMode) async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<p>x</p>", mode: mode)
        let out = await collect(sse)
        #expect(out.contains("data: mode \(mode.rawValue)\n"))
    }

    @Test("Outer (default) mode is suppressed")
    func defaultModeSuppressed() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<p>x</p>", mode: .outer)
        let out = await collect(sse)
        #expect(!out.contains("data: mode"))
    }

    @Test("SVG namespace is emitted, html is not")
    func svgNamespace() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<circle />", namespace: .svg)
        let out = await collect(sse)
        #expect(out.contains("data: namespace svg\n"))

        let sse2 = ServerSentEventGenerator()
        try sse2.patchElements("<p>x</p>", namespace: .html)
        let out2 = await collect(sse2)
        #expect(!out2.contains("data: namespace"))
    }

    @Test("useViewTransition=true is emitted; false is suppressed")
    func viewTransition() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<p>x</p>", useViewTransition: true)
        let out = await collect(sse)
        #expect(out.contains("data: useViewTransition true\n"))

        let sse2 = ServerSentEventGenerator()
        try sse2.patchElements("<p>x</p>", useViewTransition: false)
        let out2 = await collect(sse2)
        #expect(!out2.contains("useViewTransition"))
    }

    @Test("Multi-line HTML is split into one data line per source line")
    func multilineHTML() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("<div>\n  <p>hi</p>\n</div>")
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-elements
        data: elements <div>
        data: elements   <p>hi</p>
        data: elements </div>


        """)
    }

    @Test("eventID and retryDuration are emitted in SSE id/retry lines")
    func eventIDAndRetry() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements(
            "<p>x</p>",
            eventID: "abc",
            retryDuration: .milliseconds(5000)
        )
        let out = await collect(sse)
        #expect(out.contains("id: abc\n"))
        #expect(out.contains("retry: 5000\n"))
    }

    @Test("Empty HTML emits no data: elements line")
    func emptyHTML() async throws {
        let sse = ServerSentEventGenerator()
        try sse.patchElements("", selector: "#gone", mode: .remove)
        let out = await collect(sse)
        #expect(!out.contains("data: elements"))
        #expect(out.contains("data: selector #gone\n"))
        #expect(out.contains("data: mode remove\n"))
    }

    @Test("removeElements convenience sets mode=remove without elements data")
    func removeConvenience() async throws {
        let sse = ServerSentEventGenerator()
        try sse.removeElements(selector: "#gone")
        let out = await collect(sse)
        #expect(out == """
        event: datastar-patch-elements
        data: selector #gone
        data: mode remove


        """)
    }

    @Test("Writing after finish() throws streamAlreadyFinished")
    func writeAfterFinish() async throws {
        let sse = ServerSentEventGenerator()
        sse.finish()
        // Drain first so the terminated state is observed.
        for await _ in sse.body {}
        #expect(throws: DatastarError.self) {
            try sse.patchElements("<p>x</p>")
        }
    }
}
