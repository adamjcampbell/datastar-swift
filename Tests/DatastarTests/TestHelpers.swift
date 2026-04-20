import Datastar

/// Drain the full byte stream of a `DatastarSSEBody` into a UTF-8 string.
/// Call sites build a body via `DatastarSSEBody { emit in ... }` and pass it
/// here to compare the rendered wire format against a golden string.
func collect(_ body: DatastarSSEBody) async throws -> String {
    var bytes: [UInt8] = []
    for try await chunk in body {
        bytes.append(contentsOf: chunk)
    }
    return String(decoding: bytes, as: UTF8.self)
}
