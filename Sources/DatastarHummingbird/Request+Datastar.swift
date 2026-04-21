import Datastar
import Foundation
import Hummingbird
import NIOCore

extension Request {
    /// Decode Datastar signals from `?datastar=<json>` (GET requests).
    ///
    /// Synchronous — no body I/O. Falls back to `{}` when the parameter is absent,
    /// so `Decodable` types with all-defaulted fields work without the query param.
    public func datastarSignals<T: Decodable>(
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let raw = uri.queryParameters[DatastarDefaults.datastarKey[...]]
            .map(String.init) ?? "{}"
        return try decoder.decode(T.self, from: Data(raw.utf8))
    }

    /// Decode Datastar signals from the request body (POST/PUT/PATCH requests).
    ///
    /// Collects the full body up to `context.maxUploadSize`, then JSON-decodes it.
    /// Treats an empty body as `{}`, so all-defaulted signal types succeed without
    /// special handling in the route.
    public mutating func datastarSignals<T: Decodable>(
        as type: T.Type,
        context: some RequestContext,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let buffer = try await collectBody(upTo: context.maxUploadSize)
        if buffer.readableBytes == 0 {
            return try decoder.decode(T.self, from: Data("{}".utf8))
        }
        return try decoder.decode(T.self, from: Data(buffer: buffer))
    }
}
