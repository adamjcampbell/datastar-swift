# datastar-swift

A Swift SDK for [Datastar](https://data-star.dev) — the hypermedia-driven framework that unifies server-rendered HTML with reactive client-side signals over Server-Sent Events.

This package provides a framework-agnostic core: an SSE event generator that emits the Datastar v1 wire format, plus helpers for decoding client-sent signals. It has no runtime dependencies and can be plugged into any Swift HTTP server (Vapor, Hummingbird, swift-nio, or a handwritten one).

## Requirements

- Swift 6.0+
- macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+, or Linux

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/<owner>/datastar-swift.git", from: "0.1.0")
```

Then add `Datastar` to your target's dependencies.

## Usage

### Emit SSE events

Write a straight-line producer closure. Each `try await sse.patchElements(...)` / `sse.patchSignals(...)` call suspends until the HTTP consumer reads the previous chunk, so the producer paces itself to the client automatically. If the client disconnects, the next emit throws `CancellationError` and the closure exits:

```swift
import Datastar

let body = ServerSentEventGenerator.stream { sse in
    try await sse.patchElements(
        #"<div id="clock">12:00</div>"#,
        selector: "#clock",
        mode: .inner
    )
    try await Task.sleep(for: .seconds(1))
    try await sse.patchSignals(["count": 42])
}

// Hand `body` (a DatastarSSEBody — an AsyncSequence<ArraySlice<UInt8>>)
// to your HTTP framework's streaming response body. Set
// Content-Type: text/event-stream.
```

### Advanced: handle-based API (escape hatch)

For patterns where the event source is not a straight-line producer — e.g. handing the generator to an external observer (pub/sub, database watcher, middleware) — use the handle-based class:

```swift
let sse = ServerSentEventGenerator()
// Register onCancel to learn when the client disconnects.
sse.onCancel { /* cancel whatever produced events */ }

// From any task, synchronously:
try sse.patchElements(#"<div id="live">update</div>"#)
try sse.patchSignals(["count": 42])
sse.finish()

// `sse.body` is an AsyncStream<ArraySlice<UInt8>> — plug it into your
// framework's streaming response the same way.
```

Use the pull API (`stream { ... }`) by default. Reach for the class only when you genuinely need the sse handle to outlive a single closure.

### Decode signals from a request

```swift
struct MySignals: Decodable {
    var count: Int
}

// For POST/PUT/PATCH — raw JSON body:
let signals = try DatastarSignals.decode(
    MySignals.self,
    fromBody: requestBody
)

// For GET/DELETE — the `datastar` query parameter value:
let signals = try DatastarSignals.decode(
    MySignals.self,
    fromQueryValue: query["datastar"] ?? ""
)
```

## Examples

Runnable demos live in [`Examples/`](./Examples) as a separate Swift package (so Hummingbird doesn't leak into the library's dep graph):

- `HelloWorldExample` — streams `"Hello, world!"` one character at a time with a client-configurable delay.
- `ActivityFeedExample` — live log with reactive counters; demonstrates `patchElements` + `patchSignals` cooperating.

```sh
cd Examples
swift run HelloWorldExample    # http://127.0.0.1:8080
swift run ActivityFeedExample  # http://127.0.0.1:8081
```

See [`Examples/README.md`](./Examples/README.md) for details.

## Status

v0.2 — pull-based `stream { ... }` API is the primary entry point; the handle-based class remains as an escape hatch for observer/middleware patterns. Framework adapters for Vapor and Hummingbird, plus an `executeScript` convenience helper, are planned.

## License

MIT. Based on the [Datastar SDK specification](https://github.com/starfederation/datastar/blob/main/sdk/ADR.md) by starfederation.
