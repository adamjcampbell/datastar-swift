# datastar-swift — Examples

Runnable demos for the datastar-swift SDK, wired up with [Hummingbird 2](https://github.com/hummingbird-project/hummingbird).

This directory is a separate Swift package (its own `Package.swift` with a `path: "../"` dependency on the core library), so the main `Datastar` library stays free of any HTTP-framework dependency — library consumers never pull Hummingbird into their resolve graph.

## Running

```sh
cd Examples
swift run HelloWorldExample   # serves http://127.0.0.1:8080
swift run ActivityFeedExample # serves http://127.0.0.1:8081
```

Both servers log to stdout; stop them with Ctrl-C.

The browser loads the Datastar client from the official CDN (`https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0/bundles/datastar.js`), so you need a network connection the first time you open a page.

## HelloWorldExample

Port of [datastar-rust's axum-hello](https://github.com/starfederation/datastar-rust/blob/main/examples/axum-hello.rs). Opens a page with a delay input and a Start button; clicking Start issues `GET /hello-world?datastar=…`, and the server streams "Hello, world!" one character at a time by emitting a `datastar-patch-elements` frame per character.

**Features exercised:** `patchElements` (default `outer` mode), `DatastarSignals.decode(_:fromQueryValue:)`.

## ActivityFeedExample

Port of [datastar-rust's axum-activity-feed](https://github.com/starfederation/datastar-rust/blob/main/examples/axum-activity-feed.rs). A live log with reactive counters. Click the single-status buttons (done/warn/fail/info) to append one entry, or configure count × interval and click Generate to stream a batch.

The server is stateless: counter values live in the client's Datastar signals. Each request POSTs the current counters as JSON; the server increments them and sends the updated values back via `patchSignals`.

**Features exercised:** `patchElements` with `.prepend` and a selector, `patchSignals` (Encodable struct), `DatastarSignals.decode(_:fromBody:)`, multiple events per request with timing.

## Verifying the SSE wire format

With either server running, `curl -N` shows the raw Datastar protocol:

```sh
curl -N 'http://127.0.0.1:8080/hello-world?datastar=%7B%22delay%22%3A50%7D'
curl -N -X POST -H 'Content-Type: application/json' \
    -d '{"total":0,"done":0,"warn":0,"fail":0,"info":0,"count":3,"interval":100}' \
    http://127.0.0.1:8081/event/generate
```

Each frame is `event: datastar-patch-elements` (or `-signals`) followed by one or more `data:` lines and a terminating blank line.

## Adapting to your own server

The generator's `body` property is an `AsyncStream<ArraySlice<UInt8>>`. Any framework whose response body accepts an `AsyncSequence` of bytes can stream it — see `App.swift` for the one-line bridge to Hummingbird's `ResponseBody`. For Vapor, swift-nio, or a hand-rolled server, the shape is the same: map the byte slices into the framework's native buffer type and hand the sequence to the response.
