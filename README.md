# datastar-swift

A Swift SDK for [Datastar](https://data-star.dev) — the hypermedia-driven framework that unifies server-rendered HTML with reactive client-side signals over Server-Sent Events.

This package provides a framework-agnostic core: a value-oriented Datastar-event API that emits the Datastar v1 wire format as an `AsyncSequence` of bytes, ready to plug into any Swift HTTP server (Vapor, Hummingbird, swift-nio, or a handwritten one).

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

Datastar events are modeled as data (`DatastarEvent` values) rather than method calls on a writer. Two primary entry points:

**Trailing-closure init** — for the common case of emitting events in order. Each `try await emit(...)` suspends until the HTTP consumer reads the previous chunk, so the producer paces itself to the client automatically. If the client disconnects, the closure exits cleanly:

```swift
import Datastar

let body = DatastarSSEBody { emit in
    try await emit(.patchElements(
        #"<div id="clock">12:00</div>"#,
        selector: "#clock",
        mode: .inner
    ))
    try await Task.sleep(for: .seconds(1))
    try await emit(try .patchSignals(encoding: ["count": 42]))
    try await emit(.executeScript("console.log('done')"))
}

// Hand `body` (a DatastarSSEBody — an AsyncSequence<ArraySlice<UInt8>>)
// to your HTTP framework's streaming response body. Set
// Content-Type: text/event-stream.
```

`emit` accepts both the enum-case shorthand (`.patchElements(...)`) and the fully-qualified struct-literal form (`DatastarEvent.PatchElements(...)`):

```swift
try await emit(.patchElements("<p>hi</p>"))                            // shorthand
try await emit(DatastarEvent.PatchElements("<p>bye</p>", selector: "#x"))  // explicit
```

**From any `AsyncSequence`** of `DatastarEventConvertible` values — for event sources you already have (domain streams, file watchers, upstream APIs):

```swift
let events = domainEvents.map { DatastarEvent.PatchElements(render($0)) }
let body = DatastarSSEBody(events)
```

### Events

Three cases, matching the Rust SDK's first-class event types:

- `.patchElements(html, selector:, mode:, ...)` — patch HTML into the DOM.
- `.patchSignals(encoding: value)` / `.patchSignalsJSON(json)` — update client signals.
- `.executeScript(script, autoRemove:, attributes:, ...)` — run JavaScript (sugar over `patchElements`).

Removals are expressed via the core events — no dedicated helpers:

```swift
// Remove a DOM element:
try await emit(.patchElements("", selector: "#gone", mode: .remove))

// Remove (null out) client signals:
try await emit(.patchSignalsJSON(#"{"stale":null}"#))
```

### Decoding signals from a request

The framework-agnostic core does NOT ship a request-side signals helper. The Datastar protocol splits signal transport by HTTP method (query param `datastar` for GET/DELETE, JSON body for others); framework-specific adapters (planned for a later release) will provide method-aware extractors. Until then, decode directly with `JSONDecoder`:

```swift
struct MySignals: Decodable {
    var count: Int
}

// POST/PUT/PATCH — raw JSON body:
let signals = try JSONDecoder().decode(MySignals.self, from: requestBody)

// GET/DELETE — the `datastar` query parameter value:
let raw = queryParameter("datastar") ?? "{}"
let signals = try JSONDecoder().decode(MySignals.self, from: Data(raw.utf8))
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

v0.3 — value-oriented API around `DatastarEvent` (pre-ship; no releases yet). Framework adapters for Vapor and Hummingbird — including method-aware `ReadSignals` extractors — are planned for a follow-up release.

## License

MIT. Based on the [Datastar SDK specification](https://github.com/starfederation/datastar/blob/main/sdk/ADR.md) by starfederation.
