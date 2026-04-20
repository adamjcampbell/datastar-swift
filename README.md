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

```swift
import Datastar

let sse = ServerSentEventGenerator()

// Stream handler (pseudocode — plug `sse.body` into your HTTP response)
Task {
    try sse.patchElements(
        "<div id=\"clock\">12:00</div>",
        selector: "#clock",
        mode: .inner
    )

    try sse.patchSignals(["count": 42])

    sse.finish()
}

// Hand `sse.body` (an AsyncStream<ArraySlice<UInt8>>) to your server's
// streaming response body. Set Content-Type: text/event-stream.
```

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

## Status

v0.1 — core library only. Framework adapters for Vapor and Hummingbird, plus an `executeScript` convenience helper, are planned.

## License

MIT. Based on the [Datastar SDK specification](https://github.com/starfederation/datastar/blob/main/sdk/ADR.md) by starfederation.
