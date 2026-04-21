import Datastar
import Hummingbird
import NIOCore

extension DatastarSSEBody: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: ResponseBody(asyncSequence: map { ByteBuffer(bytes: $0) })
        )
    }
}
