import Hummingbird

/// Hummingbird specialization of the generic `ServerSentEventGenerator`.
/// Binds `Writer` to `any ResponseBodyWriter` and supplies a sink that
/// writes each encoded SSE chunk through the response-body writer.
extension ServerSentEventGenerator where Writer == any ResponseBodyWriter {
    public init(_ writer: consuming any ResponseBodyWriter) {
        self.init(writer) { writer, bytes in
            try await writer.write(ByteBuffer(bytes: bytes))
        }
    }
}
