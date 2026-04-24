import Foundation
import Hummingbird

extension Request {
    /// Decode Datastar signals from the request, dispatching on the HTTP method.
    ///
    /// - `GET` and `DELETE` read the `?datastar=<json>` query parameter.
    /// - `POST`, `PUT`, and `PATCH` read the JSON body, up to
    ///   `context.maxUploadSize`.
    /// - Other methods fall back to the query parameter.
    ///
    /// A missing query parameter or empty body decodes as `"{}"`, so
    /// `Decodable` types with all-defaulted fields succeed without special
    /// handling in the route.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode the signals into.
    ///   - context: The request context; its `maxUploadSize` caps body
    ///     collection.
    ///   - decoder: The JSON decoder to use. Defaults to a fresh
    ///     `JSONDecoder`.
    /// - Returns: The decoded signals value.
    public mutating func datastarSignals<T: Decodable>(
        as type: T.Type,
        context: some RequestContext,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        switch method {
        case .post, .put, .patch:
            let buffer = try await collectBody(upTo: context.maxUploadSize)
            if buffer.readableBytes == 0 {
                return try decoder.decode(T.self, from: Data("{}".utf8))
            }
            return try decoder.decode(T.self, from: Data(buffer.readableBytesView))
        default:
            let raw = uri.queryParameters[DatastarDefaults.datastarKey[...]]
                .map(String.init) ?? "{}"
            return try decoder.decode(T.self, from: Data(raw.utf8))
        }
    }
}
