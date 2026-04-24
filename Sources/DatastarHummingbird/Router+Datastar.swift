import Hummingbird

// MARK: - Generic primitive

extension RouterMethods {
    /// Register a Datastar SSE route that decodes request signals and emits
    /// events through a `ServerSentEventGenerator`.
    ///
    /// Sugar over the composable primitives `request.datastarSignals(as:context:)`
    /// and `Response.datastarSSE { sse in ... }`. The handler closure runs
    /// with the decoded signals already in hand and a generator bound to
    /// the response-body writer.
    ///
    /// ```swift
    /// router.datastarOn("/stream", method: .get, signals: MySignals.self) { signals, sse in
    ///     try await sse.patchElements("<p>\(signals.message)</p>")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: The route path. Defaults to the router's current scope.
    ///   - method: The HTTP verb to register.
    ///   - signals: The `Decodable` type to decode request signals into.
    ///   - handler: Closure that receives the decoded signals and an `inout`
    ///     generator; errors propagate out of the response body.
    @discardableResult
    public func datastarOn<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        method: HTTPRequest.Method,
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        on(path, method: method) { request, context -> Response in
            var request = request
            let signals = try await request.datastarSignals(as: Signals.self, context: context)
            return .datastarSSE { sse in
                try await handler(signals, &sse)
            }
        }
    }
}

// MARK: - Per-verb wrappers

extension RouterMethods {
    /// Register a Datastar SSE route for `GET` requests.
    @discardableResult
    public func datastarGet<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        datastarOn(path, method: .get, signals: signals, use: handler)
    }

    /// Register a Datastar SSE route for `POST` requests.
    @discardableResult
    public func datastarPost<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        datastarOn(path, method: .post, signals: signals, use: handler)
    }

    /// Register a Datastar SSE route for `PUT` requests.
    @discardableResult
    public func datastarPut<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        datastarOn(path, method: .put, signals: signals, use: handler)
    }

    /// Register a Datastar SSE route for `PATCH` requests.
    @discardableResult
    public func datastarPatch<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        datastarOn(path, method: .patch, signals: signals, use: handler)
    }

    /// Register a Datastar SSE route for `DELETE` requests.
    @discardableResult
    public func datastarDelete<Signals: Decodable & Sendable>(
        _ path: RouterPath = "",
        signals: Signals.Type,
        use handler: @Sendable @escaping (
            Signals,
            inout ServerSentEventGenerator<any ResponseBodyWriter>
        ) async throws -> Void
    ) -> Self {
        datastarOn(path, method: .delete, signals: signals, use: handler)
    }
}
