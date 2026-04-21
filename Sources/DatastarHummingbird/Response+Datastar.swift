import Hummingbird

// MARK: - ResponseBodyWriter

extension ResponseBodyWriter {
    /// Encode and write a Datastar event as an SSE frame.
    public mutating func emit(_ event: DatastarEvent) async throws {
        try await write(ByteBuffer(bytes: SSEEncoding.encode(event.toWireEvent())))
    }

    /// Encode and write any `DatastarEventConvertible` value as an SSE frame.
    public mutating func emit<E: DatastarEventConvertible>(_ event: E) async throws {
        try await write(ByteBuffer(bytes: SSEEncoding.encode(event.toDatastarEvent().toWireEvent())))
    }
}

// MARK: - Response

extension Response {
    /// Create a Datastar SSE streaming response.
    ///
    /// Hummingbird drives the write loop inline — no background Task is spawned.
    /// Use `writer.emit(...)` inside the closure to send events.
    ///
    /// ```swift
    /// router.get("/stream") { request, _ -> Response in
    ///     let signals = try request.datastarSignals(as: MySignals.self)
    ///     return .datastarSSE { writer in
    ///         try await writer.emit(.patchElements("<div>Hello</div>"))
    ///     }
    /// }
    /// ```
    public static func datastarSSE(
        _ write: @escaping @Sendable (inout any ResponseBodyWriter) async throws -> Void
    ) -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: ResponseBody { writer in
                try await write(&writer)
                try await writer.finish(nil)
            }
        )
    }
}
