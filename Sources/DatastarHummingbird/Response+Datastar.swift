import Hummingbird

extension Response {
    /// Create a Datastar SSE streaming response.
    ///
    /// The producer closure receives an `inout ServerSentEventGenerator` whose
    /// writer is bound to Hummingbird's response-body writer —
    /// `sse.patchElements(...)`, `sse.patchSignals(...)`, and
    /// `sse.executeScript(...)` emit on the wire immediately. Hummingbird
    /// drives the write loop inline; no background Task is spawned and no
    /// class box or `@unchecked Sendable` is involved — writer state flows
    /// through `inout` from Hummingbird down into `sse.writer` and back to
    /// `finish()`.
    ///
    /// Sets the three ADR-mandated SSE response headers:
    /// `Content-Type: text/event-stream`, `Cache-Control: no-cache`,
    /// `Connection: keep-alive`.
    ///
    /// ```swift
    /// router.get("/stream") { request, context -> Response in
    ///     let signals = try await request.datastarSignals(as: MySignals.self, context: context)
    ///     return .datastarSSE { sse in
    ///         try await sse.patchElements("<div>Hello</div>", options: .init(selector: "#msg"))
    ///     }
    /// }
    /// ```
    public static func datastarSSE(
        _ perform: @escaping @Sendable (inout ServerSentEventGenerator<any ResponseBodyWriter>) async throws -> Void
    ) -> Response {
        Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive",
            ],
            body: ResponseBody { writer in
                var sse = ServerSentEventGenerator<any ResponseBodyWriter>(writer)
                try await perform(&sse)
                try await sse.writer.finish(nil)
            }
        )
    }
}
