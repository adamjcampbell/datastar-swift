/// Errors raised by the Datastar SDK.
public enum DatastarError: Error, Sendable {
    /// `finish()` has already been called on the generator; no further events can be written.
    case streamAlreadyFinished

    /// Encoding a value (e.g. a signals payload) failed.
    case encodingFailed(underlying: any Error)
}
