import Hummingbird

extension Response {
    /// Create a Datastar SSE streaming response.
    ///
    /// The producer closure receives an `inout ServerSentEventGenerator`
    /// whose writer is bound to Hummingbird's response-body writer, so
    /// `sse.patchElements(...)`, `sse.patchSignals(...)`, and
    /// `sse.executeScript(...)` emit on the wire immediately. Hummingbird
    /// drives the write loop inline; no background task is spawned.
    ///
    /// The response carries the three standard SSE headers:
    /// `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and
    /// `Connection: keep-alive`.
    ///
    /// ```swift
    /// router.get("/stream") { request, context -> Response in
    ///     var request = request
    ///     let signals = try await request.datastarSignals(as: MySignals.self, context: context)
    ///     return .datastarSSE { sse in
    ///         try await sse.patchElements("<div>Hello</div>", options: .init(selector: "#msg"))
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter perform: Closure that emits events through the
    ///   generator. Errors thrown from the closure propagate out of the
    ///   response body.
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
