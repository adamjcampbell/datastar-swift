import Hummingbird

extension ServerSentEventGenerator where Writer == any ResponseBodyWriter {
    /// Create a generator whose sink writes to a Hummingbird
    /// `ResponseBodyWriter`.
    ///
    /// Binds `Writer` to `any ResponseBodyWriter` and supplies a sink
    /// that writes each encoded SSE chunk through the response-body
    /// writer as a `ByteBuffer`.
    ///
    /// - Parameter writer: The Hummingbird response-body writer to emit
    ///   through.
    public init(_ writer: consuming any ResponseBodyWriter) {
        self.init(writer) { writer, bytes in
            try await writer.write(ByteBuffer(bytes: bytes))
        }
    }
}
