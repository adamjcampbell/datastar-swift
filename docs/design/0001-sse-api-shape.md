# 0001 — SSE API shape: push vs. pull

**Status:** accepted
**Date:** 2026-04-20
**Shipping version impacted:** v0.2 (v0.1 remains as-is)

## Background

datastar-swift v0.1 ships a **push-based** `ServerSentEventGenerator`: callers construct the generator, pass `sse.body` (an unbounded `AsyncStream<ArraySlice<UInt8>>`) to their HTTP framework, and call synchronous `sse.patchElements(...)` / `sse.patchSignals(...)` methods from a producer task. Emissions are enqueued into the stream's buffer regardless of whether the consumer has read them yet.

That shape has two weaknesses, both surfaced in the Swift-concurrency review:

1. **No backpressure.** With `.unbounded` buffering, a slow consumer causes monotonic memory growth. Any other buffering policy silently drops SSE frames, which is unacceptable for the protocol.
2. **Manual cancellation wiring.** When the client disconnects, the producer only finds out at its next `yield` attempt. Callers must add `sse.onCancel { producer.cancel() }` by hand to cancel the producer Task promptly; forgetting costs up to one full sleep interval of wasted work per request.

A natural fix is a **pull-based** API where `patchElements` is `async throws` and suspends until the consumer demands the next chunk:

```swift
let body = ServerSentEventGenerator.stream { sse in
    try await sse.patchElements("<p>1</p>")   // awaits the consumer
    try await Task.sleep(for: .seconds(1))
    try await sse.patchElements("<p>2</p>")
}
return Response(body: ResponseBody(asyncSequence: body))
```

This note investigates whether making pull the **primary** API mechanism meaningfully limits what the SDK can express.

## Cross-SDK baseline

None of the reference SDKs actually use pull-based backpressure. The TypeScript SDK's `stream((sse) => { ... })` looks closure-scoped but internally calls `controller.enqueue(...)` synchronously — identical behavior to our v0.1, just with a nicer entry point. The Go SDK writes directly to an `http.ResponseWriter`, which buffers. A true rendezvous-channel design would be novel for this ecosystem.

## Prototype

A throwaway spike at `/tmp/datastar-pull-spike.swift` (not merged) proves the pull shape works in Swift 6 using an actor-backed rendezvous channel:

```swift
actor PullChannel<Element: Sendable> {
    enum State {
        case idle
        case pendingConsumer(CheckedContinuation<Element?, Never>)
        case pendingProducer(Element, CheckedContinuation<Void, Error>)
        case finished
    }
    // send() parks until a receive() rendezvous; receive() parks until send().
}
```

Running a 13-chunk HelloWorld producer against a 200ms-per-pull consumer with a 50ms producer delay shows each emission correctly awaits ~150ms for the consumer — the backpressure is real, not buffered:

```
producer: emission 1 awaited 0.000s for consumer
producer: emission 2 awaited 0.154s for consumer
producer: emission 3 awaited 0.158s for consumer
...
```

Implementation choices considered:

- **AsyncStream.init(unfolding:)** — rejected; the closure is re-entered per pull and must maintain its own state, which forces the caller to structure producer code as a state machine rather than straight-line async.
- **CheckedContinuation pair (actor-mediated)** — chosen. Direct, ~40 LOC primitive, no external dependencies. Single-producer/single-consumer by design (concurrent send or receive traps) — fine for the straight-line-closure use case this API targets.
- **AsyncChannel from swift-async-algorithms** — feasible but adds a dependency the SDK has so far avoided. Semantically equivalent to the channel we'd write by hand.

## Use-case matrix

Ten real patterns, ranked against both APIs:

| # | Use case | Push (v0.1) | Pull (prototype) |
|---|---|---|---|
| 1 | Linear producer with delays (HelloWorld) | Works; requires fire-and-forget Task + manual `onCancel` wiring. | **Strict win.** Closure replaces Task; cancellation is automatic via channel termination. |
| 2 | Bounded batch emit (/event/generate) | Works, same Task + onCancel pattern as #1. | **Strict win**, same reason. |
| 3 | Single-shot emission (/event/done) | Trivial: one `try sse.patchElements(...)` call. | Works; very minor overhead of wrapping in a closure. |
| 4 | Long-running unbounded stream (clock/chat) | **Risky.** Unbounded buffer grows if consumer stalls; bounded policies drop frames. | **Strict win.** Backpressure is inherent; no memory risk. |
| 5 | Two concurrent tasks writing to the same stream | Works naturally — multiple tasks can call synchronous `patchElements`; stream buffer serializes FIFO. | **Limitation.** The rendezvous channel is single-producer. Needs a merging layer (e.g., `AsyncMerge`) or an extra mutex around `send`. |
| 6 | Handle to external observer (pub/sub, DB watcher, NotificationCenter) | **Strict win.** The generator is a `Sendable` class — pass the reference to the observer and be done. | **Limitation.** The `sse` handle is closure-scoped. Bridging an outside observer requires introducing a second channel the closure pumps from, which reintroduces a push layer. |
| 7 | Actor-hosted handler (`@MainActor` emitter) | Works; synchronous emit runs on the actor. | Works; `await patchElements` suspends cleanly, no actor-hopping. |
| 8 | Unit testing from the producer side | Easy: call the sync methods, assert on `sse.body`. | Slightly heavier: tests must drive both sides (producer + consumer). Fixture setup ~2–3 extra lines. |
| 9 | Middleware wanting to inject events into an existing stream | Works by passing `sse` through the request context; middleware calls its methods. | **Limitation.** Middleware has to wrap or extend the producer closure. Nested closures or an explicit channel handoff needed. |
| 10 | Graceful shutdown / drain on server stop | Works; cancel the producer task, let `finish()` close the body. | **Strict win.** Cancel the enclosing Task, `defer channel.finish()` runs in the closure, consumer's `next()` returns `nil`. |

## Summary of limits

Pull-as-primary is strictly better for straight-line producers (cases 1, 2, 4, 10) and neutral-to-better for actor and shutdown scenarios (7, 10). It has three concrete limits:

- **Single-producer only** (case 5). Merging multiple concurrent emitters needs extra plumbing.
- **Short handle lifetime** (case 6). The `sse` reference can't outlive the closure, so handing it to a long-lived observer requires a second channel layer.
- **Middleware injection** (case 9). Composing layers that emit into a stream is awkward when the stream's producer is closure-scoped.

None of these are fatal — all three have known workarounds using additional channel plumbing. But they're all patterns where the v0.1 push API stays noticeably simpler.

## Recommended API shape for v0.2

**Ship both, with pull as the primary documented API.** Internally implement pull on top of the existing push primitive (so there's one underlying wire-format encoder, no duplication):

```swift
public enum ServerSentEventGenerator {
    /// Primary entry point: run a straight-line producer closure whose
    /// emissions respect consumer backpressure and cooperative cancellation.
    public static func stream(
        _ produce: @Sendable @escaping (PullGenerator) async throws -> Void
    ) -> some AsyncSequence<ArraySlice<UInt8>, any Error> & Sendable

    /// Escape hatch for handle-holder patterns (external observers, middleware,
    /// multi-producer). Returns the v0.1 class-based generator.
    public static func make() -> Handle
}

public struct PullGenerator: Sendable {
    public func patchElements(_ html: String, /* ...same options... */) async throws
    public func patchSignals<T: Encodable>(_ signals: T, /* ... */) async throws
    // etc.
}

public final class Handle: Sendable {   // was `ServerSentEventGenerator` in v0.1
    public var body: AsyncStream<ArraySlice<UInt8>> { get }
    public func patchElements(_ html: String, /* ... */) throws
    public func patchSignals<T: Encodable>(_ signals: T, /* ... */) throws
    public func onCancel(_ handler: @escaping @Sendable () -> Void)
    public func finish()
}
```

Examples and README lead with `stream { sse in ... }`. The class-based `make()` is documented as the escape hatch for the three limit-cases above. Tests cover both.

## Migration from v0.1

- Rename `ServerSentEventGenerator` (the class) to `Handle` under a new namespacing enum `ServerSentEventGenerator`. Keep a `typealias ServerSentEventGenerator = Handle` deprecation alias for one version so v0.1 users get a warning, not a hard break.
- Both examples switch to `stream { sse in ... }` and lose the `Task { ... } + onCancel { producer.cancel() }` boilerplate.
- `OnCancelTests` moves onto `Handle`; new tests cover the pull API.

## Decision

**Adopt both APIs in v0.2, with pull as the primary and push retained as a documented escape hatch.** The limits identified above are real but narrow, and all have reasonable workarounds on the pull side when you genuinely need them. The ergonomics and safety wins for the common case (straight-line producers, which dominates the Rust SDK's examples, our own examples, and the patterns expected by Datastar users) justify leading with pull.

Follow-up issue should reference this document and implement the v0.2 API per the sketch above.

---

## Postscript — v0.2.1 primitive choice

**What we shipped:** `ServerSentEventGenerator.stream(_:)` is backed by `AsyncThrowingChannel` from [apple/swift-async-algorithms](https://github.com/apple/swift-async-algorithms) (1.1+), with a small class-based iterator on `DatastarSSEBody` whose `deinit` cancels the producer Task when the consumer drops the iterator.

v0.2.1 replaced an earlier bespoke `PullChannel` actor after two real bugs were found (orphaned continuation on consumer task-cancel; leaked producer Task on iterator drop). The channel primitive closes both.

**Alternative considered: `AsyncThrowingStream.makeStream` (stdlib).** Zero-dep, ~15 LOC shorter, has a clean `continuation.onTermination` hook that would let us skip the class-iterator trick. Rejected because:

- `AsyncThrowingStream` has **no real backpressure**. `.unbounded` grows memory without limit if the consumer stalls; `.bufferingNewest(n)` / `.bufferingOldest(n)` silently drop SSE frames, which would corrupt the Datastar client's DOM state (every `datastar-patch-elements` frame is protocol-significant — dropped frames are not recoverable).
- For short, bounded-iteration producers (today's HelloWorld and ActivityFeed), either primitive works equivalently. The channel's backpressure is latent safety, not currently exercised.

**Why this choice is forward-compatible.** The channel's rendezvous backpressure becomes load-bearing the moment we ship a long-running example — a ticker, chat feed, progress stream, live log, anything that emits indefinitely. On the stdlib stream, a slow or backgrounded client would balloon server memory (unbounded policy) or silently corrupt the UI (bounded-drop policies). On the channel, the producer simply parks; if the consumer truly disappears, the iterator's deinit fires, the producer is cancelled, no leak. **Adding long-running example(s) in v0.3 requires no changes to the primitive or to `SSEWriter` / `DatastarSSEBody` / `stream(_:)`.** Just write the example.

**When we'd revisit.** If the swift-async-algorithms dependency becomes a problem (CVEs, breaking changes, build-time cost) OR if we conclude after a few releases that we'll never ship a long-running example and want to trim deps, the swap to `AsyncThrowingStream.makeStream` is a clean patch-level change — the public API (`SSEWriter`, `DatastarSSEBody`, `stream(_:)`) is stable across either implementation. Neither trigger is imminent; Apple is actively maintaining swift-async-algorithms and we do intend long-running examples.

---

## Postscript — v0.3 value-oriented redesign (pre-ship)

**Context.** A full review against Go, TypeScript, Python, and Rust SDKs surfaced that our v0.2.1 had two public entry points (pull-closure + push-class). No other SDK does this. We haven't cut a release, so there are no breaking-change concerns.

**What changed.** Dropped the push class. Replaced `SSEWriter` (methods-on-an-opaque-handle) with `DatastarEvent` — an enum with three cases (`patchElements`, `patchSignals`, `executeScript`) + nested struct payloads. Users construct events as values, either through ergonomic static methods (`.patchElements(...)`) or by building the struct directly. `ServerSentEventGenerator.stream(_:)` stays as the straight-line-closure entry point, but now hands an `Emitter` that takes a `DatastarEvent` value instead of exposing typed methods. A new `DatastarSSEBody.init(_:)` accepts any `AsyncSequence<DatastarEvent>` so callers with existing event streams don't need the stream helper.

**Why value-oriented.** Matches Rust (`PatchElements`, `PatchSignals`, `ExecuteScript` structs + `DatastarEvent` trait) and Python (yield `SSEEvent` values). Events become inspectable, testable, and composable — users can `map`/`filter`/`merge` sequences of events using existing AsyncSequence operators before handing them off.

**Why drop the push class.** No user shipped, and no other SDK has a "keep the handle around past a scoped closure" pattern. `stream { emit in ... }` covers the straight-line case; `DatastarSSEBody(mySequence)` covers the "events come from somewhere else" case. The observer/middleware use case the push class targeted isn't meaningfully different from "hand the middleware your emitter or your domain event stream."

**Why drop `DatastarSignals`.** Rust's framework-agnostic core has no equivalent; `axum.rs`/`rocket.rs`/`warp.rs` each provide their own `ReadSignals<T>` extractor. We'll ship the same pattern in `DatastarHummingbird`/`DatastarVapor` adapters. Until then, users outside a framework adapter call `JSONDecoder` directly — one line, no abstraction cost.

**Why no `removeElements` / `removeSignals` / `redirect` conveniences.** Rust doesn't ship them. Users write `.patchElements("", selector: "#x", mode: .remove)` and `.patchSignalsJSON(#"{"name":null}"#)` — one-liners, no dedicated API surface. (Datastar's client treats these cases uniformly with their non-remove counterparts; no semantic distinction at the protocol level.)

**What's unchanged.** The AsyncThrowingChannel-backed rendezvous primitive (v0.2.1 postscript above still applies), the class-based `DatastarSSEBody.Iterator` with deinit cancellation, wire-format parity with the Go SDK. Public types held for parity: `ElementPatchMode`, `Namespace`, `DatastarDefaults` (spec-generated), `ServerSentEventGenerator` (ADR-mandated), `DatastarSSEBody`.
