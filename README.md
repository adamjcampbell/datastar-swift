# datastar-swift

A Swift SDK for [Datastar](https://data-star.dev) — the hypermedia-driven framework that unifies server-rendered HTML with reactive client-side signals over Server-Sent Events.

This package provides an ADR-compliant core: the Go-style `ServerSentEventGenerator` that emits Datastar v1 wire format through a pluggable byte sink, with `DatastarHummingbird` as the built-in transport and a generic core ready to specialize for other frameworks. The API matches the [Datastar SDK ADR](https://github.com/starfederation/datastar/blob/develop/sdk/ADR.md) literally — call sites look the same as they do in Go and TypeScript.

## Requirements

- Swift 6.0+ (package uses `swiftLanguageModes: [.v6]`)
- macOS 14+, Linux, or Windows (untested; `DatastarHummingbird` requires Hummingbird v2 which does not support Windows)

Install the Swift toolchain via [swiftly](https://www.swift.org/install/) (`swiftly install latest`) if you don't already have Swift 6.0 or later.

## Installation

Add to your `Package.swift`:

```swift
// Alpha — pin to the exact pre-release tag until v0.1.0 is released
.package(url: "https://github.com/adamjcampbell/datastar-swift.git", exact: "0.1.0-alpha.1")
```

Then add the targets you need to your target's dependencies:

| Target | When to use |
|--------|-------------|
| `Datastar` | Value types (`DatastarEvent`, payload structs), wire-format primitives, generic `ServerSentEventGenerator<Writer>` — no HTTP framework dependency |
| `DatastarHummingbird` | Hummingbird 2 integration: `Response.datastarSSE` (specializes the generator to `any ResponseBodyWriter`), method-aware `request.datastarSignals`, and `router.datastarGet` / `datastarPost` / `datastarOn` route sugar |

To integrate with another server framework, specialize `ServerSentEventGenerator<YourWriter>` with a sink that pushes bytes into your framework's response-body primitive. See the Hummingbird adapter for a one-liner reference implementation.

## Usage

### Emit SSE events

With `DatastarHummingbird` — the closure receives an `inout` generator bound to the response-body writer:

```swift
import DatastarHummingbird

router.get("/stream") { _, _ -> Response in
    .datastarSSE { sse in
        try await sse.patchElements("<div>Hello</div>", options: .init(selector: "#msg"))
    }
}
```

`sse.emit(_:)` accepts any pre-built `DatastarEventConvertible` value — useful with the flat-kwargs factories (`.patchElements("<p/>", selector: "#x")`) or `DatastarEvent.PatchElements(...)` struct literals.

### Route sugar

Most Datastar routes decode signals and return an SSE response. The `RouterMethods` extension collapses that four-line scaffold into a single call:

```swift
router.datastarGet("/hello-world", signals: HelloSignals.self) { signals, sse in
    for i in 1...message.count {
        try await sse.patchElements(#"<div id="message">\#(message.prefix(i))</div>"#)
        try await Task.sleep(for: .milliseconds(Int(signals.delay)))
    }
}
```

Equivalent without the sugar:

```swift
router.get("/hello-world") { request, context -> Response in
    var request = request
    let signals = try await request.datastarSignals(as: HelloSignals.self, context: context)
    return .datastarSSE { sse in
        // ...
    }
}
```

`datastarOn(_:method:signals:use:)` is the primitive; `datastarGet` / `datastarPost` / `datastarPut` / `datastarPatch` / `datastarDelete` are one-liner wrappers over it. Routes that need `context` (auth, tracing) or no signals fall back to the composable primitives above.

See [`Examples/`](./Examples) for complete, runnable Hummingbird integrations.

### Events

Three ADR operations, available as both methods on `ServerSentEventGenerator` and value constructors on `DatastarEvent`:

- `sse.patchElements(elements, options:)` / `DatastarEvent.PatchElements(_:options:)` — patch HTML into the DOM.
- `sse.patchSignals(signals, options:)` / `DatastarEvent.PatchSignals(_:options:)` — update client signals.
- `sse.executeScript(script, options:)` / `DatastarEvent.ExecuteScript(_:options:)` — run JavaScript (sugar over `patchElements`).

Removals are expressed via the core events — no dedicated helpers:

```swift
// Remove a DOM element:
try await sse.patchElements(options: .init(selector: "#gone", mode: .remove))

// Remove (null out) client signals:
try await sse.patchSignals(#"{"stale":null}"#)
```

### Decoding signals from a request

**With `DatastarHummingbird`** — one method-aware extractor for every HTTP verb:

```swift
import DatastarHummingbird

// Routes automatically per ADR:
//   GET, DELETE        → ?datastar=<json> query parameter
//   POST, PUT, PATCH   → JSON request body
var request = request
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

## ADR conformance

datastar-swift is **ADR-first**: the public API mirrors the [Datastar SDK ADR](https://github.com/starfederation/datastar/blob/develop/sdk/ADR.md) literally.

| ADR | datastar-swift |
|-----|----------------|
| `ServerSentEventGenerator` | Generic `ServerSentEventGenerator<Writer>` in `Datastar` core; `DatastarHummingbird` specializes `Writer == any ResponseBodyWriter` |
| `PatchElements(elements?, options?)` | `sse.patchElements(_:options:)` / `DatastarEvent.PatchElements(_:options:)` |
| `PatchSignals(signals, options?)` | `sse.patchSignals(_:options:)` / `DatastarEvent.PatchSignals(_:options:)` |
| `ExecuteScript(script, options?)` | `sse.executeScript(_:options:)` / `DatastarEvent.ExecuteScript(_:options:)` |
| `ReadSignals(r, &signals)` (method-aware) | `request.datastarSignals(as:context:)` (method-aware) |
| Response headers: Content-Type, Cache-Control, Connection | All three set by `Response.datastarSSE` |
| Retry omitted when equal to default (1000 ms) | Implemented |
| Nested options objects | Nested `PatchElements.Options` / `PatchSignals.Options` / `ExecuteScript.Options` |

Flat-keyword-argument factories (`DatastarEvent.patchElements(_:selector:mode:...)`) are provided as Swift-idiomatic sugar on top of the ADR-literal core.

**One language-idiomatic deviation:** `Response.datastarSSE` in `DatastarHummingbird` doesn't take a `Request` parameter, because Hummingbird route handlers already bind the request in scope. This matches the Swift-on-server adapter idiom; the ADR's "constructor accepts Request and Response" semantic is satisfied by the route handler itself.

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

**Alpha** — the wire format and ADR-aligned API are in place, but the library is untested in production. Breaking changes are possible before v0.1.0; the ADR-alignment pass (nested `Options`, `ServerSentEventGenerator` with per-transport sinks, method-aware `datastarSignals`) is a breaking revision of `0.1.0-alpha.1`.

> **Disclaimer:** This library was developed with LLM (AI) assistance. At alpha stage, documentation and implementation details may be incorrect or misleading in places. Please verify anything critical against the [Datastar specification](https://data-star.dev) and open an issue if you find something wrong.

- `Datastar` — value types, ADR-named generic `ServerSentEventGenerator<Writer>`, wire-format encoding, complete
- `DatastarHummingbird` — Hummingbird 2 adapter with `Response.datastarSSE`, method-aware `request.datastarSignals`, and `router.datastarGet`/`Post`/`Put`/`Patch`/`Delete`/`On` route sugar, complete

Planned for a future release: Vapor adapter.

## License

MIT.
