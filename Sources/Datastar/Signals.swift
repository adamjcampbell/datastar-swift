import Foundation

/// Helpers for decoding signals the Datastar client sends with every request.
///
/// Datastar clients send signals as JSON. The transport depends on the HTTP method:
/// - `GET` and `DELETE`: JSON is in the `datastar` query parameter.
/// - All other methods: JSON is the raw request body.
///
/// This type provides one entry point for each transport. Framework adapters are
/// expected to route based on the request method and call the appropriate one.
public enum DatastarSignals {
    /// Decode signals from the raw JSON body of a `POST`/`PUT`/`PATCH`/etc. request.
    public static func decode<T: Decodable>(
        _ type: T.Type,
        fromBody data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// Decode signals from the value of the `datastar` query parameter of a
    /// `GET` or `DELETE` request.
    public static func decode<T: Decodable>(
        _ type: T.Type,
        fromQueryValue value: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decoder.decode(type, from: Data(value.utf8))
    }
}
