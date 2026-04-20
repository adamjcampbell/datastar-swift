import Datastar

/// Drain the full body of an SSE generator into a UTF-8 string.
/// Call sites typically emit their events, then use `collect` to compare
/// against a golden string.
func collect(_ sse: ServerSentEventGenerator) async -> String {
    sse.finish()
    var bytes: [UInt8] = []
    for await chunk in sse.body {
        bytes.append(contentsOf: chunk)
    }
    return String(decoding: bytes, as: UTF8.self)
}
