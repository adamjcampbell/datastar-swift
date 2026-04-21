import Datastar
import Hummingbird
import NIOCore

/// A Datastar SSE streaming response backed by an `AsyncSequence` of events.
///
/// Analogous to Axum's `Sse<S>`. Unlike `DatastarSSEBody`, no background Task
/// is spawned — Hummingbird drives the sequence inline.
public struct DatastarSSEStream<Source: AsyncSequence & Sendable>: ResponseGenerator
    where Source.Element: DatastarEventConvertible
{
    private let events: Source

    public init(_ events: Source) {
        self.events = events
    }

    public func response(from request: Request, context: some RequestContext) -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: ResponseBody(asyncSequence: events.map {
                ByteBuffer(bytes: SSEEncoding.encode($0.toDatastarEvent().toWireEvent()))
            })
        )
    }
}
