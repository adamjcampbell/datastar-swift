/// A single-producer, single-consumer rendezvous channel. Used internally by
/// `ServerSentEventGenerator.stream(_:)` to give the pull API its backpressure
/// semantics: the producer parks on `send` until the consumer asks for the next
/// element via `receive`.
///
/// Concurrent `send` or `receive` calls are a programmer error and trap.
actor PullChannel<Element: Sendable> {
    private enum State {
        case idle
        case pendingConsumer(CheckedContinuation<Element?, any Error>)
        case pendingProducer(Element, CheckedContinuation<Void, any Error>)
        case finished
        case failed(any Error)
    }

    private var state: State = .idle

    /// Send one element. Suspends until the consumer pulls it (or until the
    /// sender's task is cancelled, in which case this throws `CancellationError`).
    func send(_ value: Element) async throws {
        switch state {
        case .pendingConsumer(let cc):
            state = .idle
            cc.resume(returning: value)
        case .idle:
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (pc: CheckedContinuation<Void, any Error>) in
                    state = .pendingProducer(value, pc)
                }
            } onCancel: { [weak self] in
                Task { await self?.cancelPendingProducer() }
            }
        case .pendingProducer:
            preconditionFailure("PullChannel: concurrent send is unsupported")
        case .finished:
            throw CancellationError()
        case .failed(let error):
            throw error
        }
    }

    /// Pull the next element. Returns nil when the producer has finished cleanly,
    /// throws if the producer failed.
    func receive() async throws -> Element? {
        switch state {
        case .pendingProducer(let value, let pc):
            state = .idle
            pc.resume()
            return value
        case .idle:
            return try await withCheckedThrowingContinuation {
                (cc: CheckedContinuation<Element?, any Error>) in
                state = .pendingConsumer(cc)
            }
        case .pendingConsumer:
            preconditionFailure("PullChannel: concurrent receive is unsupported")
        case .finished:
            return nil
        case .failed(let error):
            throw error
        }
    }

    /// Terminate the channel. `error == nil` is a clean finish; otherwise the
    /// consumer's next `receive` throws the given error.
    func finish(throwing error: (any Error)? = nil) {
        switch state {
        case .pendingConsumer(let cc):
            if let error {
                cc.resume(throwing: error)
            } else {
                cc.resume(returning: nil)
            }
        case .pendingProducer(_, let pc):
            pc.resume(throwing: CancellationError())
        case .idle, .finished, .failed:
            break
        }
        state = error.map { .failed($0) } ?? .finished
    }

    private func cancelPendingProducer() {
        if case .pendingProducer(_, let pc) = state {
            state = .idle
            pc.resume(throwing: CancellationError())
        }
    }
}
