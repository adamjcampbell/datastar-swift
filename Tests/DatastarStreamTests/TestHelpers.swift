import DatastarStream

/// Drain the full byte stream of a `DatastarSSEStream` into a UTF-8 string.
/// Call sites build a stream via `DatastarSSEStream { emit in ... }` and pass it
/// here to compare the rendered wire format against a golden string.
func collect(_ stream: DatastarSSEStream) async throws -> String {
    var bytes: [UInt8] = []
    for try await chunk in stream {
        bytes.append(contentsOf: chunk)
    }
    return String(decoding: bytes, as: UTF8.self)
}
