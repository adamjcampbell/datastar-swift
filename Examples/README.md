# datastar-swift — Examples

Runnable demos for the datastar-swift SDK, wired up with [Hummingbird 2](https://github.com/hummingbird-project/hummingbird).

This directory is a separate Swift package to keep example dependencies separate from the library.

## Swift toolchain

These examples require **Swift 6.2 or later**. Install via [swift.org/install](https://www.swift.org/install/).

On macOS, Swift 6.2+ ships with Xcode 26 and later.

## Running

```sh
cd Examples
swift run HelloWorldExample   # serves http://127.0.0.1:8080
swift run ActivityFeedExample # serves http://127.0.0.1:8081
```

Both servers log to stdout; stop them with Ctrl-C.

The browser loads the Datastar client from the official CDN (`https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0/bundles/datastar.js`), so you need a network connection the first time you open a page.

## HelloWorldExample

Opens a page with a delay input and a Start button; clicking Start issues `GET /hello-world?datastar=…`, and the server streams "Hello, world!" one character at a time by emitting a `datastar-patch-elements` frame per character.

**Features exercised:** `Response.datastarSSE { writer in ... }` trailing-closure API, `.patchElements(_:)` (default outer merge), `request.datastarSignals(as:)` to decode GET signals.

## ActivityFeedExample

Port of [datastar-rust's axum-activity-feed](https://github.com/starfederation/datastar-rust/blob/main/examples/axum-activity-feed.rs). A live log with reactive counters. Click the single-status buttons (done/warn/fail/info) to append one entry, or configure count × interval and click Generate to stream a batch.

The server is stateless: counter values live in the client's Datastar signals. Each request POSTs the current counters as JSON; the server increments them and sends the updated values back via a `patch-signals` frame.

**Features exercised:** `.patchElements(_:selector:mode:)` with `.prepend`, `.patchSignals(encoding:)` for a `Codable` struct, `request.datastarSignals(as:context:)` to decode POST body signals, multiple events per request with timing.
