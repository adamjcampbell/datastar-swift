# datastar-swift

A Swift SDK for [Datastar](https://data-star.dev) — the hypermedia-driven framework that unifies server-rendered HTML with reactive client-side signals over Server-Sent Events.

This package provides a framework-agnostic core: a value-oriented Datastar-event API that emits the Datastar v1 wire format as an `AsyncSequence` of bytes, ready to plug into any Swift HTTP server (Vapor, Hummingbird, swift-nio, or a handwritten one).

## Requirements

- Swift 6.2+ (uses `NonisolatedNonsendingByDefault` — SE-0461)
- macOS 14+, Linux, or Windows (untested; `DatastarHummingbird` requires Hummingbird v2 which does not support Windows)

Install the Swift toolchain via [swiftly](https://www.swift.org/install/) (`swiftly install latest`) if you don't already have Swift 6.2 or later.

## Installation

Add to your `Package.swift`:

```swift
// Alpha — pin to the exact pre-release tag until v0.1.0 is released
.package(url: "https://github.com/adamjcampbell/datastar-swift.git", exact: "0.1.0-alpha.1")
```

Then add the targets you need to your target's dependencies:

| Target | When to use |
|--------|-------------|
| `Datastar` | Wire-format primitives only — no HTTP framework dependency |
| `DatastarStream` | Adds `DatastarSSEStream`, an `AsyncSequence`-based SSE body |
| `DatastarHummingbird` | Hummingbird 2 integration: `Response.datastarSSE` + `request.datastarSignals` |

## Usage

### Emit SSE events

Datastar events are values (`DatastarEvent`), not method calls on a writer. Create a `DatastarSSEStream` with a trailing closure and hand it to your HTTP framework as a streaming response body (`Content-Type: text/event-stream`):

```swift
import DatastarStream

let stream = DatastarSSEStream { emit in
    try await emit(.patchElements(
        #"<div id="clock">12:00</div>"#,
        selector: "#clock",
        mode: .inner
    ))
    try await Task.sleep(for: .seconds(1))
    try await emit(try .patchSignals(encoding: ["count": 42]))
    try await emit(.executeScript("console.log('done')"))
}
```

You can also init `DatastarSSEStream` from any `AsyncSequence` of `DatastarEventConvertible` values.

See [`Examples/`](./Examples) for complete, runnable Hummingbird integrations.

### Events

Three event types:

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

**With `DatastarHummingbird`**:

```swift
import DatastarHummingbird

// GET/DELETE — reads the ?datastar= query parameter
let signals = try request.datastarSignals(as: MySignals.self)

// POST/PUT/PATCH — collects the body and JSON-decodes it
let signals = try await request.datastarSignals(as: MySignals.self, context: context)
```

**Framework-agnostic fallback** — decode directly with `JSONDecoder`:

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

**Alpha** — the API is shaped and the wire format is correct, but the library is untested in production. Breaking changes are possible before v0.1.0.

> **Disclaimer:** This library was developed with LLM (AI) assistance. At alpha stage, documentation and implementation details may be incorrect or misleading in places. Please verify anything critical against the [Datastar specification](https://data-star.dev) and open an issue if you find something wrong.

- `Datastar` — wire-format encoding, complete
- `DatastarStream` — `DatastarSSEStream` AsyncSequence wrapper, complete
- `DatastarHummingbird` — Hummingbird 2 adapter with `Response.datastarSSE` and `request.datastarSignals`, complete

Planned for a future release: Vapor adapter.

## License

MIT.
